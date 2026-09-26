#!/usr/bin/env bash
# PreToolUse (Bash) — komut çalışmadan ÖNCE tanınmış tuzakları engeller.
#
# Şu an tek kural var: `pkill -f <desen>`. Desen çalışan kabuğun kendi komut
# satırıyla da eşleştiği için kabuk kendini öldürüyor (çıkış 144) ve zincirin
# geri kalanı hiç çalışmıyor. Gözlem 0018: 13, 14 ve 15 Eylül'de üç kez oldu —
# üçünde de kural defterde YAZILIYDI. Yazılı hatırlatma bu vakada kanıtlanmış
# biçimde yetmiyor, o yüzden yapısal engel kondu.
#
# Ne yapmaz: komutu düzeltmez, başka hiçbir deseni engellemez. Yalnızca durdurur
# ve doğru alternatifi söyler. `pgrep -f` okumadır, engellenmez.
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0

BEYIN_GIRDI=$(cat 2>/dev/null || :)
[ -n "$BEYIN_GIRDI" ] || exit 0

# python3 yoksa sessizce geçilir: engel çalışmasa da iş durmamalı.
command -v python3 >/dev/null 2>&1 || exit 0

BEYIN_KOMUT=$(printf '%s' "$BEYIN_GIRDI" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
if d.get("tool_name", "") != "Bash":
    sys.exit(0)
print(d.get("tool_input", {}).get("command", ""))
' 2>/dev/null || :)

[ -n "$BEYIN_KOMUT" ] || exit 0

# Kapı (Organ 5): yıkıcı silme, zorla push, kasanın dışarı çıkışı. Karar kapi.py'de;
# yalnız çıkış 2 durdurur, kapının kendi hatası geçirir.
if [ -f "$BEYIN_HOOK_DIR/kapi.py" ]; then
  printf '%s' "$BEYIN_GIRDI" | python3 "$BEYIN_HOOK_DIR/kapi.py" denetle
  [ $? -eq 2 ] && exit 2
fi

# pkill + tam komut satırı eşleşmesi (-f, -9f, --full). pgrep kapsam dışı.
BEYIN_YAKALANDI=$(printf '%s' "$BEYIN_KOMUT" | python3 -c '
import re, sys
k = sys.stdin.read()
if re.search(r"(?:^|[;&|(\s])pkill\b", k) and re.search(r"(?:\s-[a-zA-Z]*f\b|\s--full\b)", k):
    print("evet")
' 2>/dev/null || :)

[ -n "$BEYIN_YAKALANDI" ] || exit 0

cat >&2 <<'UYARI'
[Engel] `pkill -f` engellendi — gözlem 0018, üç kez tekrarladı.

Desen çalışan kabuğun kendi komut satırıyla eşleşiyor; kabuk kendini öldürüyor
(çıkış 144) ve zincirin geri kalanı hiç çalışmıyor. Üç ayrı oturumda üç kez oldu.

Bunun yerine, sırayla:
  1. Arka plandaki bir şerit/görev ise harness'ın görev durdurma aracını kullan.
  2. PID'i bul, sonra öldür:  pgrep -f '<desen>'  →  kill <pid>
  3. Zorunluysa deseni kendi satırıyla eşleşmeyecek biçimde yaz:  pkill -f '[k]de-inhibit'

Gerçekten `pkill -f` gerekiyorsa kullanıcıya sebebini söyle ve onayını al.
UYARI
exit 2
