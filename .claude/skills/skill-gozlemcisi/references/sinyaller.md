# Sinyaller — neye bakılacağının tam listesi

Ana skill kısa tetikleyici listesini taşır. Bu dosya örnekli tam katalogdur. Bir şeyin
kaydedilmeye değer olup olmadığından emin olmadığında, bir oturumdan çok sayıda aday
çıkıp sıralaman gerektiğinde, ve toplu incelemede bir skill'in neyi **kaybetmesi**
gerektiğine karar verirken yükle.

Kaynak: `one-skill-to-rule-them-all/references/signals.md` (CC BY 4.0, Eoghan Henn),
NemesesOS'a uyarlanmış hâli.

## Yeni skill sinyalleri

Tekrar eden çok adımlı bir iş akışı; <KULLANICI>'nın anlattığı ve hiçbir skill'in karşılamadığı
bir yöntem; benzer yapıda tekrarlayan bir görev tipi; girdisi, aşamaları ve çıktısı belli
bir süreç; <KULLANICI>'nın "ben bunu hep şöyle yaparım" demesi; iş sırasında kendiliğinden ortaya
çıkan yapılandırılmış bir yaklaşım.

## Mevcut skill'i iyileştirme sinyalleri

- Skill'de yazılı bir kurala uyulmadı — **kural yetersiz değil, zorlayıcılığı yetersizdir**;
  daha yüksek sesle yazmak çözmez, yapısal bir adıma çevirmek çözer.
- <KULLANICI>'nın bir düzeltmesi eksik bir kuralı veya sınır durumu açığa çıkardı.
- Skill'in önerdiğinden daha iyi bir yol ortaya çıktı.
- Tesadüfen kullanılan bir teknik, önerilen hâle getirilecek kadar iyi çalıştı.
- Belgelenmemiş bir kullanım durumu.
- Genelleşen bir geri bildirim; yanlış çıkan bir varsayım.
- Yeni bir araç bir adımı gereksiz kıldı.
- Düzeltmeler bir örüntü oluşturuyor.
- Başka skill'lere de uyan bir ilke.
- Adlandırma, çerçeveleme veya yapı önerisi — sohbet sırasında geçmiş olsa bile.

## Sadeleştirme sinyalleri

Bu bölüm en kolay atlanan bölümdür. **"Ne ekleyelim" sorusu kadar kasıtlı biçimde
"ne çıkaralım" da sorulmalıdır.**

Uzun süredir hiçbir oturumda işe yaramayan bir bölüm; tek ve doğrulanmamış bir gözlemden
doğmuş bir kural; kullanıcının sürekli kestirmeden geçtiği akışlar; yüklenen ama hiç
uygulanmayan bölümler; birbiriyle çelişen kurallar; "olur da lazım olur" diye eklenip hiç
tetiklenmemiş karmaşıklık; ve modelin sürekli uymadığı bir kural — bu sonuncusu ya yapısal
zorlayıcılığa çevrilir (kontrol listesi, doğrulama adımı, atlanamaz bir çağrı) ya da
kaldırılır.

## Genelleştirilebilirlik testi

Bir aday gözlemi kaydetmeden önce dört soru:

1. Bu düzeltme **başka bir projede** de anlamlı olur muydu?
2. Aynı skill'i kullanan **başka bir görevde** de geçerli olur muydu?
3. Eksik bir kuralı, akış adımını veya ilkeyi mi işaret ediyor — yoksa yalnızca bu görevi mi
   düzeltiyor?
4. Sorunun **tekrarlayacağına** dair bir belirti var mı?

Cevapların çoğu hayırsa bu bir gözlem değil, göreve özgü bağlamdır. Tek bir depoya özgü bir
geçici çözüm, tek bir duruma özgü bir tercih, geçici bir kısıttan doğan bir karar — iş
sürerken skill iyileştirmesi gibi görünürler, değildirler.

Kaydedecekse **soyutlama düzeyini yükselt**: "<KULLANICI> modülleri tek depoda tutmayı tercih etti"
değil, "skill, ortak modüllerin ne zaman merkezileştirileceğine dair yönlendirme içermiyor".

**Ne zaman öğrenmemek gerektiğini bilmek, sinyali fark etmek kadar önemlidir.** Tek tük
örnekten fazla ders çıkarmak, bir skill'in aşırı özelleşmiş karmaşıklığa sürüklenme yoludur.

## Kaydedilmeyecekler

Genelleşmeyen tek seferlik düzeltmeler; bir skill'de zaten yazılı olan tercihler; yöntemle
ilgisi olmayan araç hataları; ve <KULLANICI>'nın anlık tercihleri — bunlar kalıcı hafızaya gider,
gözlem defterine değil.

## Gözlem kipi ne zaman açık

Bütün çalışma oturumu boyunca: işin yapılması, iş sonrası geri bildirim, inceleme tartışması,
skill ve yöntem üzerine meta-konuşmalar, ve işin nasıl yapılması gerektiğine dair düşünsel
sohbetler.

**Konu işi yapmaktan işi konuşmaya kaydığında gözlem kipi kapanmaz** — inceleme
aşamalarındaki geri bildirim çoğu zaman en yüksek sinyalli girdidir.

Yalnızca araç kullanımı ve çıktısı olmayan gündelik sohbetlerde ve hızlı olgu sorularında
kapalıdır.
