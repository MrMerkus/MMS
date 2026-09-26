---
title: Paslama kuralları
created: 2026-09-17
modified: 2026-09-25
type: memory
tags: [kurallar, paslama, alt-ajan, ajans]
---

# Alt ajana iş verilirken

Bu dosya bir işi Codex'e paslamadan önce açılır. `agy` bırakıldı (Karar 8); alt ajan
`~/ofis/ajans/` şerit protokolüyle çalışır (Karar 9): emir → worktree → durum/teslim → makbuz.
Komut ayrıntısı `codex-fleet`, `gorsel-handoff` ve ajansın `CLAUDE.md`'sinde; burada yalnız
kullanıcının doğrudan koyduğu kurallar var.

- **kural:** Alt ajan yalnız Codex'tir; Claude alt ajanı (`Agent`) kapalıdır. Codex aboneliği
  yokken Codex adımlarını ana döngü yapar, bunu **söyleyerek**. kullanıcı doğrudan "Claude alt
  ajanı / Sonnet" derse yasak **o oturum boyunca** açılır ve mekanik iş ana döngüde kalmaz.
  **neden:** "alt ajan olarak antigravity ve codex alt ajanlarını kullan manasında dedim";
  izin verildikten sonra da işi kendim yapmaya devam etmiştim. Paslama aynı zamanda ölçümdür:
  *"hem kotamızdan az yer hem de sonnet performansını görürüz"*.
- **kural:** Codex işi şeritsiz açılmaz: önce `ajans/seritler/<tarih>-<ad>/emir.md` (ne, hangi
  proje, hangi worktree, kabul ölçütü, dokunabileceği yollar), `kadro/`dan bir rol, panoya
  satır. Kod yalnız projenin git worktree'sinde yazılır. **İlk gerçek şeritten önce Kapı-0
  kodda olmalı**; kadrodaki yetki yazısı kapı sayılmaz. Alt ajan beyne yazmaz; `🔐 kasa/` ve
  kişisel günlük/şifre dosyaları hiçbir emre girmez. **neden:** Karar 9 — yarım şerit asıl
  projeyi bozamaz; kapı modelin sözünde değil kodda.
- **kural:** "Bitti" makbuzdur, teslim değil. Makbuzu ana döngü kendi ölçümüyle keser
  (`kabul-kontrolu`); makbuzsuz şerit açık sayılır. **neden:** alt katmanın "bitti"si
  iddiadır; çıkış kodu 0 ile boş dönen şeritler görüldü.
- **kural:** Şerit açmak kota yer; **açmadan önce sor**: kaç şerit, ne kadar sürer, alternatifi
  ne. "Mekanik işi şeride ver" izni süresiz açık çek değildir. **neden:** "bundan sonra şerit
  çalıştırma konuşalım kotam bitiyorda" — altı şeridi sormadan açmıştım.
- **kural:** Paslamayı istenmesini bekleme. Spec'i yazılabilen çok adımlı icra şeride gider;
  ana döngüde yargı, spec, sentez, makbuz ve kullanıcıyla konuşma kalır. **neden:** "çoğu işte
  alt ajan kullanmayı unutma deha."
- **kural:** Küçük, mekanik işi paslama: depo kurmak, commit, tek dosya düzeltmek, yedek.
  **neden:** "Bunları alt ajanlara verme kendin yap" — emir yazıp beklemek yavaşlatıyor.
- **kural:** Emri yazmadan önce projenin durumunu (backlog, proje notu, kalan iş) kısa oku.
  **neden:** "4. madde doğru" — şeridin kalitesi emrin kalitesiyle sınırlı.
- **kural:** Yarım şeridi sıfırdan başlatma; `durum.md` ve logdaki somut bulgular (adresler,
  başarısız URL ve HTTP kodları, doğrulanmış sürümler, kısmi dosyalar) yeni emre devredilir.
  **neden:** "iki şeritte yarım kalırsa içindeki bilgileri bir sonraki modele ver."
- **kural:** Codex arızalanırsa (izin hatası, dolan kota) işi Claude alt ajanına çekme; dur,
  kullanıcıya durumu yaz, karar onun. İş küçükse ana döngü yapar, söyleyerek.
- **kural:** Alt ajan kullanıcının ekranında pencere açmaz; yalıtılamıyorsa kodla çalışır ya da
  önce sorulur. **neden:** "sürekli acıp acıp durdurmasan işimi" (25 Eylül, ~20 pencere).
- **kural:** Görsel işte ilk rota `gorsel-handoff` (ChatGPT web, Go aboneliği); Codex
  `gpt-image-2` yedektir. Modele prompt **İngilizce**, kullanıcıya açıklama Türkçe. **neden:**
  görsel Codex kotasını 3-5 kat hızlı yiyor; "promptu normalde İngilizce verirdin?"
- **kural:** Şeridin okuyacağı skill'i ana döngü **kendi bağlamına açmaz**; emre "şu skill'i
  aç" yazılır. **neden:** "Onu sen değil -52 söyleyecektin o açacaktı" — aynı skill iki
  bağlama girdi, biri boşa yandı. İstisna: paslama kararı için politikayı gerçekten okumak.
