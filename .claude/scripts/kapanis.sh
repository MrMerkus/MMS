#!/usr/bin/env bash
# Kapanış döngüsü: frontmatter'ında "durum: kapandı" olan dosyaları
# "📦 bitmiş olanlar/<yıl>/" altına taşır. Silmez, taşır.
#
# Neden var: NemesesOS'un eski 900-Archive klasörü hiç dolmadı, çünkü elle
# doldurulması gerekiyordu. Kural vardı, taşıyan mekanizma yoktu.
#
# Kuru çalıştırma: .claude/scripts/kapanis.sh --dene
set -euo pipefail

kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
dene=${1:-}
tasinan=0

tara=(
  "$kok/🔮 zihin/kalan-isler"
  "$kok/🏰 İş"
  "$kok/🎯 Hedefler"
)

while IFS= read -r -d '' dosya; do
  # Frontmatter YALNIZCA dosyanın ilk satırı '---' ise geçerlidir. Aksi halde
  # gövdedeki yatay çizgi frontmatter sanılıyor ve mekanizmayı ANLATAN bir doküman
  # bile arşive taşınabiliyordu (denetimde deneyle doğrulandı).
  [ "$(head -n 1 "$dosya")" = "---" ] || continue
  awk 'NR==1 && /^---$/{n=1; next} n==1 && /^---$/{exit} n==1' "$dosya" \
    | grep -qi '^durum:[[:space:]]*kapandı' || continue
  yil=$(date -r "$dosya" +%Y)
  hedef="$kok/📦 bitmiş olanlar/$yil"
  if [ "$dene" = "--dene" ]; then
    echo "taşınacak: ${dosya#"$kok"/}  ->  📦 bitmiş olanlar/$yil/"
  else
    mkdir -p "$hedef"
    ad=$(basename "$dosya")
    # Aynı adlı dosya iki farklı klasörden gelebilir; üzerine yazmak veri kaybıdır.
    # Çakışma varsa kaynak klasörün adı öneke eklenir, yine varsa numara verilir.
    if [ -e "$hedef/$ad" ]; then
      onek=$(basename "$(dirname "$dosya")")
      ad="${onek}--${ad}"
      n=2
      while [ -e "$hedef/$ad" ]; do
        ad="${onek}--${n}--$(basename "$dosya")"
        n=$((n+1))
      done
    fi
    mv -n "$dosya" "$hedef/$ad"
    echo "taşındı: ${dosya#"$kok"/}  ->  📦 bitmiş olanlar/$yil/$ad"
  fi
  tasinan=$((tasinan+1))
done < <(find "${tara[@]}" -name '*.md' ! -name 'INDEKS.md' ! -name 'OKU.md' -print0 2>/dev/null)

echo "toplam: $tasinan"

# Takvimle çalışan kardeş iş: geçmiş yılların derleme günlüğünü arşive döndür.
# Aynı fikir — biten şey açıkların arasında durmaz — sadece tetikleyicisi tarih.
if [ -x "$kok/.claude/scripts/log-dondur.py" ]; then
  python3 "$kok/.claude/scripts/log-dondur.py" 2>/dev/null || :
fi
