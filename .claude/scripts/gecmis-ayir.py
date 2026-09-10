#!/usr/bin/env python3
"""Bir konu dosyasındaki <details> arşiv bloğunu alt dosyaya taşır.

Neden var: 500 kelimeyi aşan dosyaların çoğunda sorun "uzun bir hikâye" değil,
ESKİ oturumların üst üste yığılmasıydı — Threads.md hastalığının dosya
ölçeğinde tekrarı. Katlanmış <details> bloğu kelimeleri saklıyor ama
kaldırmıyor; dosya yine şişik, tavan yine aşılıyor.

Ne yapar: <details> bloğunu <slug>-gecmis.md dosyasına taşır, yerine
ÇIPLAK OLMAYAN bir bağlantı bırakır (ne olduğu + ne zaman açılacağı).
Üst dosya kendi başına eksiksiz cevap olarak kalır.

Ne yapmaz: yargı gerektiren bölmeyi yapmaz. Yalnızca açıkça arşiv diye
işaretlenmiş bloğu taşır. İşaret yoksa dokunmaz.

Kullanım: gecmis-ayir.py <dosya.md> [--dene]
"""
import re
import sys
from pathlib import Path


def kelime(m):
    return len(re.sub(r"^---\n.*?\n---\n", "", m, flags=re.S).split())


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    f = Path(sys.argv[1])
    dene = "--dene" in sys.argv
    if not f.is_file():
        print(f"dosya yok: {f}")
        return 1

    metin = f.read_text(encoding="utf-8")
    # Birden fazla arşiv bloğu olabilir (her oturum bir katman eklemiş);
    # hepsi toplanır, sırası korunur.
    bloklar = list(re.finditer(r"\n<details>.*?</details>\s*", metin, re.S))
    if not bloklar:
        print(f"  arşiv bloğu yok, dokunulmadı: {f.name}")
        return 0

    ic = "\n\n".join(
        re.sub(r"</?details>|<summary>.*?</summary>", "", b.group(0), flags=re.S).strip()
        for b in bloklar
    )

    baslik = re.search(r"^title: (.+)$", metin, re.M)
    baslik = baslik.group(1).strip('"') if baslik else f.stem
    hedef = f.with_name(f.stem + "-gecmis.md")

    onceki = kelime(metin)
    # Blokları sondan başa sil ki konumlar kaymasın, sonra tek bağlantı ekle.
    yeni_metin = metin
    for b in reversed(bloklar):
        yeni_metin = yeni_metin[: b.start()] + "\n" + yeni_metin[b.end():]
    yeni_metin = yeni_metin.rstrip() + (
        f"\n\n**Geçmiş:** [[{hedef.stem}|önceki oturumların kaydı]] — bu konunun daha eski "
        f"durumları ve kapanmış kararları. Yalnızca \"bu karar ne zaman, neden alınmıştı\" "
        f"sorulursa aç.\n")
    sonraki = kelime(yeni_metin)

    print(f"  {f.name}: {onceki} -> {sonraki} kelime "
          f"({kelime(ic)} kelime {hedef.name} dosyasına taşınıyor)")
    if dene:
        return 0

    hedef.write_text(
        f"---\ntitle: {baslik} — geçmiş\ntype: gecmis\ndurum: arşiv\n---\n\n"
        f"# {baslik} — geçmiş\n\n"
        f"Bu konunun önceki oturumlardaki durumları. Güncel hâli: [[{f.stem}|konunun kendisi]].\n\n"
        f"{ic}\n", encoding="utf-8")
    f.write_text(yeni_metin, encoding="utf-8")
    return 0


if __name__ == "__main__":
    sys.exit(main())
