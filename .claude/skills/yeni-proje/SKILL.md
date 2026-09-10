---
name: yeni-proje
description: Çalışma ofisinde yeni bir proje başlatır. Ofiste kendi alt klasörünü açar, git deposu kurar, vault'ta ikiz proje notunu yazar ve Threads'e kaydeder. "yeni proje", "proje başlat", "buna başlayalım", "şu projeyi açalım" dendiğinde veya ofiste daha önce var olmayan bir işe kod yazılmaya başlanacağında kullan.
---

# Yeni Proje

Bu skill ofisin dağılmasını önler. <KULLANICI>'nın kuralı: **ofiste her iş kendi alt klasöründe durur,
klasörün adı projenin ne olduğunu söyler.** Ofis kökünde başıboş dosya birikmez.

Skill sadece klasör açmaz; projenin **iki tarafını birden** kurar. Kod ofiste, projenin beyni
vault'ta. Biri nasıl çalıştığını, diğeri neden öyle yapıldığını tutar. Tek başına klasör açmak
altı ay sonra "bu kod neden böyle" sorusunu cevapsız bırakır.

## Sabit yollar

| Ne | Yol |
| --- | --- |
| Ofis (kod) | `~/ofis` → `~/Documents/Benim yapay zeka sistemim/ofis` |
| Vault (beyin) | `~/Documents/Benim yapay zeka sistemim/NemesesOS` |
| Proje notları | `🏰 İş/<slug>/` |

`~/ofis` kısayolunu kullan. Uzun yolda boşluk ve Türkçe karakter var, bazı araç zincirleri
tökezliyor. Uzun yolu yazman gerekirse tırnak içine al.

## Adımlar

### 1. Önce ara, sonra aç

Bu adımı atlama. Dağınıklığı önleyen asıl adım budur.

```bash
ls -A ~/ofis/
```

Benzer isimli veya aynı işi yapan bir klasör varsa **yeni klasör açma**. <KULLANICI>'ya sor: mevcut
projenin devamı mı, yoksa gerçekten ayrı bir iş mi? Devamıysa oraya gir, yenisini açma.

### 2. Slug belirle

Klasör adı ASCII, küçük harf, kelimeler arası tire: `nemeses-web`, `fare-scripti`,
`butce-takip`. Türkçe karakter, boşluk ve büyük harf kullanma; build araçları ve import
yolları bunlarda takılıyor. Projenin güzel Türkçe adı not dosyasının başlığında durur, klasör
adında değil.

Slug'ı projenin ne yaptığından türet, tarihten veya `proje-1` gibi sayaçtan değil. İsim altı ay
sonra klasör listesine bakınca ne olduğunu söylemeli.

### 3. Ofiste klasörü aç ve depoyu kur

```bash
mkdir -p ~/ofis/<slug>
cd ~/ofis/<slug> && git init -q && echo "git deposu kuruldu"
```

İlk günden versiyon alınır. "Sonra hallederim" denen an kayıp başlar.

### 4. Projeye kimlik köprüsü koy

Ofis ayrı bir dizin olduğu için orada çalışırken vault'un talimatları kendiliğinden yüklenmez.
Bu dosya köprüyü kurar:

```bash
cat > ~/ofis/<slug>/CLAUDE.md <<'EOF'
# <Proje Adı>

Bu proje NemesesOS'a bağlıdır. Kimlik, ton ve hafıza protokolü için
`~/Documents/Benim yapay zeka sistemim/NemesesOS/CLAUDE.md` ve `🔮 zihin/Ruh.md` dosyalarını oku.

**Bu klasör:** kaynak kod, çalışan iş.
**Projenin beyni:** `~/Documents/Benim yapay zeka sistemim/NemesesOS/🏰 İş/<slug>/`
kararlar, açık sorular ve öğrenilenler oraya yazılır, buraya değil.

## Çalışma protokolü

- **`AGENTS.md` bu dosyaya symlink'tir.** Codex ve Claude aynı kuralları okur; birini
  değiştirmek ikisini birden değiştirir. Symlink'i kopyaya çevirme.
- **Yarım kalan iş `backlog.md`'ye düşer.** Oturum işi bitiremeden kapanıyorsa nerede kaldığı
  ve sıradaki adım oraya tek satır yazılır. Biten satır silinmez, `backlog-log.md`'ye taşınır.
- **Arka plan araştırmaları `reports/` altına yazılır.** Alt ajanlara yaptırılan keşif ve
  doküman taraması oraya düşer, doğrudan koda girmez: önce okunur, sonra karar olur.
EOF
```

`<Proje Adı>` ve `<slug>` yerlerini gerçek değerlerle doldur.

### 4b. İki ajanı tek kurala bağla ve süreklilik dosyalarını kur

```bash
cd ~/ofis/<slug>
ln -sfn CLAUDE.md AGENTS.md
mkdir -p reports && touch reports/.gitkeep
cat > backlog.md <<'EOF'
# Backlog — <slug>

Yarım kalan iş buraya düşer. Her satır: **ne** yarım kaldı, **nerede** kaldı, **sıradaki
adım** ne. Biten satır silinmez, `backlog-log.md`'ye taşınır.

## Açık

_(şu an açık yarım iş yok)_
EOF
```

`AGENTS.md` **kopya değil symlink** olur. Codex `AGENTS.md`, Claude `CLAUDE.md` okur; iki
dosya tutulursa zamanla birbirinden kayar ve hangi ajanın hangi kuralı gördüğü belirsizleşir.
Symlink bu kaymayı model disiplinine değil dosya sistemine bağlar.

`reports/` boş klasör olduğu için git'te durmaz, `.gitkeep` onu tutar. Ofis Obsidian vault'unda
`AGENTS.md` ve `reports/` gizlidir (`ofis/.obsidian/app.json`), symlink kopya not olarak görünmesin diye.

### 5. Vault'ta ikiz notu yaz

```bash
mkdir -p "$HOME/Documents/Benim yapay zeka sistemim/NemesesOS/🏰 İş/<slug>"
```

Ardından `🏰 İş/<slug>/<slug>.md` dosyasını şu iskeletle oluştur (frontmatter alanları
`📋 Şablonlar/Note.md` ile uyumlu olmalı):

```markdown
---
title: <Proje Adı>
created: <YYYY-MM-DD>
modified: <YYYY-MM-DD>
type: project
status: active
tags: [proje]
---

# <Proje Adı>

**Kod:** `~/ofis/<slug>` · **Stack:** <henüz belli değil>

## Ne yapıyor, neden var
<tek paragraf: bu proje hangi problemi çözüyor>

## Mimari kararlar
<karar ve gerekçesi. boş bırakma, ilk karar bile olsa yaz>

## Açık sorular
<cevabı bilinmeyenler>

## Öğrendiklerim
<işin kendisine dair kavranan şeyler. <KULLANICI> hem projeyi bitirmek hem işi öğrenmek istiyor,
bu bölüm ikinci amacın kaydıdır>
```

Boş başlıklar bırakma; en azından "Ne yapıyor" ve ilk mimari kararı doldur.

### 6. Threads'e kaydet

`🔮 zihin/kalan-isler/<slug>.md` olarak yeni bir konu dosyası aç ve
`kalan-isler/INDEKS.md` tablosuna bir satır ekle:

```markdown
### Thread: <Proje Adı>
**Status:** 🟢 Aktif: <tarih>. Kod `~/ofis/<slug>`, notlar `🏰 İş/<slug>/`.
<tek cümle: şu an nerede duruyor, sıradaki adım ne>
```

Bu adım olmadan proje gelecek oturumda görünmez olur.

### 7. Raporla

<KULLANICI>'ya kısa bir özet ver: açılan klasör, slug, not dosyasının yolu. Sonra doğrudan işe geç,
kutlama cümlesi kurma.

## Sınırlar

- Proje **ofis dışına** kurulmaz, vault içine hiç kurulmaz.
- Var olan projeye ikinci klasör açılmaz; şüphedeysen sor.
- Stack seçimi, iskelet kodu, bağımlılık kurulumu bu skill'in işi değil. Burası projeyi
  doğurur, sonrası normal iş akışı.
