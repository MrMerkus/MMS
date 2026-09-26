#!/usr/bin/env python3
"""Olay defteri (SOZLESME Karar 4): daily/olaylar/YYYY-AA.jsonl, yalnız eklenir.

Şartname: ~/ofis/ajans/seritler/2026-09-24-olay-defteri/emir.md. Düşman testleri:
testler-defter.sh. pano.md ve makbuz.md bağımsız kayıt değil, bu defterin yansımasıdır.

Kurallar kısaca: kimlik idempotency anahtarıdır; aynı kimlik + aynı hash tek satır kalır,
farklı hash çakışmadır ve hiçbir şey yazılmaz. Ekleme kilit altında tek write + fsync'tir.
\\n ile bitmeyen kuyruk kaydedilmemiş sayılır, kesilir ve parçası .state'e taşınır.
BEYIN_INVOKED_BY doluysa (şerit, iç çağrı) hiçbir şey yazılmaz: şerit oturum sayılmaz.
"""

from __future__ import annotations

import argparse
import datetime as dt
import hashlib
import json
import os
import re
import sys
import time
from pathlib import Path
from typing import Any, Iterator

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import _portalock  # noqa: E402

VARSAYILAN_KOK = Path(__file__).resolve().parent.parent.parent
TIPLER = ("oturum", "serit", "derleme", "yedek", "makbuz", "jev", "duzeltme")
SERIT_ASAMALARI = ("acildi", "kesildi", "teslim-edildi")
ALANLAR = {"v", "tip", "kimlik", "zaman", "kaynak", "veri", "hash"}
SATIR_TAVANI = 16 * 1024
KASA = "🔐 kasa"
GUVENLI_AD = re.compile(r"[A-Za-z0-9][A-Za-z0-9._-]*\Z")
PANO_NOTU = "> Bu dosya `daily/olaylar/` defterinden üretilir (`olaylar.py pano`). Elle yazma."


class OlayHatasi(Exception):
    """Üreticilerin tek yakalaması gereken üst sınıf."""


class GecersizOlay(OlayHatasi):
    pass


class Cakisma(OlayHatasi):
    pass


class Reddedildi(OlayHatasi):
    pass


def _kanonik(nesne: Any) -> str:
    return json.dumps(nesne, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def olay_hash(tip: Any, kimlik: Any, veri: Any) -> str:
    # zaman ve kaynak dışarıda: aynı olayın yeniden denenmesi başka saatte gelir.
    govde = _kanonik({"kimlik": kimlik, "tip": tip, "veri": veri})
    return "sha256:" + hashlib.sha256(govde.encode("utf-8")).hexdigest()


def _metinler(deger: Any) -> Iterator[str]:
    if isinstance(deger, dict):
        for anahtar, alt in deger.items():
            yield str(anahtar)
            yield from _metinler(alt)
    elif isinstance(deger, list):
        for alt in deger:
            yield from _metinler(alt)
    elif isinstance(deger, str):
        yield deger


def _zaman(zaman: str | None) -> tuple[str, dt.datetime]:
    if zaman is None:
        simdi = dt.datetime.now().astimezone()
        return simdi.isoformat(timespec="seconds"), simdi
    try:
        cozulen = dt.datetime.fromisoformat(zaman)
    except (TypeError, ValueError) as exc:
        raise GecersizOlay(f"zaman-gecersiz:{zaman}") from exc
    if cozulen.tzinfo is None:
        raise GecersizOlay("zaman-ofsetsiz")
    return zaman, cozulen


def _dogrula_girdi(tip: str, kimlik: str, veri: Any, kaynak: Any) -> None:
    if tip not in TIPLER:
        raise GecersizOlay(f"bilinmeyen-tip:{tip}")
    if not isinstance(kimlik, str) or not kimlik.startswith(f"{tip}:") or kimlik == f"{tip}:":
        raise GecersizOlay("kimlik-oneki-yanlis")
    if tip == "serit" and kimlik.rsplit(":", 1)[-1] not in SERIT_ASAMALARI:
        raise GecersizOlay("serit-asamasi-yanlis")
    if not isinstance(veri, dict):
        raise GecersizOlay("veri-nesne-degil")
    if not isinstance(kaynak, str):
        raise GecersizOlay("kaynak-metin-degil")
    if any(KASA in metin for metin in _metinler(veri)):
        raise GecersizOlay("kasa-yolu")


def _onceki_ay(ay: str) -> str:
    yil, no = (int(p) for p in ay.split("-"))
    return f"{yil - 1}-12" if no == 1 else f"{yil}-{no - 1:02d}"


def _saglik_yaz(kok: Path, hata: str) -> None:
    """flush.write_health biçimi; raporlama hiçbir zaman yazımı düşürmez."""
    yol = kok / ".claude" / "scripts" / ".state" / "health.json"
    try:
        yuk: dict[str, Any] = {}
        if yol.exists():
            try:
                eski = json.loads(yol.read_text(encoding="utf-8"))
                if isinstance(eski, dict):
                    yuk.update(eski)
            except (OSError, ValueError):
                pass
        uyarilar = yuk.get("warnings", [])
        if not isinstance(uyarilar, list):
            uyarilar = []
        if hata not in uyarilar:
            uyarilar.append(hata)
        yuk.update({"ts": int(time.time()), "component": "olaylar", "error": hata,
                    "warnings": uyarilar[-20:]})
        _atomik_yaz(yol, json.dumps(yuk, ensure_ascii=False) + "\n")
    except OSError:
        pass


def _atomik_yaz(yol: Path, metin: str) -> bool:
    """Değişmediyse dokunmaz (mtime Farkındalık'ı boşuna uyandırmasın)."""
    try:
        if yol.read_text(encoding="utf-8") == metin:
            return False
    except (OSError, UnicodeError):
        pass
    yol.parent.mkdir(parents=True, exist_ok=True)
    gecici = yol.with_name(f".{yol.name}.{os.getpid()}.tmp")
    try:
        gecici.write_text(metin, encoding="utf-8")
        os.replace(gecici, yol)
    finally:
        try:
            gecici.unlink()
        except FileNotFoundError:
            pass
    return True


def _kirik_kuyrugu_kes(kok: Path, hedef: Path) -> None:
    # Bir satır \n yazılmadan kaydedilmiş sayılmaz: yarım parça kayıt değildir.
    ham = hedef.read_bytes()
    if not ham or ham.endswith(b"\n"):
        return
    kesim = ham.rfind(b"\n") + 1
    durum = kok / ".claude" / "scripts" / ".state"
    durum.mkdir(parents=True, exist_ok=True)
    parca = durum / f"olaylar-kirik-{int(time.time())}-{os.getpid()}.parca"
    parca.write_bytes(hedef.name.encode("utf-8") + b"\n" + ham[kesim:])
    os.truncate(hedef, kesim)
    _saglik_yaz(kok, "olaylar-kirik-kuyruk")


def _satirlar(yol: Path) -> Iterator[dict[str, Any]]:
    if not yol.exists():
        return
    for satir in yol.read_text(encoding="utf-8", errors="replace").splitlines():
        try:
            nesne = json.loads(satir)
        except ValueError:
            continue
        if isinstance(nesne, dict):
            yield nesne


def yaz(
    kok: Path | str,
    tip: str,
    kimlik: str,
    veri: dict[str, Any],
    zaman: str | None = None,
    kaynak: str = "",
) -> str:
    """Olayı deftere ekler. "yazildi" ya da "zaten-var" döner."""
    kok = Path(kok)
    cagiran = os.environ.get("BEYIN_INVOKED_BY")
    if cagiran:
        raise Reddedildi(f"BEYIN_INVOKED_BY={cagiran}")
    _dogrula_girdi(tip, kimlik, veri, kaynak)
    zaman_metni, cozulen = _zaman(zaman)
    ozet = olay_hash(tip, kimlik, veri)
    satir = _kanonik({"v": 1, "tip": tip, "kimlik": kimlik, "zaman": zaman_metni,
                      "kaynak": kaynak, "veri": veri, "hash": ozet}) + "\n"
    ham = satir.encode("utf-8")
    if len(ham) > SATIR_TAVANI:
        raise GecersizOlay("satir-tavani")

    dizin = kok / "daily" / "olaylar"
    dizin.mkdir(parents=True, exist_ok=True)
    ay = cozulen.strftime("%Y-%m")
    hedef = dizin / f"{ay}.jsonl"
    with (dizin / ".kilit").open("a+", encoding="utf-8") as kilit, _portalock.exclusive(kilit):
        if hedef.exists():
            _kirik_kuyrugu_kes(kok, hedef)
        for dosya in (dizin / f"{_onceki_ay(ay)}.jsonl", hedef):
            for eski in _satirlar(dosya):
                if eski.get("kimlik") != kimlik:
                    continue
                if eski.get("hash") == ozet:
                    return "zaten-var"
                raise Cakisma(kimlik)
        tanimlayici = os.open(hedef, os.O_WRONLY | os.O_APPEND | os.O_CREAT, 0o644)
        try:
            yazilan = 0
            while yazilan < len(ham):
                yazilan += os.write(tanimlayici, ham[yazilan:])
            os.fsync(tanimlayici)
        finally:
            os.close(tanimlayici)
    return "yazildi"


def dogrula(kok: Path) -> list[str]:
    sorunlar: list[str] = []
    gorulen: set[str] = set()
    for dosya in sorted((kok / "daily" / "olaylar").glob("*.jsonl")):
        ham = dosya.read_bytes()
        satirlar = ham.decode("utf-8", errors="replace").split("\n")
        if ham and not ham.endswith(b"\n"):
            sorunlar.append(f"{dosya.name}:{len(satirlar)} \\n ile bitmiyor")
        for no, satir in enumerate(satirlar[:-1] if ham.endswith(b"\n") else satirlar, 1):
            try:
                nesne = json.loads(satir)
            except ValueError:
                sorunlar.append(f"{dosya.name}:{no} ayrıştırılamıyor")
                continue
            if not isinstance(nesne, dict) or set(nesne) != ALANLAR:
                sorunlar.append(f"{dosya.name}:{no} alanlar eksik ya da fazla")
                continue
            if nesne["hash"] != olay_hash(nesne["tip"], nesne["kimlik"], nesne["veri"]):
                sorunlar.append(f"{dosya.name}:{no} hash tutmuyor")
            if nesne["kimlik"] in gorulen:
                sorunlar.append(f"{dosya.name}:{no} kimlik tekrarı")
            gorulen.add(nesne["kimlik"])
    return sorunlar


def _an(nesne: dict[str, Any]) -> float:
    try:
        return dt.datetime.fromisoformat(nesne["zaman"]).timestamp()
    except (KeyError, TypeError, ValueError):
        return 0.0


def _hucre(deger: Any) -> str:
    return str(deger if deger is not None else "").replace("|", "\\|").replace("\n", " ")


def pano(kok: Path, ajans: Path) -> None:
    olaylar: list[dict[str, Any]] = []
    for dosya in sorted((kok / "daily" / "olaylar").glob("*.jsonl")):
        olaylar.extend(o for o in _satirlar(dosya) if isinstance(o.get("veri"), dict))
    olaylar.sort(key=_an)  # kararlı sıralama: aynı anda dosya sırası korunur

    seritler: dict[str, dict[str, Any]] = {}
    makbuzlar: dict[str, dict[str, Any]] = {}
    for olay in olaylar:
        veri = olay["veri"]
        ad = veri.get("serit")
        if not isinstance(ad, str) or not GUVENLI_AD.fullmatch(ad):
            continue
        if olay.get("tip") == "serit":
            kayit = seritler.setdefault(ad, {"acilis": _an(olay)})
            for alan in ("proje", "rol", "ajan"):
                if veri.get(alan) and not kayit.get(alan):
                    kayit[alan] = veri[alan]
            kayit["durum"] = str(olay.get("kimlik", "")).rsplit(":", 1)[-1]
        elif olay.get("tip") == "makbuz":
            makbuzlar[ad] = olay

    acik = sorted((a for a in seritler if a not in makbuzlar), key=lambda a: seritler[a]["acilis"])
    teslim = sorted(makbuzlar, key=lambda a: _an(makbuzlar[a]), reverse=True)[:10]
    satirlar = ["# Pano", "", PANO_NOTU, "", "## Açık", "",
                "| Şerit | Proje | Rol | Ajan | Durum |", "| --- | --- | --- | --- | --- |"]
    for ad in acik:
        s = seritler[ad]
        satirlar.append("| " + " | ".join(_hucre(x) for x in (
            ad, s.get("proje"), s.get("rol"), s.get("ajan"), s.get("durum"))) + " |")
    satirlar += ["", "## Teslim (son 10)", "", "| Şerit | Makbuz | Tarih |", "| --- | --- | --- |"]
    for ad in teslim:
        m = makbuzlar[ad]
        satirlar.append(f"| {_hucre(ad)} | {_hucre(m['veri'].get('sonuc'))} | {_hucre(str(m.get('zaman', ''))[:10])} |")
    _atomik_yaz(ajans / "pano.md", "\n".join(satirlar) + "\n")

    for ad, m in makbuzlar.items():
        klasor = ajans / "seritler" / ad
        if not klasor.is_dir():
            continue
        v = m["veri"]
        _atomik_yaz(klasor / "makbuz.md", (
            f"# Makbuz: {ad}\n\n"
            f"- Sonuç: **{v.get('sonuc', '')}**\n"
            f"- Tarih: {m.get('zaman', '')}\n"
            f"- Ölçüm: {v.get('olcum', '')}\n"
            f"- Oturum: {v.get('oturum', '')}\n\n"
            f"{v.get('ozet', '')}\n\n{PANO_NOTU}\n"))


def _ajans_yolu(verilen: str | None) -> Path:
    if verilen:
        return Path(verilen)
    ortam = os.environ.get("BEYIN_AJANS_DIR")
    return Path(ortam) if ortam else Path.home() / "ofis" / "ajans"


def main(argv: list[str] | None = None) -> int:
    ayristirici = argparse.ArgumentParser(description="Olay defteri")
    ayristirici.add_argument("--kok", type=Path, default=VARSAYILAN_KOK)
    alt = ayristirici.add_subparsers(dest="komut", required=True)
    y = alt.add_parser("yaz")
    y.add_argument("--tip", required=True)
    y.add_argument("--kimlik", required=True)
    y.add_argument("--veri", default="{}")
    y.add_argument("--zaman")
    y.add_argument("--kaynak", default="")
    for ad in ("dogrula", "pano"):
        p = alt.add_parser(ad)
        if ad == "pano":
            p.add_argument("--ajans")
    for p in alt.choices.values():
        p.add_argument("--kok", type=Path, default=argparse.SUPPRESS)
    try:
        args = ayristirici.parse_args(argv)
    except SystemExit as exc:
        return 2 if exc.code else 0

    if args.komut == "dogrula":
        sorunlar = dogrula(args.kok)
        for sorun in sorunlar:
            print(sorun)
        return 1 if sorunlar else 0
    if args.komut == "pano":
        try:
            pano(args.kok, _ajans_yolu(args.ajans))
        except OSError as exc:
            print(f"pano yazılamadı: {exc}", file=sys.stderr)
            return 1
        return 0
    try:
        veri = json.loads(args.veri)
        sonuc = yaz(args.kok, args.tip, args.kimlik, veri, args.zaman, args.kaynak)
    except (ValueError, GecersizOlay) as exc:
        print(f"geçersiz olay: {exc}", file=sys.stderr)
        return 2
    except Cakisma as exc:
        print(f"çakışma: {exc}", file=sys.stderr)
        return 3
    except Reddedildi as exc:
        print(f"reddedildi: {exc}", file=sys.stderr)
        return 4
    print(f"{sonuc} {args.kimlik}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
