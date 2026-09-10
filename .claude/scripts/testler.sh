#!/usr/bin/env bash
# Hook test takımı — mekanizmaların hâlâ çalıştığını kanıtlar.
#
# Neden var: bütün kurallar mekanizmaya bağlandı ama mekanizmaların kendisi
# elle doğrulanıyordu. Testsiz bir mekanizma, sessizce bozulabilen bir
# mekanizmadır — sistemin tam olarak kaçındığı arıza türü.
#
# Yan etkisiz: gerçek dosyalara yazmaz. Durum dosyalarına dokunanları
# yedekleyip geri koyar.
#
# Kullanım: testler.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
H="$kok/.claude/hooks"
S="$kok/.claude/scripts"
DURUM="$S/.state"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }
icerir() { case "$3" in *"$2"*) gec "$1" ;; *) kal "$1" "içinde '$2'" "${3:0:80}" ;; esac; }
bos_mu() { [ -z "$3" ] && gec "$1" || kal "$1" "boş çıktı" "${3:0:80}"; }

# dokunma kaydını koru: testler ona yazacak
yedek=$(mktemp)
[ -f "$DURUM/dokunma.tsv" ] && cp "$DURUM/dokunma.tsv" "$yedek"

echo "Hook test takımı — $(date '+%Y-%m-%d %H:%M')"
echo

echo "1) Sözdizimi"
for f in "$H"/*.sh "$S"/*.sh; do
  if bash -n "$f" 2>/dev/null; then gec "$(basename "$f")"; else kal "$(basename "$f")" "geçerli bash" "sözdizimi hatası"; fi
done
for f in "$S"/*.py; do
  if python3 -m py_compile "$f" 2>/dev/null; then gec "$(basename "$f")"; else kal "$(basename "$f")" "geçerli python" "derlenmedi"; fi
done

echo
echo "2) Yükleyici (session-start)"
c=$(echo '{"session_id":"test"}' | bash "$H/session-start.sh" 2>/dev/null)
metin=$(printf '%s' "$c" | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)
[ -n "$metin" ] && gec "geçerli JSON üretiyor" || kal "geçerli JSON üretiyor" "JSON" "ayrıştırılamadı"
uz=${#metin}
[ "$uz" -le 16000 ] && gec "bağlam bütçesi içinde ($uz/16000)" || kal "bağlam bütçesi" "≤16000" "$uz"
icerir "kimlik yükleniyor" "[Hafıza: Kimlik]" "$metin"
icerir "kalan işler indeksi yükleniyor" "[Hafıza: Kalan İşler" "$metin"
icerir "kurallar yükleniyor" "[Hafıza: Kurallar]" "$metin"
# Çıktıda "kasa" aramak zayıf bir test: yükleyici kasa'yı okusa ama dosya içinde
# o kelime geçmese test geçerdi. Bunun yerine kasa'ya İZ dosyası koyup okunup
# okunmadığını doğruluyoruz.
iz="$kok/🔐 kasa/.test-izi.md"
printf -- '---\ntitle: iz\n---\n\nKASATESTIZI7391\n' > "$iz" 2>/dev/null
m2=$(echo '{"session_id":"kasatest"}' | bash "$H/session-start.sh" 2>/dev/null \
     | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)
rm -f "$iz"
case "$m2" in *KASATESTIZI7391*) kal "kasa bağlama sızmıyor" "iz görünmemeli" "iz bağlama girdi" ;; *) gec "kasa bağlama sızmıyor (iz dosyasıyla)" ;; esac
case "$metin" in *"[not:"*) kal "hiçbir bölüm kırpılmıyor" "kırpma yok" "kırpma var" ;; *) gec "hiçbir bölüm kırpılmıyor" ;; esac

echo
echo "3) Tavan ölçer / dokunma kaydı (dosya-kancasi)"
buyuk=""; kucuk="$kok/🔮 zihin/Çekirdek.md"
for f in "$kok/🔮 zihin/kalan-isler"/*.md; do
  [ "$(basename "$f")" = "INDEKS.md" ] && continue
  # Arşiv dosyaları tavandan muaf; örnek olarak seçilirse test yanlış kalır.
  head -n 10 "$f" | grep -qiE '^(type:[[:space:]]*gecmis|durum:[[:space:]]*arşiv)' && continue
  n=$(sed -n '/^---$/,/^---$/!p' "$f" | wc -w | tr -d ' ')
  [ "$n" -gt 500 ] && { buyuk="$f"; break; }
done
if [ -n "$buyuk" ]; then
  o=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$buyuk\"}}" | bash "$H/dosya-kancasi.sh" 2>/dev/null)
  icerir "tavanı aşanda uyarıyor" "[Tavan]" "$o"
else
  # Atlanan test GEÇTİ sayılmaz: tavan ölçer tamamen bozulsa bile takım yeşil kalırdı.
  # Bunun yerine geçici bir örnek dosya üretip gerçekten ölçtürüyoruz.
  gecici="$kok/🏰 İş/.tavan-testi-gecici.md"
  { printf -- '---\ntitle: gecici\n---\n\n'; for i in $(seq 1 600); do printf 'kelime '; done; } > "$gecici"
  o=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$gecici\"}}" | bash "$H/dosya-kancasi.sh" 2>/dev/null)
  icerir "tavanı aşanda uyarıyor (üretilen örnekle)" "[Tavan]" "$o"
  rm -f "$gecici"
fi
o=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$kucuk\"}}" | bash "$H/dosya-kancasi.sh" 2>/dev/null)
bos_mu "tavan altında susuyor" "" "$o"
o=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$kok/daily/$(ls "$kok/daily" | tail -1)\"}}" | bash "$H/dosya-kancasi.sh" 2>/dev/null)
bos_mu "makine klasörü muaf (daily)" "" "$o"
o=$(echo '{"tool_name":"Write","tool_input":{"file_path":"/tmp/disarida.md"}}' | bash "$H/dosya-kancasi.sh" 2>/dev/null)
bos_mu "vault dışına karışmıyor" "" "$o"
arsiv=$(ls -1 "$kok/🔮 zihin/kalan-isler"/*-gecmis.md 2>/dev/null | head -1)
if [ -n "$arsiv" ]; then
  o=$(echo "{\"tool_name\":\"Write\",\"tool_input\":{\"file_path\":\"$arsiv\"}}" | bash "$H/dosya-kancasi.sh" 2>/dev/null)
  bos_mu "arşiv dosyası tavandan muaf" "" "$o"
fi
o=$(echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$buyuk\"}}" | bash "$H/dosya-kancasi.sh" 2>/dev/null)
bos_mu "okumada tavan uyarısı vermiyor" "" "$o"
onceki=$(wc -l < "$DURUM/dokunma.tsv" 2>/dev/null || echo 0)
echo "{\"tool_name\":\"Read\",\"tool_input\":{\"file_path\":\"$kucuk\"}}" | bash "$H/dosya-kancasi.sh" >/dev/null 2>&1
sonraki=$(wc -l < "$DURUM/dokunma.tsv" 2>/dev/null || echo 0)
[ "$sonraki" -gt "$onceki" ] && gec "dokunma kaydı yazılıyor" || kal "dokunma kaydı" ">$onceki satır" "$sonraki"

echo
echo "4) Kapanış döngüsü (kapanis --dene)"
o=$("$S/kapanis.sh" --dene 2>/dev/null)
icerir "kuru çalıştırma özet veriyor" "toplam:" "$o"
case "$o" in *"taşındı:"*) kal "kuru çalıştırmada taşımıyor" "yalnızca liste" "taşıdı" ;; *) gec "kuru çalıştırmada taşımıyor" ;; esac

echo
echo "4b) Günlük döndürme (log-dondur)"
# Gerçek günlüğe dokunmadan, sahte geçmiş yıl verisiyle sınanır.
lt=$(mktemp -d); mkdir -p "$lt/.claude/scripts" "$lt/knowledge"
cp "$S/log-dondur.py" "$lt/.claude/scripts/"
printf '# Derleme Günlüğü\n\nGiriş.\n\n## [2025-11-02T10:00:00+03:00] compile | a.md\n\nEski.\n\n## [%s-09-09T18:00:00+03:00] compile | b.md\n\nYeni.\n' "$(date +%Y)" > "$lt/knowledge/log.md"
o=$(cd "$lt" && python3 .claude/scripts/log-dondur.py --dene 2>&1)
icerir "kuru çalıştırma yazmıyor" "yazılmadı" "$o"
[ -f "$lt/knowledge/log-2025.md" ] && kal "kuru çalıştırmada dosya oluşturmuyor" "dosya yok" "oluşturdu" || gec "kuru çalıştırmada dosya oluşturmuyor"
(cd "$lt" && python3 .claude/scripts/log-dondur.py >/dev/null 2>&1)
[ -f "$lt/knowledge/log-2025.md" ] && gec "geçmiş yıl arşive taşınıyor" || kal "geçmiş yıl arşive taşınıyor" "log-2025.md" "oluşmadı"
log_kalan=$(grep -c "^## \\[" "$lt/knowledge/log.md" 2>/dev/null || echo 0)
esit "bu yılın girdisi log.md'de kalıyor" "1" "$log_kalan"
grep -q "^# Derleme Günlüğü" "$lt/knowledge/log.md" && gec "giriş başlığı korunuyor" || kal "giriş başlığı korunuyor" "başlık" "kayıp"
rm -rf "$lt"

echo
echo "5) Denetçi"
if "$S/denetci.sh" >/dev/null 2>&1; then gec "denetçi 0 hata ile çıkıyor"; else kal "denetçi" "çıkış 0" "hata var"; fi

echo
echo "6) İndeks üretici (--dene)"
o=$(python3 "$S/indeks-uret.py" "$kok/🔮 zihin/kalan-isler" --dene 2>/dev/null)
icerir "kuru çalıştırma yazmıyor" "yazılmadı" "$o"

echo
echo "7) Soru sırası"
# Gerçek bekleme sayaçlarını bozmamak için yedekle
sy=$(mktemp -d); cp "$DURUM"/soruldu-* "$sy/" 2>/dev/null || :
rm -f "$DURUM"/soruldu-* 2>/dev/null
o=$(bash "$H/soru-sirasi.sh" "$kok" 2>/dev/null)
if [ -n "$(find "$kok/💪 Beden" -name '*.md' 2>/dev/null)" ]; then
  bos_mu "dolu klasör için soru üretmiyor" "" "$o"
else
  icerir "boş klasör için soru üretiyor" "Beden" "$o"
  o2=$(bash "$H/soru-sirasi.sh" "$kok" 2>/dev/null)
  bos_mu "aynı soruyu tekrar sormuyor" "" "$o2"
fi
rm -f "$DURUM"/soruldu-* 2>/dev/null
cp "$sy"/soruldu-* "$DURUM/" 2>/dev/null || :
rm -rf "$sy"

# dokunma kaydını geri koy
# -s değil -f: boş ama var olan bir kayıt dosyası silinmemeli
if [ -f "$yedek" ]; then cp "$yedek" "$DURUM/dokunma.tsv"; else rm -f "$DURUM/dokunma.tsv"; fi
rm -f "$yedek"
find "$S" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || :

echo
printf 'Sonuç: %s geçti, %s kaldı\n' "$gecen" "$kalan"
[ "$kalan" -eq 0 ]
