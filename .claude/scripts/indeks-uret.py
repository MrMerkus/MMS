#!/usr/bin/env python3
"""İndeks taslağı üretir. Kararı insana bırakır, yazımı üstlenir.

Neden var: "İndeks satırını yazan taraf yazar" kuralı, sistemin kendi tezine
("kural yeterli değildir") aykırıydı. Bu script tutarsızlığı kapatır.

Neden taslak: indeks satırının "ne zaman aç" sütunu bir yargıdır, script
üretemez. Bu yüzden elle yazılmış açıklamalar KORUNUR, yalnızca eksik satırlar
eklenir ve silinen dosyaların satırları çıkarılır.

Neden üç dosya: tek indeks 6.100 karaktere çıkıp yükleyicinin 4.600'lük
tavanında sessizce kırpıldı — alttaki satırlar yazılı ama görünmezdi. Kesim
konuya göre değil DURUMA göre yapılır: karar bekleyen üstte kalır, sessizce
aktif olan bir alt dosyaya, uyuyan bir alta iner. Bölmeyi script yapar, çünkü
elle bölünen indeks ilk üretimde geri düzlenir.

Kullanım:
  indeks-uret.py "🔮 zihin/kalan-isler"          # yaz
  indeks-uret.py "🔮 zihin/kalan-isler" --dene   # yalnızca farkı göster
"""
import os
import re
import sys
from datetime import date, datetime
from pathlib import Path

ONCELIK = {"🔴": 0, "🟡": 1, "🟢": 2, "⚪": 3, "⏸️": 4, "✅": 5}
RENKLER = ["🔴", "🟡", "🟢", "⏸️", "⚪", "✅"]

# Katman = durum. Tavanı aşmak (⚠️) katmanı değiştirmez: terfi, uyuyan dosyaları
# açılışa taşıyıp karar bekleyenlerin yerini alıyordu (test günü C, 25 Eylül).
# Açılış dosyası (INDEKS.md) yine de her açık konuyu tek kısa satırla gösterir:
# sorular konu hakkındadır, durum hakkında değil.
ON, ORTA, ALT = "on", "orta", "alt"
KATMAN_DOSYA = {ON: "INDEKS.md", ORTA: "INDEKS-aktif.md", ALT: "INDEKS-uyuyan.md"}

# Emeklilik (organ 4, SOZLESME Karar 1): uzun süre dokunulmamış 🟡/🟢 kayıt
# enjeksiyondan düşer, dosyası yerinde kalır, soğuk indekste tek satır iz bırakır.
# Karar burada verilir ki indeks-uret tek başına çalışınca da soğuk satır geri
# dönmesin; tek yazıcı bu script'tir. 🔴 düşmez: unutulmuş bir karar görünür kalmalı.
# ⚪/⏸️ zaten uyuyan katmandadır, onlara dokunulmaz.
SOGUK = "soguk"
SOGUK_DOSYA = "INDEKS-soguk.md"
SOGUYAN_RENK = ("🟡", "🟢")


def soguma_gunu():
    try:
        return int(os.environ.get("BEYIN_EMEKLILIK_GUN", "30"))
    except ValueError:
        return 30


def son_dokunus(dosya: Path, fm):
    """max(dosyanın mtime'ı, frontmatter `modified`) — hangisi tazeyse o."""
    t = datetime.fromtimestamp(dosya.stat().st_mtime).date()
    m = re.match(r"(\d{4}-\d{2}-\d{2})", fm.get("modified", ""))
    if m:
        try:
            t = max(t, date.fromisoformat(m.group(1)))
        except ValueError:
            pass
    return t


def soguk_mu(renk, dokunus, bugun=None):
    bugun = bugun or date.today()
    return renk in SOGUYAN_RENK and (bugun - dokunus).days >= soguma_gunu()


# Katmanlama her klasöre uygulanmaz: yalnızca yükleyicinin tavanına giren ve
# kayıtları "durum" taşıyan klasörlerde anlamlı. son-oturum gibi hepsi ⚪ olan bir
# arşivde bölmek üst dosyayı boşaltırdı. --katmanli ile elle de açılır.
KATMANLI_KLASOR = {"kalan-isler"}


def katmanli_mi(klasor, bayrak):
    return bayrak or klasor.name in KATMANLI_KLASOR


def katman(renk, kelime):
    if renk in ("🔴", "🟡"):
        return ON
    if renk == "🟢":
        return ORTA
    return ALT


def frontmatter(metin):
    m = re.match(r"^---\n(.*?)\n---\n", metin, re.S)
    if not m:
        return {}
    alan = {}
    for satir in m.group(1).splitlines():
        if ":" in satir:
            k, v = satir.split(":", 1)
            alan[k.strip()] = v.strip().strip('"')
    return alan


def durum_satiri(metin):
    m = re.search(r"^\*\*Status:\*\*\s*(.+)$", metin, re.M)
    return m.group(1).strip() if m else ""


def kisalt(s, n=78):
    s = re.sub(r"^[🟢🟡🔴⚪✅⏸️]\s*", "", s)
    s = re.sub(r":\s*20\d\d-\d\d-\d\d.*$", "", s).strip().rstrip(".")
    return s[: n - 1].rsplit(" ", 1)[0] + "…" if len(s) > n else s


def bol(baslik):
    """Başlığı (ad, konu) olarak ayır. İki ayraç desteklenir:
    '2026-09-09 — Konu'  ve  'Session: 2026-09-09 (üçüncü): Konu'."""
    if "—" in baslik:
        a, k = baslik.split("—", 1)
        return a.strip(), k.strip()
    m = re.match(r"^Session:\s*(.+?):\s*(.+)$", baslik)
    if m:
        return m.group(1).strip(), m.group(2).strip()
    return baslik.strip(), ""


def kisa_ad(baslik):
    return bol(baslik)[0]


def konu(baslik, metin):
    """Başlıkta konu yoksa gövdenin ilk anlamlı cümlesine düş.
    Çıplak bağlantı yasak olduğu için indeks satırı boş bırakılamaz."""
    k = bol(baslik)[1]
    if k:
        return k
    govde = re.sub(r"^---\n.*?\n---\n", "", metin, flags=re.S)
    govde = re.sub(r"^#.*$", "", govde, flags=re.M)
    for satir in govde.splitlines():
        t = re.sub(r"[*_`\[\]]", "", satir).strip()
        if t.startswith("Status:"):
            continue
        if len(t) > 25:
            return t.split(". ")[0]
    return ""


OTOMATIK = "❔"   # elle açıklama yok; Status yedeği kaldırıldı (test günü C)
GOZDEN = "↻"      # açıklama korunurken renk değişti; elle bakılınca silinir


def mevcut_aciklamalar(klasor: Path):
    """Elle yazılmış 'ne zaman aç' sütununu koru — üç katmanın hepsinden.
    Bir kayıt katman değiştirdiğinde açıklaması onunla birlikte taşınır.
    Döner: {stem: (renk, açıklama)}. Aynı kayıt iki dosyada varsa (açılış
    dosyasının kısaltılmış satırı ve ayrıntı tablosu) uzun olan korunur."""
    tut = {}
    for ad in list(KATMAN_DOSYA.values()) + [SOGUK_DOSYA]:
        indeks = klasor / ad
        if not indeks.exists():
            continue
        for satir in indeks.read_text(encoding="utf-8").splitlines():
            m = re.match(r"^\|\s*\[\[([^\\\]|]+)", satir)
            if not m:
                continue
            # Wikilink içindeki \| kaçışı sütun ayrımını bozar; kaçışsız | ile böl.
            sutunlar = [s.strip() for s in re.split(r"(?<!\\)\|", satir.strip())]
            sutunlar = [s for s in sutunlar if s != ""]
            # "—" bir açıklama değil, açıklamanın yokluğudur; korunmaz.
            if len(sutunlar) >= 3 and sutunlar[2] not in ("—", "-", "") \
                    and not sutunlar[2].startswith(OTOMATIK):
                eski = tut.get(m.group(1), ("", ""))[1]
                if len(sutunlar[2]) > len(eski):
                    tut[m.group(1)] = (sutunlar[1], sutunlar[2])
    return tut


def uret(klasor: Path):
    korunan = mevcut_aciklamalar(klasor)
    satirlar = []
    for f in sorted(klasor.glob("*.md")):
        if f.name.startswith("INDEKS"):
            continue
        metin = f.read_text(encoding="utf-8")
        fm = frontmatter(metin)
        # Arşiv dosyaları açık iş değildir; üst dosyalarından bağlantıyla ulaşılır.
        if fm.get("type") == "gecmis" or fm.get("durum") == "arşiv":
            continue
        baslik = fm.get("title", f.stem)
        durum = durum_satiri(metin)
        renk = next((c for c in RENKLER if c in durum), "⚪")
        # Elle yazılmış açıklama varsa korunur; rengi değiştiyse ↻ alır. Yoksa
        # konu cümlesi ❔ ile yazılır: Status ("Aktif", "Planlandı") ne zaman
        # açılacağını söylemez, denetçi ❔ satırları sayar.
        eski_renk, elle = korunan.get(f.stem, ("", ""))
        if elle:
            aciklama = elle
            if eski_renk in RENKLER and eski_renk != renk and not elle.startswith(GOZDEN):
                aciklama = f"{GOZDEN} {elle}"
        else:
            aciklama = f"{OTOMATIK} " + (kisalt(konu(baslik, metin)) or "açıklama yok")
        satirlar.append((renk, kisa_ad(baslik), f.stem, aciklama, len(metin.split()),
                         son_dokunus(f, fm)))
    if satirlar and all(re.match(r"\d{4}-\d{2}-\d{2}", s[2]) for s in satirlar):
        satirlar.sort(key=lambda s: s[2], reverse=True)   # günlük arşiv: yeni üstte
    else:
        satirlar.sort(key=lambda s: (ONCELIK.get(s[0], 9), -s[4]))
    return satirlar


def kisa_liste(satirlar):
    """Açılışın ikinci bölümü: renge göre dosya adları. Ad konuyu söyler
    (deha-arayuz, minecraft-turkce-yama-wiki); açıklama ayrıntı tablosunda."""
    g = []
    for renk in RENKLER:
        adlar = [s[2] for s in satirlar if s[0] == renk]
        if adlar:
            g.append(f"- {renk} " + " · ".join(f"`{a}`" for a in adlar))
    return g


def tablo(satirlar, soguk=False):
    if soguk:
        # Elle yazılan açıklama 3. sütunda korunur; iz ayrı sütundadır, geri dönüşte
        # açıklama iz metniyle ezilmesin diye.
        g = ["| Konu | Durum | Ne zaman aç | İz |", "| --- | --- | --- | --- |"]
        for renk, ad, stem, aciklama, kelime, dokunus in satirlar:
            g.append(f"| [[{stem}\\|{ad}]] | {renk} | {aciklama} | "
                     f"❄️ soğudu, son dokunuş {dokunus.isoformat()}, gerekirse aç |")
        return g
    g = ["| Konu | Durum | Ne zaman aç |", "| --- | --- | --- |"]
    for renk, ad, stem, aciklama, kelime, _ in satirlar:
        isaret = " ⚠️" if kelime > 500 else ""
        g.append(f"| [[{stem}\\|{ad}]]{isaret} | {renk} | {aciklama} |")
    if any(s[4] > 500 for s in satirlar):
        g += ["", "⚠️ = 500 kelimeyi aşıyor; bölme sinyali verdi."]
    return g


def yaz(klasor: Path, ad, baslik, giris, satirlar, soguk=False):
    g = ["---", f"title: {baslik}", "type: indeks", "---", "", f"# {baslik}", ""]
    g += giris + [""] + tablo(satirlar, soguk) + [""]
    (klasor / ad).write_text("\n".join(g), encoding="utf-8")


def giris_metni(bolum, sayi, toplam, soguk_var=False):
    if bolum == ON:
        soguk_satir = (f"Soğuyanlar (30+ gün dokunulmamış) [[{SOGUK_DOSYA[:-3]}|ayrı dosyada]]; konusu açılırsa aç."
                       if soguk_var else "Soğuyan kayıt henüz yok (ilk soğuma ekimde).")
        return [
            f"{toplam} açık konu; hepsi aşağıda. Yalnız **bu dosya** bağlama girer, içerikler girmez.",
            "Önce karar bekleyenler (🔴 🟡) tabloda, sonra diğerleri adıyla. Satır ilgini çekerse dosyayı aç.",
            f"{OTOMATIK} = elle \"ne zaman aç\" yazılmamış, konu cümlesi duruyor · {GOZDEN} = renk değişti, açıklamaya bak.",
            soguk_satir,
        ]
    if bolum == ORTA:
        return [
            f"{sayi} kayıt (toplam {toplam}). **Orta bellek:** yürüyen ama karar beklemeyen işler.",
            "Bu dosya bağlama otomatik **girmez**. Bir konuşmada bu konulardan biri adıyla",
            f"geçerse açılır; açık kayıtlar için [[{KATMAN_DOSYA[ON][:-3]}|ön bellek indeksi]]",
            "zaten yüklüdür.",
        ]
    return [
        f"{sayi} kayıt (toplam {toplam}). **Alt bellek:** uyuyan (⚪) ve ertelenmiş (⏸️) işler.",
        "Hiçbiri bağlama girmez ve kendiliğinden taranmaz. Bir iş burada duruyorsa dış bir",
        "şart bekliyordur; yalnızca kullanıcı o konuyu kendisi açarsa bu dosya açılır.",
        f"Açık kayıtlar için [[{KATMAN_DOSYA[ON][:-3]}|ön bellek indeksi]] zaten yüklüdür.",
    ]


def main():
    if len(sys.argv) < 2:
        print(__doc__)
        return 1
    klasor = Path(sys.argv[1])
    dene = "--dene" in sys.argv
    if not klasor.is_dir():
        print(f"klasör yok: {klasor}")
        return 1

    eski = set(mevcut_aciklamalar(klasor))
    satirlar = uret(klasor)
    yeni = {s[2] for s in satirlar}

    eklenen, cikan = yeni - eski, eski - yeni
    for s in sorted(eklenen):
        print(f"  + {s}")
    for s in sorted(cikan):
        print(f"  - {s}")
    if not eklenen and not cikan:
        print("  (satır listesi değişmedi, durumlar tazelenecek)")

    if dene:
        print("kuru çalıştırma — yazılmadı")
        return 0

    if not katmanli_mi(klasor, "--katmanli" in sys.argv):
        yaz(klasor, KATMAN_DOSYA[ON], f"{klasor.name} — indeks",
            [f"{len(satirlar)} kayıt. Bu dosya kayıtların **içeriğini yüklemez**.",
             "Bir satır ilgini çekerse dosyayı aç. Tasarrufu yapan şey bölme değil,",
             "**açmama kararıdır**.",
             "",
             "Taslağı `.claude/scripts/indeks-uret.py` yazar; \"ne zaman aç\" sütununa elle yazılan",
             "açıklamalar korunur. Yargı insanda, yazım script'te."],
            satirlar)
        print(f"yazıldı: {klasor}/{KATMAN_DOSYA[ON]} ({len(satirlar)} satır)")
        return 0

    baslik_ek = {ON: "indeks", ORTA: "indeks (aktif)", ALT: "indeks (uyuyan)"}
    soguk = [s for s in satirlar if soguk_mu(s[0], s[5])]
    sicak = [s for s in satirlar if not soguk_mu(s[0], s[5])]
    soguk_var = bool(soguk) or (klasor / SOGUK_DOSYA).exists()
    for bolum in (ON, ORTA, ALT):
        kume = [s for s in sicak if katman(s[0], s[4]) == bolum]
        if bolum == ON:
            diger = [s for s in sicak if katman(s[0], s[4]) != ON]
            g = ["---", f"title: {klasor.name} — {baslik_ek[ON]}", "type: indeks", "---", "",
                 f"# {klasor.name} — {baslik_ek[ON]}", ""]
            g += giris_metni(ON, len(kume), len(sicak), soguk_var) + [""] + tablo(kume)
            g += ["", "## Diğer açık konular", "",
                  "Yürüyen 🟢 ve uyuyan ⚪ ⏸️; dosya adı konuyu söyler. Konu adıyla geçince",
                  "`kalan-isler/<ad>.md` aç. \"Ne zaman aç\" [[INDEKS-aktif|aktif]] ve",
                  "[[INDEKS-uyuyan|uyuyan]] tablolarında; açıklamayı orada düzelt.", ""]
            g += kisa_liste(diger) + [""]
            (klasor / KATMAN_DOSYA[ON]).write_text("\n".join(g), encoding="utf-8")
        else:
            yaz(klasor, KATMAN_DOSYA[bolum], f"{klasor.name} — {baslik_ek[bolum]}",
                giris_metni(bolum, len(kume), len(satirlar)), kume)
        print(f"yazıldı: {klasor}/{KATMAN_DOSYA[bolum]} ({len(kume)} satır)")
    if soguk or (klasor / SOGUK_DOSYA).exists():
        yaz(klasor, SOGUK_DOSYA, f"{klasor.name} — indeks (soğuyanlar)",
            [f"{len(soguk)} kayıt (toplam {len(satirlar)}). **Emeklilik:** {soguma_gunu()} gündür dokunulmamış",
             "🟡/🟢 işler. Bağlama girmez. Dosyalar silinmedi; birine dokunulunca (ya da",
             "`emeklilik.py --geri <ad>`) bir sonraki üretimde kendi katmanına döner."],
            soguk, soguk=True)
        print(f"yazıldı: {klasor}/{SOGUK_DOSYA} ({len(soguk)} satır)")
    return 0


if __name__ == "__main__":
    sys.exit(main())
