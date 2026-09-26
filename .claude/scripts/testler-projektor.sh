#!/usr/bin/env bash
# Projektör düşman testleri — Organ 3 (SOZLESME Karar 4 + Karar 6 satır 3).
#
# Şartname: ~/ofis/ajans/seritler/2026-09-24-projektor/emir.md. Ölçüt: compile.py
# silinmişken daily/*.md ve knowledge/ üretilir, "claude -p" hiçbir yerde yok,
# 17–22 Eylül derlenebilir. Kavram çıkarımı (AÇIK SORU 1) bu takımın dışında.
#
# Yan etkisiz: sahte vault'ta çalışır, compile.py oraya hiç kopyalanmaz. Gerçek
# depoya yalnız okumak için bakılır (grep); sonda gerçek daily ve log'un değişmediği ölçülür.
#
# projektor.py yokken kırmızıdır; bu beklenen hal (PLAN adım 6, yalnız şartname).
#
# 2026-09-24: log.md ve defter koruması eşzamanlı yazıma dayanıklı (önek + test izi), gevşetme değil.
#
# Kullanım: testler-projektor.sh [-v]
set -uo pipefail
kok="$(cd "$(dirname "$(readlink -f "$0")")/../.." && pwd)"
S="$kok/.claude/scripts"
H="$kok/.claude/hooks"
ayrintili=${1:-}
gecen=0; kalan=0

gec() { gecen=$((gecen+1)); printf '  ✅ %s\n' "$1"; }
kal() { kalan=$((kalan+1)); printf '  ❌ %s\n' "$1"; [ -n "$ayrintili" ] && printf '     beklenen: %s\n     gelen:    %s\n' "$2" "$3"; return 0; }
esit() { [ "$2" = "$3" ] && gec "$1" || kal "$1" "$2" "$3"; }
icerir() { case "$3" in *"$2"*) gec "$1" ;; *) kal "$1" "içinde '$2'" "${3:0:80}" ;; esac; }
icermez() { case "$3" in *"$2"*) kal "$1" "'$2' olmamalı" "${3:0:80}" ;; *) gec "$1" ;; esac; }
bos_mu() { [ -z "$3" ] && gec "$1" || kal "$1" "boş çıktı" "${3:0:80}"; }

gecici=$(mktemp -d)
trap 'rm -rf "$gecici"' EXIT
export HOME="$gecici/ev" BEYIN_AJANS_DIR="$gecici/ajans" TMPDIR="$gecici"
unset BEYIN_INVOKED_BY
mkdir -p "$HOME"

# Model çağrısı tuzağı: claude ya da codex çalışırsa iz bırakır.
tuzak="$gecici/bin"; mkdir -p "$tuzak"
for m in claude codex agy; do printf '#!/bin/sh\n: > "%s/MODEL-CAGRILDI-%s"\nexit 0\n' "$gecici" "$m" > "$tuzak/$m"; chmod +x "$tuzak/$m"; done
export PATH="$tuzak:$PATH"

# Bugünün daily'si hariç: başka bir oturumun kapanışı onu meşru olarak büyütebilir.
# log.md ve defter yalnız eklenir (açılış projeksiyonu, derle, flush koşu sırasında yazabilir):
# onlarda ölçü eski içeriğin bayt bayt aynı kalması ve testin izinin girmemesidir.
iz() { find "$kok/daily" -maxdepth 1 -name '*.md' ! -name "$(date +%F).md" -print0 2>/dev/null | sort -z \
         | xargs -0 cat 2>/dev/null | sha256sum; }
iz_once=$(iz)
log_once="$gecici/log-once"; cat "$kok/knowledge/log.md" > "$log_once" 2>/dev/null
defter_ham() { cat "$kok"/daily/olaylar/*.jsonl 2>/dev/null || true; }  # yeni kurulumda defter yok
defter_once="$gecici/defter-once"; defter_ham > "$defter_once"
# Sahte oturumlar ve sahte günler: gerçek deftere ya da log'a sızarsa izleri bunlardır.
TEST_IZI='"session_id":"(s1[0179]|s2[02][ab]?|s20b|uctan-uca-1)"|projeksiyon \| 2026-09-(1[0179]|2[025])\.md'
onek_ayni() { local boy; boy=$(wc -c < "$1"); [ "$(head -c "$boy" | sha256sum)" = "$(sha256sum < "$1")" ]; }
yeni_kisim() { tail -c +"$(( $(wc -c < "$1") + 1 ))"; }

sahte_vault() {
  local v="$gecici/$1"
  mkdir -p "$v/.claude/scripts/.state" "$v/daily" "$v/knowledge"
  printf '# Derleme Günlüğü\n' > "$v/knowledge/log.md"
  for f in olaylar.py _portalock.py flush.py projektor.py; do
    [ -f "$S/$f" ] && cp "$S/$f" "$v/.claude/scripts/"
  done
  printf '%s' "$v"
}
pj() { local v=$1; shift; (cd "$v" && timeout 60 python3 .claude/scripts/projektor.py "$@"); }
ol() { local v=$1; shift; (cd "$v" && timeout 60 python3 .claude/scripts/olaylar.py "$@"); }
# oturum olayı: gün, saat, oturum, sebep, açılış
oturum() {
  ol "$1" yaz --tip oturum --kimlik "oturum:$4:$5:3" --zaman "$2T$3:00+03:00" --kaynak flush.py \
    --veri "{\"session_id\":\"$4\",\"sebep\":\"$5\",\"tur\":3,\"daily\":\"daily/$2.md\",\"ozet\":[],\"acilis\":\"$6\",\"dosyalar\":[\"a.md\"],\"komutlar\":[\"ls\"]}" >/dev/null 2>&1
}
isaret='<!-- projeksiyon: daily/olaylar -->'

echo "Projektör düşman testleri — $(date '+%Y-%m-%d %H:%M')"
[ -f "$S/projektor.py" ] || echo "  (projektor.py yok: kırmızı beklenen hal)"
echo

echo "1) Emeklilik (gerçek depoda yalnız okuma)"
# --exclude, "--"dan önce: sonrası dosya yolu sayılır (ilk sürümde hariç tutma çalışmıyordu).
o=$(grep -rn --exclude=testler-projektor.sh -- "claude -p" "$kok/.claude" 2>/dev/null)
bos_mu "grep \"claude -p\" boş dönüyor" "" "$o"
if [ -e "$S/compile.py" ]; then kal "compile.py emekli" "dosya yok" "duruyor"; else gec "compile.py emekli"; fi
o=$(grep -n "compile.py\|maybe.compile" "$S/flush.py" "$H/session-start.sh" 2>/dev/null)
bos_mu "flush ve açılış compile'ı tetiklemiyor" "" "$o"
[ -f "$S/projektor.py" ] && gec "projektor.py var" || kal "projektor.py var" "dosya" "yok"

echo
echo "2) 17–22 Eylül defterden yansıyor (compile.py yokken)"
v=$(sahte_vault p1)
oturum "$v" 2026-09-17 10:00 s17 sessionend "on yedi"
oturum "$v" 2026-09-19 10:00 s19 sessionend "on dokuz"
oturum "$v" 2026-09-20 10:00 s20 sessionend "yirmi"
oturum "$v" 2026-09-22 15:30 s22b precompact "ikinci oturum"   # sonra olan önce yazılır
oturum "$v" 2026-09-22 09:00 s22a sessionend "birinci oturum"
o=$(pj "$v" --hepsi 2>&1); k=$?
esit "projektör çıkış 0" "0" "$k"
n=0; for g in 17 19 20 22; do [ -f "$v/daily/2026-09-$g.md" ] && n=$((n+1)); done
esit "dört günün daily'si üretildi" "4" "$n"
d22=$(cat "$v/daily/2026-09-22.md" 2>/dev/null)
icerir "daily başlığı flush biçiminde" "# Günlük Log: 2026-09-22" "$d22"
icerir "yansıma işaretli" "$isaret" "$d22"
icerir "açılış isteği kayıtta" "birinci oturum" "$d22"
icerir "precompact işareti korunuyor" "### Oturum (15:30), compaction öncesi" "$d22"
sira=$(printf '%s\n' "$d22" | grep -o '### Oturum ([0-9:]*)' | tr '\n' ' ')
esit "oturumlar zaman sırasında" "### Oturum (09:00) ### Oturum (15:30) " "$sira"
icermez "gün başka günün oturumunu almıyor" "on yedi" "$d22"
log=$(cat "$v/knowledge/log.md" 2>/dev/null)
esit "her gün için tek projeksiyon bloğu" "4" "$(grep -c '^## \[[0-9-]\{10\}.*\] projeksiyon | 2026-09-' "$v/knowledge/log.md" 2>/dev/null || echo 0)"
icerir "log bloğu günü adlandırıyor" "projeksiyon | 2026-09-19.md" "$log"
der=$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | grep -c '"kaynak":"projektor.py".*"tip":"derleme"' || :)
esit "her gün bir derleme olayı (kaynak projektor.py)" "4" "$der"
ol "$v" dogrula >/dev/null 2>&1; k=$?
esit "defter projeksiyondan sonra temiz" "0" "$k"

echo
echo "3) Deterministik ve idempotent"
cp "$v/daily/2026-09-22.md" "$gecici/d22" 2>/dev/null
rm -f "$v/daily/2026-09-22.md"
pj "$v" --gun 2026-09-22 >/dev/null 2>&1
cmp -s "$v/daily/2026-09-22.md" "$gecici/d22" && [ -s "$gecici/d22" ] \
  && gec "silinen daily bayt bayt geri geliyor" || kal "silinen daily bayt bayt geri geliyor" "özdeş" "farklı ya da yok"
satir_once=$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | wc -l)
o=$(pj "$v" --hepsi 2>&1)
icerir "ikinci çalıştırma 'degismedi' diyor" "degismedi" "$o"
esit "ikinci çalıştırma log bloğu eklemiyor" "4" "$(grep -c '] projeksiyon | ' "$v/knowledge/log.md" 2>/dev/null || echo 0)"
esit "ikinci çalıştırma deftere satır eklemiyor" "$satir_once" "$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null | wc -l)"
oturum "$v" 2026-09-20 18:00 s20b sessionend "yeni oturum"
pj "$v" --gun 2026-09-20 >/dev/null 2>&1
icerir "yeni olay günü yeniden yansıtıyor" "yeni oturum" "$(cat "$v/daily/2026-09-20.md" 2>/dev/null)"
esit "değişen gün yeni log bloğu alıyor" "2" "$(grep -c '] projeksiyon | 2026-09-20.md' "$v/knowledge/log.md" 2>/dev/null || echo 0)"

echo
echo "4) Defter öncesi tarih ve kuru çalıştırma"
v=$(sahte_vault p2)
printf '# Günlük Log: 2026-09-10\n\n## Oturumlar\n\n### Oturum (08:00)\n\nelle-eski-kayit\n' > "$v/daily/2026-09-10.md"
once=$(sha256sum < "$v/daily/2026-09-10.md")
oturum "$v" 2026-09-10 12:00 s10 sessionend "gec gelen"
o=$(pj "$v" --gun 2026-09-10 2>&1)
esit "işaretsiz daily'ye dokunulmuyor" "$once" "$(sha256sum < "$v/daily/2026-09-10.md")"
icerir "işaretsiz gün sessiz geçilmiyor ('atlandi')" "atlandi" "$o"
oturum "$v" 2026-09-11 12:00 s11 sessionend "kuru"
pj "$v" --gun 2026-09-11 --dene >/dev/null 2>&1
if [ -e "$v/daily/2026-09-11.md" ]; then kal "--dene daily yazmıyor" "yok" "yazdı"; else gec "--dene daily yazmıyor"; fi
icermez "--dene log yazmıyor" "2026-09-11" "$(cat "$v/knowledge/log.md")"
icermez "--dene derleme olayı yazmıyor" "derleme:2026-09-11" "$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null)"

echo
echo "5) Uçtan uca: flush → yansıma (compile.py yok)"
v=$(sahte_vault p3)
# Eski bir derleme girdisi: projeksiyon bloğu gelmezse sağlık satırı "derlenmiyor" der.
printf '\n## [2026-09-01T10:00:00+03:00] compile | 2026-09-01.md\n\neski\n' >> "$v/knowledge/log.md"
tr="$gecici/transcript.jsonl"
printf '%s\n' '{"type":"user","message":{"role":"user","content":"projektore bak"}}' \
  '{"type":"assistant","message":{"role":"assistant","content":[{"type":"text","text":"baktım"}]}}' > "$tr"
printf '{"session_id":"uctan-uca-1","transcript_path":"%s"}' "$tr" > "$gecici/hook.json"
# 19:00: eskiden compile'ı tetikleyen saat. Artık model yok, yansıma eşzamanlı.
(cd "$v" && BEYIN_FAKE_NOW=2026-09-25T19:00:00+03:00 timeout 60 python3 .claude/scripts/flush.py --hook-input "$gecici/hook.json" >/dev/null 2>&1)
d=$(cat "$v/daily/2026-09-25.md" 2>/dev/null)
icerir "flush sonrası daily bir yansıma" "$isaret" "$d"
icerir "yansıma oturumu içeriyor" "projektore bak" "$d"
icerir "oturum olayı kaydı tam taşıyor (acilis)" '"acilis":"projektore bak"' "$(cat "$v"/daily/olaylar/*.jsonl 2>/dev/null)"
cp "$v/daily/2026-09-25.md" "$gecici/d25" 2>/dev/null
rm -f "$v/daily/2026-09-25.md"
pj "$v" --gun 2026-09-25 >/dev/null 2>&1
cmp -s "$v/daily/2026-09-25.md" "$gecici/d25" && [ -s "$gecici/d25" ] \
  && gec "flush'ın daily'si defterden bayt bayt yeniden üretiliyor" || kal "flush'ın daily'si defterden yeniden üretiliyor" "özdeş" "farklı ya da yok"
o=$(cd "$v/.claude/scripts" && python3 - "$v" 2>&1 <<'PY'
import sys
from pathlib import Path
sys.dont_write_bytecode = True
sys.path.insert(0, ".")
import flush, projektor
kok = Path(sys.argv[1])
beklenen = flush.build_session_record(
    [("user", "merhaba  dünya"), ("assistant", "selam")],
    {"files": [str(kok / "notlar" / "a.md")], "commands": ["ls   -la"]},
    "abcdef1234", 2, ["2026-09-25-1.md"], kok)
veri = {"session_id": "abcdef1234", "sebep": "sessionend", "tur": 2, "daily": "daily/2026-09-25.md",
        "ozet": ["2026-09-25-1.md"], "acilis": "merhaba dünya", "dosyalar": ["notlar/a.md"], "komutlar": ["ls -la"]}
print("ayni" if projektor.kayit_metni(veri) == beklenen else "farkli")
PY
)
esit "kayit_metni flush.build_session_record ile aynı" "ayni" "$o"
o=$(bash "$H/saglik.sh" "$v" 2>/dev/null)
icermez "projeksiyon sağlık satırının derleme ölçüsünü besliyor" "derlenmiyor" "$o"

echo
echo "6) Model ve gerçek dosyalar"
bos_mu "hiçbir model çağrılmadı (claude/codex/agy tuzağı)" "" "$(ls "$gecici"/MODEL-CAGRILDI-* 2>/dev/null)"
esit "gerçek daily'ler (bugün hariç) değişmedi" "$iz_once" "$(iz)"
{ cat "$kok/knowledge/log.md" 2>/dev/null || true; } | onek_ayni "$log_once" \
  && gec "gerçek log.md'nin eski içeriği değişmedi" || kal "gerçek log.md'nin eski içeriği değişmedi" "önek aynı" "değişti"
defter_ham | onek_ayni "$defter_once" \
  && gec "gerçek defterin eski içeriği değişmedi" || kal "gerçek defterin eski içeriği değişmedi" "önek aynı" "değişti"
o=$( { cat "$kok/knowledge/log.md" 2>/dev/null | yeni_kisim "$log_once"; defter_ham | yeni_kisim "$defter_once"; } | grep -E "$TEST_IZI")
[ -z "$o" ] && gec "testin izi gerçek log'a ve deftere girmedi" || kal "testin izi gerçek log'a ve deftere girmedi" "iz yok" "${o:0:80}"

echo
printf 'Sonuç: %s geçti, %s kaldı\n' "$gecen" "$kalan"
[ "$kalan" -eq 0 ]
