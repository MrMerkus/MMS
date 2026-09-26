#!/usr/bin/env bash
# Emeklilik düşman testleri — Organ 4 (SOZLESME Karar 1 + Karar 6 satır 4).
#
# Ölçüt: 30 gün dokunulmamış kalan-iş enjeksiyondan (INDEKS.md) kendiliğinden düşer,
# dosyası yerinde kalır, indekste tek satır iz bırakır, dokunulunca geri döner.
#
# Arayüz sözleşmesi (uygulama bu dosyayı değiştirerek geçemez):
#   emeklilik.py [klasör] [--dene] [--gun N] [--geri <ad>]
#   - Tek yazıcı indeks-uret.py'dir; emeklilik yalnız karar verir. indeks-uret
#     tek başına çalıştırılınca da soğumuş satır INDEKS.md'ye geri dönmez.
#   - Soğuyan satır INDEKS-soguk.md'ye iner: "❄️ soğudu, son dokunuş <tarih>, gerekirse aç".
#   - Son dokunuş = max(dosyanın mtime'ı, frontmatter `modified`).
#   - Tetik kapanis.sh'tadır (oturum sonu).
#
# 🔴 düşmez. Gerekçe (Karar 1): düşme ölçütünün ilk ayağı DURUM'dur. 🔴 "karar
# bekliyor, acil" demektir; 30 gün dokunulmamış 🔴 unutulmuş bir karardır ve onu
# enjeksiyondan düşürmek tam da "hiçbir mekanizma sessizce bozulamaz" değişmezini
# çiğner. Soğutmak yerine görünür kalır; durumunu değiştirmek insanın işidir.
# ⚪/⏸️ zaten uyuyan katmandadır, bağlama girmez; emeklilik onlara dokunmaz.
#
# Yan etkisiz: sahte vault'ta çalışır, sonda gerçek kalan-isler'in değişmediği ölçülür.
# emeklilik.py yokken kırmızıdır.
#
# Kullanım: testler-emeklilik.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
S="$kok/.claude/scripts"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; return 0; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }
icerir() { case "$3" in *"$2"*) gec "$1" ;; *) kal "$1" "içinde '$2'" "${3:0:120}" ;; esac; }
icermez() { case "$3" in *"$2"*) kal "$1" "'$2' olmamalı" "${3:0:120}" ;; *) gec "$1" ;; esac; }

gecici=$(mktemp -d)
trap 'rm -rf "$gecici"' EXIT
GERCEK="$kok/🔮 zihin/kalan-isler"
iz() { (cd "$GERCEK" && ls -la --time-style=+%s . && cat ./*.md) 2>/dev/null | sha256sum; }
iz_once=$(iz)

# Sahte vault: script'ler kopyalanır, kök script konumundan bulunur.
v="$gecici/vault"; K="$v/🔮 zihin/kalan-isler"
mkdir -p "$v/.claude/scripts" "$K"
for f in emeklilik.py indeks-uret.py kapanis.sh; do
  [ -f "$S/$f" ] && cp "$S/$f" "$v/.claude/scripts/"
done

kayit() { # ad renk gün-önce [ek-frontmatter]
  printf -- '---\ntitle: %s\ntype: kalan-is\ndurum: açık\n%s---\n\n# %s\n\n**Status:** %s iş\n\nGövde.\n' \
    "$1" "${4:-}" "$1" "$2" > "$K/$1.md"
  touch -d "$3 days ago" "$K/$1.md"
}
kayit eski   🟡 31
kayit taze   🟡 29
kayit kirmizi 🔴 40
kayit yesil  🟢 45
kayit uyuyan ⚪ 50
kayit fm-taze 🟡 40 "modified: $(date -d '3 days ago' +%F)
"
kayit geri-al 🟡 35
printf -- '---\ntitle: eski geçmiş\ntype: gecmis\ndurum: arşiv\n---\n\nArşiv.\n' > "$K/eski-gecmis.md"
touch -d "90 days ago" "$K/eski-gecmis.md"
# Elle yazılmış "ne zaman aç" açıklaması: soğuyup geri dönünce kaybolmamalı.
printf -- '---\ntitle: kalan-isler — indeks\ntype: indeks\n---\n\n| Konu | Durum | Ne zaman aç |\n| --- | --- | --- |\n| [[eski\\|eski]] | 🟡 | ELLE-YAZILDI eski konuşulurken |\n' > "$K/INDEKS.md"

em() { (cd "$v" && timeout 60 python3 .claude/scripts/emeklilik.py "$K" "$@" 2>&1); }
satir_var() { grep -q "\[\[$1\\\\|" "$K/$2" 2>/dev/null; }

echo "Emeklilik düşman testleri — $(date '+%Y-%m-%d %H:%M')"
[ -f "$S/emeklilik.py" ] || echo "  (emeklilik.py yok: kırmızı beklenen hal)"
echo

echo "1) Kuru çalıştırma"
once=$(cd "$K" && cat ./* | sha256sum)
o=$(em --dene)
icerir "31 günlük soğuyacak listesinde" "eski" "$o"
icermez "29 günlük listede yok" "taze" "$o"
esit "kuru çalıştırma hiçbir şey yazmıyor" "$once" "$(cd "$K" && cat ./* | sha256sum)"
[ -f "$K/INDEKS-soguk.md" ] && kal "kuru çalıştırma soğuk indeksi açmıyor" "dosya yok" "var" \
  || gec "kuru çalıştırma soğuk indeksi açmıyor"

echo
echo "2) Düşme ve iz"
em >/dev/null
satir_var eski INDEKS.md && kal "31 günlük INDEKS.md'den düştü" "satır yok" "var" || gec "31 günlük INDEKS.md'den düştü"
[ -f "$K/eski.md" ] && gec "düşmek silmek değil: dosya yerinde" || kal "dosya yerinde" "eski.md" "yok"
satir_var eski INDEKS-soguk.md && gec "soğuk indekste satırı var" || kal "soğuk indekste satırı var" "satır" "yok"
o=$(grep "\[\[eski\\\\|" "$K/INDEKS-soguk.md" 2>/dev/null)
icerir "iz satırı 'soğudu' diyor" "soğudu" "$o"
icerir "iz satırı son dokunuş tarihini veriyor" "$(date -d '31 days ago' +%F)" "$o"
icerir "iz satırı 'gerekirse aç' diyor" "gerekirse aç" "$o"
esit "iz tek satır (tüm indekslerde bir kez)" "1" "$(cat "$K"/INDEKS*.md | grep -c '\[\[eski\\|')"
icerir "INDEKS.md soğuk indekse yol gösteriyor" "INDEKS-soguk" "$(cat "$K/INDEKS.md")"
satir_var yesil INDEKS-aktif.md && kal "45 günlük 🟢 aktif'ten de düştü" "aktif'te yok" "var" || gec "45 günlük 🟢 aktif'ten de düştü"
satir_var eski-gecmis INDEKS-soguk.md && kal "geçmiş/arşiv dosyası soğuk listeye girmiyor" "yok" "var" \
  || gec "geçmiş/arşiv dosyası soğuk listeye girmiyor"

echo
echo "3) Düşmeyenler"
satir_var taze INDEKS.md && gec "29 günlük yerinde" || kal "29 günlük yerinde" "INDEKS.md'de" "yok"
satir_var kirmizi INDEKS.md && gec "🔴 karar bekleyen 40 günde de düşmüyor" || kal "🔴 düşmüyor" "INDEKS.md'de" "yok"
satir_var uyuyan INDEKS-uyuyan.md && gec "⚪ uyuyan katmanında kalıyor" || kal "⚪ uyuyanda" "INDEKS-uyuyan.md'de" "yok"
satir_var fm-taze INDEKS.md && gec "frontmatter 'modified' tazeyse düşmüyor" || kal "modified tazeyse düşmüyor" "INDEKS.md'de" "yok"

echo
echo "4) Tek yazıcı"
(cd "$v" && python3 .claude/scripts/indeks-uret.py "$K" >/dev/null 2>&1)
satir_var eski INDEKS.md && kal "indeks-uret tek başına soğuğu geri getirmiyor" "INDEKS.md'de yok" "geri geldi" \
  || gec "indeks-uret tek başına soğuğu geri getirmiyor"

echo
echo "5) Geri alma"
touch "$K/eski.md"
em >/dev/null
satir_var eski INDEKS.md && gec "dosyaya dokunulunca INDEKS.md'ye dönüyor" || kal "dokununca dönüyor" "INDEKS.md'de" "yok"
satir_var eski INDEKS-soguk.md && kal "dönen satır soğuktan çıkıyor" "yok" "var" || gec "dönen satır soğuktan çıkıyor"
icerir "elle yazılan açıklama dönüşte korunuyor" "ELLE-YAZILDI" "$(grep '\[\[eski\\|' "$K/INDEKS.md" 2>/dev/null)"
o=$(em --geri geri-al); k=$?
esit "geri alma komutu çıkış 0" "0" "$k"
satir_var geri-al INDEKS.md && gec "--geri ile INDEKS.md'ye dönüyor" || kal "--geri ile dönüyor" "INDEKS.md'de" "yok"
o=$(em --geri olmayan-kayit); k=$?
[ "$k" -ne 0 ] && gec "olmayan kayıt için --geri hata veriyor" || kal "olmayan kayıt --geri" "çıkış ≠ 0" "0"

echo
echo "6) Otomatik tetik (kapanis.sh)"
touch -d "33 days ago" "$K/eski.md"
D="$v/📓 Günlük/defter"; mkdir -p "$D"
printf -- '---\ntitle: 2026-09-20 — Yeni gün girdisi\n---\n\nBugün uzun bir konu cümlesi yazıldı burada.\n' > "$D/2026-09-20.md"
(cd "$v" && bash .claude/scripts/kapanis.sh >/dev/null 2>&1)
satir_var eski INDEKS-soguk.md && gec "oturum sonu kapanışı soğutuyor" || kal "kapanış soğutuyor" "INDEKS-soguk.md'de" "yok"
grep -q '\[\[2026-09-20' "$D/INDEKS.md" 2>/dev/null && gec "kapanış defter indeksini tamamlıyor" || kal "kapanış defter indeksini tamamlıyor" "2026-09-20 satırı" "yok"

echo
echo "7) Gerçek vault"
esit "gerçek kalan-isler değişmedi" "$iz_once" "$(iz)"

echo
echo "Sonuç: $gecen geçti, $kalan kaldı"
[ "$kalan" -eq 0 ]
