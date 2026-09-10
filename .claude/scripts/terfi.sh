#!/usr/bin/env bash
# Terfi/tenzil — hangi dosyaya ne sıklıkla dokunulduğunu ölçer ve söyler.
#
# Neden var: tasarımın iddiası "sık dokunulan yukarı çıkar, dokunulmayan aşağı
# iner" idi, ama bunu ölçen hiçbir şey yoktu. Ölçüm olmadan katman yerleşimi
# insan sezgisine kalıyordu — sistemin tam olarak güvenmemeyi öğrettiği şey.
#
# Ne yapmaz: kendiliğinden taşımaz. Terfi ve tenzil bir yargıdır; script
# sayıyı verir, kararı insan verir. (Kapanış döngüsünden farkı budur: orada
# karar zaten "durum: kapandı" yazılarak verilmiş oluyor.)
#
# Kullanım: terfi.sh [gün]   (varsayılan 30)
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
kayit="$kok/.claude/scripts/.state/dokunma.tsv"
pencere=${1:-30}
simdi=$(date '+%s')
esik=$((simdi - pencere * 86400))
soguk_gun=${BEYIN_SOGUK_GUN:-45}
soguk_esik=$((simdi - soguk_gun * 86400))

if [ ! -f "$kayit" ]; then
  echo "Henüz dokunma kaydı yok ($kayit)."
  echo "PostToolUse kancası biriktirmeye başladıkça bu rapor dolar."
  exit 0
fi

echo "Terfi/tenzil raporu — son $pencere gün"
echo

echo "SICAK (en çok dokunulan — yüzeyde durmalı)"
awk -F'\t' -v e="$esik" '$1>=e {say[$3]++} END {for (d in say) printf "%6d  %s\n", say[d], d}' "$kayit" \
  | sort -rn | head -10 | sed 's/^/  /'
[ -s "$kayit" ] || echo "  (veri yok)"

echo
echo "SOĞUK (kalan işler içinde $soguk_gun gündür hiç dokunulmayan — tenzil adayı)"
bulundu=0
for f in "$kok/🔮 zihin/kalan-isler"/*.md; do
  [ -f "$f" ] || continue
  ad=$(basename "$f")
  [ "$ad" = "INDEKS.md" ] && continue
  gor="🔮 zihin/kalan-isler/$ad"
  son=$(awk -F'\t' -v d="$gor" '$3==d {s=$1} END {print s+0}' "$kayit")
  # hiç kaydı yoksa dosya değişiklik zamanına düş
  [ "$son" -eq 0 ] && son=$(date -r "$f" '+%s' 2>/dev/null || echo 0)
  if [ "$son" -lt "$soguk_esik" ]; then
    gun=$(( (simdi - son) / 86400 ))
    printf '  %4d gündür sessiz  %s\n' "$gun" "$ad"
    bulundu=$((bulundu+1))
  fi
done
[ "$bulundu" -eq 0 ] && echo "  (yok — hepsi $soguk_gun günden taze)"

echo
echo "REFLEKS KATMANI BOYUTU (şişme kontrolü)"
for f in "$kok/🔮 zihin/Ruh.md" "$kok/🔮 zihin/Çekirdek.md" "$kok/🔮 zihin/Kurallar.md" \
         "$kok/🔮 zihin/kalan-isler/INDEKS.md"; do
  [ -f "$f" ] || continue
  n=$(sed -n '/^---$/,/^---$/!p' "$f" | wc -w | tr -d ' ')
  isaret=""; [ "$n" -gt 500 ] && isaret="  ⚠️ tavanı aşıyor"
  printf '  %5d kelime  %s%s\n' "$n" "$(basename "$f")" "$isaret"
done

echo
echo "Karar senin: sıcak olan yüzeyde kalsın, soğuk olan kapatılsın veya derine insin."
