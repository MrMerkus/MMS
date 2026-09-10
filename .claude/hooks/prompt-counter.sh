#!/bin/bash
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
# Count prompts and nudge at every multiple of fifteen.

BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0

BEYIN_SESSION_KEY=$(beyin_session_key 2>/dev/null || :)
[ -n "$BEYIN_SESSION_KEY" ] || exit 0

BEYIN_PROMPT_COUNT_FILE="$BEYIN_STATE_DIR/prompt_count.$BEYIN_SESSION_KEY"
BEYIN_LOCK_DIR="$BEYIN_PROMPT_COUNT_FILE.lock"
# Sahipsiz kalmış bir kilit hook'u kalıcı olarak susturuyordu: 500 deneme x 10ms
# hook timeout'unu (5 sn) aşıyor, süreç öldürülüyor, sayaç hiç artmıyor ve
# "hafıza yazılmadı" bayrağı hiç düşmüyordu. Artık 100 deneme (~1 sn) ve
# 60 saniyeden eski kilit zorla kaldırılıyor.
if [ -d "$BEYIN_LOCK_DIR" ]; then
  BEYIN_LOCK_MT=$(beyin_mtime "$BEYIN_LOCK_DIR" 2>/dev/null || echo 0)
  case "$BEYIN_LOCK_MT" in ''|*[!0-9]*) BEYIN_LOCK_MT=0 ;; esac
  BEYIN_SIMDI=$(date '+%s' 2>/dev/null || echo 0)
  if [ "$BEYIN_LOCK_MT" -gt 0 ] && [ $((BEYIN_SIMDI - BEYIN_LOCK_MT)) -gt 60 ]; then
    rmdir "$BEYIN_LOCK_DIR" 2>/dev/null || :
  fi
fi
BEYIN_LOCK_ATTEMPT=0
while ! mkdir "$BEYIN_LOCK_DIR" 2>/dev/null; do
  BEYIN_LOCK_ATTEMPT=$((BEYIN_LOCK_ATTEMPT + 1))
  [ "$BEYIN_LOCK_ATTEMPT" -lt 100 ] || exit 0
  sleep 0.01 2>/dev/null || sleep 1 2>/dev/null || exit 0
done
trap 'rmdir "$BEYIN_LOCK_DIR" 2>/dev/null || :' EXIT
trap 'exit 0' HUP INT TERM

BEYIN_COUNT=0
if [ -f "$BEYIN_PROMPT_COUNT_FILE" ]; then
  BEYIN_COUNT=$(sed -n '1p' "$BEYIN_PROMPT_COUNT_FILE" 2>/dev/null || :)
fi
case "$BEYIN_COUNT" in
  ''|*[!0-9]*) BEYIN_COUNT=0 ;;
esac

BEYIN_COUNT=$((BEYIN_COUNT + 1))
BEYIN_COUNT_TMP="$BEYIN_PROMPT_COUNT_FILE.tmp.$$"
if printf '%s\n' "$BEYIN_COUNT" > "$BEYIN_COUNT_TMP" 2>/dev/null; then
  mv -f "$BEYIN_COUNT_TMP" "$BEYIN_PROMPT_COUNT_FILE" 2>/dev/null || :
fi
rm -f "$BEYIN_COUNT_TMP" 2>/dev/null || :
rmdir "$BEYIN_LOCK_DIR" 2>/dev/null || :
trap - EXIT HUP INT TERM

# Kör periyodik hatırlatma kaldırıldı (konsey kararı: gürültü körleşme yaratır).
# Yerine koşullu tetik: oturum uzadı VE hafızaya hiç yazılmadıysa, bir kez uyar.
# Uyarı oturum başına bir defa verilir; tekrarı körleştirir.
BEYIN_ESIK=${BEYIN_HATIRLATMA_ESIGI:-25}
if [ "$BEYIN_COUNT" -ge "$BEYIN_ESIK" ]; then
  BEYIN_UYARILDI_FILE="$BEYIN_STATE_DIR/hatirlatildi.$BEYIN_SESSION_KEY"
  if [ ! -f "$BEYIN_UYARILDI_FILE" ]; then
    BEYIN_SESSION_START_FILE="$BEYIN_STATE_DIR/session_start_time.$BEYIN_SESSION_KEY"
    BEYIN_BASLANGIC=0
    [ -f "$BEYIN_SESSION_START_FILE" ] && BEYIN_BASLANGIC=$(sed -n '1p' "$BEYIN_SESSION_START_FILE" 2>/dev/null || :)
    case "$BEYIN_BASLANGIC" in ''|*[!0-9]*) BEYIN_BASLANGIC=0 ;; esac

    BEYIN_SON_OTURUM=$(ls -1 "$BEYIN_PROJECT_DIR/🔮 zihin/son-oturum"/20*.md 2>/dev/null | tail -n 1)
    BEYIN_YAZILDI=0
    if [ -n "$BEYIN_SON_OTURUM" ] && [ -f "$BEYIN_SON_OTURUM" ]; then
      BEYIN_MT=$(beyin_mtime "$BEYIN_SON_OTURUM")
      case "$BEYIN_MT" in ''|*[!0-9]*) BEYIN_MT=0 ;; esac
      [ "$BEYIN_MT" -gt "$BEYIN_BASLANGIC" ] 2>/dev/null && BEYIN_YAZILDI=1
    fi

    if [ "$BEYIN_YAZILDI" -eq 0 ]; then
      : > "$BEYIN_UYARILDI_FILE" 2>/dev/null || :
      beyin_emit UserPromptSubmit "[Hafıza] $BEYIN_COUNT. mesaj oldu ve bu oturumda hafızaya hiç yazılmadı.
Anlamlı bir şey konuşulduysa 🔮 zihin/son-oturum/ altına yeni bir dosya aç ve kalan-isler/ içindeki
ilgili konuyu düzelt. Konuşulmadıysa bu uyarıyı yok say; tekrarlanmayacak."
    fi
  fi
fi
exit 0
