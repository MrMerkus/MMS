#!/usr/bin/env bash
# Yedek — vault'u uzak depoya gönderir.
#
# ÇALIŞMA BİÇİMİ: <KULLANICI>'nın onayıyla SessionEnd'e bağlandı; her oturum sonunda
# arka planda çalışır (günlük yazıcısını beklemek için 25 sn gecikmeli). Ayrıca
# elle de çağrılabilir. Hassas klasör .gitignore'da olduğu için uzağa gitmez.
#
# Push başarısız olursa .state/yedek-basarisiz bayrağı bırakılır ve bir sonraki
# açılışta bağlama basılır — sessiz kalmasın diye.
set -euo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
cd "$kok"

if ! git remote get-url origin >/dev/null 2>&1; then
  echo "uzak depo tanımlı değil — önce 'git remote add origin <url>'"; exit 1
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
durum_dizin="$kok/.claude/scripts/.state"
if [ "$gonderilmemis" -gt 0 ]; then
  if git push -q origin HEAD 2>/dev/null; then
    rm -f "$durum_dizin/yedek-basarisiz" 2>/dev/null || :
    echo "$gonderilmemis commit gönderildi -> $(git remote get-url origin)"
  else
    mkdir -p "$durum_dizin" 2>/dev/null || :
    printf 'Yedek push edilemedi (%s commit bekliyor): %s\n' \
      "$gonderilmemis" "$(date '+%Y-%m-%d %H:%M')" > "$durum_dizin/yedek-basarisiz"
    echo "PUSH BAŞARISIZ — bayrak bırakıldı"
    exit 1
  fi
else
  rm -f "$durum_dizin/yedek-basarisiz" 2>/dev/null || :
  echo "gönderilecek commit yok, uzak güncel"
fi
