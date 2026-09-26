#!/bin/bash
[ -n "${BEYIN_INVOKED_BY:-}" ] && exit 0
# Inject relational memory, rules, recent journal context, and the knowledge index.

BEYIN_HOOK_DIR=$(CDPATH= cd "$(dirname "$0")" 2>/dev/null && pwd)
. "$BEYIN_HOOK_DIR/lib.sh" 2>/dev/null || exit 0
. "$BEYIN_HOOK_DIR/esikler.sh" 2>/dev/null || exit 0

BEYIN_MEMORY_DIR="$BEYIN_PROJECT_DIR/🔮 zihin"
mkdir -p "$BEYIN_STATE_DIR" 2>/dev/null || :
beyin_cleanup_session_state

BEYIN_SESSION_KEY=$(beyin_session_key 2>/dev/null || :)
if [ -n "$BEYIN_SESSION_KEY" ]; then
  BEYIN_SESSION_START_FILE="$BEYIN_STATE_DIR/session_start_time.$BEYIN_SESSION_KEY"
  BEYIN_PROMPT_COUNT_FILE="$BEYIN_STATE_DIR/prompt_count.$BEYIN_SESSION_KEY"
  date '+%s' > "$BEYIN_SESSION_START_FILE" 2>/dev/null || :
  printf '%s\n' 0 > "$BEYIN_PROMPT_COUNT_FILE" 2>/dev/null || :
fi

# Son oturum: klasördeki en yeni dosya. Ad YYYY-AA-GG-<sıra>.md olduğu için
# alfabetik son = kronolojik son. Tek büyük dosya tutulmuyor, bilerek.
BEYIN_LAST_SESSION=""
BEYIN_LAST_SESSION_FILE=$(ls -1 "$BEYIN_MEMORY_DIR/son-oturum"/20*.md 2>/dev/null | tail -n 1)
if [ -n "$BEYIN_LAST_SESSION_FILE" ] && [ -f "$BEYIN_LAST_SESSION_FILE" ]; then
  BEYIN_LAST_SESSION=$(sed -n '/^---$/,/^---$/!p' "$BEYIN_LAST_SESSION_FILE" 2>/dev/null | sed -n '1,60p')
fi

# Kalan işler: konuların içeriği değil, yalnızca indeksi yüklenir.
# Tasarrufu yapan şey bölme değil, açmama kararıdır.
BEYIN_THREADS=""
if [ -f "$BEYIN_MEMORY_DIR/kalan-isler/INDEKS.md" ]; then
  BEYIN_THREADS=$(sed -n '/^---$/,/^---$/!p' "$BEYIN_MEMORY_DIR/kalan-isler/INDEKS.md" 2>/dev/null)
fi

BEYIN_RULES=""
if [ -f "$BEYIN_MEMORY_DIR/Kurallar.md" ]; then
  BEYIN_RULES=$(sed -n '/^---$/,/^---$/!p' "$BEYIN_MEMORY_DIR/Kurallar.md" 2>/dev/null | sed -n '1,60p')
fi

# Kimlik: Ruh (kişilik, üç mod) + Çekirdek (kullanıcı hakkında kalıcı veri).
# İkisi de küçük tutulur; büyürlerse refleks katmanı şişer.
BEYIN_JOURNAL=""
for BEYIN_KIMLIK_DOSYA in "$BEYIN_MEMORY_DIR/Ruh.md" "$BEYIN_MEMORY_DIR/Çekirdek.md"; do
  [ -f "$BEYIN_KIMLIK_DOSYA" ] || continue
  BEYIN_KIMLIK_METIN=$(sed -n '/^---$/,/^---$/!p' "$BEYIN_KIMLIK_DOSYA" 2>/dev/null)
  [ -n "$BEYIN_KIMLIK_METIN" ] || continue
  if [ -n "$BEYIN_JOURNAL" ]; then
    BEYIN_JOURNAL="${BEYIN_JOURNAL}
${BEYIN_KIMLIK_METIN}"
  else
    BEYIN_JOURNAL="$BEYIN_KIMLIK_METIN"
  fi
done

# Bilgi tabanı indeks katmanındadır: içeriği değil, varlığı yüklenir.
# 150 satırlık tablo bağlamın yarısını yiyordu; artık yalnızca işaretçi giriyor.
BEYIN_INDEX=""
if [ -f "$BEYIN_PROJECT_DIR/knowledge/index.md" ]; then
  BEYIN_INDEX_SAYI=$(grep -c '^| \[\[' "$BEYIN_PROJECT_DIR/knowledge/index.md" 2>/dev/null)
  case "$BEYIN_INDEX_SAYI" in ''|*[!0-9]*) BEYIN_INDEX_SAYI=0 ;; esac
  BEYIN_INDEX="knowledge/index.md — ${BEYIN_INDEX_SAYI} derlenmiş makale (kavramlar ve bağlantılar).
Bir konunun geçmişi veya gerekçesi sorulursa aç; kendiliğinden tarama."
fi

BEYIN_DAILY=""
BEYIN_TODAY=$(date '+%Y-%m-%d' 2>/dev/null || :)
BEYIN_DAILY_FILE=""
if [ -n "$BEYIN_TODAY" ] && [ -f "$BEYIN_PROJECT_DIR/daily/$BEYIN_TODAY.md" ]; then
  BEYIN_DAILY_FILE="$BEYIN_PROJECT_DIR/daily/$BEYIN_TODAY.md"
else
  BEYIN_YESTERDAY=$(beyin_yesterday)
  if [ -n "$BEYIN_YESTERDAY" ] && [ -f "$BEYIN_PROJECT_DIR/daily/$BEYIN_YESTERDAY.md" ]; then
    BEYIN_DAILY_FILE="$BEYIN_PROJECT_DIR/daily/$BEYIN_YESTERDAY.md"
  fi
fi
[ -n "$BEYIN_DAILY_FILE" ] && BEYIN_DAILY=$(tail -n 25 "$BEYIN_DAILY_FILE" 2>/dev/null)

BEYIN_NL='
'
BEYIN_REFLECTION=""
for BEYIN_REFLECTION_FILE in \
  "$BEYIN_STATE_DIR/needs_reflection" \
  "$BEYIN_STATE_DIR"/needs_reflection.*
do
  [ -f "$BEYIN_REFLECTION_FILE" ] || continue
  BEYIN_REFLECTION_DETAIL=$(sed -n '1p' "$BEYIN_REFLECTION_FILE" 2>/dev/null || :)
  if [ -n "$BEYIN_REFLECTION_DETAIL" ]; then
    [ -n "$BEYIN_REFLECTION" ] && BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_NL}"
    BEYIN_REFLECTION="${BEYIN_REFLECTION}⚠️ Önceki oturum hafıza güncellemeden bitti: ${BEYIN_REFLECTION_DETAIL}. Anlamlı bir şey olduysa 🔮 zihin/son-oturum ve kalan-isler güncelle."
  fi
  rm -f "$BEYIN_REFLECTION_FILE" 2>/dev/null || :
done

# Bölüm tavanları (kırpma notu dahil) aşağıdaki çağrılarda; denetçi 4.600 / 3.800 ile izler.
# Boş kalan klasörler için soru sırası (💪 Beden, 🧘 Düşünceler).
# Klasör tazeyse veya yakında sorulduysa hiçbir şey üretmez.
# Yedek push'u başarısız olduysa bunu yüzüne söyle: sessiz kalan bir yedek
# hatası, haftalarca yedeksiz kalmak demektir.
if [ -f "$BEYIN_STATE_DIR/yedek-basarisiz" ]; then
  BEYIN_YEDEK_HATA=$(sed -n '1p' "$BEYIN_STATE_DIR/yedek-basarisiz" 2>/dev/null || :)
  if [ -n "$BEYIN_YEDEK_HATA" ]; then
    [ -n "$BEYIN_REFLECTION" ] && BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_NL}"
    BEYIN_REFLECTION="${BEYIN_REFLECTION}⚠️ ${BEYIN_YEDEK_HATA} — .claude/scripts/yedek.sh çalıştır."
  fi
fi

# Sağlık satırı çekirdeğe girer: ölçen her mekanizma sorulmadan konuşur.
BEYIN_SAGLIK=$(bash "$BEYIN_HOOK_DIR/saglik.sh" "$BEYIN_PROJECT_DIR" 2>/dev/null || :)
if [ -n "$BEYIN_SAGLIK" ]; then
  [ -n "$BEYIN_REFLECTION" ] && BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_NL}"
  BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_SAGLIK}"
fi

# Farkındalık (organ 1b): ofiste ne değişti, açık şerit, bayat bilgi. Susabilir.
BEYIN_FARKINDALIK=$(bash "$BEYIN_HOOK_DIR/farkindalik.sh" "$BEYIN_PROJECT_DIR" 2>/dev/null || :)
if [ -n "$BEYIN_FARKINDALIK" ]; then
  [ "${#BEYIN_FARKINDALIK}" -gt 800 ] && BEYIN_FARKINDALIK="${BEYIN_FARKINDALIK:0:780}
[not: kırpıldı]"
  [ -n "$BEYIN_REFLECTION" ] && BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_NL}"
  BEYIN_REFLECTION="${BEYIN_REFLECTION}[Farkındalık]${BEYIN_NL}${BEYIN_FARKINDALIK}"
fi

BEYIN_SORULAR=$(bash "$BEYIN_HOOK_DIR/soru-sirasi.sh" "$BEYIN_PROJECT_DIR" 2>/dev/null || :)
if [ -n "$BEYIN_SORULAR" ]; then
  [ -n "$BEYIN_REFLECTION" ] && BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_NL}"
  BEYIN_REFLECTION="${BEYIN_REFLECTION}${BEYIN_SORULAR}"
fi

beyin_cap_section() {
  BEYIN_CAP_VALUE=$1
  BEYIN_CAP_LIMIT=$2
  BEYIN_CAP_NOTE=$3
  if [ "${#BEYIN_CAP_VALUE}" -le "$BEYIN_CAP_LIMIT" ]; then
    printf '%s' "$BEYIN_CAP_VALUE"
    return 0
  fi

  BEYIN_CAP_KEEP=$((BEYIN_CAP_LIMIT - ${#BEYIN_CAP_NOTE} - 1))
  [ "$BEYIN_CAP_KEEP" -gt 0 ] || BEYIN_CAP_KEEP=0
  printf '%s\n%s' "${BEYIN_CAP_VALUE:0:$BEYIN_CAP_KEEP}" "$BEYIN_CAP_NOTE"
}

BEYIN_LAST_SESSION=$(beyin_cap_section "$BEYIN_LAST_SESSION" 3800 \
  '[not: son oturum 3.800 karakterde kırpıldı, beyin-doktor çalıştır]')
BEYIN_THREADS=$(beyin_cap_section "$BEYIN_THREADS" 4600 \
  '[not: kalan işler indeksi 4.600 karakterde kırpıldı, beyin-doktor çalıştır]')
# ÇEKİRDEK — kurallar, kimlik ve sağlık satırı kırpılmaz (SOZLESME.md, Karar 2).
# Bunlar büyürse çözüm kırpmak değil, bölmektir; tavanı saglik.sh söyler.

BEYIN_TRUNCATED=0
BEYIN_CLOSING='[Hafıza] Süreklilik senin sorumluluğun. Kimliğin yukarıda yüklü. Kalan işlerden biri gerekirse "🔮 zihin/kalan-isler/<dosya>" aç.
Hafıza protokolü zorunludur.'
BEYIN_TRUNCATION_NOTE='[not: indeks kırpıldı, beyin-doktor çalıştır]'
BEYIN_CAP_DIAGNOSTIC="Beyin uyarısı: Oturum başlangıç bağlamı $(binlik "$BAGLAM_TAVAN") karakter sınırına sığmadı. Bölüm limitlerini kontrol etmek için beyin-doktor çalıştır."

beyin_build_context() {
  BEYIN_CONTEXT=""
  [ -n "$BEYIN_REFLECTION" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}${BEYIN_REFLECTION}${BEYIN_NL}${BEYIN_NL}"
  [ -n "$BEYIN_LAST_SESSION" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Hafıza: Son Oturum]${BEYIN_NL}${BEYIN_LAST_SESSION}${BEYIN_NL}${BEYIN_NL}"
  [ -n "$BEYIN_THREADS" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Hafıza: Kalan İşler — indeks, içerik değil]${BEYIN_NL}${BEYIN_THREADS}${BEYIN_NL}${BEYIN_NL}"
  [ -n "$BEYIN_RULES" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Hafıza: Kurallar]${BEYIN_NL}${BEYIN_RULES}${BEYIN_NL}${BEYIN_NL}"
  [ -n "$BEYIN_JOURNAL" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Hafıza: Kimlik]${BEYIN_NL}${BEYIN_JOURNAL}${BEYIN_NL}${BEYIN_NL}"
  [ -n "$BEYIN_INDEX" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Bilgi Tabanı: İndeks]${BEYIN_NL}${BEYIN_INDEX}${BEYIN_NL}${BEYIN_NL}"
  [ -n "$BEYIN_DAILY" ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}[Bugünün Logu]${BEYIN_NL}${BEYIN_DAILY}${BEYIN_NL}${BEYIN_NL}"
  [ "$BEYIN_TRUNCATED" -eq 1 ] && BEYIN_CONTEXT="${BEYIN_CONTEXT}${BEYIN_TRUNCATION_NOTE}${BEYIN_NL}${BEYIN_NL}"
  BEYIN_CONTEXT="${BEYIN_CONTEXT}${BEYIN_CLOSING}"
}

beyin_build_context
if [ "${#BEYIN_CONTEXT}" -gt "$BAGLAM_TAVAN" ]; then
  BEYIN_TRUNCATED=1
  beyin_build_context

  BEYIN_OVER=$(( ${#BEYIN_CONTEXT} - BAGLAM_TAVAN ))
  if [ "$BEYIN_OVER" -gt 0 ] && [ -n "$BEYIN_INDEX" ]; then
    if [ "$BEYIN_OVER" -ge "${#BEYIN_INDEX}" ]; then
      BEYIN_INDEX=""
    else
      BEYIN_KEEP=$(( ${#BEYIN_INDEX} - BEYIN_OVER ))
      BEYIN_INDEX=${BEYIN_INDEX:0:$BEYIN_KEEP}
    fi
    beyin_build_context
  fi

  BEYIN_OVER=$(( ${#BEYIN_CONTEXT} - BAGLAM_TAVAN ))
  if [ "$BEYIN_OVER" -gt 0 ] && [ -n "$BEYIN_DAILY" ]; then
    if [ "$BEYIN_OVER" -ge "${#BEYIN_DAILY}" ]; then
      BEYIN_DAILY=""
    else
      BEYIN_DAILY=${BEYIN_DAILY:$BEYIN_OVER}
    fi
    beyin_build_context
  fi

  # Durum katmanı kısılır; çekirdeğe (kurallar, kimlik, sağlık) dokunulmaz.
  BEYIN_OVER=$(( ${#BEYIN_CONTEXT} - BAGLAM_TAVAN ))
  if [ "$BEYIN_OVER" -gt 0 ] && [ -n "$BEYIN_THREADS" ]; then
    if [ "$BEYIN_OVER" -ge "${#BEYIN_THREADS}" ]; then
      BEYIN_THREADS=""
    else
      BEYIN_KEEP=$(( ${#BEYIN_THREADS} - BEYIN_OVER ))
      BEYIN_THREADS=${BEYIN_THREADS:0:$BEYIN_KEEP}
    fi
    beyin_build_context
  fi

  BEYIN_OVER=$(( ${#BEYIN_CONTEXT} - BAGLAM_TAVAN ))
  if [ "$BEYIN_OVER" -gt 0 ] && [ -n "$BEYIN_LAST_SESSION" ]; then
    if [ "$BEYIN_OVER" -ge "${#BEYIN_LAST_SESSION}" ]; then
      BEYIN_LAST_SESSION=""
    else
      BEYIN_KEEP=$(( ${#BEYIN_LAST_SESSION} - BEYIN_OVER ))
      BEYIN_LAST_SESSION=${BEYIN_LAST_SESSION:0:$BEYIN_KEEP}
    fi
    beyin_build_context
  fi
fi

# Hedef niyettir, tavan sınırdır; aradaki turuncu bölge belirgin uyarır. Aşım kırpmaz, haber verir.
if [ "${#BEYIN_CONTEXT}" -gt "$BAGLAM_TURUNCU" ]; then
  BEYIN_REFLECTION="🟠 Bağlam ${#BEYIN_CONTEXT}/$(binlik "$BAGLAM_TAVAN") karakter — turuncu bölge ($(binlik "$BAGLAM_TURUNCU") üstü). Açılışı küçült: beyin-doktor.${BEYIN_NL}${BEYIN_REFLECTION}"
  beyin_build_context
elif [ "${#BEYIN_CONTEXT}" -gt "$BAGLAM_HEDEF" ]; then
  BEYIN_REFLECTION="⚠️ Bağlam ${#BEYIN_CONTEXT}/$(binlik "$BAGLAM_HEDEF") karakter — hedefin üstünde, turuncu $(binlik "$BAGLAM_TURUNCU"), tavan $(binlik "$BAGLAM_TAVAN").${BEYIN_NL}${BEYIN_REFLECTION}"
  beyin_build_context
fi

if [ "${#BEYIN_CONTEXT}" -gt "$BAGLAM_TAVAN" ]; then
  BEYIN_CONTEXT=$BEYIN_CAP_DIAGNOSTIC
fi

[ -n "$BEYIN_CONTEXT" ] && beyin_emit SessionStart "$BEYIN_CONTEXT"

# Projektör yakalama turu: defterde olup yansımamış gün varsa daily/ ve
# knowledge/log.md'ye yansıtır. Deterministik, model yok; değişmeyen gün için ucuz.
# Bağlam yazıldıktan sonra ve ayrık çalışır: açılışı geciktiremez, JSON'u bozamaz.
if command -v python3 >/dev/null 2>&1; then
  nohup python3 "$BEYIN_PROJECT_DIR/.claude/scripts/projektor.py" \
    --hepsi >/dev/null 2>&1 &
fi

exit 0
