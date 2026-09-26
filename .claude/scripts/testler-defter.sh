#!/usr/bin/env bash
# Olay defteri düşman testleri — Organ 2 (SOZLESME Karar 4 + Karar 6 satır 2).
#
# Şartname: ~/ofis/ajans/seritler/2026-09-24-olay-defteri/emir.md. Testler o emrin
# arayüz sözleşmesine bağlı; uygulama bu dosyayı değiştirerek geçemez.
#
# Yan etkisiz: her bölüm kendi sahte vault'unda çalışır. Script'ler sahte vault'un
# .claude/scripts/ altına kopyalanır, kök script'in konumundan bulunur (flush.py gibi).
# HOME ve BEYIN_AJANS_DIR sahteye çevrilir: yedek.sh ek depoları ve pano varsayılanı
# gerçek dosyalara uzanamaz. Sonda gerçek defter ve panonun değişmediği ölçülür.
#
# olaylar.py yokken kırmızıdır; bu beklenen hal (PLAN adım 3).
#
# 2026-09-24: compile.py emekli, 5. bölüm derleme testleri projektöre taşındı, kullanıcı D kararı.
# 2026-09-24: gerçek defter koruması eşzamanlı yazıma dayanıklı (önek + test izi), gevşetme değil.
#
# Kullanım: testler-defter.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
S="$kok/.claude/scripts"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; return 0; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }
icerir() { case "$3" in *"$2"*) gec "$1" ;; *) kal "$1" "içinde '$2'" "${3:0:80}" ;; esac; }
icermez() { case "$3" in *"$2"*) kal "$1" "'$2' olmamalı" "${3:0:80}" ;; *) gec "$1" ;; esac; }

gecici=$(mktemp -d)
trap 'rm -rf "$gecici"' EXIT
export HOME="$gecici/ev" BEYIN_AJANS_DIR="$gecici/ajans-varsayilan" TMPDIR="$gecici"
unset BEYIN_INVOKED_BY
mkdir -p "$HOME"

# Gerçek dünyanın parmak izi: testten sonra aynı kalmalı.
# Defter yalnız eklenir; başka oturumlar koşu sırasında meşru satır ekleyebilir. Ölçü:
# eski içerik bayt bayt aynı + testin izi gerçek deftere girmedi + pano aynı.
HOME_GERCEK=$(getent passwd "$(id -un)" | cut -d: -f6)
defter_ham() { cat "$kok"/daily/olaylar/*.jsonl 2>/dev/null; }
defter_once="$gecici/defter-once"; defter_ham > "$defter_once"
pano_iz() { sha256sum < "$HOME_GERCEK/.config/beyin/ajans/pano.md" 2>/dev/null; }
pano_once=$(pano_iz)
TEST_IZI='"kaynak":"test"|test-oturum-|"session_id":"d6"'

# Sahte vault: script'ler kopyalanır. olaylar.py yoksa kopyalanmaz; testler kırmızı kalır.
sahte_vault() {
  local v="$gecici/$1"
  mkdir -p "$v/.claude/scripts/.state" "$v/daily" "$v/knowledge"
  for f in olaylar.py _portalock.py flush.py projektor.py yedek.sh; do
    [ -f "$S/$f" ] && cp "$S/$f" "$v/.claude/scripts/"
  done
  printf '%s' "$v"
}
# olaylar CLI'si sahte vault içinden (kök varsayılanı script konumu)
ol() { local v=$1; shift; (cd "$v" && timeout 60 python3 .claude/scripts/olaylar.py "$@"); }
satir() { cat "$1"/daily/olaylar/*.jsonl 2>/dev/null | grep -c . || :; }
ay=$(date +%Y-%m)

echo "Olay defteri düşman testleri — $(date '+%Y-%m-%d %H:%M')"
[ -f "$S/olaylar.py" ] || echo "  (olaylar.py yok: kırmızı beklenen hal)"
echo

echo "1) Şema ve idempotency"
v=$(sahte_vault d1)
o=$(ol "$v" yaz --tip makbuz --kimlik makbuz:deneme:1 --zaman 2026-09-24T10:00:00+03:00 \
      --kaynak test --veri '{"serit":"deneme","sonuc":"kabul","olcum":"x","ozet":"y","oturum":"s1"}' 2>&1); k=$?
esit "ilk olay yazılıyor (çıkış 0)" "0" "$k"
icerir "ilk olay 'yazildi' diyor" "yazildi" "$o"
[ -f "$v/daily/olaylar/2026-09.jsonl" ] && gec "ay dosyası zamandan seçiliyor (2026-09.jsonl)" \
  || kal "ay dosyası zamandan seçiliyor" "daily/olaylar/2026-09.jsonl" "$(ls "$v/daily/olaylar" 2>&1)"
# Hash'i şartnameden bağımsız hesapla: uygulamanın kendi söylediğine güvenme.
o=$(python3 - "$v/daily/olaylar/2026-09.jsonl" <<'PY' 2>&1
import hashlib, json, sys
k = lambda o: json.dumps(o, ensure_ascii=False, sort_keys=True, separators=(",", ":"))
satir = open(sys.argv[1], encoding="utf-8").read().splitlines()[0]
o = json.loads(satir)
assert satir == k(o), "kanonik değil"
assert set(o) == {"v", "tip", "kimlik", "zaman", "kaynak", "veri", "hash"}, sorted(o)
assert o["v"] == 1 and o["tip"] == "makbuz" and o["zaman"] == "2026-09-24T10:00:00+03:00"
h = "sha256:" + hashlib.sha256(k({"kimlik": o["kimlik"], "tip": o["tip"], "veri": o["veri"]}).encode()).hexdigest()
assert o["hash"] == h, "hash tutmuyor"
print("tamam")
PY
)
esit "satır kanonik, alanlar ve hash sözleşmeye uygun" "tamam" "$o"
o=$(ol "$v" yaz --tip makbuz --kimlik makbuz:deneme:1 --zaman 2026-09-24T11:30:00+03:00 \
      --kaynak test --veri '{"serit":"deneme","sonuc":"kabul","olcum":"x","ozet":"y","oturum":"s1"}' 2>&1); k=$?
esit "aynı olay (başka saatte) çıkış 0" "0" "$k"
icerir "aynı olay 'zaten-var' diyor" "zaten-var" "$o"
esit "aynı olay 2 kez → tek satır" "1" "$(satir "$v")"
ol "$v" yaz --tip makbuz --kimlik makbuz:deneme:1 --zaman 2026-09-24T12:00:00+03:00 \
  --veri '{"serit":"deneme","sonuc":"ret","olcum":"x","ozet":"y","oturum":"s1"}' >/dev/null 2>&1; k=$?
esit "aynı kimlik farklı içerik → çakışma (çıkış 3)" "3" "$k"
esit "çakışmada hiçbir şey yazılmıyor" "1" "$(satir "$v")"
ol "$v" yaz --tip gunluk --kimlik gunluk:x --veri '{}' >/dev/null 2>&1; k=$?
esit "bilinmeyen tip reddediliyor (çıkış 2)" "2" "$k"
ol "$v" yaz --tip yedek --kimlik oturum:x --veri '{}' >/dev/null 2>&1; k=$?
esit "kimlik öneki tiple uyuşmazsa reddediliyor (çıkış 2)" "2" "$k"
ol "$v" yaz --tip serit --kimlik serit:x:acildi --veri '{"ozet":"🔐 kasa/sifre.md"}' >/dev/null 2>&1; k=$?
esit "kasa yolu geçen olay reddediliyor (çıkış 2)" "2" "$k"
BEYIN_INVOKED_BY=codex-serit ol "$v" yaz --tip oturum --kimlik oturum:serit-oturumu:sessionend:3 \
  --veri '{"session_id":"serit-oturumu","sebep":"sessionend","tur":3}' >/dev/null 2>&1; k=$?
esit "BEYIN_INVOKED_BY doluyken reddediliyor (çıkış 4)" "4" "$k"
esit "reddedilenlerin hiçbiri yazılmadı" "1" "$(satir "$v")"
ol "$v" dogrula >/dev/null 2>&1; k=$?
esit "doğrula temiz defterde 0" "0" "$k"

echo
echo "2) Eşzamanlı iki yazıcı"
v=$(sahte_vault d2)
# İki süreç aynı anda yazar; 50 kimlik ikisinde ortak. Beklenen: 150+150+50, kayıp yok.
cat > "$gecici/yazici.py" <<'PY'
import sys
from pathlib import Path
kok = Path(sys.argv[1]); sys.path.insert(0, str(kok / ".claude" / "scripts"))
import olaylar
on = sys.argv[2]
kimlikler = [f"{on}{i}" for i in range(150)] + [f"ortak{i}" for i in range(50)]
if on == "b":
    kimlikler.reverse()
for k in kimlikler:
    olaylar.yaz(kok, "derleme", f"derleme:{k}", {"daily": k, "durum": "ok"},
                zaman="2026-09-24T10:00:00+03:00", kaynak="test")
PY
timeout 120 python3 "$gecici/yazici.py" "$v" a 2>"$gecici/a.err" & pa=$!
timeout 120 python3 "$gecici/yazici.py" "$v" b 2>"$gecici/b.err" & pb=$!
wait $pa; ka=$?; wait $pb; kb=$?
esit "iki yazıcı da hatasız bitti" "0 0" "$ka $kb"
esit "iki paralel yazıcı → satır kaybı yok (350)" "350" "$(satir "$v")"
tekil=$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | python3 -c 'import sys,json;print(len({json.loads(l)["kimlik"] for l in sys.stdin if l.strip()}))' 2>/dev/null)
esit "ortak kimlikler tek satır (350 tekil)" "350" "$tekil"
ol "$v" dogrula >/dev/null 2>&1; k=$?
esit "paralel yazım sonrası doğrula temiz" "0" "$k"

echo
echo "3) Kesilen yazım"
v=$(sahte_vault d3)
cat > "$gecici/sonsuz.py" <<'PY'
import sys
from pathlib import Path
kok = Path(sys.argv[1]); sys.path.insert(0, str(kok / ".claude" / "scripts"))
import olaylar
i = 0
while True:
    olaylar.yaz(kok, "serit", f"serit:{sys.argv[2]}-{i}:acildi",
                {"serit": f"{sys.argv[2]}-{i}", "proje": "p", "rol": "kodcu", "ajan": "codex",
                 "oturum": "s", "dolgu": "x" * 2000},
                zaman="2026-09-24T10:00:00+03:00", kaynak="test")
    i += 1
PY
pids=""
for n in 1 2 3 4; do python3 "$gecici/sonsuz.py" "$v" "y$n" 2>/dev/null & pids="$pids $!"; done
sleep 1.5
kill -9 $pids 2>/dev/null; wait $pids 2>/dev/null
n=$(satir "$v")
[ "${n:-0}" -gt 0 ] && gec "öldürülen yazıcılar önce yazabildi ($n satır)" || kal "öldürülen yazıcılar önce yazabildi" ">0 satır" "$n"
bozuk=$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | python3 -c '
import sys, json
b = 0
for l in sys.stdin.read().split("\n")[:-1]:
    try: json.loads(l)
    except ValueError: b += 1
print(b)' 2>/dev/null)
esit "kill -9 sonrası bozuk satır yok" "0" "$bozuk"
ol "$v" dogrula >/dev/null 2>&1; k=$?
esit "kill -9 sonrası doğrula temiz" "0" "$k"

v=$(sahte_vault d3b)
ol "$v" yaz --tip yedek --kimlik yedek:abc:ok --zaman 2026-09-24T10:00:00+03:00 \
  --veri '{"commit":"abc","gonderilen":1,"sonuc":"ok"}' >/dev/null 2>&1
printf '{"v":1,"tip":"serit","kimlik":"serit:yar' >> "$v/daily/olaylar/2026-09.jsonl"
ol "$v" dogrula >/dev/null 2>&1; k=$?
esit "kırık kuyruğu doğrula yakalıyor (çıkış 1)" "1" "$k"
ol "$v" yaz --tip yedek --kimlik yedek:def:ok --zaman 2026-09-24T11:00:00+03:00 \
  --veri '{"commit":"def","gonderilen":1,"sonuc":"ok"}' >/dev/null 2>&1; k=$?
esit "kırık kuyruktan sonra yazım başarılı" "0" "$k"
esit "kırık parça kayıt sayılmıyor (2 satır)" "2" "$(satir "$v")"
ol "$v" dogrula >/dev/null 2>&1; k=$?
esit "kırık kuyruk kesildi, doğrula temiz" "0" "$k"
parca=$(cat "$v"/.claude/scripts/.state/olaylar-kirik-*.parca 2>/dev/null)
icerir "kırık parça silinmedi, saklandı" "serit:yar" "$parca"
icerir "kırık kuyruk sessiz kalmıyor (health.json)" "olaylar-kirik-kuyruk" "$(cat "$v/.claude/scripts/.state/health.json" 2>/dev/null)"

echo
echo "4) Pano defterden üretiliyor"
v=$(sahte_vault d4); a="$gecici/ajans"
mkdir -p "$a/seritler/2026-01-01-a" "$a/seritler/2026-01-02-b"
printf '# Pano\n\n## Açık\n\n| elle-yazilmis | x | x | x | x |\n' > "$a/pano.md"
s() { ol "$v" yaz --tip serit --kimlik "serit:$1:$2" --zaman "$3" --kaynak test \
        --veri "{\"serit\":\"$1\",\"proje\":\"$4\",\"rol\":\"kodcu\",\"ajan\":\"codex\",\"oturum\":\"s1\"}" >/dev/null 2>&1; }
s 2026-01-01-a acildi 2026-01-01T10:00:00+03:00 ProjeA
s 2026-01-02-b acildi 2026-01-02T10:00:00+03:00 ProjeB
s 2026-01-02-b kesildi 2026-01-02T10:30:00+03:00 ProjeB
ol "$v" yaz --tip makbuz --kimlik makbuz:2026-01-01-a:1 --zaman 2026-01-03T09:00:00+03:00 \
  --veri '{"serit":"2026-01-01-a","sonuc":"kabul","olcum":"testler yeşil","ozet":"tamam","oturum":"s1"}' >/dev/null 2>&1
ol "$v" pano --ajans "$a" >/dev/null 2>&1; k=$?
esit "pano üretimi çıkış 0" "0" "$k"
p=$(cat "$a/pano.md" 2>/dev/null)
acik=$(printf '%s\n' "$p" | awk '/^## Açık/{f=1;next} /^## /{f=0} f')
teslim=$(printf '%s\n' "$p" | awk '/^## Teslim/{f=1;next} /^## /{f=0} f')
icermez "elle yazılan satır üretimde siliniyor" "elle-yazilmis" "$p"
icerir "kesilen şerit kaybolmuyor, açıkta görünüyor" "2026-01-02-b" "$acik"
icerir "kesilen şeridin durumu 'kesildi'" "kesildi" "$(printf '%s\n' "$acik" | grep 2026-01-02-b)"
icerir "açık satır projeyi defterden alıyor" "ProjeB" "$acik"
# Boş bölüm "açıkta değil" testini boşuna geçirmesin: açık bölüm dolu olmalı.
case "$acik" in *2026-01-02-b*) icermez "makbuzlu şerit açıkta değil" "2026-01-01-a" "$acik" ;;
  *) kal "makbuzlu şerit açıkta değil" "dolu açık bölüm" "açık bölüm boş" ;; esac
icerir "makbuzlu şerit teslimde, sonucuyla" "kabul" "$(printf '%s\n' "$teslim" | grep 2026-01-01-a)"
icerir "teslim tarihi makbuz anı" "2026-01-03" "$(printf '%s\n' "$teslim" | grep 2026-01-01-a)"
cp "$a/pano.md" "$gecici/pano-1" 2>/dev/null
ol "$v" pano --ajans "$a" >/dev/null 2>&1
# Hiç üretilmemiş pano da "aynı" kalır; bu yüzden önce üretilmiş olmalı.
if ! grep -q ProjeB "$gecici/pano-1" 2>/dev/null; then kal "aynı defter → bayt bayt aynı pano" "üretilmiş pano" "üretilmedi"
elif cmp -s "$a/pano.md" "$gecici/pano-1"; then gec "aynı defter → bayt bayt aynı pano"
else kal "aynı defter → bayt bayt aynı pano" "özdeş" "farklı"; fi
icerir "makbuz.md defterden üretiliyor" "kabul" "$(cat "$a/seritler/2026-01-01-a/makbuz.md" 2>/dev/null)"
[ -e "$a/seritler/2026-01-02-b/makbuz.md" ] && kal "makbuzsuz şeride makbuz.md yazılmıyor" "yok" "var" \
  || gec "makbuzsuz şeride makbuz.md yazılmıyor"
(cd "$v" && timeout 60 python3 .claude/scripts/olaylar.py pano >/dev/null 2>&1)
[ -f "$BEYIN_AJANS_DIR/pano.md" ] && gec "ajans yolu BEYIN_AJANS_DIR'den okunuyor" \
  || kal "ajans yolu BEYIN_AJANS_DIR'den okunuyor" "$BEYIN_AJANS_DIR/pano.md" "yok"

echo
echo "5) Üreticiler deftere yazıyor"
# olay arama: tip + kimlik öneki (+ isteğe bağlı sonek); bulunanın verisini yazdırır
bul() { cat "$1"/daily/olaylar/*.jsonl 2>/dev/null | python3 -c '
import sys, json
for l in sys.stdin:
    try: o = json.loads(l)
    except ValueError: continue
    k = o.get("kimlik", "")
    if o.get("tip") == sys.argv[1] and k.startswith(sys.argv[2]) and k.endswith(sys.argv[3]):
        print(json.dumps(o.get("veri", {}), ensure_ascii=False, sort_keys=True)); break' "$2" "$3" "${4:-}" 2>/dev/null; }

v=$(sahte_vault d5)
tr="$gecici/transcript.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"deftere bak"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"baktım"}]}}' > "$tr"
printf '{"session_id":"test-oturum-1","transcript_path":"%s"}' "$tr" > "$gecici/hook1.json"
(cd "$v" && BEYIN_FAKE_HOUR=10 timeout 60 python3 .claude/scripts/flush.py --hook-input "$gecici/hook1.json" >/dev/null 2>&1)
[ -n "$(ls "$v"/daily/*.md 2>/dev/null)" ] && gec "flush sahte vault'ta çalıştı (daily yazıldı)" \
  || kal "flush sahte vault'ta çalıştı" "daily/*.md" "yok"
icerir "flush oturum olayı yazıyor" "test-oturum-1" "$(bul "$v" oturum oturum:test-oturum-1:sessionend:)"
printf '{"session_id":"test-oturum-2","transcript_path":"%s"}' "$tr" > "$gecici/hook2.json"
(cd "$v" && BEYIN_INVOKED_BY=codex-serit BEYIN_FAKE_HOUR=10 timeout 60 python3 .claude/scripts/flush.py --hook-input "$gecici/hook2.json" >/dev/null 2>&1)
esit "şerit oturum sayılmıyor (BEYIN_INVOKED_BY)" "" "$(bul "$v" oturum oturum:test-oturum-2:)"

v=$(sahte_vault d6)
# Derleme projektördür (compile.py emekli). Hata yolu: log.md yazılamaz → sağlığa düşer.
ol "$v" yaz --tip oturum --kimlik oturum:d6:sessionend:1 --zaman 2026-09-01T10:00:00+03:00 --kaynak test \
  --veri '{"session_id":"d6","sebep":"sessionend","tur":1,"ozet":[]}' >/dev/null 2>&1
mkdir -p "$v/knowledge/log.md"
(cd "$v" && timeout 60 python3 .claude/scripts/projektor.py --gun 2026-09-01 >/dev/null 2>&1)
icerir "derleme hatası sağlığa düşüyor (health.json)" "projektor:" "$(cat "$v/.claude/scripts/.state/health.json" 2>/dev/null)"
rmdir "$v/knowledge/log.md"
(cd "$v" && timeout 60 python3 .claude/scripts/projektor.py --gun 2026-09-01 >/dev/null 2>&1)
icerir "başarılı derleme deftere düşüyor" '"durum": "ok"' "$(bul "$v" derleme derleme:2026-09-01.md: :ok)"

v=$(sahte_vault d7); uzak="$gecici/uzak.git"
git init -q --bare "$uzak"
(
  cd "$v" && git init -q -b main && git config user.email t@t && git config user.name t &&
  git remote add origin "$uzak" && git add -A && git commit -qm ilk && git push -qu origin main
) >/dev/null 2>&1
: > "$v/yeni.md"
(cd "$v" && timeout 60 bash .claude/scripts/yedek.sh >/dev/null 2>&1)
bas=$(git -C "$v" rev-parse HEAD 2>/dev/null)
o=$(bul "$v" yedek "yedek:$bas:")
icerir "yedek başarılı push'u deftere yazıyor" '"sonuc": "ok"' "$o"
icerir "yedek olayı gönderilen commit'i taşıyor" "$bas" "$o"
git -C "$v" remote set-url origin "$gecici/olmayan.git"
: > "$v/yeni2.md"
(cd "$v" && timeout 60 bash .claude/scripts/yedek.sh >/dev/null 2>&1)
bas=$(git -C "$v" rev-parse HEAD 2>/dev/null)
icerir "başarısız push da deftere düşüyor" "push-basarisiz" "$(bul "$v" yedek "yedek:$bas:")"

# Yedek kapısı (kullanıcı, 24 Eylül): testler kırmızıysa commit yok, kullanıcıya söylenir.
git -C "$v" remote set-url origin "$uzak"
printf '#!/usr/bin/env bash\necho "Sonuç: 1 geçti, 2 kaldı"; exit 1\n' > "$v/.claude/scripts/testler.sh"
git -C "$v" add -A >/dev/null 2>&1; git -C "$v" commit -qm testler >/dev/null 2>&1
bas_once=$(git -C "$v" rev-parse HEAD); : > "$v/kirmizi.md"
(cd "$v" && unset BEYIN_TESTLER_KOSUYOR && timeout 60 bash .claude/scripts/yedek.sh >/dev/null 2>&1)
esit "testler kırmızıyken yedek commit atmıyor" "$bas_once" "$(git -C "$v" rev-parse HEAD)"
icerir "kırmızı yedek açılış bayrağı bırakıyor" "testler kırmızı" "$(cat "$v/.claude/scripts/.state/yedek-basarisiz" 2>/dev/null)"
icerir "kırmızı yedek deftere düşüyor" "testler-kirmizi" "$(bul "$v" yedek "yedek:$bas_once:")"
printf '#!/usr/bin/env bash\nexit 0\n' > "$v/.claude/scripts/testler.sh"
(cd "$v" && unset BEYIN_TESTLER_KOSUYOR && timeout 60 bash .claude/scripts/yedek.sh >/dev/null 2>&1)
[ "$(git -C "$v" rev-parse HEAD)" != "$bas_once" ] && gec "testler yeşilken yedek commit atıyor" \
  || kal "testler yeşilken yedek commit atıyor" "yeni commit" "$bas_once"
[ ! -f "$v/.claude/scripts/.state/yedek-basarisiz" ] && gec "yeşil yedek bayrağı kaldırıyor" \
  || kal "yeşil yedek bayrağı kaldırıyor" "bayrak yok" "bayrak duruyor"

# Tek yedek (25 Eylül): iki yedek aynı anda çalışınca testler çarpışmamalı. Sahte takım,
# kendisinin ikinci kopyası koşarken kırmızı döner; kilit yoksa bu bölüm kırmızıdır.
printf '#!/usr/bin/env bash\nk="$(dirname "$0")/.state/kosuyor"\nmkdir "$k" 2>/dev/null || { echo "Sonuç: 0 geçti, 1 kaldı"; exit 1; }\nsleep 2; rmdir "$k"; exit 0\n' \
  > "$v/.claude/scripts/testler.sh"
git -C "$v" add -A >/dev/null 2>&1; git -C "$v" commit -qm carpisma >/dev/null 2>&1
bas_once=$(git -C "$v" rev-parse HEAD); : > "$v/paralel.md"
# Bayrağa bakmak yetmez: kırmızı yedeğin bayrağını yanındaki yeşil yedek siler. Defter kalıcıdır.
kirmizi_once=$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | grep -c testler-kirmizi)
(cd "$v" && unset BEYIN_TESTLER_KOSUYOR && timeout 60 bash .claude/scripts/yedek.sh >/dev/null 2>&1) &
(cd "$v" && unset BEYIN_TESTLER_KOSUYOR && timeout 60 bash .claude/scripts/yedek.sh >/dev/null 2>&1) &
wait
esit "aynı anda iki yedek birbirini kırmızıya düşürmüyor" "$kirmizi_once" \
  "$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | grep -c testler-kirmizi)"
icermez "paralel yedekten sonra değişiklik commit'lendi" "paralel.md" "$(git -C "$v" status --porcelain)"
[ "$(git -C "$v" rev-parse HEAD)" != "$bas_once" ] && gec "paralel yedek commit attı" \
  || kal "paralel yedek commit attı" "yeni commit" "$bas_once"

echo
echo "6) Gerçek dosyalar"
boy=$(wc -c < "$defter_once")
esit "gerçek defterin eski içeriği değişmedi" "$(sha256sum < "$defter_once")" "$(defter_ham | head -c "$boy" | sha256sum)"
o=$(defter_ham | tail -c +"$((boy + 1))" | grep -E "$TEST_IZI")
[ -z "$o" ] && gec "testin izi gerçek deftere girmedi" || kal "testin izi gerçek deftere girmedi" "iz yok" "${o:0:80}"
esit "gerçek pano değişmedi" "$pano_once" "$(pano_iz)"

echo
printf 'Sonuç: %s geçti, %s kaldı\n' "$gecen" "$kalan"
[ "$kalan" -eq 0 ]
