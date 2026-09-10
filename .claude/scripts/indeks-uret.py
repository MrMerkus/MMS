#!/usr/bin/env python3
"""İndeks taslağı üretir. Kararı insana bırakır, yazımı üstlenir.

Neden var: "İndeks satırını yazan taraf yazar" kuralı, sistemin kendi tezine
("kural yeterli değildir") aykırıydı. Bu script tutarsızlığı kapatır.

Neden taslak: indeks satırının "ne zaman aç" sütunu bir yargıdır, script
üretemez. Bu yüzden elle yazılmış açıklamalar KORUNUR, yalnızca eksik satırlar
eklenir ve silinen dosyaların satırları çıkarılır.

Kullanım:
  indeks-uret.py "🔮 zihin/kalan-isler"          # yaz
  indeks-uret.py "🔮 zihin/kalan-isler" --dene   # yalnızca farkı göster
"""
import re
import sys
from pathlib import Path

ONCELIK = {"🟡": 0, "🟢": 1, "⚪": 2, "🔴": 3, "✅": 4}


def frontmatter(metin):
    m = re.match(r"^---\n(.*?)\n---\n", metin, re.S)
    if not m:
        return {}
    alan = {}
    for satir in m.group(1).splitlines():
        if ":" in satir:
            k, v = satir.split(":", 1)
            alan[k.strip()] = v.strip().strip('"')
    return alan


def durum_satiri(metin):
    m = re.search(r"^\*\*Status:\*\*\s*(.+)$", metin, re.M)
    return m.group(1).strip() if m else ""


def kisalt(s, n=78):
    s = re.sub(r"^[🟢🟡🔴⚪✅]\s*", "", s)
    s = re.sub(r":\s*20\d\d-\d\d-\d\d.*$", "", s).strip().rstrip(".")
    return s[: n - 1].rsplit(" ", 1)[0] + "…" if len(s) > n else s


def bol(baslik):
    """Başlığı (ad, konu) olarak ayır. İki ayraç desteklenir:
    '2026-09-09 — Konu'  ve  'Session: 2026-09-09 (üçüncü): Konu'."""
    if "—" in baslik:
        a, k = baslik.split("—", 1)
        return a.strip(), k.strip()
    m = re.match(r"^Session:\s*(.+?):\s*(.+)$", baslik)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return baslik.strip(), ""


def kisa_ad(baslik):
    return bol(baslik)[0]


def konu(baslik, metin):
    """Başlıkta konu yoksa gövdenin ilk anlamlı cümlesine düş.
    Çıplak bağlantı yasak olduğu için indeks satırı boş bırakılamaz."""
    k = bol(baslik)[1]
    if k:
        return k
    govde = re.sub(r"^---\n.*?\n---\n", "", metin, flags=re.S)
    govde = re.sub(r"^#.*$", "", govde, flags=re.M)
    for satir in govde.splitlines():
        t = re.sub(r"[*_`\[\]]", "", satir).strip()
        if len(t) > 25:
            return t.split(". ")[0]
    return ""


def mevcut_aciklamalar(indeks: Path):
    """Elle yazılmış 'ne zaman aç' sütununu koru."""
    if not indeks.exists():
        return {}
    tut = {}
    for satir in indeks.read_text(encoding="utf-8").splitlines():
        m = re.match(r"^\|\s*\[\[([^\\\]|]+)", satir)
        if m:
            # Wikilink içindeki \| kaçışı sütun ayrımını bozar; kaçışsız | ile böl.
            sutunlar = [s.strip() for s in re.split(r"(?<!\\)\|", satir.strip())]
            sutunlar = [s for s in sutunlar if s != ""]
            # "—" bir açıklama değil, açıklamanın yokluğudur; korunmaz.
            if len(sutunlar) >= 3 and sutunlar[2] not in ("—", "-", ""):
                tut[m.group(1)] = sutunlar[2]
    return tut


def uret(klasor: Path):
    indeks = klasor / "INDEKS.md"
    korunan = mevcut_aciklamalar(indeks)
    satirlar = []
    for f in sorted(klasor.glob("*.md")):
        if f.name == "INDEKS.md":
            continue
        metin = f.read_text(encoding="utf-8")
        fm = frontmatter(metin)
        # Arşiv dosyaları açık iş değildir; üst dosyalarından bağlantıyla ulaşılır.
        if fm.get("type") == "gecmis" or fm.get("durum") == "arşiv":
            continue
        baslik = fm.get("title", f.stem)
        durum = durum_satiri(metin)
        renk = next((c for c in "🟡🟢🔴⚪✅" if c in durum), "⚪")
        # Elle yazılmış açıklama varsa korunur. Yoksa sırayla: Status satırı,
        # sonra başlığın "—" sonrası (günlük/oturum dosyalarının konusu orada).
        # Çıplak bağlantı yasak olduğu için "—" son çaredir.
        aciklama = korunan.get(f.stem) or kisalt(durum) or kisalt(konu(baslik, metin)) or "—"
        satirlar.append((renk, kisa_ad(baslik), f.stem, aciklama, len(metin.split())))
    satirlar.sort(key=lambda s: (ONCELIK.get(s[0], 9), -s[4]))
    return satirlar


def yaz(klasor: Path, satirlar, baslik, giris):
    g = ["---", f"title: {baslik}", "type: indeks", "---", "", f"# {baslik}", ""]
    g += giris + ["", "| Konu | Durum | Ne zaman aç |", "| --- | --- | --- |"]
    for renk, ad, stem, aciklama, kelime in satirlar:
        isaret = " ⚠️" if kelime > 500 else ""
        g.append(f"| [[{stem}\\|{ad}]]{isaret} | {renk} | {aciklama} |")
    if any(k > 500 for *_, k in satirlar):
        g += ["", "⚠️ = 500 kelimeyi aşıyor; bölme sinyali verdi.", ""]
    else:
        g += [""]
    (klasor / "INDEKS.md").write_text("\n".join(g), encoding="utf-8")


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    klasor = Path(sys.argv[1])
    dene = "--dene" in sys.argv
    if not klasor.is_dir():
        print(f"klasör yok: {klasor}")
        return 1

    eski = set(mevcut_aciklamalar(klasor / "INDEKS.md"))
    satirlar = uret(klasor)
    yeni = {s[2] for s in satirlar}

    eklenen, cikan = yeni - eski, eski - yeni
    for s in sorted(eklenen):
        print(f"  + {s}")
    for s in sorted(cikan):
        print(f"  - {s}")
    if not eklenen and not cikan:
        print("  (satır listesi değişmedi, durumlar tazelenecek)")

    if dene:
        print("kuru çalıştırma — yazılmadı")
        return 0

    yaz(
        klasor,
        satirlar,
        f"{klasor.name} — indeks",
        [
            f"{len(satirlar)} kayıt. Bu dosya bağlama otomatik girer, kayıtların **içeriği girmez**.",
            "Bir satır ilgini çekerse dosyayı aç. Tasarrufu yapan şey bölme değil, **açmama kararıdır**.",
            "",
            "Taslağı `.claude/scripts/indeks-uret.py` yazar; \"ne zaman aç\" sütununa elle yazılan",
            "açıklamalar korunur. Yargı insanda, yazım script'te.",
        ],
    )
    print(f"yazıldı: {klasor}/INDEKS.md ({len(satirlar)} satır)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
