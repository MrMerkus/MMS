#!/usr/bin/env python3
"""Kavram çıkarımının deterministik yarısı: hangi gün bekliyor, derleme nasıl kaydedilir.

Yargı (hangi kavram, ne yazılır) `derle` skill'inde ana döngüdedir; bu script yalnız
sayar ve kaydeder. Model çağrısı yok, ağ yok.

  derle.py bekleyen [--bugun]
      Projeksiyon işareti taşıyan ve bu içerikle kavram çıkarımı görmemiş daily günleri.
      Satır biçimi: "<gün> <digest12> <oturum-sayısı>". Bugün varsayılan olarak hariç:
      gün bitmeden içerik değişir, yarım günü derlemek ertesi gün tekrar ettirir.
  derle.py kaydet --gun <gün> --digest <digest12> [--olusturulan a,b] [--guncellenen c]
                  --not "<2-3 cümle>"
      Deftere derleme:<gün>.md:<digest12>:kavram yazar, knowledge/log.md'ye
      "derleme | <gün>.md" bloğu ekler. Daily okunduktan sonra değiştiyse (digest tutmuyorsa)
      reddeder: eski içerikten çıkarılan kavram yeni günü kapatmış sayılmaz.

Bekleme ölçütü dosya içeriğidir: sha256(daily)[:12] ile eşleşen `kavram` satırı yoksa gün
bekliyor. Projektör aynı digest'i kullanır (derleme:<gün>.md:<digest12>:ok). İşaretsiz daily
geçiş öncesinin tarihidir; eski compile.py derlemişti, dokunulmaz. Düşman testleri: testler-derle.sh.
"""
import argparse
import datetime as dt
import hashlib
import re
import sys
from pathlib import Path

sys.dont_write_bytecode = True
sys.path.insert(0, str(Path(__file__).resolve().parent))
import olaylar  # noqa: E402

KOK = Path(__file__).resolve().parent.parent.parent
ISARET = "<!-- projeksiyon: daily/olaylar -->"
GUN = re.compile(r"\d{4}-\d\d-\d\d\Z")
SLUG = re.compile(r"[a-z0-9]+(?:-[a-z0-9]+)*\Z")


def _kimlik(gun, digest):
    return f"derleme:{gun}.md:{digest}:kavram"


def _kimlikler(kok):
    k = set()
    for dosya in sorted((kok / "daily" / "olaylar").glob("*.jsonl")):
        k.update(str(o.get("kimlik")) for o in olaylar._satirlar(dosya) if o.get("tip") == "derleme")
    return k


def _digest(yol):
    return hashlib.sha256(yol.read_bytes()).hexdigest()[:12]


def bekleyen(kok, bugun_dahil=False):
    bugun = dt.date.today().isoformat()
    gorulen = _kimlikler(kok)
    sonuc = []
    for yol in sorted((kok / "daily").glob("*.md")):
        gun = yol.stem
        if not GUN.match(gun) or (gun >= bugun and not bugun_dahil):
            continue
        try:
            metin = yol.read_text(encoding="utf-8")
        except (OSError, UnicodeError):
            continue
        if ISARET not in metin.split("\n", 2)[:2]:
            continue
        d = _digest(yol)
        if _kimlik(gun, d) not in gorulen:
            sonuc.append((gun, d, metin.count("\n### Oturum")))
    return sonuc


def kaydet(kok, gun, digest, olusturulan, guncellenen, notu):
    if not GUN.match(gun):
        raise ValueError(f"gün biçimi: {gun}")
    yol = kok / "daily" / f"{gun}.md"
    if not yol.exists():
        raise ValueError(f"daily yok: {gun}")
    if _digest(yol) != digest:
        raise ValueError(f"digest tutmuyor: daily okunduktan sonra değişti ({digest} ≠ {_digest(yol)})")
    for s in olusturulan + guncellenen:
        if not SLUG.match(s):
            raise ValueError(f"slug ASCII kebab-case değil: {s}")
    if not notu.strip():
        raise ValueError("not boş")
    simdi = dt.datetime.now().astimezone().isoformat(timespec="seconds")
    sonuc = olaylar.yaz(kok, "derleme", _kimlik(gun, digest),
                        {"daily": f"daily/{gun}.md", "digest": digest, "durum": "ok", "detay": "kavram",
                         "olusturulan": olusturulan, "guncellenen": guncellenen},
                        zaman=simdi, kaynak="derle")
    if sonuc == "zaten-var":  # aynı derleme ikinci kez: log da tek blok kalır
        return sonuc
    log = kok / "knowledge" / "log.md"
    log.parent.mkdir(parents=True, exist_ok=True)
    liste = lambda xs: ", ".join(xs) if xs else "—"
    with log.open("a", encoding="utf-8") as akis:
        akis.write(f"\n## [{simdi}] derleme | {gun}.md\n\n**Oluşturulan:** {liste(olusturulan)}\n\n"
                   f"**Güncellenen:** {liste(guncellenen)}\n\n{notu.strip()}\n")
    return sonuc


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    p.add_argument("--kok", type=Path, default=KOK)
    alt = p.add_subparsers(dest="islem", required=True)
    b = alt.add_parser("bekleyen")
    b.add_argument("--bugun", action="store_true")
    k = alt.add_parser("kaydet")
    k.add_argument("--gun", required=True)
    k.add_argument("--digest", required=True)
    k.add_argument("--olusturulan", default="")
    k.add_argument("--guncellenen", default="")
    k.add_argument("--not", dest="notu", required=True)
    a = p.parse_args()
    if a.islem == "bekleyen":
        satirlar = bekleyen(a.kok, a.bugun)
        for gun, d, n in satirlar:
            print(f"{gun} {d} {n}")
        print(f"bekleyen: {len(satirlar)}")
        return 0
    bol = lambda s: [x.strip() for x in s.split(",") if x.strip()]
    try:
        print(kaydet(a.kok, a.gun, a.digest, bol(a.olusturulan), bol(a.guncellenen), a.notu))
    except (ValueError, olaylar.OlayHatasi) as h:
        print(f"derle: {h}", file=sys.stderr)
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
