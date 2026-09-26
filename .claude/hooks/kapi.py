#!/usr/bin/env python3
"""Kapı (Organ 5): ana oturumun kendi kapısı. Tehlikeli komut durur, kasa dışarı
çıkmaz, dış etki makbuz bırakır. Şeritlerin kapısı ayrıdır (ajans/kapi0.py).

  kapi.py denetle   PreToolUse JSON'u stdin'den: 0 geçer, 2 durur (sebep stderr'de)
  kapi.py makbuz    PostToolUse JSON'u stdin'den: dış etki ise deftere makbuz, hep 0

Şartname: ~/ofis/ajans/seritler/2026-09-24-kapi/emir.md. Düşman testleri: testler-kapi.sh.

İlke: yanlış blok ana oturumu kilitler. Bu yüzden yalnız sözdiziminden kesin
çıkarılabilen durdurulur; çözülemeyen değişken, bozuk girdi, beklenmeyen hata → geçir.
Kapı model değildir: karar koddadır, deterministiktir (SOZLESME, değişmezler).
"""
import hashlib
import json
import os
import re
import shlex
import sys
from pathlib import Path

sys.dont_write_bytecode = True
KOK = Path(__file__).resolve().parent.parent.parent
KASA = "🔐"  # yalnız kasa klasörünün adında geçer
AYRAC = re.compile(r"&&|\|\||[;|&\n]")
ONEK = {"sudo", "command", "exec", "nohup", "time", "env", "doas"}
AG = {"curl", "wget", "nc", "ncat", "netcat", "socat", "telnet", "scp", "sftp", "ftp",
      "rsync", "ssh", "mail", "mailx", "sendmail", "msmtp", "rclone", "aws", "gsutil",
      "gh", "codex", "gemini", "agy"}
YAZAN_HTTP = re.compile(r"(?:^|\s)(?:-X\s*(?:POST|PUT|PATCH|DELETE)|--request\s+(?:POST|PUT|PATCH|DELETE)"
                        r"|-d\b|--data\S*|-F\b|--form\b|-T\b|--upload-file|--post-(?:data|file))")


NOKTALAMA = "();<>|&\n"
KABUK = {"bash", "sh", "zsh", "dash", "ksh", "fish"}
SSH_ARGLI = set("bcDEeFIiJLlmOopQRSWw")  # ssh'ta değer alan tek harfli seçenekler
DERINLIK = 4


def _onek_at(s):
    while s and (s[0] in ONEK or re.fullmatch(r"[A-Za-z_]\w*=.*", s[0])):
        s = s[1:]
    return s


def _parcalar(komut):
    """Komutu tırnağa duyarlı sözcüklere ayır, ; && || | ( ) ile böl, önekleri at.

    Ayraç yalnız tırnak dışındaysa ayraçtır: tırnaklı verinin içindeki "; rm -rf ~"
    komut değildir (24 Eylül yanlış alarmı). Bozuk tırnakta eski kaba bölmeye düşer.
    """
    try:
        lx = shlex.shlex(komut, posix=True, punctuation_chars=NOKTALAMA)
        lx.whitespace_split = True
        lx.whitespace = " \t\r"
        sozcukler = list(lx)
    except ValueError:
        for ham in AYRAC.split(komut):
            s = _onek_at(ham.split())
            if s:
                yield s, ham
        return
    parca = []
    for t in sozcukler + [";"]:
        if t and all(c in NOKTALAMA for c in t):
            s = _onek_at(parca)
            if s:
                yield s, " ".join(s)
            parca = []
        else:
            parca.append(t)


def _ic_komutlar(s):
    """Sözcüklerin içinde çalışacak komut metinleri: kabuk -c, eval, ssh uzak komutu.
    ($(…) ve `…` ham metinden, tırnak durumu bilinerek _alt_komutlar'da çıkarılır.)"""
    ad = os.path.basename(s[0])
    if ad in KABUK:
        for i, t in enumerate(s[1:-1], 1):
            if re.fullmatch(r"-[A-Za-z]*c[A-Za-z]*", t):
                yield s[i + 1]
                break
    elif ad == "eval" and len(s) > 1:
        yield " ".join(s[1:])
    elif ad == "ssh":
        # Uzaktaki ~ uzağın evidir, ama şüphede durdur: yerel kök gibi denetlenir.
        i = 1
        while i < len(s) and s[i].startswith("-"):
            i += 2 if s[i][-1] in SSH_ARGLI and len(s[i]) == 2 else 1
        if i + 1 < len(s):
            yield " ".join(s[i + 1:])


def _alt_komutlar(komut):
    """Ham metindeki $(…) ve `…` içleri; tek tırnak içindekiler atlanır (düz metindir).

    shlex tırnakları siler, hangisinin tek tırnak olduğu kaybolur; bu yüzden ham metin
    taranır. Çift tırnak içindeki $(…) çalışır, denetlenir. İç içe parantez sayılır.
    """
    i, n, tirnak = 0, len(komut), None
    while i < n:
        c = komut[i]
        if tirnak == "'":
            if c == "'":
                tirnak = None
        elif c == "\\":
            i += 1
        elif c == "'" and tirnak is None:
            tirnak = "'"
        elif c == '"':
            tirnak = None if tirnak == '"' else '"'
        elif c == "`":
            son = komut.find("`", i + 1)
            son = n if son == -1 else son
            yield komut[i + 1:son]
            i = son
        elif komut.startswith("$(", i):
            derin, j = 1, i + 2
            while j < n and derin:
                derin += {"(": 1, ")": -1}.get(komut[j], 0)
                j += 1
            yield komut[i + 2:j - 1 if derin == 0 else n]
            i = j - 1
        i += 1


def _korunan():
    ev = Path(os.environ.get("HOME", str(Path.home())))
    ofis = Path(os.environ.get("BEYIN_OFIS_DIR", ev / "ofis"))
    # Kasanın gerçek yeri (kapi0.py ile aynı varsayılan): kopyadan çalışırken de korunur.
    # Tek yol ayarı ~/.config/beyin/vault (taşımada yalnız o değişir); yoksa kapının kendi vault'u.
    ayar = ev / ".config/beyin/vault"
    vault = Path(os.environ.get("BEYIN_VAULT", ayar.resolve() if ayar.exists() else KOK))
    return [Path("/"), ev, ofis, KOK, vault]


def _coz(hedef, cwd):
    """~ ve $HOME açılır; başka değişken çözülemez → None (şüphede geçir)."""
    ev = os.environ.get("HOME", str(Path.home()))
    hedef = re.sub(r"^(~|\$HOME|\$\{HOME\})(?=/|$)", ev, hedef)
    if "$" in hedef or "`" in hedef:
        return None
    hedef = re.sub(r"(/\*|\*)$", "", hedef) or "."
    return Path(os.path.normpath(os.path.join(cwd, hedef)))


def _ata_mi(yol, korunan):
    """yol, korunan köklerden birinin kendisi ya da atası mı? (rm onu da götürür)"""
    for k in korunan:
        k = Path(os.path.normpath(k))
        if yol == k or yol in k.parents:
            return True
    return False


def _git_silici(s):
    """Kaydedilmemiş işi geri dönüşsüz silen git alt komutu (kullanıcı, 24 Eylül: bütün şeyler gitmesin)."""
    i = 1
    while i < len(s) and s[i].startswith("-"):
        i += 2 if s[i] in ("-C", "-c", "--git-dir", "--work-tree") else 1
    if i >= len(s):
        return None
    alt, arg = s[i], s[i + 1:]
    kisa = "".join(t[1:] for t in arg if t.startswith("-") and not t.startswith("--"))
    if alt == "reset" and "--hard" in arg:
        return "kaydedilmemiş iş silinir: git reset --hard"
    if alt == "clean" and ("f" in kisa or "--force" in arg) and "n" not in kisa and "--dry-run" not in arg:
        return "izlenmeyen dosyalar silinir: git clean -f (önce git clean -n ile bak)"
    if alt == "checkout" and ("-f" in arg or "--force" in arg or arg[-2:] == ["--", "."] or arg == ["."]):
        return "kaydedilmemiş değişiklikler silinir: git checkout -f / -- ."
    if alt == "restore" and "." in arg and "--staged" not in arg and "-S" not in arg:
        return "kaydedilmemiş değişiklikler silinir: git restore ."
    if alt == "stash" and arg[:1] == ["clear"]:
        return "bütün stash'ler silinir: git stash clear"
    if alt == "branch" and ("-D" in arg or ("--delete" in arg and "--force" in arg)):
        return "birleşmemiş dal silinir: git branch -D (birleşmişse -d yeter)"
    return None


def sebep(komut, cwd, derinlik=0):
    """Durdurma sebebi ya da None."""
    parcalar = list(_parcalar(komut))
    kasa = KASA in komut
    if derinlik < DERINLIK:
        for ic in _alt_komutlar(komut):
            neden = sebep(ic, cwd, derinlik + 1)
            if neden:
                return neden
    for s, ham in parcalar:
        if derinlik < DERINLIK:
            for ic in _ic_komutlar(s):
                neden = sebep(ic, cwd, derinlik + 1)
                if neden:
                    return neden
        ad = os.path.basename(s[0])
        if ad == "rm":
            bayrak = "".join(t[1:] for t in s[1:] if t.startswith("-") and not t.startswith("--"))
            uzun = [t for t in s[1:] if t.startswith("--")]
            if "r" in bayrak.lower() or "--recursive" in uzun:
                for t in s[1:]:
                    if t.startswith("-"):
                        continue
                    if KASA in t:
                        return f"kasa silinemez: rm {t}"
                    yol = _coz(t, cwd)
                    if yol is not None and _ata_mi(yol, _korunan()):
                        return f"korunan kök siliniyor: rm -r {t} → {yol}"
        elif ad.startswith("mkfs"):
            return f"dosya sistemi biçimlendirme: {ad}"
        elif ad == "dd" and any(re.match(r"of=/dev/(sd|nvme|hd|vd|mmcblk|disk)", t) for t in s):
            return "disk aygıtına ham yazma: dd of=/dev/…"
        elif ad == "git" and (neden := _git_silici(s)):
            return neden
        elif ad == "git" and "push" in s:
            sonra = s[s.index("push") + 1:]
            if any(t in ("--force", "-f") or re.fullmatch(r"-[a-z]*f[a-z]*", t) for t in sonra):
                return "zorla push: git push --force (gerekirse --force-with-lease, kullanıcının onayıyla)"
            if any(t.startswith("+") for t in sonra):
                return "zorla push: +refspec"
        if kasa and ad in AG:
            return f"kasa dışarı çıkamaz: '{ad}' komutu kasa yoluyla aynı satırda"
        if kasa and ad == "git" and "add" in s and any(KASA in t for t in s):
            return "kasa depoya eklenemez: git add 🔐 kasa (yedek uzağa gönderir)"
        if kasa and ad.startswith("python") and "http.server" in ham:
            return "kasa dışarı çıkamaz: http.server"
    return None


def dis_etki(komut):
    """(etki, hedef) ya da None. Dışarıda iz bırakan, geri alınamaz işler."""
    for s, ham in _parcalar(komut):
        ad = os.path.basename(s[0])
        if ad == "git" and "push" in s:
            sonra = [t for t in s[s.index("push") + 1:] if not t.startswith("-")]
            return "git-push", " ".join(sonra[:2]) or "varsayılan"
        if ad == "gh" and len(s) > 2:
            if s[1] == "api":
                if re.search(r"(?:-X|--method)\s*(?:POST|PUT|PATCH|DELETE)|\s-[fF]\s|--field|--raw-field", ham):
                    return "gh-api", s[2]
                continue
            if s[2] in ("create", "merge", "close", "comment", "edit", "delete", "upload",
                        "review", "reopen", "ready", "fork", "sync") or s[1] == "release":
                return f"gh-{s[1]}-{s[2]}", s[1]
        if ad in ("curl", "wget") and YAZAN_HTTP.search(ham):
            url = next((t for t in s if re.match(r"https?://", t)), "")
            return "http-yazma", re.sub(r"^(https?://[^/?#]+).*", r"\1", url)
        if ad in ("scp", "rsync") and any(re.match(r"[^/\s]+:", t) for t in s[1:]):
            return f"{ad}-uzak", next(t for t in s[1:] if re.match(r"[^/\s]+:", t)).split(":")[0]
        if ad in ("mail", "mailx", "sendmail", "msmtp"):
            return "e-posta", ""
        if (ad in ("npm", "pnpm", "yarn") and "publish" in s) or (ad == "twine" and "upload" in s) \
                or (ad in ("docker", "podman") and "push" in s) or (ad == "cargo" and "publish" in s):
            return "paket-yayini", ad
    return None


def _girdi():
    try:
        d = json.load(sys.stdin)
    except Exception:
        return None
    if not isinstance(d, dict) or d.get("tool_name") != "Bash":
        return None
    komut = (d.get("tool_input") or {}).get("command") or ""
    return (d, komut) if isinstance(komut, str) and komut else None


def denetle():
    g = _girdi()
    if not g:
        return 0
    d, komut = g
    cwd = d.get("cwd") or os.getcwd()
    neden = sebep(komut, cwd)
    if not neden:
        return 0
    print(f"[Kapı] Durduruldu: {neden}\n"
          "Kapı yalnız kesin tehlikeyi durdurur. Gerçekten gerekiyorsa kullanıcıya sebebini "
          "söyle; komutu kullanıcı kendisi çalıştırır (`! <komut>`).", file=sys.stderr)
    return 2


def makbuz():
    g = _girdi()
    if not g or os.environ.get("BEYIN_INVOKED_BY"):
        return 0
    d, komut = g
    etki = dis_etki(komut)
    if not etki:
        return 0
    oturum = str(d.get("session_id") or "")
    anahtar = f"{oturum}\0{d.get('tool_use_id') or ''}\0{komut}"
    kimlik = "makbuz:dis-etki:" + hashlib.sha256(anahtar.encode()).hexdigest()[:16]
    ozet = komut.replace(KASA, "[kasa]")
    ozet = re.sub(r"(?i)(token|key|password|secret|authorization)[=: ]\S+", r"\1=[gizli]", ozet)[:160]
    veri = {"etki": etki[0], "hedef": etki[1], "ozet": ozet, "oturum": oturum,
            "cwd": str(d.get("cwd") or "")[:200]}
    sys.path.insert(0, str(KOK / ".claude" / "scripts"))
    try:
        import olaylar
        olaylar.yaz(KOK, "makbuz", kimlik, veri, kaynak="kapi.py")
    except Exception as h:  # makbuz yazılamazsa iş durmaz ama susmaz
        print(f"[Kapı] makbuz yazılamadı: {h}", file=sys.stderr)
    return 0


if __name__ == "__main__":
    try:
        islem = sys.argv[1] if len(sys.argv) > 1 else ""
        sys.exit({"denetle": denetle, "makbuz": makbuz}.get(islem, lambda: 0)())
    except SystemExit:
        raise
    except Exception:
        sys.exit(0)  # kapının kendi hatası oturumu kilitlemez
