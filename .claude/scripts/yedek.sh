#!/usr/bin/env bash
# Yedek — vault'u uzak depoya gönderir.
#
# ÇALIŞMA BİÇİMİ: kullanıcının onayıyla SessionEnd'e bağlandı; her oturum sonunda
# arka planda çalışır (günlük yazıcısını beklemek için 25 sn gecikmeli). Ayrıca
# elle de çağrılabilir. Hassas klasör .gitignore'da olduğu için uzağa gitmez.
#
# Push başarısız olursa .state/yedek-basarisiz bayrağı bırakılır ve bir sonraki
# açılışta bağlama basılır — sessiz kalmasın diye.
set -euo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"

# Tek yedek (kullanıcı, 25 Eylül): oturumlar yakın kapanınca iki yedek aynı anda testleri koşturup
# birbirini kırmızıya düşürüyordu ("Yedek durdu" bildirimi). İkinci yedek birincisini bekler;
# beklerken değişiklik birincinin commit'ine girmişse "commit edilecek değişiklik yok" der.
mkdir -p "$kok/.claude/scripts/.state" 2>/dev/null || :
exec 9>"$kok/.claude/scripts/.state/yedek.lock"
flock -w 300 9 || { echo "başka bir yedek 300 sn'dir sürüyor, bu tur atlandı"; exit 0; }

# Ek depolar (2026-09-15, kullanıcı onayı): vault dışında yaşayan skill'ler ve gözlem defteri.
# Private GitHub depoları. Biri başarısız olsa da vault yedeği sürer.
for ek in "$HOME/.claude/skills" "$HOME/ofis/skill-gozlemleri"; do
  [ -d "$ek/.git" ] || continue
  (
    cd "$ek"
    if [ -n "$(git status --porcelain)" ]; then
      git add -A && git commit -q -m "Yedek: $(date '+%Y-%m-%d %H:%M')"
    fi
    git push -q origin HEAD 2>/dev/null && echo "ek yedek: $ek" || echo "EK YEDEK BAŞARISIZ: $ek"
  ) || :
done

cd "$kok"

# Olay defteri (Karar 4): push sonucu deftere düşer. Defter yedeği asla düşürmez.
# Olay push'tan sonra yazıldığı için bir sonraki yedekte commit'lenir (kabul edildi).
olay_yaz() {
  local bas
  bas=$(git rev-parse HEAD 2>/dev/null) || return 0
  python3 "$kok/.claude/scripts/olaylar.py" yaz --tip yedek --kimlik "yedek:$bas:$1" \
    --kaynak yedek.sh --veri "{\"commit\":\"$bas\",\"gonderilen\":$2,\"sonuc\":\"$1\"}" \
    >/dev/null 2>&1 || :
}

if ! git remote get-url origin >/dev/null 2>&1; then
  olay_yaz uzak-yok 0
  echo "uzak depo tanımlı değil — önce 'git remote add origin <url>'"; exit 1
fi

durum_dizin="$kok/.claude/scripts/.state"

# Yedek kapısı (kullanıcı, 24 Eylül): testler kırmızıysa commit yok, kullanıcıya söylenir.
# Paralel oturumun yarım işi yedeğe girip push edilmesin diye (35f663c, 469aa72).
# Test takımı yedek.sh'ı sahte vault'ta çağırır; BEYIN_TESTLER_KOSUYOR döngüyü keser.
testler="$kok/.claude/scripts/testler.sh"
if [ -n "$(git status --porcelain)" ] && [ -f "$testler" ] && [ -z "${BEYIN_TESTLER_KOSUYOR:-}" ]; then
  if ! sonuc=$(BEYIN_TESTLER_KOSUYOR=1 timeout 300 bash "$testler" 2>&1); then
    ozet=$(printf '%s\n' "$sonuc" | grep -E '^Sonuç|kaldı' | tail -1)
    mkdir -p "$durum_dizin" 2>/dev/null || :
    printf 'Yedek durdu, testler kırmızı (%s), commit atılmadı: %s\n' \
      "${ozet:-sonuç okunamadı}" "$(date '+%Y-%m-%d %H:%M')" > "$durum_dizin/yedek-basarisiz"
    olay_yaz testler-kirmizi 0
    command -v notify-send >/dev/null 2>&1 && \
      notify-send -u critical "Yedek durdu" "Testler kırmızı, commit atılmadı. ${ozet}" 2>/dev/null || :
    echo "TESTLER KIRMIZI — commit atılmadı, bayrak bırakıldı"
    exit 1
  fi
fi

if [ -n "$(git status --porcelain)" ]; then
  mesaj="${1:-Yedek: $(date '+%Y-%m-%d %H:%M')}"
  git add -A
  git commit -q -m "$mesaj"
  echo "commit atıldı: $mesaj"
else
  echo "commit edilecek değişiklik yok"
fi

gonderilmemis=$(git rev-list --count '@{u}..HEAD' 2>/dev/null || echo 0)
if [ "$gonderilmemis" -gt 0 ]; then
  if git push -q origin HEAD 2>/dev/null; then
    rm -f "$durum_dizin/yedek-basarisiz" 2>/dev/null || :
    olay_yaz ok "$gonderilmemis"
    echo "$gonderilmemis commit gönderildi -> $(git remote get-url origin)"
  else
    mkdir -p "$durum_dizin" 2>/dev/null || :
    printf 'Yedek push edilemedi (%s commit bekliyor): %s\n' \
      "$gonderilmemis" "$(date '+%Y-%m-%d %H:%M')" > "$durum_dizin/yedek-basarisiz"
    olay_yaz push-basarisiz "$gonderilmemis"
    echo "PUSH BAŞARISIZ — bayrak bırakıldı"
    exit 1
  fi
else
  rm -f "$durum_dizin/yedek-basarisiz" 2>/dev/null || :
  echo "gönderilecek commit yok, uzak güncel"
fi
