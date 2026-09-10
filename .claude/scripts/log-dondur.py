#!/usr/bin/env python3
"""Derleme günlüğünü yıla göre döndürür.

Neden var: knowledge/log.md ekleme-yapılan bir kayıttır ve 500 kelime tavanından
bilerek muaftır — çünkü tavan diski değil BAĞLAMI korur, bu dosya ise hiçbir
oturumda bağlama girmez. Ama muafiyet sınırsız büyüme demek değildi: derleyici
her çalıştığında bu dosyayı açıp sonuna ekliyor, yani birikmiş her satırın bir
derleme maliyeti var. Muafiyet vardı, sınır yoktu.

Ne yapar: geçmiş yılların girdilerini log-<yıl>.md dosyalarına taşır, içinde
bulunulan yılın girdilerini log.md'de bırakır. Silmez, taşır — kapanış
döngüsünün (kapanis.sh) takvimle çalışan kardeşi.

Kullanım: log-dondur.py [--dene]
"""
import datetime as dt
import re
import sys
from pathlib import Path

# Bir yıl içinde bile aşırı birikme olursa haber ver: yıllık döndürme tek başına
# yetmeyebilir (günde 2 derleme = yılda ~700 girdi).
UYARI_ESIGI = 400


def main():
    dene = "--dene" in sys.argv
    kok = Path(__file__).resolve().parents[2]
    log = kok / "knowledge" / "log.md"
    if not log.is_file():
        print("knowledge/log.md yok, yapacak bir şey yok")
        return 0

    metin = log.read_text(encoding="utf-8")
    parcalar = re.split(r"(?m)^(## \[(\d{4})-\d{2}-\d{2}T[^\]]*\][^\n]*)$", metin)
    if len(parcalar) < 4:
        print("girdi bulunamadı (biçim beklenenden farklı), dokunulmadı")
        return 0

    bas = parcalar[0]
    girdiler = []
    for i in range(1, len(parcalar), 3):
        girdiler.append((parcalar[i + 1], parcalar[i] + parcalar[i + 2]))

    bu_yil = str(dt.date.today().year)
    kalan = [(y, g) for y, g in girdiler if y == bu_yil]
    tasinacak = {}
    for y, g in girdiler:
        if y != bu_yil:
            tasinacak.setdefault(y, []).append(g)

    if not tasinacak:
        print(f"döndürülecek yıl yok — {len(kalan)} girdinin hepsi {bu_yil} yılından")
        if len(kalan) >= UYARI_ESIGI:
            print(f"UYARI: {bu_yil} günlüğü {len(kalan)} girdiye ulaştı "
                  f"({UYARI_ESIGI} eşiği aşıldı). Yıl içi bölme düşünülmeli.")
        return 0

    for yil, bloklar in sorted(tasinacak.items()):
        hedef = kok / "knowledge" / f"log-{yil}.md"
        print(f"  {yil}: {len(bloklar)} girdi -> knowledge/{hedef.name}")
        if dene:
            continue
        mevcut = hedef.read_text(encoding="utf-8") if hedef.exists() else (
            f"# Derleme Günlüğü — {yil} (arşiv)\n\n"
            f"Bu dosya `knowledge/log.md`'den döndürülmüştür. Güncel günlük orada.\n"
            f"Bağlama girmez; yalnızca \"o tarihte ne derlendi\" sorulursa açılır.\n"
        )
        hedef.write_text(mevcut.rstrip() + "\n\n" + "".join(bloklar).strip() + "\n",
                         encoding="utf-8")

    if dene:
        print("kuru çalıştırma — yazılmadı")
        return 0

    log.write_text(bas.rstrip() + "\n\n" + "".join(g for _, g in kalan).strip() + "\n",
                   encoding="utf-8")
    print(f"log.md'de {len(kalan)} girdi kaldı ({bu_yil})")
    return 0


if __name__ == "__main__":
    sys.exit(main())
