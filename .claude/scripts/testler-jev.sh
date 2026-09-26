#!/usr/bin/env bash
# Jev düşman testleri — PLAN adım 10 (SOZLESME Karar 1, Karar 6 satır 6, Karar 7).
#
# Ölçüt: `off` iken hiç ağ çağrısı yok; `shadow`'da teslim edilen sonuç `off` ile bayt
# bayt aynı, Jev'in önerisi yalnız gözlem dosyasına düşer. `on` bu adımda YOK: fayda
# kapısından (Karar 7) geçmeden açılmaz, istenirse off gibi davranır.
#
# Arayüz sözleşmesi (uygulama bu dosyayı değiştirerek geçemez):
#   jev.py golge --amac <ad> --yerel <json> --sorular <json> [--state-dosya <yol>]
#     stdout: yerel sonuç, kanonik JSON. Mod ne olursa olsun yalnız bu.
#     Gözlem: olay defterinde `jev` tipi; olaylar.py yoksa <kök>/.claude/scripts/.state/jev-gozlem.jsonl (amaç, mod, degraded, gecikme,
#     Jev'in cevap sayıları; state/soru METNİ ve anahtar yazılmaz).
#   Mod: BEYIN_JEV_MODE ortamı > <kök>/.claude/jev.json {"mod": ...} > "off".
#   Kill switch: BEYIN_JEV_DISABLE=1. Uç nokta: BEYIN_JEV_URL. Süre: BEYIN_JEV_TIMEOUT (sn).
#   Anahtar: TYPESAFE_API_KEY; yoksa shadow sessizce off'a iner (stderr boş).
#
# Gerçek ağ ve gerçek anahtar YOK: yerel sahte sunucu (python http.server, 127.0.0.1).
# Kullanım: testler-jev.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
S="$kok/.claude/scripts"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }
icermez() { case "$3" in *"$2"*) kal "$1" "'$2' olmamalı" "${3:0:120}" ;; *) gec "$1" ;; esac; }

gecici=$(mktemp -d)
sunucu_pid=""
trap '[ -n "$sunucu_pid" ] && kill "$sunucu_pid" 2>/dev/null; rm -rf "$gecici"' EXIT
unset BEYIN_JEV_MODE BEYIN_JEV_DISABLE BEYIN_INVOKED_BY
export TYPESAFE_API_KEY="test-anahtar-gercek-degil"
# Sahte HOME: gerçek ~/.config/jev/key hiçbir testte okunmaz.
export HOME="$gecici/ev"; mkdir -p "$HOME"

# Sahte vault: jev.py kopyalanır, kök script konumundan bulunur.
v="$gecici/vault"; mkdir -p "$v/.claude/scripts/.state"
[ -f "$S/jev.py" ] && cp "$S/jev.py" "$v/.claude/scripts/"
GOZLEM="$v/.claude/scripts/.state/jev-gozlem.jsonl"

# Sahte Jev: her isteği gövdesiyle kaydeder. Davranış dosyadan okunur: ok / yavas / 500 / bozuk.
cat > "$gecici/sunucu.py" <<'PY'
import http.server, json, sys, time, pathlib
d = pathlib.Path(sys.argv[1])
class H(http.server.BaseHTTPRequestHandler):
    def log_message(self, *a): pass
    def do_POST(self):
        govde = self.rfile.read(int(self.headers.get("Content-Length", 0))).decode("utf-8", "replace")
        with open(d / "istekler.log", "a", encoding="utf-8") as f:
            f.write(json.dumps({"yol": self.path, "yetki": self.headers.get("Authorization", ""),
                                "govde": govde}, ensure_ascii=False) + "\n")
        mod = (d / "mod").read_text().strip()
        if mod == "yavas":
            time.sleep(6)
        if mod == "yarim":   # bozuk durum satırı: http.client.BadStatusLine (OSError değil)
            self.wfile.write(b"BOZUK\r\n\r\n"); self.wfile.flush(); self.close_connection = True; return
        if mod == "damla":   # başlık hemen, gövde damla damla: soket süresi hiç dolmaz
            self.send_response(200); self.send_header("Content-Length", "40"); self.end_headers()
            for _ in range(12):
                self.wfile.write(b" "); self.wfile.flush(); time.sleep(0.5)
            return
        if mod == "500":
            self.send_response(500); self.end_headers(); return
        cevap = b"{bozuk" if mod == "bozuk" else json.dumps({"answers": {"onemli": {"noul": 0.02}},
                                                            "usage": {"input_tokens": 12}}).encode()
        self.send_response(200); self.send_header("Content-Type", "application/json")
        self.end_headers(); self.wfile.write(cevap)
s = http.server.ThreadingHTTPServer(("127.0.0.1", 0), H)
(d / "port").write_text(str(s.server_address[1]))
s.serve_forever()
PY
echo ok > "$gecici/mod"
python3 "$gecici/sunucu.py" "$gecici" & sunucu_pid=$!
for _ in $(seq 50); do [ -s "$gecici/port" ] && break; sleep 0.1; done
export BEYIN_JEV_URL="http://127.0.0.1:$(cat "$gecici/port" 2>/dev/null)/v1/systemone"
export BEYIN_JEV_TIMEOUT=1

istek() { grep -c . "$gecici/istekler.log" 2>/dev/null || echo 0; }
YEREL='{"karar":"logla","puan":0.7,"not":"yerel sonuç ğüşiöç"}'
SORU='{"onemli":{"type":"noul","instructions":"Is this session worth logging?"}}'
printf 'Bu oturumda emeklilik organı yazıldı.\n' > "$gecici/state.txt"
golge() { (cd "$v" && timeout 20 python3 .claude/scripts/jev.py golge --amac baglam \
  --yerel "$YEREL" --sorular "$SORU" --state-dosya "${1:-$gecici/state.txt}" "${@:2}" 2>"$gecici/err"); }

echo "Jev düşman testleri — $(date '+%Y-%m-%d %H:%M')"
[ -f "$S/jev.py" ] || echo "  (jev.py yok: kırmızı beklenen hal)"
echo

echo "1) Varsayılan off: sıfır ağ çağrısı"
off_cikti=$(golge); k=$?
esit "off çıkış 0" "0" "$k"
esit "mod ayarı yokken sahte sunucu hiç istek almadı" "0" "$(istek)"
beklenen=$(python3 -c 'import json,sys; print(json.dumps(json.loads(sys.argv[1]),ensure_ascii=False,sort_keys=True,separators=(",",":")))' "$YEREL")
esit "off yerel sonucu kanonik JSON olarak teslim ediyor" "$beklenen" "$off_cikti"
o=$(BEYIN_JEV_MODE=off golge)
esit "açık off da sıfır çağrı" "0" "$(istek)"
echo '{"mod":"off"}' > "$v/.claude/jev.json"; golge >/dev/null
esit "dosyada off: sıfır çağrı" "0" "$(istek)"

echo
echo "2) shadow: istek gider, sonuç değişmez"
echo '{"mod":"shadow"}' > "$v/.claude/jev.json"
o=$(golge); k=$?
esit "shadow çıkış 0" "0" "$k"
esit "shadow sunucuya bir istek gönderdi" "1" "$(istek)"
esit "shadow çıktısı off ile bayt bayt aynı" "$off_cikti" "$o"
son=$(tail -n 1 "$gecici/istekler.log" 2>/dev/null)
case "$son" in *'Bearer test-anahtar-gercek-degil'*) gec "anahtar Authorization başlığında" ;; *) kal "anahtar başlıkta" "Bearer …" "${son:0:80}" ;; esac
case "$son" in *'jev-latest'*) gec "model jev-latest" ;; *) kal "model jev-latest" "jev-latest" "${son:0:120}" ;; esac
g=$(tail -n 1 "$GOZLEM" 2>/dev/null)
case "$g" in *'"mod":"shadow"'*'0.02'*|*'0.02'*'"mod":"shadow"'*) gec "öneri gözlem dosyasına düştü" ;; *) kal "öneri gözlemde" "mod shadow + 0.02" "${g:0:160}" ;; esac
icermez "gözlem state metnini yazmıyor" "emeklilik organı" "$g"
icermez "gözlem anahtarı yazmıyor" "test-anahtar" "$(cat "$GOZLEM" 2>/dev/null)"
esit "shadow stderr'e bir şey yazmıyor" "" "$(cat "$gecici/err")"
o=$(BEYIN_JEV_MODE=off golge)
esit "ortam dosyayı ezer: BEYIN_JEV_MODE=off → çağrı yok" "1" "$(istek)"
o=$(BEYIN_JEV_DISABLE=1 golge)
esit "kill switch shadow'u durduruyor" "1" "$(istek)"
o=$(BEYIN_JEV_MODE=on golge)
esit "on bu adımda yok: off gibi, çağrı yok" "1" "$(istek)"
esit "on isteğinde de sonuç aynı" "$off_cikti" "$o"

echo
echo "3) Sağlayıcı bozuk: sonuç aynı, süre sınırlı"
for m in yavas 500 bozuk; do
  echo "$m" > "$gecici/mod"
  bas=$(date +%s%N); o=$(golge); k=$?; sure=$(( ($(date +%s%N) - bas) / 1000000 ))
  esit "$m: çıkış 0" "0" "$k"
  esit "$m: sonuç off ile aynı" "$off_cikti" "$o"
  [ "$sure" -lt 3000 ] && gec "$m: süre sınırlı (${sure} ms < 3000)" || kal "$m: süre sınırlı" "<3000 ms" "$sure ms"
  case "$(tail -n 1 "$GOZLEM" 2>/dev/null)" in *'"degraded":true'*) gec "$m: gözlem degraded diyor" ;;
    *) kal "$m: degraded" '"degraded":true' "$(tail -n 1 "$GOZLEM" | head -c 160)" ;; esac
done
echo ok > "$gecici/mod"
( cd "$v" && BEYIN_JEV_URL="http://127.0.0.1:9/yok" timeout 20 python3 .claude/scripts/jev.py golge \
  --amac x --yerel "$YEREL" --sorular "$SORU" >"$gecici/o" 2>/dev/null ); k=$?
esit "sunucu hiç yokken çıkış 0" "0" "$k"
esit "sunucu hiç yokken sonuç aynı" "$off_cikti" "$(cat "$gecici/o")"

echo
echo "4) Anahtar yoksa shadow sessizce off'a iner"
once=$(istek)
o=$(TYPESAFE_API_KEY= golge); k=$?
esit "anahtarsız çıkış 0" "0" "$k"
esit "anahtarsız istek yok" "$once" "$(istek)"
esit "anahtarsız sonuç aynı" "$off_cikti" "$o"
esit "anahtarsız stderr boş (sessiz)" "" "$(cat "$gecici/err")"

echo
echo "5) Kasa içeriği isteğe asla girmez"
printf 'Not: 🔐 kasa/sifreler.md içinde GIZLI-DEGER-42 var.\n' > "$gecici/kasa-state.txt"
once=$(istek)
o=$(golge "$gecici/kasa-state.txt")
esit "kasa yolu geçen state ile istek yok" "$once" "$(istek)"
esit "kasa durumunda sonuç aynı" "$off_cikti" "$o"
mkdir -p "$gecici/🔐 kasa"; printf 'masum görünen metin\n' > "$gecici/🔐 kasa/a.md"
o=$(golge "$gecici/🔐 kasa/a.md")
esit "state dosyası kasadan okunuyorsa istek yok" "$once" "$(istek)"
printf 'api_key=sk-ant-abc123def456ghi789jkl012mno345\n' > "$gecici/sir-state.txt"
o=$(golge "$gecici/sir-state.txt")
esit "sır örüntüsü geçen state ile istek yok" "$once" "$(istek)"
icermez "sahte sunucu hiçbir zaman kasa içeriği görmedi" "GIZLI-DEGER" "$(cat "$gecici/istekler.log" 2>/dev/null)"

echo
echo "6) Anahtar dosyası (~/.config/jev/key)"
mkdir -p "$HOME/.config/jev"; printf 'dosya-anahtari-sahte\n' > "$HOME/.config/jev/key"
chmod 600 "$HOME/.config/jev/key"
once=$(istek)
o=$(TYPESAFE_API_KEY= golge); k=$?
esit "600 izinli dosyayla shadow istek gönderdi" "$((once+1))" "$(istek)"
case "$(tail -n 1 "$gecici/istekler.log")" in *'Bearer dosya-anahtari-sahte"'*) gec "dosyadaki anahtar kullanıldı (sondaki satır sonu atıldı)" ;;
  *) kal "dosya anahtarı başlıkta" "Bearer dosya-anahtari-sahte" "$(tail -n 1 "$gecici/istekler.log" | head -c 120)" ;; esac
esit "dosya anahtarıyla sonuç aynı" "$off_cikti" "$o"
icermez "gözlem dosya anahtarını yazmıyor" "dosya-anahtari" "$(cat "$GOZLEM")"
o=$(golge)
case "$(tail -n 1 "$gecici/istekler.log")" in *'test-anahtar-gercek-degil'*) gec "ortam dosyadan önce gelir" ;; *) kal "ortam önce" "ortam anahtarı" "dosya anahtarı" ;; esac
for izin in 644 640 604; do
  chmod "$izin" "$HOME/.config/jev/key"; once=$(istek)
  o=$(TYPESAFE_API_KEY= golge); k=$?
  esit "izin $izin: istek yok" "$once" "$(istek)"
  esit "izin $izin: sonuç aynı" "$off_cikti" "$o"
  case "$(tail -n 1 "$GOZLEM")" in *'"neden":"anahtar-izin"'*) gec "izin $izin: gözlem degraded anahtar-izin" ;;
    *) kal "izin $izin: anahtar-izin" "anahtar-izin" "$(tail -n 1 "$GOZLEM" | head -c 120)" ;; esac
done
chmod 600 "$HOME/.config/jev/key"
o=$(TYPESAFE_API_KEY= BEYIN_JEV_MODE=off golge)
esit "dosya varken off: istek yok" "$once" "$(istek)"
rm -f "$HOME/.config/jev/key"; : > "$GOZLEM"
o=$(TYPESAFE_API_KEY= golge)
esit "dosya da yoksa sessiz: gözlem boş" "" "$(cat "$GOZLEM")"

echo
echo "7) flush-deger kapandı (İyileştirme 5): flush shadow'da da Jev'i çağırmaz"
echo ok > "$gecici/mod"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"emeklilik testlerine bak"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"baktım"}]}}' > "$gecici/tr.jsonl"
fv() { local f="$gecici/$1"; mkdir -p "$f/.claude/scripts/.state" "$f/daily" "$f/knowledge"
  for x in flush.py olaylar.py projektor.py _portalock.py jev.py; do [ -f "$S/$x" ] && cp "$S/$x" "$f/.claude/scripts/"; done
  printf '%s' "$f"; }
fl() { printf '{"session_id":"%s","transcript_path":"%s"}' "$2" "$3" > "$gecici/hook-$2.json"
  (cd "$1" && BEYIN_FAKE_NOW=2026-09-25T19:00:00+03:00 timeout 30 python3 .claude/scripts/flush.py \
     --hook-input "$gecici/hook-$2.json" >/dev/null 2>&1); }
fs=$(fv flush-golge); echo '{"mod":"shadow"}' > "$fs/.claude/jev.json"
once=$(istek); fl "$fs" s1 "$gecici/tr.jsonl"
esit "shadow flush sunucuya istek atmadı" "$once" "$(istek)"
[ -s "$fs/daily/2026-09-25.md" ] && gec "flush kaydı yine yazıldı" || kal "flush kaydı" "daily var" "yok"
esit "defterde jev satırı yok" "0" "$(cat "$fs"/daily/olaylar/*.jsonl 2>/dev/null | grep -c '"tip":"jev"')"
fo3=$(fv flush-off3); rm -f "$fo3/.claude/scripts/jev.py"; fl "$fo3" s4 "$gecici/tr.jsonl"
[ -s "$fo3/daily/2026-09-25.md" ] && gec "jev.py yokken flush çalışıyor (Jev'siz taban)" || kal "jev.py yokken flush" "daily var" "yok"

echo
echo "8) J1–J4 (İyileştirme 5)"
echo damla > "$gecici/mod"
bas=$(date +%s%N); o=$(golge); sure=$(( ($(date +%s%N) - bas) / 1000000 ))
[ "$sure" -lt 2500 ] && gec "J1 damla sunucu: duvar saati sınırlı (${sure} ms)" || kal "J1 duvar saati" "<2500 ms" "$sure ms"
case "$(tail -n 1 "$GOZLEM")" in *'"neden":"sure"'*) gec "J1 gözlem degraded sure" ;; *) kal "J1 neden sure" "sure" "$(tail -n 1 "$GOZLEM" | head -c 120)" ;; esac
esit "J1 damlada sonuç aynı" "$off_cikti" "$o"
echo yavas > "$gecici/mod"; once=$(istek)
golge >/dev/null & p1=$!; sleep 0.3; golge >/dev/null; wait $p1
esit "J2 aynı anda tek çağrı (ikincisi istek atmadı)" "$((once+1))" "$(istek)"
grep -q '"neden":"mesgul"' "$GOZLEM" && gec "J2 ikinci çağrı degraded mesgul" || kal "J2 mesgul" "mesgul" "yok"
echo yarim > "$gecici/mod"; satir_once=$(grep -c . "$GOZLEM")
o=$(golge)
esit "bozuk HTTP yanıtında da gözlem düşüyor (sessiz hata yok)" "$((satir_once+1))" "$(grep -c . "$GOZLEM")"
esit "bozuk HTTP yanıtında sonuç aynı" "$off_cikti" "$o"
echo ok > "$gecici/mod"; once=$(istek)
o=$(golge "$gecici/state.txt" --kaynak "/ev/🔐 kasa/not.md")
esit "J3 kaynaklardan biri kasadaysa istek yok" "$once" "$(istek)"
o=$(golge "$gecici/state.txt" --kaynak "/ev/proje/not.md")
esit "J3 kasasız kaynakla istek gider" "$((once+1))" "$(istek)"
head -c 7000 /dev/zero | tr '\0' a > "$gecici/buyuk.txt"; once=$(istek)
o=$(golge "$gecici/buyuk.txt")
esit "J4 kaldırıldı: 7.000 karakterlik istek de gider" "$((once+1))" "$(istek)"
echo
echo "Sonuç: $gecen geçti, $kalan kaldı"
[ "$kalan" -eq 0 ]
