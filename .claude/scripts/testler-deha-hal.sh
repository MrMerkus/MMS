#!/usr/bin/env bash
# Deha hal kancası düşman testleri (Karar 12, adım 3).
#
# Kanca Claude'un her mesajında ve her aracında çalışır. Sessizce bozulursa iki zarar verir:
# stdout'a sızarsa her mesajın bağlamına karışır, sıfırdan farklı dönerse Claude'u durdurur.
# Yan etkisiz: sahte bir XDG_RUNTIME_DIR kullanır.
#
# Kullanım: testler-deha-hal.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
K="$kok/.claude/hooks/deha-hal.sh"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; return 0; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }

gecici=$(mktemp -d)
trap 'rm -rf "$gecici"' EXIT
export XDG_RUNTIME_DIR="$gecici/run"
mkdir -p "$XDG_RUNTIME_DIR"
durum="$XDG_RUNTIME_DIR/deha/durum-1.json"

cagir() { # cagir <olay> [DEHA_DURUM] → "cikti|kod"
  local cikti kod
  cikti=$(DEHA_DURUM="${2-}" bash "$K" "$1" < /dev/null 2>&1); kod=$?
  printf '%s|%s' "$cikti" "$kod"
}

echo "1) İşaretsiz oturum (kardeş oturumlar)"
esit "DEHA_DURUM yokken sessiz ve 0" "|0" "$(cagir UserPromptSubmit)"
[ ! -e "$XDG_RUNTIME_DIR/deha" ] && gec "DEHA_DURUM yokken hiçbir şey yazmıyor" \
  || kal "DEHA_DURUM yokken hiçbir şey yazmıyor" "deha/ yok" "var"

echo
echo "2) Arayüz oturumu"
for olay in UserPromptSubmit PreToolUse Stop Notification SessionStart; do
  esit "$olay: sessiz ve 0" "|0" "$(cagir "$olay" "$durum")"
  esit "$olay: durum dosyasına olay yazıldı" "$olay" \
    "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["olay"])' "$durum" 2>&1)"
done
z=$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["zaman"])' "$durum" 2>&1)
[[ "$z" =~ ^[0-9]{13}$ ]] && gec "zaman milisaniye damgası" || kal "zaman milisaniye damgası" "13 hane" "$z"
ls "$XDG_RUNTIME_DIR/deha/" | grep -q '\.json\.' && kal "yarım geçici dosya kalmadı" "yok" "var" \
  || gec "yarım geçici dosya kalmadı"

echo
echo "3) Düşman girdiler"
esit "bilinmeyen olay yazılmıyor" "|0" "$(cagir 'Kotu"olay' "$durum")"
esit "bilinmeyen olay dosyayı değiştirmedi" "SessionStart" \
  "$(python3 -c 'import json,sys; print(json.load(open(sys.argv[1]))["olay"])' "$durum" 2>&1)"
esit "çalışma dizini dışına yol reddedilir" "|0" "$(cagir Stop "$gecici/disari.json")"
[ ! -e "$gecici/disari.json" ] && gec "dışarı yazılmadı" || kal "dışarı yazılmadı" "yok" "var"
esit "../ ile kaçış reddedilir" "|0" "$(cagir Stop "$XDG_RUNTIME_DIR/deha/../kacis.json")"
[ ! -e "$XDG_RUNTIME_DIR/kacis.json" ] && gec "kaçış yazılmadı" || kal "kaçış yazılmadı" "yok" "var"
chmod 500 "$XDG_RUNTIME_DIR/deha"
esit "yazılamayan dizinde bile sessiz ve 0" "|0" "$(cagir Stop "$durum")"
chmod 700 "$XDG_RUNTIME_DIR/deha"

echo
echo "4) Hız"
bas=$(date +%s%N)
for _ in 1 2 3 4 5 6 7 8 9 10; do bash "$K" PreToolUse >/dev/null 2>&1 < /dev/null; done
DEHA_DURUM="$durum" bash "$K" PreToolUse < /dev/null
ms=$(( ($(date +%s%N) - bas) / 11000000 ))
[ "$ms" -lt 50 ] && gec "çağrı başına ${ms} ms (< 50)" || kal "çağrı başına < 50 ms" "< 50" "$ms"

echo
echo "5) Bağlantı"
for olay in UserPromptSubmit PreToolUse Stop Notification SessionStart; do
  python3 - "$kok/.claude/settings.json" "$olay" <<'EOF' && gec "settings.json: $olay kancaya bağlı" || kal "settings.json: $olay kancaya bağlı" "bağlı" "değil"
import json, sys
d = json.load(open(sys.argv[1]))
ok = any(f"deha-hal.sh\" {sys.argv[2]}" in h["command"] for g in d["hooks"].get(sys.argv[2], []) for h in g["hooks"])
sys.exit(0 if ok else 1)
EOF
done

echo
echo "Sonuç: $gecen geçti, $kalan kaldı"
[ "$kalan" -eq 0 ]
