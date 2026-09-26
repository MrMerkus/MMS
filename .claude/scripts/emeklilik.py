#!/usr/bin/env python3
"""Emeklilik (organ 4): uzun süre dokunulmamış kalan-işi enjeksiyondan düşürür.

SOZLESME Karar 1: düşmek silmek değildir; otomatik ve geri alınabilir. Kararın
kuralı indeks-uret.py içindedir (tek yazıcı odur, tek başına çalışınca da soğuk
satır geri dönmez). Bu script o kuralın kapısıdır: önizler, uygular, geri alır.

Kullanım:
  emeklilik.py [klasör] [--dene] [--gun N] [--geri <ad>]
    klasör     varsayılan: "🔮 zihin/kalan-isler" (vault köküne göre)
    --dene     neyin soğuyacağını yazar, hiçbir dosyaya dokunmaz
    --gun N    soğuma eşiği (varsayılan 30)
    --geri ad  kaydı geri getirir: dosyaya dokunur ve indeksi yeniden üretir

Tetik: kapanis.sh (oturum sonu).
"""
import importlib.util
import os
import subprocess
import sys
from datetime import date
from pathlib import Path

BURASI = Path(__file__).resolve().parent
KOK = BURASI.parent.parent


def indeks_uret_modulu():
    spec = importlib.util.spec_from_file_location("indeks_uret", BURASI / "indeks-uret.py")
    mod = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(mod)
    return mod


def uret(klasor: Path):
    r = subprocess.run([sys.executable, str(BURASI / "indeks-uret.py"), str(klasor)],
                       capture_output=True, text=True)
    return r.returncode


def main():
    arg = sys.argv[1:]
    dene = "--dene" in arg
    gun = geri = None
    if "--gun" in arg:
        gun = arg[arg.index("--gun") + 1]
    if "--geri" in arg:
        geri = arg[arg.index("--geri") + 1]
    atla = {gun, geri}
    konum = [a for a in arg if not a.startswith("--") and a not in atla]
    klasor = Path(konum[0]) if konum else KOK / "🔮 zihin" / "kalan-isler"
    if not klasor.is_dir():
        print(f"klasör yok: {klasor}")
        return 1
    if gun:
        os.environ["BEYIN_EMEKLILIK_GUN"] = str(int(gun))

    if geri:
        dosya = klasor / f"{geri}.md"
        if not dosya.is_file():
            print(f"kayıt yok: {geri}")
            return 1
        os.utime(dosya)
        kod = uret(klasor)
        print(f"geri getirildi: {geri}")
        return kod

    iu = indeks_uret_modulu()
    soguyan = [s for s in iu.uret(klasor) if iu.soguk_mu(s[0], s[5])]
    bugun = date.today()
    for renk, ad, stem, aciklama, kelime, dokunus in soguyan:
        print(f"  ❄️ {stem} ({renk}, {(bugun - dokunus).days} gün, son dokunuş {dokunus.isoformat()})")
    print(f"soğuk: {len(soguyan)} kayıt (eşik {iu.soguma_gunu()} gün)")
    if dene:
        print("kuru çalıştırma — yazılmadı")
        return 0
    return uret(klasor)


if __name__ == "__main__":
    sys.exit(main())
