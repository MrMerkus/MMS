#!/usr/bin/env python3
"""Hafıza sistemi şablon yer tutucularını sistem.json ayarlarına göre yapılandırır.

Yalnızca Python 3 standart kütüphanesini kullanır.
"""

import argparse
import json
import os
import sys
from pathlib import Path

CONTRACT_SETTING_PLACEHOLDERS = [
    "<SİSTEM ADI>",
    "<ASİSTAN ADI>",
    "<KULLANICI>",
    "<DİL>",
    "<AD 1>",
    "<AD 2>",
    "<AD 3>",
    "<OFIS>",
    "<HAFIZA>",
    "<BİR İKİ CÜMLE — kim, ne yapıyor, bu beyni neden kuruyor>",
]


def render_path(p: str) -> str:
    """Yolu $HOME ile başlıyorsa '~/...' biçimine dönüştürür."""
    if not p:
        return ""
    p_str = str(p)
    if p_str == "~" or p_str.startswith("~/"):
        return p_str
    home = os.path.expanduser("~")
    expanded = os.path.expandvars(p_str)
    norm = os.path.normpath(expanded)
    if norm == home:
        return "~"
    if norm.startswith(home + "/"):
        return "~" + norm[len(home):]
    if p_str == "$HOME":
        return "~"
    if p_str.startswith("$HOME/"):
        return "~" + p_str[len("$HOME"):]
    return norm


def parse_args():
    parser = argparse.ArgumentParser(
        description="Hafıza sistemi şablon yer tutucularını sistem.json ayarlarına göre yapılandırır."
    )
    parser.add_argument(
        "--ayarlar",
        type=str,
        default=os.path.expanduser("~/.config/my-ai-system/sistem.json"),
        help="sistem.json dosyasının yolu (varsayılan: $HOME/.config/my-ai-system/sistem.json)",
    )
    parser.add_argument(
        "--hedef",
        type=str,
        default=str(Path(__file__).resolve().parent.parent),
        help="Hedef vault dizini (varsayılan: kurulum/ dizininin üst klasörü)",
    )
    parser.add_argument(
        "--dene",
        action="store_true",
        help="Değişiklik yapmadan hangi dosyaların ve yer tutucuların değişeceğini gösterir",
    )
    return parser.parse_args()


def main():
    args = parse_args()

    hedef_path = Path(os.path.expanduser(os.path.expandvars(args.hedef))).resolve()
    if not hedef_path.exists() or not hedef_path.is_dir():
        print(f"Hata: Hedef dizin bulunamadı veya bir dizin değil: {hedef_path}", file=sys.stderr)
        sys.exit(2)

    ayarlar_path = Path(os.path.expanduser(os.path.expandvars(args.ayarlar))).resolve()
    if not ayarlar_path.exists() or not ayarlar_path.is_file():
        print(f"Hata: Ayar dosyası bulunamadı: {ayarlar_path}", file=sys.stderr)
        sys.exit(2)

    try:
        with open(ayarlar_path, "r", encoding="utf-8") as f:
            config = json.load(f)
    except Exception as e:
        print(f"Hata: Ayar dosyası okunamadı veya JSON geçersiz: {e}", file=sys.stderr)
        sys.exit(2)

    if not isinstance(config, dict):
        print("Hata: Ayar dosyası bir JSON nesnesi (object) olmalıdır.", file=sys.stderr)
        sys.exit(2)

    # Zorunlu anahtarların denetimi
    asistan_adi = config.get("asistan_adi")
    kullanici = config.get("kullanici")

    if not asistan_adi or not str(asistan_adi).strip():
        print("Hata: 'asistan_adi' zorunlu bir ayardır ve sistem.json içinde bulunamadı.", file=sys.stderr)
        sys.exit(2)

    if not kullanici or not str(kullanici).strip():
        print("Hata: 'kullanici' zorunlu bir ayardır ve sistem.json içinde bulunamadı.", file=sys.stderr)
        sys.exit(2)

    asistan_adi = str(asistan_adi).strip()
    kullanici = str(kullanici).strip()

    # İsteğe bağlı anahtarlar ve sözleşme varsayılanları
    sistem_adi = str(config.get("sistem_adi") or "My AI System").strip()
    hitap_gunluk = str(config.get("hitap_gunluk") or asistan_adi).strip()
    hitap_resmi = str(config.get("hitap_resmi") or asistan_adi).strip()
    hitap_odak = str(config.get("hitap_odak") or hitap_resmi).strip()
    dil = str(config.get("dil") or "Türkçe").strip()
    baglam = str(config.get("baglam") or "").strip().rstrip(".")

    kok = str(config.get("kok") or os.path.expanduser("~/yapay-zeka-sistemim")).strip()
    hafiza = str(config.get("hafiza") or f"{kok}/hafiza").strip()
    ofis = str(config.get("ofis") or f"{kok}/ofis").strip()

    hafiza_rendered = render_path(hafiza)
    ofis_rendered = render_path(ofis)

    # Yer tutucu eşleme tablosu
    replacements = {
        "<SİSTEM ADI>": sistem_adi,
        "<ASİSTAN ADI>": asistan_adi,
        "<KULLANICI>": kullanici,
        "<DİL>": dil,
        "<AD 1>": hitap_gunluk,
        "<AD 2>": hitap_resmi,
        "<AD 3>": hitap_odak,
        "<OFIS>": ofis_rendered,
        "<HAFIZA>": hafiza_rendered,
    }

    # baglam boşsa yer tutucu olduğu gibi bırakılır
    if baglam:
        replacements["<BİR İKİ CÜMLE — kim, ne yapıyor, bu beyni neden kuruyor>"] = baglam

    # Hedef altındaki *.md dosyalarını tara (.git, "🔐 kasa", knowledge, daily atlanır)
    md_files = []
    for root, dirs, files in os.walk(hedef_path):
        dirs[:] = [
            d for d in dirs
            if d != ".git"
            and "kasa" not in d.lower()
            and d not in ("knowledge", "daily")
        ]
        for f in files:
            if f.endswith(".md") and "kasa" not in f.lower():
                full_path = Path(root) / f
                md_files.append(full_path)

    md_files.sort()

    if args.dene:
        total_files_to_change = 0
        total_placeholder_counts = {ph: 0 for ph in replacements}
        for file_path in md_files:
            rel_path = file_path.relative_to(hedef_path)
            try:
                with open(file_path, "r", encoding="utf-8") as f:
                    content = f.read()
            except Exception as e:
                print(f"Hata: '{rel_path}' okunamadı: {e}", file=sys.stderr)
                continue

            file_counts = {}
            for ph in replacements:
                c = content.count(ph)
                if c > 0:
                    file_counts[ph] = c
                    total_placeholder_counts[ph] += c

            if file_counts:
                total_files_to_change += 1
                print(f"[DENE] Değişecek dosya: {rel_path}")
                for ph, c in file_counts.items():
                    print(f"  {ph}: {c}")

        print(f"\n[DENE] Özet: {total_files_to_change} dosya değişecek.")
        for ph, c in total_placeholder_counts.items():
            if c > 0:
                print(f"  {ph}: toplam {c} adet")
        print("[DENE] Hiçbir dosyaya yazılmadı.")
        sys.exit(0)

    # Dosyalara yazma
    changed_count = 0
    for file_path in md_files:
        rel_path = file_path.relative_to(hedef_path)
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception as e:
            print(f"Hata: '{rel_path}' okunamadı: {e}", file=sys.stderr)
            continue

        new_content = content
        for ph, val in replacements.items():
            new_content = new_content.replace(ph, val)

        if new_content != content:
            with open(file_path, "w", encoding="utf-8") as f:
                f.write(new_content)
            changed_count += 1
            print(f"Güncellendi: {rel_path}")

    print(f"Değiştirilen dosya sayısı: {changed_count}")

    # Yazım sonrası kalan sözleşme ayar yer tutucularını tara ve uyar
    for file_path in md_files:
        rel_path = file_path.relative_to(hedef_path)
        try:
            with open(file_path, "r", encoding="utf-8") as f:
                content = f.read()
        except Exception:
            continue

        for ph in CONTRACT_SETTING_PLACEHOLDERS:
            if ph in content:
                print(f"UYARI: '{rel_path}' içinde ayar yer tutucusu kaldı: {ph}", file=sys.stderr)

    sys.exit(0)


if __name__ == "__main__":
    main()
