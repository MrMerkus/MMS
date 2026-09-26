#!/usr/bin/env bash
# Denetçi — konseyin şart koştuğu dört koşulu ve yedek tazeliğini kontrol eder.
#
# Neden var: konsey kararında Torvalds'ın şerhi şuydu — "mesafeyle korunan sınır
# dosya sisteminin doğal sonucuydu, bakımı bedavaydı; yapılandırmayla korunan
# sınır insan alışkanlığına bağlıdır: parmaklar `git init .` yazar."
# Bu script o alışkanlığın açtığı deliği kapatır. Kural denetlenmezse sözdür.
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
hata=0
uyari=0

ok()  { printf '  ✅ %s\n' "$1"; }
no()  { printf '  ❌ %s\n' "$1"; hata=$((hata+1)); }
uy()  { printf '  ⚠️  %s\n' "$1"; uyari=$((uyari+1)); }

echo "Denetçi — $(date '+%Y-%m-%d %H:%M')"
echo

echo "1) Depo sınırı"
ic=$(find "$kok" -name .git -mindepth 2 -maxdepth 4 2>/dev/null | head -5)
if [ -n "$ic" ]; then
  no "vault içinde ikinci .git bulundu:"; printf '     %s\n' $ic
else
  ok "vault içinde başka depo yok"
fi
ust="$(dirname "$kok")"
if [ -e "$ust/.git" ]; then
  no "üst klasörde .git var ($ust) — vault başka bir deponun içinde kalmış"
else
  ok "üst klasörde depo yok"
fi

echo
echo "2) Obsidian vault kökü"
if [ -d "$kok/.obsidian" ]; then ok "vault kökü doğru yerde (.obsidian vault içinde)"
else uy "vault kökünde .obsidian yok — Obsidian yapılandırması kontrol edilmeli"; fi
if [ -e "$ust/.obsidian" ]; then no "üst klasörde .obsidian var — Obsidian ofisi de indeksliyor olabilir"
else ok "üst klasör Obsidian vault'u değil"; fi

echo
echo "3) Derleyici kapsamı"
if grep -q 'ofis\|çalışma ofisi' "$kok/.claude/scripts/projektor.py" 2>/dev/null; then
  uy "projektor.py ofis yolu içeriyor — kapsamı gözden geçir"
else
  ok "derleyici ofise bakmıyor"
fi
kod=$(find "$kok" -maxdepth 3 \( -name node_modules -o -name venv -o -name .venv \) 2>/dev/null | head -3)
if [ -n "$kod" ]; then no "vault içinde kod klasörü sızmış:"; printf '     %s\n' $kod
else ok "vault içinde node_modules/venv yok"; fi

echo
echo "4) Uzak yedek"
if ! git -C "$kok" remote get-url origin >/dev/null 2>&1; then
  no "uzak depo tanımlı değil — yedek yok"
else
  ok "uzak depo: $(git -C "$kok" remote get-url origin)"
  bekleyen=$(git -C "$kok" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
  [ "$bekleyen" -gt 0 ] && uy "$bekleyen commit edilmemiş değişiklik var" || ok "çalışma ağacı temiz"
  gonderilmemis=$(git -C "$kok" rev-list --count '@{u}..HEAD' 2>/dev/null || echo "?")
  if [ "$gonderilmemis" = "0" ]; then ok "her şey uzağa gönderilmiş"
  else uy "$gonderilmemis commit henüz push edilmemiş — .claude/scripts/yedek.sh çalıştır"; fi
fi

echo
echo "5) Kasa dokunulmazlığı"
if grep -q 'kasa' "$kok/.claude/hooks/session-start.sh" 2>/dev/null; then
  uy "yükleyici 'kasa' kelimesini içeriyor — okumadığını doğrula"
else
  ok "yükleyici kasa'ya hiç bakmıyor"
fi

echo
echo "6) Enjeksiyon tavanları (sessiz kırpılma erken uyarısı)"
# Kırpılma bir not bırakıyor ama iş işten geçmiş oluyor: kural bağlama girmemiş
# oluyor. Bu yüzden tavana YAKLAŞMA da bildirilir.
tavan_kontrol() {
  ad=$1; dosya=$2; tavan=$3; kirp=${4:-}
  [ -f "$dosya" ] || return 0
  if [ "$kirp" = "60satir" ]; then
    boy=$(sed -n '/^---$/,/^---$/!p' "$dosya" | sed -n '1,60p' | LC_ALL=C.UTF-8 wc -m | tr -d ' ')
  else
    boy=$(sed -n '/^---$/,/^---$/!p' "$dosya" | LC_ALL=C.UTF-8 wc -m | tr -d ' ')  # karakter: SOZLESME ve saglik.sh ile aynı ölçü
  fi
  yuzde=$((boy * 100 / tavan))
  if [ "$yuzde" -ge 100 ]; then
    no "$ad: $boy/$tavan karakter (%$yuzde) — KIRPILIYOR, içerik bağlama girmiyor"
  elif [ "$yuzde" -ge 85 ]; then
    uy "$ad: $boy/$tavan karakter (%$yuzde) — tavana yaklaştı, sadeleştir veya tavanı yükselt"
  else
    ok "$ad: $boy/$tavan karakter (%$yuzde)"
  fi
}
tavan_kontrol "Kurallar" "$kok/🔮 zihin/Kurallar.md" 4000 60satir
# Alt kural dosyaları enjekte edilmez, tetiklenince açılır: aşım kırpılma değil,
# bölme sinyalidir (SOZLESME.md, Karar 3). Bu yüzden hata değil uyarı.
for kural_alt in "$kok/🔮 zihin/kurallar/"*.md; do
  [ -f "$kural_alt" ] || continue
  case "$kural_alt" in */INDEKS.md) continue ;; esac
  alt_boy=$(wc -m < "$kural_alt" 2>/dev/null | tr -d ' ')
  case "$alt_boy" in ''|*[!0-9]*) continue ;; esac
  if [ "$alt_boy" -gt 4000 ]; then
    uy "kurallar/$(basename "$kural_alt"): $alt_boy/4000 — bölme sinyali (enjekte edilmiyor)"
  else
    ok "kurallar/$(basename "$kural_alt"): $alt_boy/4000"
  fi
done
tavan_kontrol "kalan işler indeksi" "$kok/🔮 zihin/kalan-isler/INDEKS.md" 4600
if [ -n "$(ls -1 "$kok/🔮 zihin/son-oturum"/20*.md 2>/dev/null)" ]; then
  tavan_kontrol "son oturum" "$(ls -1 "$kok/🔮 zihin/son-oturum"/20*.md | tail -n 1)" 3800
fi
toplam=$(echo '{"session_id":"denetci"}' | bash "$kok/.claude/hooks/session-start.sh" 2>/dev/null \
  | python3 -c 'import sys,json;print(len(json.load(sys.stdin)["hookSpecificOutput"]["additionalContext"]))' 2>/dev/null || echo 0)
. "$kok/.claude/hooks/esikler.sh"
if [ "$toplam" -ge "$BAGLAM_TAVAN" ]; then
  no "toplam bağlam $toplam/$(binlik "$BAGLAM_TAVAN") — kırmızı: tavan aşıldı, kırpılıyor"
elif [ "$toplam" -gt "$BAGLAM_TURUNCU" ]; then
  uy "toplam bağlam $toplam — turuncu bölge ($(binlik "$BAGLAM_TURUNCU") üstü, tavan $(binlik "$BAGLAM_TAVAN"))"
elif [ "$toplam" -gt "$BAGLAM_HEDEF" ]; then
  uy "toplam bağlam $toplam — hedef $(binlik "$BAGLAM_HEDEF")'in üstünde (turuncu $(binlik "$BAGLAM_TURUNCU"))"
else
  ok "toplam bağlam $toplam/$(binlik "$BAGLAM_HEDEF") hedef"
fi

# "Ne zaman aç" yazılmamış (❔) ya da rengi değişmiş (↻) kalan-iş satırı: indeks
# durum metnini açıklama sanmasın diye yedek kaldırıldı; boşluk burada görünür.
isaretli=$(cat "$kok/🔮 zihin/kalan-isler"/INDEKS*.md 2>/dev/null | grep -cE '^\| \[\[.*\| (❔|↻)')
if [ "$isaretli" -gt 0 ]; then
  uy "kalan-iş indeksinde $isaretli satır ❔/↻ — \"ne zaman aç\" elle yazılmalı"
else
  ok "kalan-iş indeksinde her satırın \"ne zaman aç\" açıklaması var"
fi

echo
echo "6d) Bayat kayıt (yerini aldı işareti)"
motor="${BEYIN_MOTOR:-$HOME/.config/beyin/motor}"
bayat=$(python3 "$kok/.claude/scripts/bayat-tara.py" "$kok" "$motor/DURUM.md" "$motor/PLAN.md" \
  "$motor/SOZLESME.md" "$motor/IYILESTIRME.md" "$HOME/.claude/skills" 2>/dev/null)
if [ -n "$bayat" ]; then
  uy "işaretsiz bayat kayıt: $(printf '%s\n' "$bayat" | wc -l) (eski kayda 'yerini aldı: <yeni>' yaz)"
  printf '%s\n' "$bayat" | sed "s#$HOME#~#; s/^/     /"
else
  ok "işaretsiz bayat kayıt yok"
fi

echo
echo "6b) Derleme günlüğü büyüklüğü"
# knowledge/ tavandan muaftır çünkü bağlama girmez; ama derleyici her çalıştığında
# log.md'yi açıp sonuna ekler, yani birikmiş her satırın bir derleme maliyeti var.
logd="$kok/knowledge/log.md"
if [ -f "$logd" ]; then
  girdi=$(grep -c '^## \[' "$logd" 2>/dev/null || echo 0)
  eski_yil=$(grep -oE '^## \[[0-9]{4}' "$logd" 2>/dev/null | grep -oE '[0-9]{4}' \
             | sort -u | grep -v "^$(date +%Y)$" | tr '\n' ' ')
  if [ -n "$eski_yil" ]; then
    uy "günlükte geçmiş yıl girdisi var ($eski_yil) — log-dondur.py çalıştır"
  elif [ "$girdi" -ge 400 ]; then
    uy "$girdi girdi ($(date +%Y)) — yıl içi birikme eşiği aşıldı"
  else
    ok "$girdi girdi, hepsi $(date +%Y) yılından"
  fi
else
  uy "knowledge/log.md yok"
fi

echo
echo "6c) Bilgi indeksi büyüklüğü"
# index.md döndürülemez (arama tablosudur, geçmişi değil güncel hâli işe yarar)
# ama derleyici her çalışmada onu okuyup satır güncelliyor. Büyüdükçe her
# derleme pahalılaşır. log.md ile aynı eksen, farklı çözüm: bölme, döndürme değil.
idx="$kok/knowledge/index.md"
if [ -f "$idx" ]; then
  satir=$(grep -c '^| \[\[' "$idx" 2>/dev/null || echo 0)
  kar=$(wc -c < "$idx" | tr -d ' ')
  if [ "$satir" -ge 400 ]; then
    no "$satir makale satırı ($kar karakter) — konuya göre bölünmeli"
  elif [ "$satir" -ge 200 ]; then
    uy "$satir makale satırı ($kar karakter) — bölme eşiğine yaklaşıyor"
  else
    ok "$satir makale satırı ($kar karakter)"
  fi
else
  uy "knowledge/index.md yok"
fi

echo
echo "7) Kasa git yoksayımında mı"
if grep -q '🔐 kasa/\*' "$kok/.gitignore" 2>/dev/null; then
  ok "kasa .gitignore'da — otomatik yedek onu uzağa göndermez"
else
  no "kasa .gitignore'da DEĞİL — SessionEnd yedeği hassas dosyaları push edebilir"
fi

echo
printf 'Sonuç: %s hata, %s uyarı\n' "$hata" "$uyari"
[ "$hata" -eq 0 ]
