#!/usr/bin/env bash
# PostToolUse — bir dosyaya dokunulduktan sonra iki iş yapar:
#   1) DOKUNMA KAYDI (her Read/Write/Edit): terfi/tenzil için kullanım verisi biriktirir.
#   2) TAVAN ÖLÇÜMÜ (yalnızca Write/Edit): 500 kelime kuralını sayar.
#
# Neden tek script: ikisi de aynı olayda, aynı JSON'u ayrıştırarak çalışıyor.
# Ayrı hook'lar her araç çağrısında iki süreç açardı.
#
# Ne yapmaz: bölmez, taşımaz, dosyaya dokunmaz. Yalnızca sayar ve söyler.
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0

BEYIN_TAVAN=${BEYIN_TAVAN:-500}
BEYIN_GIRDI=$(cat 2>/dev/null || :)
[ -n "$BEYIN_GIRDI" ] || exit 0

BEYIN_AYRIS=$(printf '%s' "$BEYIN_GIRDI" | python3 -c '
import json, sys
try:
    d = json.load(sys.stdin)
except Exception:
    sys.exit(0)
arac = d.get("tool_name", "")
if arac not in ("Read", "Write", "Edit", "NotebookEdit"):
    sys.exit(0)
print(arac)
print(d.get("tool_input", {}).get("file_path", ""))
' 2>/dev/null || :)

# Ayrıştırma boş döndüyse ya araç ilgisiz ya python3 yok. İkincisi sessiz bir
# ölümdür: tavan ölçümü ve dokunma kaydı çalışmaz, kimse fark etmez.
if [ -z "$BEYIN_AYRIS" ] && ! command -v python3 >/dev/null 2>&1; then
  beyin_mark_python_missing
  beyin_emit PostToolUse 'Beyin uyarısı: python3 bulunamadı, tavan ölçer ve dokunma kaydı çalışmıyor. beyin-doktor çalıştır.'
  exit 0
fi

BEYIN_ARAC=$(printf '%s' "$BEYIN_AYRIS" | sed -n '1p')
BEYIN_DOSYA=$(printf '%s' "$BEYIN_AYRIS" | sed -n '2p')
[ -n "$BEYIN_DOSYA" ] || exit 0
case "$BEYIN_DOSYA" in *.md) ;; *) exit 0 ;; esac
case "$BEYIN_DOSYA" in "$BEYIN_PROJECT_DIR"/*) ;; *) exit 0 ;; esac

BEYIN_GORECELI=${BEYIN_DOSYA#"$BEYIN_PROJECT_DIR"/}
case "$BEYIN_GORECELI" in
  daily/*|knowledge/*|.claude/*|"📦 bitmiş olanlar/"*) exit 0 ;;
esac

# --- 1) dokunma kaydı ---------------------------------------------------------
# Biriken satırlar terfi.sh tarafından okunur. Kilit yok: append tek satır ve
# kısa; kaybolan bir satır ölçümü bozmaz, kilit maliyeti faydasından büyük.
printf '%s\t%s\t%s\n' "$(date '+%s')" "$BEYIN_ARAC" "$BEYIN_GORECELI" \
  >> "$BEYIN_STATE_DIR/dokunma.tsv" 2>/dev/null || :

# --- 2) tavan ölçümü ----------------------------------------------------------
case "$BEYIN_ARAC" in Write|Edit|NotebookEdit) ;; *) exit 0 ;; esac
[ -f "$BEYIN_DOSYA" ] || exit 0

# Arşiv dosyaları tavandan muaf: geçmiş birikerek uzar, bölünmesi anlamsızdır.
# Muafiyet frontmatter'a bakar, dosya adına değil.
if head -n 10 "$BEYIN_DOSYA" 2>/dev/null | grep -qiE '^(type:[[:space:]]*gecmis|durum:[[:space:]]*arşiv)'; then
  exit 0
fi

BEYIN_SAYI=$(sed -n '/^---$/,/^---$/!p' "$BEYIN_DOSYA" 2>/dev/null | wc -w | tr -d ' ')
case "$BEYIN_SAYI" in ''|*[!0-9]*) exit 0 ;; esac
[ "$BEYIN_SAYI" -gt "$BEYIN_TAVAN" ] || exit 0

BEYIN_ASIM=$((BEYIN_SAYI - BEYIN_TAVAN))
beyin_emit PostToolUse "[Tavan] \"$BEYIN_GORECELI\" $BEYIN_SAYI kelime — tavanı $BEYIN_ASIM kelime aşıyor.
Bu bir bölme SİNYALİ, bölme yeri değil: dosya tek bir soruyu cevaplıyorsa bırak.
Birden fazla soruyu cevaplıyorsa alt dosyaya böl ve wikilink'le bağla — çıplak bağlantı yasak,
bağlantı ne olduğunu ve ne zaman açılacağını söylesin."
exit 0
