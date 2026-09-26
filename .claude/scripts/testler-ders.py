#!/usr/bin/env python3
"""Ders kapısı testi: ders-tetikleri.tsv'nin her satırı bir düşman testtir.

Kapı geçici bir vault kopyasında koşar; gerçek olay defterine ve .state'e yazmaz.
Her satır kendi "örnek" girdisiyle denenir ve beklenen karar gelmezse kırmızıdır.
Ayrıca: olumsuz örnekler susar, düzeltme deftere düşer, hook settings'e bağlıdır,
kural-mekanizma oranı eşiğin üstündedir.

Çıktı: "OK <ad>" ya da "FAIL <ad>|<beklenen>|<gelen>" satırları (testler.sh okur).
"""
import json
import re
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path

S = Path(__file__).resolve().parent
KOK = S.parent.parent
ORAN_ESIGI = 0.40


def sonuc(ad, ok, beklenen="", gelen=""):
    print(f"OK {ad}" if ok else f"FAIL {ad}|{beklenen}|{str(gelen)[:80]}")


def sahte_vault():
    v = Path(tempfile.mkdtemp())
    (v / ".claude" / "hooks").mkdir(parents=True)
    (v / ".claude" / "scripts").mkdir(parents=True)
    shutil.copy(KOK / ".claude/hooks/ders-kapisi.py", v / ".claude/hooks/")
    for f in ("ders-tetikleri.tsv", "olaylar.py", "_portalock.py"):
        shutil.copy(S / f, v / ".claude/scripts/")
    return v


def kapi(v, olay, veri):
    r = subprocess.run([sys.executable, str(v / ".claude/hooks/ders-kapisi.py"), olay],
                       input=json.dumps(veri), capture_output=True, text=True, timeout=20,
                       env={"PATH": "/usr/bin:/bin"})
    return r.stdout


def arac_adi(desen):
    return re.sub(r"[\^\$()]", "", desen).split("|")[0] if desen != "-" else "-"


def satirlar():
    for s in (S / "ders-tetikleri.tsv").read_text(encoding="utf-8").splitlines():
        if s.strip() and not s.startswith("#"):
            p = s.split("\t")
            yield dict(zip(("olay", "arac", "kalip", "karar", "kurallar", "ornek", "mesaj"), p))


def olay_verisi(r, oturum):
    ad = arac_adi(r["arac"])
    if r["olay"] == "UserPromptSubmit":
        return {"session_id": oturum, "prompt": r["ornek"]}
    girdi = {"command": r["ornek"]} if ad == "Bash" else \
        {"file_path": r["ornek"]} if ad in ("Edit", "Write") else {"prompt": r["ornek"], "query": "x"}
    return {"session_id": oturum, "tool_name": ad, "tool_input": girdi}


def main():
    v = sahte_vault()
    try:
        beklenen = {"dur": "deny", "sor": "ask", "sor-yoksa": "ask",
                    "bilgi": "additionalContext", "olay": "additionalContext"}
        for i, r in enumerate(satirlar(), 1):
            oturum = f"test-{i}"
            if r["karar"] == "sor-yoksa":   # son istem örnekse (kalıba uymuyorsa) sormalı
                kapi(v, "UserPromptSubmit", {"session_id": oturum, "prompt": r["ornek"]})
            o = kapi(v, r["olay"], olay_verisi(r, oturum))
            ad = f"ders satırı {i} ({r['kurallar']}) '{r['ornek'][:24]}' → {r['karar']}"
            try:
                cikti = json.loads(o)["hookSpecificOutput"] if o else {}
            except (ValueError, KeyError):
                cikti = {}
            gelen = cikti.get("permissionDecision") or ("additionalContext" if "additionalContext" in cikti else "")
            metin = cikti.get("permissionDecisionReason", "") + cikti.get("additionalContext", "")
            sonuc(ad, gelen == beklenen[r["karar"]] and r["mesaj"][:20] in metin, beklenen[r["karar"]], o)

        sonuc("ders kapısı sıradan istemde susuyor",
              kapi(v, "UserPromptSubmit", {"session_id": "n", "prompt": "merhaba, bugün hava güzel"}) == "",
              "boş", "çıktı var")
        o = kapi(v, "PreToolUse", {"session_id": "n", "tool_name": "Bash",
                                   "tool_input": {"command": "git commit -m x -- a.txt"}})
        sonuc("yollu commit durdurulmuyor", "deny" not in o, "deny yok", o)
        o = kapi(v, "PreToolUse", {"session_id": "n", "tool_name": "Bash",
                                   "tool_input": {"command": "git commit -m 'a\n\nb' -- x.md && git log"}})
        sonuc("çok satırlı mesajlı yollu commit durdurulmuyor", "deny" not in o, "deny yok", o)
        kapi(v, "UserPromptSubmit", {"session_id": "a", "prompt": "şunu bir araştır"})
        o = kapi(v, "PreToolUse", {"session_id": "a", "tool_name": "WebSearch", "tool_input": {"query": "x"}})
        sonuc("'araştır' denince arama sorulmuyor", o == "", "boş", o)

        defter = "".join(p.read_text() for p in (v / "daily" / "olaylar").glob("*.jsonl")) \
            if (v / "daily" / "olaylar").exists() else ""
        sonuc("düzeltme olay defterine düşüyor", '"tip":"duzeltme"' in defter, "duzeltme satırı", defter[:60])
        kapi(v, "UserPromptSubmit", {"session_id": "k", "prompt": "kasa notunu böyle yapma"})
        defter2 = "".join(p.read_text() for p in (v / "daily" / "olaylar").glob("*.jsonl"))
        sonuc("kasa geçen düzeltme deftere girmiyor", "kasa notunu" not in defter2, "yok", "var")
    finally:
        shutil.rmtree(v, ignore_errors=True)

    ayar = json.loads((KOK / ".claude/settings.json").read_text())
    for olay in ("UserPromptSubmit", "PreToolUse", "PostToolUse"):
        bagli = any("ders-kapisi.py" in h.get("command", "")
                    for grup in ayar.get("hooks", {}).get(olay, []) for h in grup.get("hooks", []))
        sonuc(f"ders kapısı {olay} olayına bağlı", bagli, "settings.json", "yok")

    toplam, korunan = kural_orani()
    sonuc(f"kural-mekanizma oranı ≥ %{int(ORAN_ESIGI*100)} ({len(korunan)}/{toplam})",
          toplam and len(korunan) / toplam >= ORAN_ESIGI, f"≥{ORAN_ESIGI}", f"{len(korunan)}/{toplam}")
    dersler = Path.home() / ".config/beyin/motor/jev-dersler.md"
    if dersler.exists():
        n = len(dersler.read_text(encoding="utf-8").splitlines())
        sonuc(f"jev-dersler.md en fazla 50 satır ({n})", n <= 50, "≤50", n)
    council = Path.home() / ".claude/skills/council/SKILL.md"
    if council.exists():
        sonuc("konsey skill'inde 1,5× koltuk yok (sinirlar:5)",
              "1.5× weight" not in council.read_text() and "which is **1.5**" not in council.read_text(),
              "1,5× yok", "var")


def kural_orani():
    """Toplam: Kurallar.md numaralı maddeler + kurallar/*.md 'kural:'/'gerçek:' satırları.
    Korunan: ders-tetikleri.tsv + kural-mekanizma.tsv'de adı geçen kimlikler."""
    zihin = KOK / "🔮 zihin"
    kimlikler = {f"Kurallar:{m}" for m in
                 re.findall(r"^(\d+)\. ", (zihin / "Kurallar.md").read_text(), re.M)}
    for f in sorted((zihin / "kurallar").glob("*.md")):
        if f.stem in ("INDEKS", "gerekceler"):
            continue
        n = len(re.findall(r"^- \*\*(kural|gerçek):\*\*", f.read_text(), re.M))
        kimlikler |= {f"{f.stem}:{i}" for i in range(1, n + 1)}
    korunan = set()
    for tablo, sutun in (("ders-tetikleri.tsv", 4), ("kural-mekanizma.tsv", 0)):
        for s in (S / tablo).read_text(encoding="utf-8").splitlines():
            if s.strip() and not s.startswith("#"):
                korunan |= set(s.split("\t")[sutun].split(","))
    return len(kimlikler), korunan & kimlikler


if __name__ == "__main__":
    if sys.argv[1:] == ["--oran"]:
        t, k = kural_orani()
        print(f"{len(k)}/{t} %{round(100*len(k)/t)}")
    else:
        main()
