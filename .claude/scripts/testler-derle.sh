#!/usr/bin/env bash
# Kavram çıkarımı (derle skill'i) deterministik yardımcısının düşman testleri.
#
# Ölçüt: yalnız projeksiyon işaretli, bu içerikle kavram görmemiş günler bekler; kayıt
# deftere tek satır ve log.md'ye tek blok düşer; okunduktan sonra değişen gün kapanmaz.
# Sahte vault'ta çalışır; sonda gerçek defter ve log.md'nin değişmediği ölçülür.
#
# Kullanım: testler-derle.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
S="$kok/.claude/scripts"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }
icerir() { case "$3" in *"$2"*) gec "$1" ;; *) kal "$1" "içinde '$2'" "${3:0:120}" ;; esac; }
icermez() { case "$3" in *"$2"*) kal "$1" "'$2' olmamalı" "${3:0:120}" ;; *) gec "$1" ;; esac; }

gecici=$(mktemp -d)
trap 'rm -rf "$gecici"' EXIT
unset BEYIN_INVOKED_BY
iz() { cat "$kok"/daily/olaylar/*.jsonl "$kok/knowledge/log.md" 2>/dev/null | sha256sum; }
iz_once=$(iz)

v="$gecici/vault"; mkdir -p "$v/.claude/scripts" "$v/daily" "$v/knowledge"
for f in derle.py olaylar.py _portalock.py; do [ -f "$S/$f" ] && cp "$S/$f" "$v/.claude/scripts/"; done
printf '# Derleme Günlüğü\n' > "$v/knowledge/log.md"
isaretli() { printf '# Günlük Log: %s\n<!-- projeksiyon: daily/olaylar -->\n\n## Oturumlar\n\n### Oturum (10:00)\n\n- %s\n\n### Oturum (12:00)\n\n- ikinci\n' "$1" "${2:-birinci}" > "$v/daily/$1.md"; }
d1=$(date -d '3 days ago' +%F); d2=$(date -d '2 days ago' +%F); bugun=$(date +%F)
isaretli "$d1"; isaretli "$d2"; isaretli "$bugun"
printf '# Günlük Log: 2026-01-01\n\n## Oturumlar\n\n- eski, işaretsiz\n' > "$v/daily/2026-01-01.md"
de() { (cd "$v" && timeout 30 python3 .claude/scripts/derle.py "$@" 2>"$gecici/err"); }
dg() { sha256sum "$v/daily/$1.md" | cut -c1-12; }

echo "Derle yardımcısı düşman testleri — $(date '+%Y-%m-%d %H:%M')"
[ -f "$S/derle.py" ] || echo "  (derle.py yok: kırmızı beklenen hal)"
echo

echo "1) Bekleyen"
o=$(de bekleyen)
icerir "işaretli eski gün bekliyor" "$d1 $(dg "$d1") 2" "$o"
icerir "ikinci gün bekliyor" "$d2" "$o"
icermez "bugün varsayılan olarak hariç" "$bugun" "$o"
icermez "işaretsiz (geçiş öncesi) gün hariç" "2026-01-01" "$o"
icerir "sayı veriyor" "bekleyen: 2" "$o"
icerir "--bugun ile bugün de" "$bugun" "$(de bekleyen --bugun)"

echo
echo "2) Kaydet"
o=$(de kaydet --gun "$d1" --digest "$(dg "$d1")" --olusturulan yeni-kavram --guncellenen eski-kavram,ikinci \
      --not "İki cümlelik not."); k=$?
esit "kaydet çıkış 0" "0" "$k"
icerir "defter yazıldı" "yazildi" "$o"
satir=$(cat "$v"/daily/olaylar/*.jsonl | grep ':kavram"' | tail -n 1)
icerir "kimlik derleme:<gün>.md:<digest>:kavram" "\"kimlik\":\"derleme:$d1.md:$(dg "$d1"):kavram\"" "$satir"
icerir "tip derleme" '"tip":"derleme"' "$satir"
icerir "detay kavram" '"detay":"kavram"' "$satir"
log=$(cat "$v/knowledge/log.md")
icerir "log.md'de derleme bloğu" "] derleme | $d1.md" "$log"
icerir "oluşturulan listesi" "**Oluşturulan:** yeni-kavram" "$log"
icerir "güncellenen listesi" "**Güncellenen:** eski-kavram, ikinci" "$log"
o=$(de bekleyen)
icermez "kaydedilen gün artık beklemiyor" "$d1" "$o"
icerir "diğer gün hâlâ bekliyor" "$d2" "$o"

echo
echo "3) Tekrar ve değişim"
de kaydet --gun "$d1" --digest "$(dg "$d1")" --not "tekrar" >/dev/null
esit "aynı kayıt iki kez: defterde tek satır" "1" "$(cat "$v"/daily/olaylar/*.jsonl | grep -c ':kavram"')"
esit "aynı kayıt iki kez: log'da tek blok" "1" "$(grep -c "] derleme | $d1.md" "$v/knowledge/log.md")"
eski=$(dg "$d2"); isaretli "$d2" "sonradan eklenen oturum"
de kaydet --gun "$d2" --digest "$eski" --not "eski içerikten" >/dev/null; k=$?
[ "$k" -ne 0 ] && gec "okunduktan sonra değişen gün reddedildi" || kal "değişen gün reddi" "çıkış ≠ 0" "0"
icerir "ret sebebi stderr'de" "digest" "$(cat "$gecici/err")"
icermez "reddedilen log'a düşmedi" "$d2.md" "$(grep '] derleme |' "$v/knowledge/log.md")"
isaretli "$d1" "gün sonradan büyüdü"
icerir "kaydedilmiş gün içeriği değişince yeniden bekliyor" "$d1" "$(de bekleyen)"

echo
echo "4) Girdi kapıları"
de kaydet --gun "$d2" --digest "$(dg "$d2")" --olusturulan "Büyük Harf" --not x >/dev/null
[ $? -ne 0 ] && gec "ASCII kebab olmayan slug reddedildi" || kal "slug reddi" "≠0" "0"
de kaydet --gun "$d2" --digest "$(dg "$d2")" --not "  " >/dev/null
[ $? -ne 0 ] && gec "boş not reddedildi" || kal "boş not reddi" "≠0" "0"
de kaydet --gun "../x" --digest abc --not x >/dev/null
[ $? -ne 0 ] && gec "gün biçimi dışı yol reddedildi" || kal "yol reddi" "≠0" "0"
o=$(cd "$v" && BEYIN_INVOKED_BY=codex-serit python3 .claude/scripts/derle.py kaydet --gun "$d2" --digest "$(dg "$d2")" --not x 2>&1); k=$?
[ "$k" -ne 0 ] && gec "şerit içinden kayıt reddedildi (şerit beyne yazmaz)" || kal "şerit reddi" "≠0" "0"

echo
echo "5) Gerçek vault"
esit "gerçek defter ve log.md değişmedi" "$iz_once" "$(iz)"

echo
echo "Sonuç: $gecen geçti, $kalan kaldı"
[ "$kalan" -eq 0 ]
