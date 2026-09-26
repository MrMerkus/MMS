#!/usr/bin/env python3
"""Projektör (SOZLESME Karar 4, Organ 3): olay defterinden deterministik yansıma.

Şartname: ~/ofis/ajans/seritler/2026-09-24-projektor/emir.md. Düşman testleri:
testler-projektor.sh. Model çağrısı yok, ağ yok, alt süreç yok.

Bir gün için yapılan iş: o günün `oturum` olaylarından daily/<gün>.md üretilir
(flush'ın biçimiyle bayt bayt aynı, üstelik işaret satırı taşır). İçerik özeti yeniyse
knowledge/log.md'ye bir projeksiyon bloğu eklenir ve deftere `derleme:<gün>.md:<digest12>:ok`
yazılır. Ayrı bir durum dosyası yoktur, durum defterdedir. İşaretsiz daily geçiş
öncesinin tarihidir, ona dokunulmaz.

flush her oturumdan sonra `yansit_gun` ile bugünü, açılış `--hepsi` ile tüm günleri çağırır.
Kavram makaleleri (knowledge/concepts/) burada değil, ana döngüdeki `derle` skill'inde
(kullanıcının kararı D, 24 Eylül). compile.py emekli; arka planda model çağrısı yok.
"""

from __future__ import annotations

import argparse
import contextlib
import datetime as dt
import hashlib
import os
import sys
from pathlib import Path
from typing import Any, Iterator, Sequence

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import _portalock  # noqa: E402
import olaylar  # noqa: E402

VARSAYILAN_KOK = Path(__file__).resolve().parent.parent.parent
ISARET = "<!-- projeksiyon: daily/olaylar -->"
RECEIPT_DIR = ("🔮 zihin", "son-oturum")
MAX_FILE_LINES = 30
MAX_COMMAND_LINES = 20


def _madde_bolumu(items: Sequence[str], limit: int, bos: str, toplam: int | None = None) -> str:
    # flush._bullet_section ile aynı; toplam, kırpılmış listenin gerçek boyunu taşır.
    if not items:
        return bos
    satirlar = [f"- {item}" for item in items[:limit]]
    kalan = (toplam if toplam is not None else len(items)) - limit
    if kalan > 0:
        satirlar.append(f"- ... ve {kalan} tane daha")
    return "\n".join(satirlar)


def kayit_metni(veri: dict[str, Any]) -> str:
    """Oturum kaydı; flush.build_session_record ile bayt bayt aynı çıktı."""
    acilis = str(veri.get("acilis") or "")
    dosyalar = [str(x) for x in veri.get("dosyalar") or []]
    komutlar = [str(x) for x in veri.get("komutlar") or []]
    ozet = [str(x) for x in veri.get("ozet") or []]
    parcalar = [
        f"- Oturum kimliği: {str(veri.get('session_id', ''))[:8]}",
        f"- Tur sayısı: {veri.get('tur', 0)}",
        "- Kayıt türü: deterministik projeksiyon (model çağrısı yok)",
        "",
        "#### Açılış isteği",
        "",
        f"> {acilis}" if acilis else "> (kullanıcı turu yok)",
        "",
        "#### Dokunulan dosyalar",
        "",
        _madde_bolumu(dosyalar, MAX_FILE_LINES, "Dosya değişikliği yok.", veri.get("dosya_sayisi")),
    ]
    if komutlar:
        parcalar += ["", "#### Komutlar", "",
                     _madde_bolumu(komutlar, MAX_COMMAND_LINES, "", veri.get("komut_sayisi"))]
    parcalar += ["", "#### Ajan özeti", ""]
    if ozet:
        parcalar.append("\n".join(f"- [[{'/'.join(RECEIPT_DIR)}/{ad}]]" for ad in ozet))
    else:
        parcalar.append("Özet yok — bu oturumda aktif ajan devir izi yazmadı.")
    return "\n".join(parcalar) + "\n"


def _gunun_oturumlari(kok: Path) -> dict[str, list[dict[str, Any]]]:
    gunler: dict[str, list[dict[str, Any]]] = {}
    for dosya in sorted((kok / "daily" / "olaylar").glob("*.jsonl")):
        for olay in olaylar._satirlar(dosya):
            if olay.get("tip") != "oturum" or not isinstance(olay.get("veri"), dict):
                continue
            zaman = str(olay.get("zaman", ""))
            try:
                dt.datetime.fromisoformat(zaman)
            except ValueError:
                continue
            gunler.setdefault(zaman[:10], []).append(olay)
    for liste in gunler.values():
        liste.sort(key=olaylar._an)  # kararlı: aynı anda defter sırası korunur
    return gunler


def gun_metni(gun: str, oturumlar: Sequence[dict[str, Any]]) -> str:
    """flush._append_daily biçimi, başlıktan sonra işaret satırıyla."""
    metin = f"# Günlük Log: {gun}\n{ISARET}\n\n## Oturumlar\n"
    for olay in oturumlar:
        an = dt.datetime.fromisoformat(olay["zaman"])
        veri = olay["veri"]
        ek = ", compaction öncesi" if veri.get("sebep") == "precompact" else ""
        metin += f"\n### Oturum ({an.strftime('%H:%M')}){ek}\n\n{kayit_metni(veri)}\n"
    return metin


def _derleme_var(kok: Path, kimlik: str) -> bool:
    for dosya in (kok / "daily" / "olaylar").glob("*.jsonl"):
        if any(o.get("kimlik") == kimlik for o in olaylar._satirlar(dosya)):
            return True
    return False


def yansit(kok: Path, gun: str, oturumlar: Sequence[dict[str, Any]], dene: bool) -> str:
    hedef = kok / "daily" / f"{gun}.md"
    if hedef.exists():
        try:
            ilk = hedef.read_text(encoding="utf-8").split("\n", 2)[:2]
        except (OSError, UnicodeError):
            ilk = []
        if ISARET not in ilk:
            return f"atlandi {gun} isaretsiz"
    metin = gun_metni(gun, oturumlar)
    ozet = hashlib.sha256(metin.encode("utf-8")).hexdigest()
    kimlik = f"derleme:{gun}.md:{ozet[:12]}:ok"
    yeni_olay = not _derleme_var(kok, kimlik)
    try:
        dosya_ayni = hedef.read_text(encoding="utf-8") == metin
    except (OSError, UnicodeError):
        dosya_ayni = False
    if dosya_ayni and not yeni_olay:
        return f"degismedi {gun}"
    if dene:
        return f"yansitilacak {gun} (kuru çalıştırma, yazılmadı)"

    if not dosya_ayni:
        olaylar._atomik_yaz(hedef, metin)
    if yeni_olay:
        simdi = dt.datetime.now().astimezone().isoformat(timespec="seconds")
        dosya_sayisi = sum(len(o["veri"].get("dosyalar") or []) for o in oturumlar)
        log = kok / "knowledge" / "log.md"
        log.parent.mkdir(parents=True, exist_ok=True)
        with log.open("a", encoding="utf-8") as akis:
            akis.write(f"\n## [{simdi}] projeksiyon | {gun}.md\n\n"
                       f"- Oturum: {len(oturumlar)}\n- Dokunulan dosya: {dosya_sayisi}\n")
        olaylar.yaz(kok, "derleme", kimlik,
                    {"daily": f"daily/{gun}.md", "digest": ozet, "durum": "ok", "detay": "projeksiyon"},
                    zaman=simdi, kaynak="projektor.py")
    return f"yansitildi {gun}"


@contextlib.contextmanager
def _kilit(kok: Path) -> Iterator[None]:
    durum = kok / ".claude" / "scripts" / ".state"
    durum.mkdir(parents=True, exist_ok=True)
    with (durum / "projektor.lock").open("a+", encoding="utf-8") as kilit, \
            _portalock.exclusive(kilit):
        yield


def yansit_gun(kok: Path, gun: str, dene: bool = False) -> str:
    """Tek günü kilit altında yansıtır; flush bunu eşzamanlı çağırır."""
    with _kilit(kok):
        oturumlar = _gunun_oturumlari(kok).get(gun)
        return yansit(kok, gun, oturumlar, dene) if oturumlar else f"olay-yok {gun}"


def main(argv: list[str] | None = None) -> int:
    ayristirici = argparse.ArgumentParser(description="Olay defterinden deterministik yansıma")
    ayristirici.add_argument("--kok", type=Path, default=VARSAYILAN_KOK)
    secim = ayristirici.add_mutually_exclusive_group(required=True)
    secim.add_argument("--gun", type=dt.date.fromisoformat)
    secim.add_argument("--hepsi", action="store_true")
    ayristirici.add_argument("--dene", action="store_true")
    args = ayristirici.parse_args(argv)
    if os.environ.get("BEYIN_INVOKED_BY"):
        return 0  # şerit ve iç çağrılar beyne yazmaz

    kok = args.kok
    try:
        with _kilit(kok):
            gunler = _gunun_oturumlari(kok)
            secilen = sorted(gunler) if args.hepsi else [args.gun.isoformat()]
            for gun in secilen:
                if gun not in gunler:
                    print(f"olay-yok {gun}")
                    continue
                print(yansit(kok, gun, gunler[gun], args.dene))
    except (OSError, olaylar.OlayHatasi) as exc:
        olaylar._saglik_yaz(kok, f"projektor:{exc.__class__.__name__}")
        print(f"projektör hatası: {exc}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
