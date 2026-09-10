#!/usr/bin/env bash
# Boş kalan klasörler için soru üretir. session-start.sh tarafından çağrılır.
#
# Neden var: 💪 Beden ve 🧘 Düşünceler iki aydır boştu, çünkü onları dolduran
# bir şey yoktu. <KULLANICI>'nın isteği: "arada bana soru sorarak bunları doldursun."
# Kural değil mekanizma — sistemin geri kalanıyla aynı mantık.
#
# Ne yapmaz: her oturumda sormaz. Klasör tazeyse susar, sorulduysa bir süre bekler.
set -uo pipefail
kok="${1:-}"
[ -n "$kok" ] && [ -d "$kok" ] || exit 0
durum="$kok/.claude/scripts/.state"
bekleme=${BEYIN_SORU_BEKLEME:-7}   # gün

sor() {
  klasor=$1; etiket=$2; soru=$3
  # klasörde son değişiklik kaç gün önce
  son=$(find "$kok/$klasor" -name '*.md' -newermt "-${bekleme} days" 2>/dev/null | head -1)
  [ -n "$son" ] && return 0                      # taze, sorma
  isaret="$durum/soruldu-$etiket"
  if [ -f "$isaret" ]; then
    [ -n "$(find "$isaret" -newermt "-${bekleme} days" 2>/dev/null)" ] && return 0
  fi
  mkdir -p "$durum" 2>/dev/null || :
  : > "$isaret" 2>/dev/null || :
  printf '%s\n' "$soru"
}

sor "💪 Beden" "beden" "💪 Beden/ $bekleme gündür boş. Uygun bir anda <KULLANICI>'ya sor: uyku düzeni, spor ve genel sağlık nasıl gidiyor? Cevabı 💪 Beden/ altına yaz; kendin doldurma."
sor "🧘 Düşünceler" "dusunceler" "🧘 Düşünceler/ $bekleme gündür boş. Uygun bir anda <KULLANICI>'ya sor: kafanı meşgul eden, henüz bir yere yazmadığı bir şey var mı? Cevabı 🧘 Düşünceler/ altına yaz; kendin doldurma."
exit 0
