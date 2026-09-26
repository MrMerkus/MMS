#!/usr/bin/env python3
"""Bayat kayıt tarayıcısı: yerini almış bir ifade işaretsiz geçiyor mu?

Neden var: test günü (25 Eylül) 22 çelişki buldu; sistem bilgiyi buluyor ama
neyin güncel olduğunu korumuyordu. Kural: karar değişince eski kayda
"yerini aldı: <yeni>" yazılır ve eski ifade bayat-kaliplar.tsv'ye eklenir.
Bu script işaretsiz kalanı bulur; denetci.sh çağırır.

Tarihî kayıtlar taranmaz, o günün gerçeğidir: son-oturum, defter, daily,
arşiv, knowledge, reports, *-gecmis.md. Kasa hiç okunmaz.

Kullanım: bayat-tara.py [--kaliplar dosya] <kök|dosya>...   çıkış 1 = bulgu var
"""
import re
import sys
from pathlib import Path

ISARET = re.compile(r"yerini aldı|~~|emekli|bırakıldı|geçersiz|DEPRECATED", re.I)
ATLA = {"son-oturum", "defter", "daily", "📦 bitmiş olanlar", "knowledge",
        "reports", ".git", "node_modules", "🔐 kasa", ".state", "tests"}


def kaliplar(yol):
    for satir in Path(yol).read_text(encoding="utf-8").splitlines():
        if not satir.strip() or satir.startswith("#"):
            continue
        k, guncel = (satir.split("\t") + [""])[:2]
        yield re.compile(k), guncel


def dosyalar(kok):
    kok = Path(kok)
    adaylar = [kok] if kok.is_file() else sorted(kok.rglob("*.md"))
    for f in adaylar:
        if ATLA & set(f.parts) or f.name.endswith("-gecmis.md"):
            continue
        yield f


def main(argv):
    kf = Path(__file__).with_name("bayat-kaliplar.tsv")
    if argv[:1] == ["--kaliplar"]:
        kf, argv = Path(argv[1]), argv[2:]
    kl = list(kaliplar(kf))
    bulgu = 0
    for kok in argv:
        for f in dosyalar(kok):
            try:
                satirlar = f.read_text(encoding="utf-8").splitlines()
            except (OSError, UnicodeDecodeError):
                continue
            for no, s in enumerate(satirlar, 1):
                if ISARET.search(s):
                    continue
                for k, guncel in kl:
                    if k.search(s):
                        print(f"{f}:{no}: '{k.pattern}' → {guncel}")
                        bulgu += 1
                        break
    return 1 if bulgu else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
