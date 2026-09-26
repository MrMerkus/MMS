#!/usr/bin/env bash
# Deha hal kancası (Karar 12, adım 3): arayüzün içindeki Claude'un olaylarını küçük bir durum
# dosyasına yazar; arayüz o dosyayı izleyip avatarın halini değiştirir.
#
# - Yalnız DEHA_DURUM tanımlıysa çalışır. Arayüz terminali açarken verir; kardeş oturumlarda
#   yoktur, Deha onlarla oynamaz. Yol yalnız $XDG_RUNTIME_DIR/deha/ altında olabilir.
# - Olayı yazar, hali değil: olay → hal eşleşmesi arayüzdedir (tek yerde değişsin).
# - Hiçbir koşulda stdout/stderr'e yazmaz (UserPromptSubmit çıktısı Claude'un bağlamına girer)
#   ve her zaman 0 döner. Hafızaya dokunmaz.
#
# Kullanım (settings.json): bash deha-hal.sh <UserPromptSubmit|PreToolUse|Stop|Notification|SessionStart>
exec >/dev/null 2>&1
[ -n "${DEHA_DURUM:-}" ] || exit 0
calisma="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}"
case "$DEHA_DURUM" in "$calisma"/deha/*) ;; *) exit 0 ;; esac
case "$DEHA_DURUM" in *..*) exit 0 ;; esac
olay="${1:-}"
case "$olay" in UserPromptSubmit|PreToolUse|Stop|Notification|SessionStart) ;; *) exit 0 ;; esac

mkdir -p "$(dirname "$DEHA_DURUM")" || exit 0
gecici="$DEHA_DURUM.$$"
printf '{"olay":"%s","zaman":%s}\n' "$olay" "$(date +%s%3N)" > "$gecici" && mv -f "$gecici" "$DEHA_DURUM"
rm -f "$gecici"
exit 0
