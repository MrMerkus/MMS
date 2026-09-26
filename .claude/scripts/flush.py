#!/usr/bin/env python3
"""Oturumu deterministik bir kayda projelendirir; model cagirmaz."""

# Semantik ozeti aktif ajan yazar (zihin/son-oturum/). Bu script yalnizca
# diskteki olaydan daily/YYYY-MM-DD.md uretir: tur sayisi, dokunulan dosya,
# komut aciklamasi ve ajan ozetine bag. Model cagiran ozetleyici dustugunde
# ozet hic dogmaz; deterministik projektor dustugunde is yalnizca gecikir.
#
# Windows portu: kilitleme _portalock uzerinden yapilir; davranis POSIX'te
# birebir ayni kalir.

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
from pathlib import Path
import re
import sys
import time

sys.dont_write_bytecode = True
import _portalock
try:
    import olaylar
except ImportError:  # defter yoksa kayıt eski yolla daily'ye eklenir, yokluk sağlıkta görünür
    olaylar = None
try:
    import projektor
except ImportError:  # projektör yoksa olay yine yazılır, daily eski yolla eklenir
    projektor = None
from typing import Any, Sequence


SCRIPT_DIR = Path(__file__).resolve().parent
VAULT_ROOT = SCRIPT_DIR.parent.parent
STATE_DIR = SCRIPT_DIR / ".state"
MAX_TURNS = 30
MAX_TRANSCRIPT_CHARS = 15_000
STALE_HOOK_INPUT_SECONDS = 3_600
STALE_SESSION_FILE_SECONDS = 7 * 86_400

MAX_PROMPT_CHARS = 400
MAX_FILE_LINES = 30
MAX_COMMAND_LINES = 20
MAX_GAP_RECORDS = 50

RECEIPT_DIR = ("🔮 zihin", "son-oturum")
KASA_MARK = "🔐 kasa"
EDIT_TOOLS = {"Edit", "Write", "NotebookEdit", "MultiEdit"}
DIRECTIVE_SHAPED = re.compile(
    r"(?im)^\s*(?:"
    r"UNTRUSTED[_ -]?DIRECTIVE|DIRECTIVE|INSTRUCTION|SYSTEM|ASSISTANT|"
    r"TAL[İI]MAT|KOMUT|IGNORE\s+(?:ALL|ANY|PREVIOUS)"
    r")\s*[:：]"
)
HOOK_INPUT_NAME = re.compile(r"hookin-[^/]+\.json\Z")
INVALID_UNICODE_ESCAPE = re.compile(r"\\u(?![0-9a-fA-F]{4})")
INVALID_JSON_ESCAPE = re.compile(r'\\(?!["\\/bfnrtu])')


def _atomic_write_json(path: Path, payload: dict[str, Any]) -> None:
    path.parent.mkdir(parents=True, exist_ok=True)
    temporary = path.with_name(f".{path.name}.{os.getpid()}.tmp")
    try:
        temporary.write_text(
            json.dumps(payload, ensure_ascii=False) + "\n",
            encoding="utf-8",
        )
        os.replace(temporary, path)
    finally:
        try:
            temporary.unlink()
        except FileNotFoundError:
            pass


def write_health(state_dir: Path, error: str, warning: bool = False) -> None:
    """Record the latest flush problem without letting reporting crash."""
    try:
        payload: dict[str, Any] = {}
        health_path = state_dir / "health.json"
        if health_path.exists():
            try:
                loaded = json.loads(health_path.read_text(encoding="utf-8"))
                if isinstance(loaded, dict):
                    payload.update(loaded)
            except (OSError, ValueError, json.JSONDecodeError):
                pass
        payload.update(
            {
                "ts": int(time.time()),
                "component": "flush",
                "error": error,
            }
        )
        if warning:
            warnings = payload.get("warnings", [])
            if not isinstance(warnings, list):
                warnings = []
            if error not in warnings:
                warnings.append(error)
            payload["warnings"] = warnings[-20:]
        _atomic_write_json(health_path, payload)
    except OSError:
        pass


def _repair_invalid_json_escapes(raw: str) -> str:
    repaired = INVALID_UNICODE_ESCAPE.sub(r"\\\\u", raw)
    return INVALID_JSON_ESCAPE.sub(r"\\\\", repaired)


def load_hook_input(path: Path) -> dict[str, Any]:
    raw = path.read_text(encoding="utf-8")
    try:
        value = json.loads(raw)
    except json.JSONDecodeError:
        value = json.loads(_repair_invalid_json_escapes(raw))
    if not isinstance(value, dict):
        raise ValueError("hook-input-not-object")
    return value


def _message_parts(record: dict[str, Any]) -> tuple[str | None, Any]:
    # Google Antigravity transcript format. Hooks expose this JSONL through
    # transcriptPath; reasoning/tool-only records deliberately carry no role.
    record_type = record.get("type")
    if record_type == "USER_INPUT":
        return "user", record.get("content")
    if record_type == "PLANNER_RESPONSE":
        return "assistant", record.get("content")

    # Codex rollout format: ~/.codex/sessions/**/rollout-*.jsonl.  The
    # user-facing turns are event_msg records; response/tool records are
    # intentionally ignored so a hook does not duplicate or ingest internals.
    if record.get("type") == "event_msg":
        payload = record.get("payload")
        if not isinstance(payload, dict):
            return None, None
        payload_type = payload.get("type")
        if payload_type == "user_message":
            return "user", payload.get("message")
        if payload_type == "agent_message":
            return "assistant", payload.get("message")
        if payload_type == "item_completed":
            item = payload.get("item")
            if not isinstance(item, dict):
                return None, None
            item_type = item.get("type")
            if item_type == "UserMessage":
                return "user", item.get("content")
            if item_type == "AgentMessage":
                return "assistant", item.get("content")
            # Reasoning, commands and file changes are implementation details,
            # not user-facing conversation turns.
            return None, None
        return None, None

    message = record.get("message")
    if isinstance(message, dict):
        role = message.get("role") or record.get("type")
        return role, message.get("content")
    return record.get("role") or record.get("type"), record.get("content")


def _text_from_content(content: Any) -> str:
    def is_text_block(block_type: Any) -> bool:
        return isinstance(block_type, str) and block_type.casefold() == "text"

    if isinstance(content, str):
        return content
    if isinstance(content, dict):
        if is_text_block(content.get("type")) and isinstance(
            content.get("text"), str
        ):
            return content["text"]
        return ""
    if not isinstance(content, list):
        return ""

    text_parts = []
    for block in content:
        if not isinstance(block, dict) or not is_text_block(block.get("type")):
            continue
        text = block.get("text")
        if isinstance(text, str):
            text_parts.append(text)
    return "\n".join(text_parts)


def read_transcript(path: Path) -> list[tuple[str, str]]:
    """Return only user and assistant text turns from transcript JSONL."""
    turns: list[tuple[str, str]] = []
    with path.open("r", encoding="utf-8") as transcript:
        for line_number, raw_line in enumerate(transcript, start=1):
            if not raw_line.strip():
                continue
            try:
                record = json.loads(raw_line)
            except json.JSONDecodeError as exc:
                raise ValueError(
                    f"transcript-jsonl-invalid:{line_number}"
                ) from exc
            if not isinstance(record, dict):
                continue
            role, content = _message_parts(record)
            if role not in {"user", "assistant"}:
                continue
            text = _text_from_content(content)
            flattened = re.sub(r"\s+", " ", text).strip()
            if flattened:
                turns.append((role, flattened))
    return turns


def format_turns(
    turns: Sequence[tuple[str, str]],
    max_turns: int = MAX_TURNS,
    max_chars: int = MAX_TRANSCRIPT_CHARS,
) -> tuple[str, int]:
    """Keep the newest complete turns and snap a character cut to a turn."""
    selected = list(turns[-max_turns:])
    rendered = "\n".join(
        f"**{'User' if role == 'user' else 'Assistant'}:** {text}"
        for role, text in selected
    )
    if len(rendered) <= max_chars:
        return rendered, len(selected)

    tentative_start = len(rendered) - max_chars
    boundary = rendered.find("\n**", tentative_start)
    if boundary != -1:
        rendered = rendered[boundary + 1 :]
    else:
        role, text = selected[-1]
        prefix = f"**{'User' if role == 'user' else 'Assistant'}:** "
        rendered = prefix + text[-max(0, max_chars - len(prefix)) :]
    return rendered, len(selected)


def _tool_use_blocks(record: dict[str, Any]) -> list[dict[str, Any]]:
    """Bir transcript kaydındaki tool_use bloklarını döndür."""
    message = record.get("message")
    content = message.get("content") if isinstance(message, dict) else None
    if not isinstance(content, list):
        return []
    return [
        block
        for block in content
        if isinstance(block, dict) and block.get("type") == "tool_use"
    ]


def read_tool_events(path: Path) -> dict[str, list[str]]:
    """Düzenlenen dosyaları ve Bash açıklamalarını transcript'ten topla.

    Ham komut metni (`input.command`) bilerek toplanmaz: günlüğe yalnızca
    ajanın kendi yazdığı açıklama düşer. Codex ve Antigravity biçimlerinde
    bu bloklar bulunmaz; orada boş liste dönmek doğru sonuçtur.
    """
    files: list[str] = []
    commands: list[str] = []
    with path.open("r", encoding="utf-8") as transcript:
        for line_number, raw_line in enumerate(transcript, start=1):
            if not raw_line.strip():
                continue
            try:
                record = json.loads(raw_line)
            except json.JSONDecodeError as exc:
                raise ValueError(
                    f"transcript-jsonl-invalid:{line_number}"
                ) from exc
            if not isinstance(record, dict):
                continue
            for block in _tool_use_blocks(record):
                payload = block.get("input")
                if not isinstance(payload, dict):
                    continue
                name = block.get("name")
                if name in EDIT_TOOLS:
                    value = payload.get("file_path")
                    if isinstance(value, str) and value and value not in files:
                        files.append(value)
                elif name == "Bash":
                    value = payload.get("description")
                    if isinstance(value, str):
                        flattened = re.sub(r"\s+", " ", value).strip()
                        if flattened and flattened not in commands:
                            commands.append(flattened)
    return {"files": files, "commands": commands}


def neutralize(text: str, limit: int = 0) -> str:
    """Transcript metnini düzleştir: yeni bir Markdown yapısı açamasın."""
    flattened = re.sub(r"\s+", " ", text).strip()
    flattened = flattened.replace("`", "'").replace("|", "/")
    flattened = flattened.lstrip("#>-*=+ ")
    if limit and len(flattened) > limit:
        flattened = flattened[: limit - 1].rstrip() + "…"
    return flattened


def _relative_path(value: str, vault_root: Path) -> str:
    """Vault içi yolu göreli yaz; dışarıdaki mutlak yol günlüğe sızmasın."""
    candidate = Path(value)
    try:
        return candidate.resolve().relative_to(vault_root.resolve()).as_posix()
    except (ValueError, OSError):
        return candidate.name or neutralize(value, 80)


def find_receipts(vault_root: Path, now: dt.datetime) -> list[str]:
    """Aktif ajanın o güne yazdığı devir izlerinin dosya adları."""
    receipt_dir = vault_root.joinpath(*RECEIPT_DIR)
    if not receipt_dir.is_dir():
        return []
    prefix = now.strftime("%Y-%m-%d")
    return sorted(
        path.name
        for path in receipt_dir.glob(f"{prefix}*.md")
        if path.is_file()
    )


def _bullet_section(items: Sequence[str], limit: int, empty: str) -> str:
    if not items:
        return empty
    lines = [f"- {item}" for item in items[:limit]]
    remaining = len(items) - limit
    if remaining > 0:
        lines.append(f"- ... ve {remaining} tane daha")
    return "\n".join(lines)


def build_session_record(
    turns: Sequence[tuple[str, str]],
    tool_events: dict[str, list[str]],
    session_id: str,
    turn_count: int,
    receipts: Sequence[str],
    vault_root: Path,
) -> str:
    """Oturumun deterministik kaydı: yorum yok, yalnızca diskteki olgular."""
    opening = next((text for role, text in turns if role == "user"), "")
    quoted = neutralize(opening, MAX_PROMPT_CHARS)

    files = [
        _relative_path(value, vault_root)
        for value in tool_events.get("files", [])
    ]
    commands = [
        neutralize(value, 120) for value in tool_events.get("commands", [])
    ]

    parts = [
        f"- Oturum kimliği: {session_id[:8]}",
        f"- Tur sayısı: {turn_count}",
        "- Kayıt türü: deterministik projeksiyon (model çağrısı yok)",
        "",
        "#### Açılış isteği",
        "",
        f"> {quoted}" if quoted else "> (kullanıcı turu yok)",
        "",
        "#### Dokunulan dosyalar",
        "",
        _bullet_section(files, MAX_FILE_LINES, "Dosya değişikliği yok."),
    ]
    if commands:
        parts += [
            "",
            "#### Komutlar",
            "",
            _bullet_section(commands, MAX_COMMAND_LINES, ""),
        ]
    parts += ["", "#### Ajan özeti", ""]
    if receipts:
        parts.append(
            "\n".join(
                f"- [[{'/'.join(RECEIPT_DIR)}/{name}]]" for name in receipts
            )
        )
    else:
        parts.append("Özet yok — bu oturumda aktif ajan devir izi yazmadı.")
    return "\n".join(parts) + "\n"


def _load_json_object(path: Path, default: dict[str, Any]) -> dict[str, Any]:
    if not path.exists():
        return default
    value = json.loads(path.read_text(encoding="utf-8"))
    if not isinstance(value, dict):
        raise ValueError("state-not-object")
    return value


def record_receipt_gap(
    state_dir: Path,
    session_id: str,
    now: dt.datetime,
    reason: str,
) -> None:
    """Özetsiz oturumu kaydet: sessiz kayıp yerine görünür boşluk."""
    path = state_dir / "ozet-bosluklari.json"
    try:
        state = _load_json_object(path, {"gaps": []})
    except (OSError, ValueError, json.JSONDecodeError):
        state = {"gaps": []}
    gaps = state.get("gaps")
    if not isinstance(gaps, list):
        gaps = []
    gaps.append(
        {
            "session": session_id,
            "ts": int(now.timestamp()),
            "reason": reason,
            "date": now.strftime("%Y-%m-%d"),
        }
    )
    _atomic_write_json(path, {"gaps": gaps[-MAX_GAP_RECORDS:]})


def _is_recent_duplicate(
    state_dir: Path,
    session_id: str,
    now_epoch: float,
) -> bool:
    session_state_path = _session_state_path(state_dir, session_id)
    state_path = (
        session_state_path
        if session_state_path.exists()
        else state_dir / "last-flush.json"
    )
    state = _load_json_object(state_path, {})
    if state.get("session_id") != session_id:
        return False
    if state.get("status", "ok") != "ok":
        return False
    timestamp = state.get("ts")
    if not isinstance(timestamp, (int, float)):
        return False
    return abs(now_epoch - float(timestamp)) < 60


def _write_flush_state(
    state_dir: Path,
    session_id: str,
    now_epoch: float,
    status: str,
    detail: str = "",
) -> None:
    payload = {
        "session_id": session_id,
        "ts": int(now_epoch),
        "status": status,
    }
    if detail:
        payload["detail"] = detail
    _atomic_write_json(_session_state_path(state_dir, session_id), payload)
    try:
        _atomic_write_json(state_dir / "last-flush.json", payload)
    except OSError:
        write_health(state_dir, "last-flush-compat-write-failed")


def _record_flush_failure(
    state_dir: Path,
    session_id: str,
    now_epoch: float,
    error: str,
) -> None:
    try:
        _write_flush_state(
            state_dir,
            session_id,
            now_epoch,
            "fail",
            error,
        )
    except OSError:
        pass
    write_health(state_dir, error)


def _session_lock_path(state_dir: Path, session_id: str) -> Path:
    key = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    return state_dir / f"flush-{key}.lock"


def _session_state_path(state_dir: Path, session_id: str) -> Path:
    key = hashlib.sha256(session_id.encode("utf-8")).hexdigest()
    return state_dir / f"flush-{key}.json"


def _append_daily(
    vault_root: Path,
    record: str,
    reason: str,
    now: dt.datetime,
) -> None:
    daily_dir = vault_root / "daily"
    daily_dir.mkdir(parents=True, exist_ok=True)
    date_text = now.strftime("%Y-%m-%d")
    daily_path = daily_dir / f"{date_text}.md"
    if not daily_path.exists():
        daily_path.write_text(
            f"# Günlük Log: {date_text}\n\n## Oturumlar\n",
            encoding="utf-8",
        )

    suffix = ", compaction öncesi" if reason == "precompact" else ""
    entry = (
        f"\n### Oturum ({now.strftime('%H:%M')}){suffix}\n\n"
        f"{record}\n"
    )
    with daily_path.open("a", encoding="utf-8") as daily_file:
        daily_file.write(entry)


def _kasasiz(text: str) -> str:
    # Defter git'le uzağa gider, kasa gitmez: kasa yolu kayda adıyla girmez.
    return text.replace(KASA_MARK, "(kasa)")


# Jev'in flush-deger gölgesi kapandı (İyileştirme 5, 26 Eylül): yerel karar "tur ≥ 1" tabanıdır,
# Jev onu devralamaz ve Karar 7'ye kanıt üretemezdi. flush artık Jev'i hiç çağırmaz.


def build_session_data(
    turns: Sequence[tuple[str, str]],
    tool_events: dict[str, list[str]],
    session_id: str,
    turn_count: int,
    receipts: Sequence[str],
    reason: str,
    now: dt.datetime,
    vault_root: Path,
) -> dict[str, Any]:
    """Oturum olayının verisi; projektor.kayit_metni bundan kaydı üretir."""
    opening = next((text for role, text in turns if role == "user"), "")
    files = [
        _kasasiz(_relative_path(value, vault_root))
        for value in tool_events.get("files", [])
    ]
    commands = [
        _kasasiz(neutralize(value, 120)) for value in tool_events.get("commands", [])
    ]
    return {
        "session_id": session_id,
        "sebep": reason,
        "tur": turn_count,
        "daily": f"daily/{now.strftime('%Y-%m-%d')}.md",
        "ozet": list(receipts),
        "acilis": _kasasiz(neutralize(opening, MAX_PROMPT_CHARS)),
        "dosyalar": files[:MAX_FILE_LINES],
        "dosya_sayisi": len(files),
        "komutlar": commands[:MAX_COMMAND_LINES],
        "komut_sayisi": len(commands),
    }


def _write_session_event(
    data: dict[str, Any],
    now: dt.datetime,
) -> str | None:
    """Olay defterine yazar; "yazildi", "zaten-var" ya da hata halinde None."""
    if olaylar is None:
        write_health(STATE_DIR, "olaylar-modulu-yok")
        return None
    try:
        return olaylar.yaz(
            VAULT_ROOT,
            "oturum",
            f"oturum:{data['session_id']}:{data['sebep']}:{data['tur']}",
            data,
            zaman=now.isoformat(timespec="seconds"),
            kaynak="flush.py",
        )
    except (olaylar.OlayHatasi, OSError) as exc:
        write_health(STATE_DIR, f"olay-yazilamadi:{exc.__class__.__name__}")
        return None


def _project_day(now: dt.datetime) -> str | None:
    """Günü defterden yansıtır (eşzamanlı, deterministik); hata halinde None."""
    if projektor is None:
        return None
    try:
        return projektor.yansit_gun(VAULT_ROOT, now.strftime("%Y-%m-%d"))
    except (olaylar.OlayHatasi, OSError, ValueError) as exc:
        write_health(STATE_DIR, f"projeksiyon-basarisiz:{exc.__class__.__name__}")
        return None


def _sha256(path: Path) -> str:
    digest = hashlib.sha256()
    with path.open("rb") as source:
        for chunk in iter(lambda: source.read(1024 * 1024), b""):
            digest.update(chunk)
    return digest.hexdigest()


def _event_now() -> dt.datetime:
    fake_now = os.environ.get("BEYIN_FAKE_NOW")
    if not fake_now:
        return dt.datetime.now().astimezone()
    parsed = dt.datetime.fromisoformat(fake_now)
    if parsed.tzinfo is None:
        return parsed.astimezone()
    return parsed


def _managed_hook_input(path: Path, state_dir: Path) -> bool:
    try:
        same_parent = path.absolute().parent.resolve() == state_dir.resolve()
    except OSError:
        return False
    return same_parent and HOOK_INPUT_NAME.fullmatch(path.name) is not None


def _sweep_stale_hook_inputs(
    state_dir: Path,
    current_input: Path,
    now_epoch: float,
) -> None:
    if not state_dir.exists():
        return
    current_absolute = current_input.absolute()
    for candidate in state_dir.glob("hookin-*.json"):
        if candidate.absolute() == current_absolute:
            continue
        try:
            age = now_epoch - candidate.lstat().st_mtime
            if age >= STALE_HOOK_INPUT_SECONDS:
                candidate.unlink()
        except FileNotFoundError:
            continue


def _sweep_stale_session_files(
    state_dir: Path,
    session_id: str,
    now_epoch: float,
) -> None:
    """Drop flush lock/state pairs left behind by long-finished sessions."""
    if not state_dir.exists():
        return
    keep = {
        _session_lock_path(state_dir, session_id).name,
        _session_state_path(state_dir, session_id).name,
    }

    def _age(path: Path) -> float | None:
        try:
            return now_epoch - path.lstat().st_mtime
        except OSError:
            return None

    for candidate in state_dir.glob("flush-*.json"):
        if candidate.name in keep:
            continue
        age = _age(candidate)
        if age is None or age < STALE_SESSION_FILE_SECONDS:
            continue
        lock = candidate.with_suffix(".lock")
        lock_age = _age(lock)
        if lock_age is not None and lock_age < STALE_SESSION_FILE_SECONDS:
            continue
        for path in (candidate, lock):
            try:
                path.unlink()
            except OSError:
                continue

    for lock in state_dir.glob("flush-*.lock"):
        if lock.name in keep or lock.with_suffix(".json").exists():
            continue
        age = _age(lock)
        if age is None or age < STALE_SESSION_FILE_SECONDS:
            continue
        try:
            lock.unlink()
        except OSError:
            continue


def _parse_args(argv: Sequence[str] | None) -> argparse.Namespace:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--hook-input", type=Path)
    parser.add_argument(
        "--reason",
        choices=("sessionend", "precompact"),
        default="sessionend",
    )
    parsed = parser.parse_args(argv)
    if parsed.hook_input is None:
        parser.error("--hook-input is required")
    return parsed


def _flush_once(args: argparse.Namespace, event_time: dt.datetime) -> int:
    now_epoch = event_time.timestamp()
    hook_input = load_hook_input(args.hook_input)
    session_id = hook_input.get("session_id")
    transcript_value = hook_input.get("transcript_path")
    if not isinstance(session_id, str) or not session_id:
        raise ValueError("session-id-missing")
    if not isinstance(transcript_value, str) or not transcript_value:
        raise ValueError("transcript-path-missing")
    transcript_path = Path(transcript_value).expanduser()

    STATE_DIR.mkdir(parents=True, exist_ok=True)
    _sweep_stale_session_files(STATE_DIR, session_id, now_epoch)
    lock_path = _session_lock_path(STATE_DIR, session_id)
    lock_handle = lock_path.open("a+", encoding="utf-8")
    with lock_handle, _portalock.exclusive(lock_handle):
        if _is_recent_duplicate(STATE_DIR, session_id, now_epoch):
            return 0

        turns = read_transcript(transcript_path)
        transcript, turn_count = format_turns(turns)
        minimum_turns = 5 if args.reason == "precompact" else 1
        if turn_count < minimum_turns:
            _write_flush_state(
                STATE_DIR,
                session_id,
                now_epoch,
                "ok",
                "below-minimum-turns",
            )
            return 0

        _write_flush_state(STATE_DIR, session_id, now_epoch, "inflight")
        if DIRECTIVE_SHAPED.search(transcript):
            write_health(
                STATE_DIR,
                "warn:directive-shaped-transcript",
                warning=True,
            )

        # Araç olayları kaydın süsü, çekirdeği değil: okunamazsa kayıt yine
        # yazılır, yalnızca dosya ve komut listesi boş kalır.
        try:
            tool_events = read_tool_events(transcript_path)
        except (OSError, ValueError) as exc:
            tool_events = {"files": [], "commands": []}
            write_health(
                STATE_DIR,
                f"warn:tool-events-okunamadi:{exc.__class__.__name__}",
                warning=True,
            )

        receipts = find_receipts(VAULT_ROOT, event_time)
        if not receipts:
            write_health(STATE_DIR, "warn:ajan-ozeti-yok", warning=True)
            try:
                record_receipt_gap(
                    STATE_DIR,
                    session_id,
                    event_time,
                    args.reason,
                )
            except OSError:
                write_health(STATE_DIR, "ozet-bosluk-yazilamadi")

        data = build_session_data(
            turns,
            tool_events,
            session_id,
            turn_count,
            receipts,
            args.reason,
            event_time,
            VAULT_ROOT,
        )
        # Önce olay: defter kanonik, daily onun yansıması (SOZLESME Karar 4).
        event = _write_session_event(data, event_time)
        if event == "zaten-var":
            _write_flush_state(STATE_DIR, session_id, now_epoch, "ok", "duplicate-event")
            return 0
        projection = _project_day(event_time) if event == "yazildi" else None
        # Geçiş günü (işaretsiz daily) ya da defter/projeksiyon hatası: kayıt eski
        # yolla eklenir, hiçbir oturum kaybolmaz. Projeksiyon işaretsiz dosyası
        # olmayan ilk günden başlar (24 Eylül, orkestratör onayı).
        if projection is None or projection.startswith("atlandi"):
            record = build_session_record(
                turns,
                tool_events,
                session_id,
                turn_count,
                receipts,
                VAULT_ROOT,
            )
            try:
                _append_daily(VAULT_ROOT, record, args.reason, event_time)
            except OSError:
                _record_flush_failure(
                    STATE_DIR,
                    session_id,
                    now_epoch,
                    "daily-append-failed",
                )
                return 0
        _write_flush_state(
            STATE_DIR,
            session_id,
            now_epoch,
            "ok",
            "projected" if projection and not projection.startswith("atlandi") else "appended",
        )
    return 0


def main(argv: Sequence[str] | None = None) -> int:
    if os.environ.get("BEYIN_INVOKED_BY"):
        return 0

    try:
        args = _parse_args(argv)
    except SystemExit as exc:
        if exc.code:
            write_health(STATE_DIR, "invalid-arguments")
        return 0

    managed_input = _managed_hook_input(args.hook_input, STATE_DIR)
    try:
        event_time = _event_now()
        _sweep_stale_hook_inputs(
            STATE_DIR,
            args.hook_input,
            event_time.timestamp(),
        )
        return _flush_once(args, event_time)
    except (OSError, ValueError, json.JSONDecodeError) as exc:
        error = str(exc) or exc.__class__.__name__
        write_health(STATE_DIR, f"input:{error}")
        return 0
    except Exception as exc:  # Defensive hook boundary: hooks must never fail.
        write_health(STATE_DIR, f"unexpected:{exc.__class__.__name__}")
        return 0
    finally:
        if managed_input:
            try:
                args.hook_input.unlink()
            except FileNotFoundError:
                pass
            except OSError:
                write_health(STATE_DIR, "hook-input-cleanup-failed")


if __name__ == "__main__":
    raise SystemExit(main())
