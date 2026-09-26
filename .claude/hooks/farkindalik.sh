#!/bin/bash
# Farkındalık (organ 1b): açılışta "şu an ne durumda?" sorusunu cevaplar.
# Deterministik: model çağırmaz, ağa çıkmaz. Söyleyecek bir şey yoksa susar.
# Ölçüt (SOZLESME.md, Karar 6): ofiste bir dosya değişir → sonraki açılışta görünür.
#
# Not: bu makinede `find` aslında bfs; `-newermt "-3 days"` desteklenmiyor.
# Zamanı `-printf '%T@'` ile alıp awk ile süzüyoruz.

BEYIN_FK_VAULT=${1:-.}
BEYIN_FK_OFIS=${BEYIN_OFIS_DIR:-$HOME/ofis}
BEYIN_FK_GUN=3       # ofiste "son değişen" penceresi
BEYIN_FK_BAYAT=60    # bilgi notu bu kadar gün güncellenmezse bayat
BEYIN_FK_SIMDI=$(date +%s)
BEYIN_FK_CIKTI=""

beyin_fk_ekle() {
  [ -n "$BEYIN_FK_CIKTI" ] && BEYIN_FK_CIKTI="${BEYIN_FK_CIKTI}
"
  BEYIN_FK_CIKTI="${BEYIN_FK_CIKTI}$1"
}

# Epoch → "bugün 14:05" / "dün 09:12" / "3 gün önce"
beyin_fk_zaman() {
  BEYIN_FK_Z_GUN=$(date -d "@$1" +%F 2>/dev/null)
  if [ "$BEYIN_FK_Z_GUN" = "$(date +%F)" ]; then
    printf 'bugün %s' "$(date -d "@$1" +%H:%M)"
  elif [ "$BEYIN_FK_Z_GUN" = "$(date -d yesterday +%F 2>/dev/null)" ]; then
    printf 'dün %s' "$(date -d "@$1" +%H:%M)"
  else
    printf '%s gün önce' $(( (BEYIN_FK_SIMDI - $1) / 86400 ))
  fi
}

# 1) Ofiste son değişen projeler: her projenin en yeni dosyası, son N gün, en fazla 3.
if [ -d "$BEYIN_FK_OFIS" ]; then
  BEYIN_FK_ESIK=$(( BEYIN_FK_SIMDI - BEYIN_FK_GUN * 86400 ))
  BEYIN_FK_LISTE=$(
    for BEYIN_FK_P in "$BEYIN_FK_OFIS"/*/; do
      [ -d "$BEYIN_FK_P" ] || continue
      BEYIN_FK_AD=$(basename "$BEYIN_FK_P")
      find "$BEYIN_FK_P" -maxdepth 6 \
        \( -name .git -o -name node_modules -o -name .build -o -name __pycache__ -o -name .venv \) -prune \
        -o -type f -printf '%T@ %P\n' 2>/dev/null \
        | sort -n | tail -n 1 \
        | awk -v ad="$BEYIN_FK_AD" -v esik="$BEYIN_FK_ESIK" \
            '{ t=int($1); if (t >= esik) { $1=""; sub(/^ /, ""); print t "\t" ad "\t" $0 } }'
    done | sort -rn | head -n 3
  )
  if [ -n "$BEYIN_FK_LISTE" ]; then
    BEYIN_FK_SATIR=""
    while IFS="$(printf '\t')" read -r BEYIN_FK_T BEYIN_FK_AD BEYIN_FK_DOSYA; do
      BEYIN_FK_PARCA="${BEYIN_FK_AD} ($(beyin_fk_zaman "$BEYIN_FK_T"), $(basename "$BEYIN_FK_DOSYA")"
      if [ -d "$BEYIN_FK_OFIS/$BEYIN_FK_AD/.git" ]; then
        BEYIN_FK_KIRLI=$(git -C "$BEYIN_FK_OFIS/$BEYIN_FK_AD" status --porcelain 2>/dev/null | wc -l | tr -d ' ')
        [ "${BEYIN_FK_KIRLI:-0}" -gt 0 ] && BEYIN_FK_PARCA="${BEYIN_FK_PARCA}, ${BEYIN_FK_KIRLI} commit'lenmemiş"
      fi
      BEYIN_FK_PARCA="${BEYIN_FK_PARCA})"
      [ -n "$BEYIN_FK_SATIR" ] && BEYIN_FK_SATIR="${BEYIN_FK_SATIR} · "
      BEYIN_FK_SATIR="${BEYIN_FK_SATIR}${BEYIN_FK_PARCA}"
    done <<EOF
$BEYIN_FK_LISTE
EOF
    beyin_fk_ekle "Ofiste son değişen: ${BEYIN_FK_SATIR}"
  fi
fi

# 2) Açık şeritler: emri olan, makbuzu olmayan şerit klasörü (Karar 9).
BEYIN_FK_SERITLER="$BEYIN_FK_OFIS/ajans/seritler"
if [ -d "$BEYIN_FK_SERITLER" ]; then
  BEYIN_FK_SATIR=""
  for BEYIN_FK_S in "$BEYIN_FK_SERITLER"/*/; do
    [ -f "$BEYIN_FK_S/emir.md" ] || continue
    [ -f "$BEYIN_FK_S/makbuz.md" ] && continue
    BEYIN_FK_PARCA=$(basename "$BEYIN_FK_S")
    if [ -f "$BEYIN_FK_S/teslim.md" ]; then
      BEYIN_FK_PARCA="${BEYIN_FK_PARCA} (teslim edildi, makbuz bekliyor)"
    fi
    [ -n "$BEYIN_FK_SATIR" ] && BEYIN_FK_SATIR="${BEYIN_FK_SATIR} · "
    BEYIN_FK_SATIR="${BEYIN_FK_SATIR}${BEYIN_FK_PARCA}"
  done
  [ -n "$BEYIN_FK_SATIR" ] && beyin_fk_ekle "Açık şerit: ${BEYIN_FK_SATIR}"
fi

# 3) Bayat bilgi notları: 🛠️ Veriler, frontmatter `modified` (yoksa dosya zamanı).
BEYIN_FK_VERILER="$BEYIN_FK_VAULT/🛠️ Veriler"
if [ -d "$BEYIN_FK_VERILER" ]; then
  BEYIN_FK_ESIK=$(( BEYIN_FK_SIMDI - BEYIN_FK_BAYAT * 86400 ))
  BEYIN_FK_SATIR=""
  BEYIN_FK_SAYI=0
  for BEYIN_FK_N in "$BEYIN_FK_VERILER"/*.md; do
    [ -f "$BEYIN_FK_N" ] || continue
    BEYIN_FK_TARIH=$(sed -n '1,15{s/^modified:[[:space:]]*//p}' "$BEYIN_FK_N" 2>/dev/null | head -n 1)
    BEYIN_FK_T=""
    [ -n "$BEYIN_FK_TARIH" ] && BEYIN_FK_T=$(date -d "$BEYIN_FK_TARIH" +%s 2>/dev/null)
    [ -n "$BEYIN_FK_T" ] || BEYIN_FK_T=$(stat -c %Y "$BEYIN_FK_N" 2>/dev/null)
    [ -n "$BEYIN_FK_T" ] || continue
    [ "$BEYIN_FK_T" -lt "$BEYIN_FK_ESIK" ] || continue
    BEYIN_FK_SAYI=$((BEYIN_FK_SAYI + 1))
    [ "$BEYIN_FK_SAYI" -le 3 ] || continue
    [ -n "$BEYIN_FK_SATIR" ] && BEYIN_FK_SATIR="${BEYIN_FK_SATIR} · "
    BEYIN_FK_SATIR="${BEYIN_FK_SATIR}$(basename "$BEYIN_FK_N" .md) ($(( (BEYIN_FK_SIMDI - BEYIN_FK_T) / 86400 )) gün)"
  done
  [ "$BEYIN_FK_SAYI" -gt 3 ] && BEYIN_FK_SATIR="${BEYIN_FK_SATIR} · +$((BEYIN_FK_SAYI - 3)) not daha"
  [ -n "$BEYIN_FK_SATIR" ] && beyin_fk_ekle "Bayat bilgi (${BEYIN_FK_BAYAT}+ gün güncellenmemiş): ${BEYIN_FK_SATIR}"
fi

[ -n "$BEYIN_FK_CIKTI" ] && printf '%s\n' "$BEYIN_FK_CIKTI"
exit 0
