---
name: skill-gozlemcisi
description: Çalışırken fark edilen tekrar eden örüntüleri ve sürtünme anlarını gözlem olarak kaydeder, biriken gözlemleri toplu incelemede yeni skill veya kural önerisine çevirir. "gözlemlere bak", "skill gözlemleri", "ne tekrar ediyor", "bundan skill çıkar mı", "toplu inceleme" dendiğinde kullan. Ayrıca bir oturumun sonunda o oturumdan kayda değer bir şey çıktıysa ve beş oturumdur inceleme yapılmadıysa kullan.
---

# Skill Gözlemcisi

Skill'ler masa başında "hadi bir skill yazalım" diyerek değil, **gerçek iş sırasında fark
edilen sürtünmeden** doğar. `yeni-proje` skill'i böyle çıktı: ofis dağılmaya başladı, <KULLANICI>
kuralı söyledi, kural skill'e dönüştü. Ama o sefer fark eden tesadüftü. Bu skill o farkedişi
sistemli hâle getirir.

Kaynak: [rebelytics/one-skill-to-rule-them-all](https://github.com/rebelytics/one-skill-to-rule-them-all)
(CC BY 4.0, Eoghan Henn). Bu, o meta-skill'in NemesesOS'a uyarlanmış hâlidir. Uyarlamada
Cowork'e özgü bölümler, skill aileleri ve eski sürüm göçü çıkarıldı; sürekli izleme yerine
**oturum sonu toplu değerlendirme** kondu. Sebebi maliyet: orijinal her oturumda bağlama
9.000 token yüklüyor ve modelden her turda "bu kayda değer mi" diye düşünmesini istiyor.

## Defter nerede

```
~/ofis/skill-gozlemleri/
├── gozlemler/     # açık gözlemler: NNNN-kisa-slug.md
├── arsiv/         # kapanmış olanlar
└── son-inceleme   # son toplu incelemenin tarihi ve oturum sayacı
```

**Vault'ta değil, ofiste.** Yılda birkaç yüz dosya birikir; `compile.py` insan yazımı notlar
için tasarlandığından makine üretimi gözlemler onu boğar ve `knowledge/` altını zehirler.
Ofis Obsidian'da ikinci vault olarak açık olduğu için <KULLANICI> oradan okur.

Numaralar asla tekrar kullanılmaz. Yeni numara için `gozlemler/` ve `arsiv/` birlikte taranır,
en büyük numaranın bir fazlası alınır. Dizin listesi indekstir; ayrı içindekiler tutulmaz.

## Ne kaydedilir

Üç sinyal var. Hepsinde ortak ölçüt şudur: **bir dahaki sefere işi değiştirir mi?**

**Yeni skill fırsatı.** Aynı yapıda bir iş ikinci veya üçüncü kez yapılıyorsa; <KULLANICI> bir yöntemi
tarif ediyorsa ("ben bunu hep şöyle yaparım"); girdisi, adımları ve çıktısı belli bir süreç
kendiliğinden ortaya çıkıyorsa.

**Mevcut skill'in eksiği.** Bir skill kullanıldı ama bir yeri tökezledi, bir adımı eksikti,
ya da fazlaydı. Olumlu sinyal de sayılır: bir adım özellikle işe yaradıysa o da yazılır.

**Sürtünme.** Bir şey beklenenden zor gitti. Üç kez başarısız olan bir komut, yanlış varsayımla
başlanıp geri dönülen bir yol, <KULLANICI>'nın "böyle değil" dediği bir an.

**Kaydedilmeyecekler:** tek seferlik işler, projeye özgü ayrıntılar, <KULLANICI>'nın anlık tercihleri
(onlar kalıcı hafızaya gider), ve zaten bilinen şeyin tekrarı. Şüphedeysen yazma — gürültülü
defter okunmaz.

**Genelleştirilebilirlik testi.** Kaydetmeden önce dört soru: başka projede de anlamlı olur
muydu, başka görevde de geçerli olur muydu, eksik bir kuralı mı işaret ediyor yoksa yalnızca
bu görevi mi düzeltiyor, tekrarlayacağına dair belirti var mı? Çoğu hayırsa bu gözlem değil,
göreve özgü bağlamdır. **Ne zaman öğrenmemek gerektiğini bilmek, sinyali fark etmek kadar
önemlidir.**

Tam sinyal kataloğu, sadeleştirme sinyalleri ve testin ayrıntısı için `references/sinyaller.md`
dosyasını yükle.

## Gözlem nasıl yazılır

Dosya adı `NNNN-kisa-slug.md`, içerik:

```markdown
---
id: 7
baslik: Ofis kökünde iş açılması
durum: acik            # acik | uygulandi | reddedildi | park
tur: yeni-skill        # yeni-skill | skill-eksigi | surtunme
skill: []              # ilgili mevcut skill'ler, liste
onerilen-skill: []     # aday yeni skill adları, liste
tarih: 2026-09-06
oturum-baglami: Ödev 3 repo incelemesi
cozum:                 # durum uygulandi/reddedildi olunca doldurulur
---

## Ne oldu
İki cümle: gözlemin çıktığı somut an.

## Neden kayda değer
Bir dahaki sefere neyi değiştirir.
```

Alanları uydurma. `oturum-baglami` boş bırakılmaz — altı ay sonra gözlemi okuyan kişi neyin
ortasında olduğunu bilmelidir.

## Ne zaman çalışır

**Oturum sonunda.** O oturumda kayda değer bir şey olduysa gözlem yazılır. Olmadıysa hiçbir
şey yazılmaz; boş kayıt gürültüdür.

**Toplu inceleme iki yolla tetiklenir.** <KULLANICI> "gözlemlere bak" dediğinde çalışır. Ayrıca son
incelemeden beri beş oturum geçtiyse hatırlatılır — ama **kendiliğinden inceleme yapılmaz**,
yalnızca "on iki gözlem birikti, bakalım mı?" denir. Kontrol <KULLANICI>'da kalır, unutma da
engellenir.

Sayaç `son-inceleme` dosyasında tutulur.

## Toplu inceleme

1. `gozlemler/` içindeki açık kayıtları oku.
2. **Tekrarı ara.** Bir kez olan şey olaydır, üç kez olan şey örüntüdür. Aynı kökü paylaşan
   gözlemleri grupla.
2b. **Ne çıkaralım diye de sor.** İncelemede yalnızca eklenecekler değil, çıkarılacaklar da
   aranır: hiç işe yaramayan bölümler, tek gözlemden doğmuş kurallar, sürekli uyulmayan
   kurallar (bunlar ya yapısal zorlayıcılığa çevrilir ya kaldırılır). Sinyal listesi
   `references/sinyaller.md` dosyasında.
3. Her örüntü için <KULLANICI>'ya **sor**: bu yeni bir skill mi, mevcut bir skill'in düzeltmesi mi,
   `🔮 zihin/Kurallar.md` dosyasına bir kural mı, yoksa hiçbiri mi?
4. **Otomatik yazma yok.** Ne `Kurallar.md`, ne kalıcı hafıza, ne yeni bir skill dosyası
   <KULLANICI> onaylamadan oluşturulmaz. Onun söylemediği bir şeyin kural hâline gelmesi bu sistemin
   en riskli senaryosudur.
5. Karara bağlanan gözlemin `durum` ve `cozum` alanları doldurulur, dosya `arsiv/` altına
   taşınır. Kalanlar `acik` kalır.
6. `son-inceleme` dosyasını güncelle.

## Sınırlar

- Gözlem **öneridir, karar değildir**. Uygulama her zaman <KULLANICI>'nın onayıyla olur.
- Bu skill <KULLANICI>'nın düzeltmelerini kaydetmez; onlar kalıcı hafızaya ve `Kurallar.md`'ye gider.
  Buradaki konu **neyi tekrar yaptığımız**, orada ise **<KULLANICI>'nın ne dediği**. İkisi karışırsa
  aynı bilgi iki yerde yaşar ve bir gün çelişirler.
- Gözlem dosyaları vault'a taşınmaz.
