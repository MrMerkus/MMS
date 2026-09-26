#!/usr/bin/env python3
"""Ders kapısı: yazılmış dersi an geldiğinde uygular.

Neden var: test günü (25 Eylül) kuralların ~%83'ünün yalnız kâğıtta olduğunu,
iki dersin yazıldıktan sonra tekrarlandığını buldu. Kural bağlama giriyordu ama
tetiklenmiyordu. Bu kapı `.claude/scripts/ders-tetikleri.tsv` satırlarını
olaya göre uygular: bağlama not düşer, kullanıcıya sordurur ya da durdurur.
kullanıcının düzeltmelerini olay defterine `duzeltme` tipiyle yazar.

Kullanım (hook): ders-kapisi.py <UserPromptSubmit|PreToolUse|PostToolUse>, JSON stdin'den.
Hata sessizdir: kapı bozulursa oturumu durdurmaz, yalnız susar.
"""
import hashlib
import json
import os
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
KOK = Path(__file__).resolve().parent.parent.parent
TABLO = KOK / ".claude" / "scripts" / "ders-tetikleri.tsv"
DURUM = KOK / ".claude" / "scripts" / ".state"


def satirlar():
    for s in TABLO.read_text(encoding="utf-8").splitlines():
        if not s.strip() or s.startswith("#"):
            continue
        p = s.split("\t")
        if len(p) >= 7:
            yield dict(olay=p[0], arac=p[1], kalip=re.compile(p[2]), karar=p[3],
                       kurallar=p[4], ornek=p[5], mesaj=p[6])


def son_istem_yolu(oturum):
    guvenli = re.sub(r"[^A-Za-z0-9_-]", "", oturum or "yok")[:64] or "yok"
    return DURUM / f"son-istem.{guvenli}"


def metin(olay, veri):
    if olay == "UserPromptSubmit":
        return veri.get("prompt", "")
    girdi = veri.get("tool_input") or {}
    if veri.get("tool_name") == "Bash":
        return girdi.get("command", "")
    if veri.get("tool_name") in ("Edit", "Write", "NotebookEdit"):
        return girdi.get("file_path", "")
    return json.dumps(girdi, ensure_ascii=False)


def duzeltme_yaz(veri):
    istem = veri.get("prompt", "")
    if "kasa" in istem.lower() or "🔐" in istem:
        return  # kasa içeriği deftere girmez
    sys.path.insert(0, str(KOK / ".claude" / "scripts"))
    import olaylar
    oturum = veri.get("session_id", "yok")
    ozet = hashlib.sha256(istem.encode("utf-8")).hexdigest()[:12]
    olaylar.yaz(KOK, "duzeltme", f"duzeltme:{oturum}:{ozet}",
                {"oturum": oturum, "metin": istem[:300]}, kaynak="ders-kapisi")


def main(olay):
    veri = json.load(sys.stdin)
    hedef = metin(olay, veri)
    arac = veri.get("tool_name", "-")
    if olay == "UserPromptSubmit":
        DURUM.mkdir(parents=True, exist_ok=True)
        son_istem_yolu(veri.get("session_id")).write_text(hedef[:2000], encoding="utf-8")
    notlar, karar_sor, karar_dur = [], [], []
    for r in satirlar():
        if r["olay"] != olay:
            continue
        if r["arac"] != "-" and not re.search(r["arac"], arac or ""):
            continue
        if r["karar"] == "sor-yoksa":
            yol = son_istem_yolu(veri.get("session_id"))
            son = yol.read_text(encoding="utf-8") if yol.exists() else ""
            if not r["kalip"].search(son):
                karar_sor.append(r["mesaj"])
            continue
        if not r["kalip"].search(hedef):
            continue
        if r["karar"] == "olay":
            try:
                duzeltme_yaz(veri)
            except Exception:
                pass
            notlar.append(r["mesaj"])
        elif r["karar"] == "dur":
            karar_dur.append(r["mesaj"])
        elif r["karar"] == "sor":
            karar_sor.append(r["mesaj"])
        else:
            notlar.append(r["mesaj"])
    cikti = {}
    if olay == "PreToolUse" and (karar_dur or karar_sor):
        cikti = {"hookSpecificOutput": {
            "hookEventName": "PreToolUse",
            "permissionDecision": "deny" if karar_dur else "ask",
            "permissionDecisionReason": "[Ders] " + " · ".join(karar_dur or karar_sor)}}
    elif notlar and olay in ("UserPromptSubmit", "PostToolUse"):
        cikti = {"hookSpecificOutput": {"hookEventName": olay,
                                        "additionalContext": "[Ders] " + " · ".join(notlar)}}
    if cikti:
        print(json.dumps(cikti, ensure_ascii=False))
    return 0


if __name__ == "__main__":
    if os.environ.get("BEYIN_INVOKED_BY"):
        sys.exit(0)
    try:
        sys.exit(main(sys.argv[1] if len(sys.argv) > 1 else ""))
    except Exception:
        sys.exit(0)
