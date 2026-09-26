#!/bin/bash
# Sağlık satırı: sessiz arızayı sesli yapar.
# Ölçen her mekanizma sorulmadan konuşur (SOZLESME.md, değişmez #6).
# Yalnızca ucuz kontroller: test paketi çalıştırmaz, ağa çıkmaz.
# Çıktı yoksa sistem sağlıklıdır.

BEYIN_SAGLIK_DIR=${1:-.}
BEYIN_SAGLIK_UYARI=""

beyin_saglik_ekle() {
  [ -n "$BEYIN_SAGLIK_UYARI" ] && BEYIN_SAGLIK_UYARI="${BEYIN_SAGLIK_UYARI}
"
  BEYIN_SAGLIK_UYARI="${BEYIN_SAGLIK_UYARI}⚠️ $1"
}

# 1) Derleme kaç gündür durdu? knowledge/log.md'deki son blok (projektör ya da eski compile).
BEYIN_LOG="$BEYIN_SAGLIK_DIR/knowledge/log.md"
if [ -f "$BEYIN_LOG" ]; then
  BEYIN_SON_DERLEME=$(grep -o '^## \[[0-9-]\{10\}' "$BEYIN_LOG" 2>/dev/null | tail -n 1 | tr -d '#[ ')
  if [ -n "$BEYIN_SON_DERLEME" ]; then
    BEYIN_S1=$(date -d "$BEYIN_SON_DERLEME" '+%s' 2>/dev/null)
    BEYIN_S2=$(date '+%s' 2>/dev/null)
    if [ -n "$BEYIN_S1" ] && [ -n "$BEYIN_S2" ]; then
      BEYIN_GUN=$(( (BEYIN_S2 - BEYIN_S1) / 86400 ))
      [ "$BEYIN_GUN" -ge 2 ] && beyin_saglik_ekle "Bilgi tabanı ${BEYIN_GUN} gündür derlenmiyor (son: ${BEYIN_SON_DERLEME}). Derleyici bozuk olabilir."
    fi
  fi
fi

# 2) Kural dosyaları tavanı (4.000 karakter) aşıyor mu?
for BEYIN_KF in "$BEYIN_SAGLIK_DIR/🔮 zihin/Kurallar.md" "$BEYIN_SAGLIK_DIR/🔮 zihin/kurallar/"*.md; do
  [ -f "$BEYIN_KF" ] || continue
  case "$BEYIN_KF" in */INDEKS.md) continue ;; esac
  BEYIN_KN=$(wc -m < "$BEYIN_KF" 2>/dev/null | tr -d ' ')
  case "$BEYIN_KN" in ''|*[!0-9]*) continue ;; esac
  if [ "$BEYIN_KN" -gt 4000 ]; then
    beyin_saglik_ekle "$(basename "$BEYIN_KF") ${BEYIN_KN}/4.000 karakter — bir madde alt dosyaya inmeli veya birleşmeli."
  fi
done

# 3) .state/ geçicidir: oturum dosyaları 7 gün tutulur, sonra silinir.
# Yalnız 7 günden eskiler sayılır; yoğun bir haftada taze dosya çok olur, bu arıza değildir.
BEYIN_STATE="$BEYIN_SAGLIK_DIR/.claude/scripts/.state"
if [ -d "$BEYIN_STATE" ]; then
  BEYIN_SN=$(find "$BEYIN_STATE" -type f -mtime +7 2>/dev/null | wc -l | tr -d ' ')
  case "$BEYIN_SN" in ''|*[!0-9]*) BEYIN_SN=0 ;; esac
  [ "$BEYIN_SN" -gt 20 ] && beyin_saglik_ekle ".state/ içinde 7 günden eski ${BEYIN_SN} dosya birikmiş — temizlik adımı çalışmıyor."
fi

# 4) Olay defterinde kırık kuyruk kesildiyse parça .state'te bekler. health.json'daki hata
# alanını sonraki bir flush ezebilir; parça dosyası ise okunup silinene kadar durur.
if [ -d "$BEYIN_STATE" ]; then
  BEYIN_KIRIK=$(find "$BEYIN_STATE" -maxdepth 1 -name 'olaylar-kirik-*.parca' 2>/dev/null | wc -l | tr -d ' ')
  case "$BEYIN_KIRIK" in ''|*[!0-9]*) BEYIN_KIRIK=0 ;; esac
  [ "$BEYIN_KIRIK" -gt 0 ] && beyin_saglik_ekle "Olay defterinde ${BEYIN_KIRIK} kırık satır kesildi — parça .claude/scripts/.state/olaylar-kirik-*.parca içinde; incele, sonra sil."
fi

# 5) Kavram çıkarımı bekleyen gün (derle skill'i elle çalışır; birikirse söyle).
BEYIN_DERLE="$(dirname "$0")/../scripts/derle.py"
if [ -f "$BEYIN_DERLE" ] && command -v python3 >/dev/null 2>&1; then
  BEYIN_BEK=$(timeout 3 python3 "$BEYIN_DERLE" --kok "$BEYIN_SAGLIK_DIR" bekleyen 2>/dev/null | sed -n 's/^bekleyen: //p')
  case "$BEYIN_BEK" in ''|*[!0-9]*) BEYIN_BEK=0 ;; esac
  [ "$BEYIN_BEK" -ge 3 ] && beyin_saglik_ekle "${BEYIN_BEK} gün kavram çıkarımı bekliyor — \"derle\" de."
fi

[ -n "$BEYIN_SAGLIK_UYARI" ] && printf '%s\n' "$BEYIN_SAGLIK_UYARI"
exit 0
