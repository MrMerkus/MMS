#!/bin/bash
# SessionEnd — oturum tüketimini 🛠️ Veriler/token-kullanimi.md dosyasına işler.
# Sayan codeburn, yazan ~/ofis/token-kaydi/kaydet.py. Bu kanca yalnızca tetikler.
#
# Kapanışı bekletmemek için arka plana ayrılır: kayıt birkaç saniye sürebilir ve
# oturumun kapanması ona bağlı olmamalı. Alt oturumlarda (derleyici, başlık üretimi)
# çalışmaz — BEYIN_INVOKED_BY o durumları işaretler.
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0

KAYIT_SCRIPT="$(readlink -f ~/ofis)/token-kaydi/kaydet.py"
[ -f "$KAYIT_SCRIPT" ] || exit 0

cat > /dev/null 2>&1   # hook girdisini tüket, kullanılmıyor

setsid nohup python3 "$KAYIT_SCRIPT" 30days \
  >> "${TMPDIR:-/tmp}/token-kaydi.log" 2>&1 < /dev/null &
exit 0
