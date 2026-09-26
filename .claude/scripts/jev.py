#!/usr/bin/env python3
"""Jev gölgesi (PLAN adım 10): yerel sonuç teslim edilir, Jev yalnız gözlenir.

Modlar: off (varsayılan) ve shadow. `on` bu adımda yoktur: fayda kapısından (SOZLESME
Karar 7) geçmeden açılmaz; istenirse off gibi davranır. Jev düşerse davranış değişmez
(Karar 1, Jev'siz taban) — shadow'un ürettiği tek şey gözlem satırıdır.

  jev.py golge --amac <ad> --yerel <json> --sorular <json> [--state-dosya <yol>]
      stdout'a yalnız yerel sonucu (kanonik JSON) basar; shadow'da Jev'e sorar ve
      önerisini olay defterine (jev tipi; yazılamazsa .state/jev-gozlem.jsonl) yazar. Hep 0 ile çıkar.
  jev.py durum      etkin modu ve nedenini söyler

Mod: BEYIN_JEV_MODE > .claude/jev.json {"mod": ...} > off. Kill switch: BEYIN_JEV_DISABLE=1.
Anahtar TYPESAFE_API_KEY, yoksa ~/.config/jev/key (izni 600 değilse reddedilir ve
gözleme degraded "anahtar-izin" düşer); ikisi de yoksa shadow sessizce off'a iner. Uç nokta BEYIN_JEV_URL,
süre BEYIN_JEV_TIMEOUT (sn, varsayılan 2): çağrının TOPLAM duvar saati, soket başına değil (J1).
Aynı anda tek çağrı; kilit tutuluyorsa istek atılmaz, yeniden deneme yok (J2). Karakter tavanı yok
(J4 kaldırıldı, kullanıcı 26 Eylül). Düşman testleri: testler-jev.sh.
İş (İyileştirme 5, 26 Eylül): flush-deger kapandı; Jev bağlam bulucuda yeniden sıralayıcı adayıdır.

Gözleme state/soru METNİ, yanıtın ham hali ve anahtar yazılmaz; yalnız amaç, mod,
degraded ve nedeni, gecikme, yerel sonucun özeti ve Jev'in sayısal cevapları.
Kasa yolu ya da sır örüntüsü geçen bir state için, ya da kaynaklarından biri kasadaysa (--kaynak,
J3) çağrı hiç yapılmaz (kapı kodda): metindeki işaret yetmez, verinin geldiği yol da bakılır.
"""
import argparse
import hashlib
import http.client
import json
import os
import re
import sys
import threading
import time
import urllib.error
import urllib.request
from pathlib import Path

sys.dont_write_bytecode = True
KOK = Path(__file__).resolve().parent.parent.parent
URL = "https://api.typesafe.ai/v1/systemone"
MODEL = "jev-latest"
KILIT = KOK / ".claude" / "scripts" / ".state" / "jev.kilit"
SIR = re.compile(r"🔐|sk-[A-Za-z0-9_-]{16,}|(?i:api[_-]?key|secret|password|token)\s*[=:]\s*\S{8,}"
                 r"|-----BEGIN [A-Z ]*PRIVATE KEY")


def _kanonik(o):
    return json.dumps(o, ensure_ascii=False, sort_keys=True, separators=(",", ":"))


def anahtar():
    """(anahtar, neden). Ortam önce; dosya yalnız sahibine açıksa (0600/0400) okunur."""
    if os.environ.get("TYPESAFE_API_KEY"):
        return os.environ["TYPESAFE_API_KEY"], "ortam"
    yol = Path(os.environ.get("HOME", str(Path.home()))) / ".config" / "jev" / "key"
    try:
        st = yol.stat()
    except OSError:
        return None, "anahtar-yok"
    if st.st_mode & 0o077:
        return None, "anahtar-izin"
    try:
        deger = yol.read_text(encoding="utf-8").strip()
    except OSError:
        return None, "anahtar-okunamadi"
    return (deger, "dosya") if deger else (None, "anahtar-yok")


def mod():
    """(mod, neden). Yalnız 'off' ya da 'shadow' döner."""
    if os.environ.get("BEYIN_JEV_DISABLE") == "1":
        return "off", "kill-switch"
    istenen = os.environ.get("BEYIN_JEV_MODE")
    kaynak = "ortam"
    if not istenen:
        try:
            istenen = json.loads((KOK / ".claude" / "jev.json").read_text(encoding="utf-8")).get("mod")
            kaynak = "jev.json"
        except (OSError, ValueError, AttributeError):
            istenen, kaynak = "off", "varsayılan"
    if istenen != "shadow":
        return "off", f"{kaynak}:{istenen}" if istenen != "off" else kaynak
    anahtar_, neden = anahtar()
    if not anahtar_:
        return "off", neden
    return "shadow", kaynak


def _gozlem(satir):
    """Gözlem olay defterine `jev` tipiyle düşer (Karar 4 eki, 24 Eylül). Defter yazılamazsa
    (olaylar.py yok, şerit, hata) .state'e düşer: gözlem kaybolmaz, sessizce de yok olmaz."""
    try:
        sys.path.insert(0, str(Path(__file__).resolve().parent))
        import olaylar
        kimlik = "jev:" + hashlib.sha256(_kanonik(satir).encode()).hexdigest()[:16]
        olaylar.yaz(KOK, "jev", kimlik, satir, kaynak="jev.py")
        return
    except Exception:
        pass
    try:
        yol = KOK / ".claude" / "scripts" / ".state" / "jev-gozlem.jsonl"
        yol.parent.mkdir(parents=True, exist_ok=True)
        with open(yol, "a", encoding="utf-8") as f:
            f.write(_kanonik(satir) + "\n")
    except OSError:
        pass


def _sayilar(cevap):
    """Jev cevabından yalnız sayısal ve seçim alanları; metin taşınmaz."""
    out = {}
    for k, a in (cevap.get("answers") or {}).items():
        if isinstance(a, dict):
            tut = {}
            for x in ("noul", "choice", "score", "confidence", "probabilities"):
                d = a.get(x)
                if isinstance(d, (int, float, dict)) or (isinstance(d, str) and len(d) <= 40):
                    tut[x] = d
            out[str(k)[:40]] = tut
    return out


def _kasadan_mi(yol):
    return "🔐" in str(yol) or "/kasa/" in str(yol).replace("\\", "/")


def _cagir(istek, sure):
    """İsteği TOPLAM `sure` saniyede bitir (J1). Soket süresi tek başına yetmez: damla
    damla gelen yanıt her okumada saati sıfırlar. İş parçacığı daemon'dır, beklenmez."""
    sonuc = {}

    def is_():
        try:
            with urllib.request.urlopen(istek, timeout=sure) as y:
                sonuc["govde"] = y.read(1_000_000)
        except Exception as h:  # noqa: BLE001 — neden aşağıda sınıflanır
            sonuc["hata"] = h
    t = threading.Thread(target=is_, daemon=True)
    t.start()
    t.join(sure)
    if t.is_alive():
        raise TimeoutError("sure")
    if "hata" in sonuc:
        raise sonuc["hata"]
    return sonuc["govde"]


def sor(sorular, state="", kaynaklar=()):
    """Kapılardan geçen tek Jev çağrısı: (cevap ya da None, bilgi). Mod dosyasına bakmaz
    (açık çağrıdır, ör. B/C sınavı); kill switch ve anahtar yine geçerlidir. Kapılar:
    kasa/sır ve kasa kaynağı (J3), tek çağrı kilidi (J2), toplam süre (J1)."""
    bilgi = {"degraded": False}
    if os.environ.get("BEYIN_JEV_DISABLE") == "1":
        bilgi.update(degraded=True, neden="kill-switch")
        return None, bilgi
    anahtar_, neden = anahtar()
    if not anahtar_:
        bilgi.update(degraded=True, neden=neden)
        return None, bilgi
    govde = _kanonik({"model": MODEL, "state": state, "questions": sorular})
    if SIR.search(govde) or any(_kasadan_mi(k) for k in kaynaklar):
        bilgi.update(degraded=True, neden="kasa-ya-da-sir")
        return None, bilgi
    istek = urllib.request.Request(
        os.environ.get("BEYIN_JEV_URL", URL), data=govde.encode("utf-8"), method="POST",
        headers={"Authorization": f"Bearer {anahtar_}", "Content-Type": "application/json"})
    try:
        sure = float(os.environ.get("BEYIN_JEV_TIMEOUT", "2"))
    except ValueError:
        sure = 2.0
    import fcntl
    KILIT.parent.mkdir(parents=True, exist_ok=True)
    cevap = None
    with open(KILIT, "a") as kilit:
        try:
            fcntl.flock(kilit, fcntl.LOCK_EX | fcntl.LOCK_NB)
        except OSError:  # J2: başka çağrı sürüyor; bekleme ve yeniden deneme yok
            bilgi.update(degraded=True, neden="mesgul")
            return None, bilgi
        bas = time.monotonic()
        try:
            cevap = json.loads(_cagir(istek, sure).decode("utf-8"))
            bilgi["token"] = (cevap.get("usage") or {}).get("input_tokens")
        except urllib.error.HTTPError as h:
            bilgi.update(degraded=True, neden=f"http-{h.code}")
        except (TimeoutError, OSError) as h:
            neden = "sure" if str(h) == "sure" else "timeout" if "timed out" in str(h) else "ag"
            bilgi.update(degraded=True, neden=neden)
        except (ValueError, AttributeError, http.client.HTTPException):
            bilgi.update(degraded=True, neden="bozuk-yanit")  # yarım yanıt da sessiz kalmaz
            cevap = None
        bilgi["gecikme_ms"] = int((time.monotonic() - bas) * 1000)
    return (cevap if isinstance(cevap, dict) else None), bilgi


def golge(amac, yerel, sorular, state="", kaynaklar=()):
    """Yerel sonucu döndürür; shadow'da Jev'i gözler. Sonucu hiçbir koşulda değiştirmez."""
    m, neden = mod()
    if m != "shadow":
        if neden in ("anahtar-izin", "anahtar-okunamadi"):  # yanlış kurulum susmaz
            _gozlem({"zaman": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "amac": amac, "mod": "off",
                     "degraded": True, "neden": neden})
        return yerel
    satir = {"zaman": time.strftime("%Y-%m-%dT%H:%M:%S%z"), "amac": amac, "mod": m,
             "yerel": hashlib.sha256(_kanonik(yerel).encode()).hexdigest()[:12]}
    cevap, bilgi = sor(sorular, state, kaynaklar)
    satir.update(bilgi)
    if cevap is not None:
        satir["oneri"] = _sayilar(cevap)
    _gozlem(satir)
    return yerel


def main():
    p = argparse.ArgumentParser(description=__doc__.splitlines()[0])
    alt = p.add_subparsers(dest="islem", required=True)
    g = alt.add_parser("golge")
    g.add_argument("--amac", required=True)
    g.add_argument("--yerel", required=True)
    g.add_argument("--sorular", default="{}")
    g.add_argument("--state-dosya")
    g.add_argument("--kaynak", action="append", default=[], help="state'in geldiği yol (J3)")
    alt.add_parser("durum")
    a = p.parse_args()
    if a.islem == "durum":
        print("mod: %s (%s)" % mod())
        return 0
    yerel = json.loads(a.yerel)
    try:
        sorular = json.loads(a.sorular)
        state = ""
        if a.state_dosya:
            state = ("🔐 " if "🔐" in a.state_dosya else "") + \
                Path(a.state_dosya).read_text(encoding="utf-8", errors="replace")
        golge(a.amac, yerel, sorular, state, a.kaynak + ([a.state_dosya] if a.state_dosya else []))
    except Exception:
        pass  # gölge hiçbir koşulda teslimi bozamaz
    print(_kanonik(yerel))
    return 0


if __name__ == "__main__":
    sys.exit(main())
