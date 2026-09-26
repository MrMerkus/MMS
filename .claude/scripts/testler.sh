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
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; return 0; }
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
# Eşikler tek kaynaktan (hooks/esikler.sh); kırmızı = tavan (kullanıcı, 26 Eylül).
BAGLAM_HEDEF=; BAGLAM_TURUNCU=; BAGLAM_TAVAN=
. "$H/esikler.sh" 2>/dev/null
if [ -n "$BAGLAM_TAVAN" ]; then
  [ "$uz" -le "$BAGLAM_TAVAN" ] && gec "bağlam tavanın altında ($uz/$BAGLAM_TAVAN)" || kal "bağlam tavanı" "≤$BAGLAM_TAVAN" "$uz"
else
  kal "eşik dosyası okunuyor" "hooks/esikler.sh" "yok ya da boş"
fi
# Tek yol ayarı (~/.config/beyin): taşımada yalnız bu üç kısayol değişir; yanlış yere bakarsa kırmızı.
for yk in "vault:.claude/hooks/kapi.py" "motor:SOZLESME.md" "ajans:serit-ac.sh"; do
  ad=${yk%%:*}; iz=${yk#*:}
  # Motor ve ajans isteğe bağlı bileşen: hiç kurulmamışsa atlanır, kurulu ama yanlışsa kırmızı.
  if [ "$ad" != vault ] && [ ! -e "$HOME/.config/beyin/$ad" ] && [ ! -L "$HOME/.config/beyin/$ad" ]; then
    gec "yol ayarı $ad yok (bileşen kurulu değil, atlandı)"; continue
  fi
  [ -e "$HOME/.config/beyin/$ad/$iz" ] && gec "yol ayarı $ad doğru yerde" || kal "yol ayarı $ad" "$ad/$iz" "$(readlink "$HOME/.config/beyin/$ad" 2>/dev/null || echo yok)"
done
[ "$(readlink -f "$HOME/.config/beyin/vault")" = "$(readlink -f "$kok")" ] && gec "yol ayarı vault bu vault'u gösteriyor" || kal "vault bu vault" "$kok" "$(readlink -f "$HOME/.config/beyin/vault")"
# İki kat yukarıdaki kökten açılış (<KÖK>/): vault tek yol ayarından bulunur,
# ama yalnız oturum kökünün İÇİNDEYSE (başka klasördeki oturum gerçek hafızaya yazmasın).
lk=$(mktemp -d); mkdir -p "$lk/ust/sistem/vault/🔮 zihin" "$lk/ev/.config/beyin" "$lk/baska"
ln -s "$lk/ust/sistem/vault" "$lk/ev/.config/beyin/vault"
lb() { HOME="$lk/ev" CLAUDE_PROJECT_DIR="$1" bash -c '. "$0"; printf %s "$BEYIN_PROJECT_DIR"' "$H/lib.sh" 2>/dev/null; }
esit "iki kat yukarıdan açılınca vault bulunuyor" "$lk/ust/sistem/vault" "$(lb "$lk/ust")"
esit "kökün dışındaki vault seçilmiyor" "$lk/baska" "$(lb "$lk/baska")"
rm -rf "$lk"
# Eşik dosyası ile KRITERLER.md aynı sayıyı söylemeli: biri tek başına değişirse kırmızı.
krit="${BEYIN_KRITERLER:-$HOME/.config/beyin/motor/KRITERLER.md}"
k_sayi() { grep -m1 -E "^- \*\*$1" "$krit" 2>/dev/null | grep -oE '[0-9]{1,3}(\.[0-9]{3})+' | head -1 | tr -d '.'; }
if [ -f "$krit" ]; then
  esit "KRITERLER hedef = esikler.sh" "${BAGLAM_HEDEF:-yok}" "$(k_sayi Hedef)"
  esit "KRITERLER turuncu = esikler.sh" "${BAGLAM_TURUNCU:-yok}" "$(k_sayi Turuncu)"
  esit "KRITERLER kırmızı = esikler.sh" "${BAGLAM_TAVAN:-yok}" "$(k_sayi Kırmızı)"
else
  gec "KRITERLER yok (motor kurulu değil, eşik karşılaştırması atlandı)"
fi
# terfi: taşınmış dosya sıcak listede görünmez (dokunma.tsv yedekli, sonda geri konur).
for i in $(seq 60); do printf '%s\tEdit\t%s\n' "$(date +%s)" "🔮 zihin/kalan-isler/yok-olan-TERFIIZ.md" >> "$DURUM/dokunma.tsv"; done
case "$(bash "$S/terfi.sh" 2>/dev/null)" in *TERFIIZ*) kal "terfi taşınmış dosyayı göstermiyor" "görünmemeli" "listede" ;; *) gec "terfi taşınmış dosyayı göstermiyor" ;; esac
# bayat-tara: işaretsiz eski ifade yakalanır, işaretlisi geçer (düşman: işaret kuralı sökülürse kırmızı).
bt=$(mktemp -d); printf 'Kalıp\tgüncel\nESKIKARARXQ\tYENI\n' > "$bt/k.tsv"
printf 'Motor ESKIKARARXQ ile çalışır.\n' > "$bt/acik.md"
printf 'Motor ESKIKARARXQ (yerini aldı: YENI).\n' > "$bt/isaretli.md"
mkdir -p "$bt/son-oturum"; printf 'ESKIKARARXQ o günün gerçeği.\n' > "$bt/son-oturum/2026.md"
bto=$(python3 "$S/bayat-tara.py" --kaliplar "$bt/k.tsv" "$bt" 2>&1)
icerir "bayat-tara işaretsiz kaydı yakalar" "acik.md:1" "$bto"
case "$bto" in *isaretli.md*|*son-oturum*) kal "bayat-tara işaretliyi ve tarihîyi geçer" "yalnız acik.md" "$bto" ;; *) gec "bayat-tara işaretliyi ve tarihîyi geçer" ;; esac
rm -rf "$bt"
# Eşik sayıları kodda elle yazılmaz; yalnız esikler.sh'de durur.
sabit=$(grep -lE '\b(12|16|24)[.]?000\b' "$H/session-start.sh" "$S/denetci.sh" 2>/dev/null | sed 's#.*/##' | tr '\n' ' ')
bos_mu "eşik sayısı kodda sabit yazılı değil" "" "$sabit"
# Turuncu bölge davranışı: eşik düşürülünce uyarı görünmeli (düşman: dal sökülürse kırmızı).
m3=$(echo '{"session_id":"esiktest"}' | BAGLAM_HEDEF=10 BAGLAM_TURUNCU=20 bash "$H/session-start.sh" 2>/dev/null \
     | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)
icerir "turuncu bölge uyarısı çıkıyor" "turuncu bölge" "$m3"
case "$metin" in *"turuncu bölge"*) [ "$uz" -gt "${BAGLAM_TURUNCU:-0}" ] && gec "turuncu uyarı yalnız eşik üstünde" || kal "turuncu uyarı yalnız eşik üstünde" "uyarı yok" "uyarı var ($uz)" ;; *) gec "turuncu uyarı yalnız eşik üstünde" ;; esac
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
# Konu ekseni (İyileştirme 3): sahte klasörde üret, gerçek indekse dokunma.
ix=$(mktemp -d); K2="$ix/kalan-isler"; mkdir -p "$K2" "$ix/son-oturum"
kayit() { printf -- '---\ntitle: %s\ntype: kalan-is\n---\n\n# %s\n\n**Status:** %s\n\n%s\n' "$1" "$1" "$2" "$3" > "$K2/$1.md"; }
kayit acik-a "🟡 Aktif" "Kısa bir konu cümlesi burada duruyor ve yeterince uzun."
kayit uzun-b "⚪ Uyuyor" "$(printf 'kelime %.0s' $(seq 600))"
kayit yesil-c "🟢 Yürüyor" "Yeşil konu cümlesi burada duruyor ve yeterince uzun."
kayit renk-d "🟡 Karar bekliyor" "Rengi değişen konu cümlesi burada duruyor, uzun."
printf -- '---\ntitle: x\n---\n\n| Konu | Durum | Ne zaman aç |\n| --- | --- | --- |\n| [[renk-d\\|renk-d]] | 🟢 | ELLE-D konuşulurken |\n' > "$K2/INDEKS.md"
printf -- '---\ntitle: x\n---\n\n| Konu | Durum | Ne zaman aç |\n| --- | --- | --- |\n| [[yesil-c\\|yesil-c]] | 🟢 | ELLE-C yeşil konu açılınca aç |\n' > "$K2/INDEKS-aktif.md"
python3 "$S/indeks-uret.py" "$K2" >/dev/null 2>&1
ix_on=$(sed -n '/^| \[\[/p;/^## /q' "$K2/INDEKS.md")
for st in acik-a uzun-b yesil-c renk-d; do grep -q -e "\[\[$st\\\\|" -e "\`$st\`" "$K2/INDEKS.md" || { kal "açılış indeksi her açık konuyu gösteriyor" "$st" "yok"; st=HATA; break; }; done
[ "${st:-}" != HATA ] && gec "açılış indeksi her açık konuyu gösteriyor"
a_hucre=$(grep "\[\[acik-a\\\\|" "$K2/INDEKS.md" | awk -F' \\| ' '{print $3}')
case "$a_hucre" in Aktif*|"") kal "durum metni açıklama yerine geçmiyor" "❔ işaretli konu" "$a_hucre" ;; *❔*) gec "durum metni açıklama yerine geçmiyor" ;; *) kal "durum metni açıklama yerine geçmiyor" "❔" "$a_hucre" ;; esac
case "$ix_on" in *uzun-b*) kal "⚠️ dosya ön tabloya terfi etmiyor" "ön tabloda yok" "var" ;; *) gec "⚠️ dosya ön tabloya terfi etmiyor" ;; esac
icerir "rengi değişen satır gözden geçir işareti alıyor" "↻" "$(grep '\[\[renk-d' "$K2/INDEKS.md")"
icerir "elle açıklama ayrıntı tablosunda korunuyor" "ELLE-C" "$(cat "$K2/INDEKS-aktif.md")"
case "$(cat "$K2/INDEKS.md")" in *"[[INDEKS-soguk"*) kal "soğuk dosyası yokken bağlantı yok" "bağlantı yok" "var" ;; *) gec "soğuk dosyası yokken bağlantı yok" ;; esac
printf -- '---\ntitle: 2026-09-01 — eski\n---\n\n%s\n' "$(printf 'uzun %.0s' $(seq 300))" > "$ix/son-oturum/2026-09-01-1.md"
printf -- '---\ntitle: 2026-09-02 — yeni\n---\n\nKısa ama yeterince uzun bir konu cümlesi.\n' > "$ix/son-oturum/2026-09-02-1.md"
python3 "$S/indeks-uret.py" "$ix/son-oturum" >/dev/null 2>&1
esit "son-oturum indeksi tarihe göre (yeni üstte)" "2026-09-02-1" "$(grep -m1 -o '\[\[2026-[0-9-]*' "$ix/son-oturum/INDEKS.md" | tr -d '[')"
rm -rf "$ix"
# Gerçek açılış indeksi: soğumamış her açık kalan-iş satırı enjekte dosyada.
eksik=""
for f in "$kok/🔮 zihin/kalan-isler"/*.md; do
  ad=$(basename "$f" .md); case "$ad" in INDEKS*|*-gecmis) continue ;; esac
  grep -q '^type: gecmis\|^durum: arşiv' "$f" && continue
  grep -q "\[\[$ad\\\\|" "$kok/🔮 zihin/kalan-isler/INDEKS-soguk.md" 2>/dev/null && continue
  grep -q -e "\[\[$ad\\\\|" -e "\`$ad\`" "$kok/🔮 zihin/kalan-isler/INDEKS.md" || eksik="$eksik $ad"
done
bos_mu "gerçek açılış indeksinde her açık konu var" "" "$eksik"

echo
echo "6b) Ders kapısı (her tetikleyici satırı bir düşman test)"
while IFS= read -r dsat; do
  case "$dsat" in
    "OK "*) gec "${dsat#OK }" ;;
    "FAIL "*) d=${dsat#FAIL }; IFS='|' read -r dad dbek dgel <<< "$d"; kal "$dad" "$dbek" "$dgel" ;;
  esac
done < <(python3 "$S/testler-ders.py" 2>&1 || echo "FAIL testler-ders.py çalıştı|çıkış 0|hata")

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

echo
echo "8) .state temizliği ve sağlık satırı"
# Sahte vault'ta çalışır, gerçek .state'e dokunmaz.
sv=$(mktemp -d); sd="$sv/.claude/scripts/.state"; mkdir -p "$sd"
for i in $(seq 1 150); do : > "$sd/flush-taze$i.json"; done
o=$(bash "$H/saglik.sh" "$sv" 2>/dev/null)
bos_mu "yoğun haftada taze dosya için susuyor" "" "$o"
for i in $(seq 1 25); do : > "$sd/bilinmeyen-$i"; touch -d '10 days ago' "$sd/bilinmeyen-$i"; done
o=$(bash "$H/saglik.sh" "$sv" 2>/dev/null)
icerir "eski dosya birikince konuşuyor" "temizlik adımı çalışmıyor" "$o"
rm -f "$sd"/bilinmeyen-*
for t in compile-trigger-2026-01-01 antigravity-x.lock hatirlatildi.x health.json; do
  : > "$sd/$t"; touch -d '10 days ago' "$sd/$t"
done
( BEYIN_STATE_DIR="$sd"; . "$H/lib.sh" >/dev/null 2>&1; BEYIN_STATE_DIR="$sd"; beyin_cleanup_session_state )
kalanlar=$(cd "$sd" && ls compile-trigger-* antigravity-* hatirlatildi.* 2>/dev/null)
bos_mu "eski tetik, agy ve hatırlatma dosyalarını siliyor" "" "$kalanlar"
[ -f "$sd/health.json" ] && gec "kalıcı durum dosyasına dokunmuyor" || kal "kalıcı durum dosyasına dokunmuyor" "health.json duruyor" "silindi"
# Olay defterinin kırık kuyruk parçası silinene kadar konuşur (olaylar.py bırakır).
rm -f "$sd"/*
: > "$sd/olaylar-kirik-x.parca"
o=$(bash "$H/saglik.sh" "$sv" 2>/dev/null)
icerir "kırık defter parçası varken konuşuyor" "kırık satır" "$o"
rm -f "$sd/olaylar-kirik-x.parca"
o=$(bash "$H/saglik.sh" "$sv" 2>/dev/null)
bos_mu "kırık defter parçası yokken susuyor" "" "$o"
# Kavram çıkarımı bekleyen gün: 3 ve üstünde konuşur, altında susar (derle.py bekleyen).
mkdir -p "$sv/daily"
for g in 5 4; do printf '# Günlük Log\n<!-- projeksiyon: daily/olaylar -->\n\n- %s\n' "$g" > "$sv/daily/$(date -d "$g days ago" +%F).md"; done
o=$(bash "$H/saglik.sh" "$sv" 2>/dev/null)
bos_mu "2 gün derlenmemişken susuyor" "" "$o"
printf '# Günlük Log\n<!-- projeksiyon: daily/olaylar -->\n\n- 3\n' > "$sv/daily/$(date -d '3 days ago' +%F).md"
o=$(bash "$H/saglik.sh" "$sv" 2>/dev/null)
icerir "3 gün derlenmemişken konuşuyor" "3 gün kavram çıkarımı bekliyor" "$o"
rm -rf "$sv"

echo
echo "9) Farkındalık (organ 1b)"
# Sahte vault + sahte ofis: gerçek dosyalara dokunmaz. Ölçüt SOZLESME Karar 6:
# ofiste bir dosya değişir → sonraki açılışta görünür; organ sökülünce kırmızı.
fv=$(mktemp -d); fo=$(mktemp -d)
mkdir -p "$fv/🛠️ Veriler" "$fo/eski-proje" "$fo/canli-proje/node_modules" "$fo/ajans/seritler"
fk() { BEYIN_OFIS_DIR="$fo" bash "$H/farkindalik.sh" "$fv" 2>/dev/null; }
: > "$fo/eski-proje/a.md"; touch -d '10 days ago' "$fo/eski-proje/a.md"
o=$(fk)
bos_mu "söyleyecek bir şey yokken susuyor" "" "$o"
: > "$fo/canli-proje/node_modules/x.js"
o=$(fk)
bos_mu "node_modules değişikliğini saymıyor" "" "$o"
: > "$fo/canli-proje/ana.py"
o=$(fk)
icerir "ofiste değişen dosya görünüyor" "canli-proje" "$o"
icerir "değişen dosyanın adını söylüyor" "ana.py" "$o"
case "$o" in *eski-proje*) kal "eski değişikliği göstermiyor" "eski-proje yok" "var" ;; *) gec "eski değişikliği göstermiyor" ;; esac
mkdir -p "$fo/ajans/seritler/2026-01-01-deneme"; : > "$fo/ajans/seritler/2026-01-01-deneme/emir.md"
o=$(fk)
icerir "makbuzsuz şeridi açık sayıyor" "2026-01-01-deneme" "$o"
: > "$fo/ajans/seritler/2026-01-01-deneme/makbuz.md"
o=$(fk)
case "$o" in *2026-01-01-deneme*) kal "makbuzlu şeridi kapalı sayıyor" "şerit yok" "var" ;; *) gec "makbuzlu şeridi kapalı sayıyor" ;; esac
printf -- '---\nmodified: 2020-01-01\n---\nnot\n' > "$fv/🛠️ Veriler/eski-bilgi.md"
printf -- '---\nmodified: %s\n---\nnot\n' "$(date +%F)" > "$fv/🛠️ Veriler/taze-bilgi.md"
o=$(fk)
icerir "bayat bilgi notunu söylüyor" "eski-bilgi" "$o"
case "$o" in *taze-bilgi*) kal "taze notu bayat saymıyor" "taze yok" "var" ;; *) gec "taze notu bayat saymıyor" ;; esac
rm -rf "$fv" "$fo"
# Organ açılışa bağlı mı? Sökülürse bu test kırmızıya döner.
# Ofiste taze bir dosya olan sahte ortamda açılış çalışır: gerçek ofisin o anki durumuna bağlı değil.
fo=$(mktemp -d); mkdir -p "$fo/p"; : > "$fo/p/taze.md"
m=$(echo '{"session_id":"test"}' | BEYIN_OFIS_DIR="$fo" bash "$H/session-start.sh" 2>/dev/null \
    | python3 -c 'import sys,json;print(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"])' 2>/dev/null)
icerir "açılış bağlamında Farkındalık bloğu var" "[Farkındalık]" "$m"
rm -rf "$fo"

echo
echo "10) Kardeş takımlar (organlar)"
# Her organın kendi düşman takımı var; ana takım onları da koşturur ki biri
# sessizce kırmızıya dönmesin.
for t in testler-defter.sh testler-emeklilik.sh testler-kapi.sh testler-jev.sh testler-projektor.sh testler-derle.sh testler-deha-hal.sh; do
  [ -f "$S/$t" ] || { kal "$t mevcut" "dosya" "yok"; continue; }
  son=$(bash "$S/$t" 2>&1 | tail -n 1)
  case "$son" in *" 0 kaldı"*) gec "$t: $son" ;; *) kal "$t yeşil" "0 kaldı" "$son" ;; esac
done

# dokunma kaydını geri koy
# -s değil -f: boş ama var olan bir kayıt dosyası silinmemeli
if [ -f "$yedek" ]; then cp "$yedek" "$DURUM/dokunma.tsv"; else rm -f "$DURUM/dokunma.tsv"; fi
rm -f "$yedek"
find "$S" -name "__pycache__" -type d -exec rm -rf {} + 2>/dev/null || :

echo
printf 'Sonuç: %s geçti, %s kaldı\n' "$gecen" "$kalan"
[ "$kalan" -eq 0 ]
