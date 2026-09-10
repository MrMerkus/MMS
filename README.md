# Hafıza Sistemi

> **Köken:** Bu sistem [`avenoxai/avenoxbeyin`](https://github.com/avenoxai/avenoxbeyin)
> (sürüm 2.3.0, MIT) temel alınarak geliştirilmiş bir çataldır. Klasör iskeleti, hook
> zinciri ve derleyici oradan gelir; aşağıda anlatılan **üç yükleme kademesi**, **tavan
> ölçer**, **kapanış döngüsü**, **denetçi** ve **soru sırası** bu çatalda eklendi.

Claude Code için kalıcı hafıza ve süreklilik katmanı. Asistanın oturumlar arasında
hatırlamasını sağlar — ama asıl derdi hatırlamak değil, **hatırladığı şeyin bağlamı
şişirmesini önlemek**.

## Sorun

Kalıcı hafıza kuran herkes aynı duvara çarpar: hafıza dosyası büyür. Büyüdükçe her oturumda
daha çok bağlam yer, sonunda ya kırpılır ya da konuşmanın yerini alır. Bu sistemde bir
hafıza dosyası 82 KB'a çıktı ve içeriğinin yalnızca %2,4'ü okunuyordu. Kural yazılıydı
("500 kelimeyi geçme"), fakat **sayan bir mekanizma yoktu.**

Ders şu: yazılı kural, çalıştıran bir şeye bağlanmadığı sürece terk edilir.

## Ana fikir

**Bölme konuya göre değil, erişim derinliğine göre yapılır.** Üç yükleme kademesi vardır:

| Kademe | Nerede | Ne zaman yüklenir |
| --- | --- | --- |
| **Refleks** | `🔮 zihin/` | Her oturumda otomatik. Küçük tutulur. |
| **İndeks** | Her klasörde `INDEKS.md` | Refleksle birlikte. **İçerik taşımaz** — "ne var, ne zaman aç" der. |
| **Derin** | Geri kalan her şey | Yalnızca sorulunca. |

Tasarrufu yapan şey bölmek değil, **açmama kararıdır**. Bu yüzden çıplak bağlantı yasaktır:
her bağlantı ne olduğunu ve ne zaman açılacağını söyler, böylece açmamaya karar verilebilir.

Ölçülen etki: konu listesi bağlama 10.570 kelime olarak giriyordu, indeks katmanına
çevrilince 447 kelimeye indi. Derlenmiş bilgi tabanının 150 satırlık tablosu tek satırlık
işaretçiye dönüştü ve tek başına 8.000 karakter kazandırdı.

## Kurallar mekanizmaya bağlıdır

Sistemin ayırt edici yanı budur. Her kuralın onu çalıştıran bir parçası vardır:

| Kural | Mekanizma |
| --- | --- |
| Dosya 500 kelimeyi aşmaz | `dosya-kancasi.sh` (PostToolUse) yazımdan sonra sayar |
| Her anlamlı oturum iz bırakır | `session-end.sh` yazılmadıysa bayrak bırakır, açılışta yüzüne söyler |
| Bitmiş iş açıkların arasında durmaz | `kapanis.sh` `durum: kapandı` olanı arşive taşır |
| Hassas klasör bağlama girmez | Yükleyici oraya hiç bakmaz, `denetci.sh` doğrular |
| Yedeksiz yapı değiştirilmez | `denetci.sh` yedeğin bayatladığını söyler |
| Boş klasörler kendiliğinden dolmaz | `soru-sirasi.sh` arada kullanıcıya soru üretir |
| İndeks satırı yazılmadan kalmaz | `indeks-uret.py` taslağı üretir, elle yazılanı korur |
| Katman yerleşimi sezgiye kalmaz | `terfi.sh` dokunma sayılarından sıcak/soğuk listesi çıkarır |
| Derleme günlüğü sonsuza büyümez | `log-dondur.py` geçmiş yılın günlüğünü arşive döndürür |
| Tavanı aşan dosya elle bölünmez | `gecmis-ayir.py` arşiv bloğunu alt dosyaya taşır |
| Taşınan dosya kırık bağlantı bırakmaz | `graf_kontrol.py` kırık bağlantı ve yetim not tarar |
| Codex ile Claude farklı kural okumaz | Ofis projesinde `AGENTS.md` her zaman `CLAUDE.md`'ye symlink'tir |
| Mekanizmalar sessizce bozulmaz | `testler.sh` — 47 test, hook değişiminde çalıştırılır |

## Kurulum

1. Bu depoyu vault'unun olacağı klasöre kopyala (Obsidian vault'u olarak açabilirsin).
2. `CLAUDE.md` içindeki `<...>` yer tutucularını doldur: sistem adı, asistan adı, kullanıcı,
   dil, ofis yolu.
3. `🔮 zihin/Ruh.md` ve `🔮 zihin/Çekirdek.md` şablonlarını doldur. Çekirdek'i asistan
   sorarak da doldurabilir — tasarım gereği tahminle yazmaz.
4. `git init` yap ve bir uzak depo bağla (`.claude/scripts/yedek.sh` bunu kullanır).
5. `.claude/scripts/denetci.sh` çalıştır. Hepsi ✅ olmalı.

Gereksinimler: `bash`, `python3`, `git`. Windows'ta hook'ların PowerShell karşılıkları kullanılır. Claude Code hook'ları `.claude/settings.json`
üzerinden bağlanır; dosya hazır gelir.

## Klasörler

```
🔮 zihin/        refleks katmanı: kimlik, kurallar, son oturum, kalan işler
🏰 İş/           yapılan işlerin notları (kod değil — kod ofiste durur)
🛠️ Veriler/      toplanan veri, araç ve kaynak kayıtları
📓 Günlük/       defter/ asistan yazar; daily/ makine yazar
🎯 Hedefler/     hedefler ve takip
🔐 kasa/         bağlama asla yüklenmeyen hassas veri
💪 Beden/        sağlık, spor, uyku
🧘 Düşünceler/   zihinsel alan
📦 bitmiş olanlar/  kapanan işler, yıl klasörlerinde
knowledge/       derlenmiş bilgi tabanı (makine üretir)
```

**Kod bu vault'a girmez.** Vault kendisi bir git deposudur, Obsidian her dosyayı indeksler,
derleyici insan yazımı notlar için tasarlanmıştır. Kod ayrı bir "ofis" klasöründe durur;
ikisi tek bir ana klasörün altında kardeş olabilir, yeter ki git kökü, Obsidian vault kökü
ve derleyici kapsamı hafıza klasörüyle sınırlı kalsın. `denetci.sh` bunu denetler.

## Neden bu tasarım

Asıl ilke tek cümleye iner: **bir sistemin iyi olması yanlış şeyi yapmayı imkânsız kılmasıyla
değil, pahalı kılmasıyla ölçülür.** Kural koymak ucuzdur; kuralı ölçen bir şey yazmak
pahalıdır ama kalıcı olan odur.

## Köken ve katkılar

Temel: [`avenoxai/avenoxbeyin`](https://github.com/avenoxai/avenoxbeyin) — Obsidian + Claude
Code üzerine kurulu, oturumlar arası kalıcı hafızalı açık kaynak ikinci beyin sistemi.
Bu çatalın devraldığı parçalar: klasör iskeleti, dört hook olayının zinciri (SessionStart,
UserPromptSubmit, SessionEnd, PreCompact), günlük yazıcı ve bilgi derleyici.

Bu çatalda eklenenler:

- **Üç yükleme kademesi** (refleks / indeks / derin) ve indeks katmanının içerik taşımaması
- **`dosya-kancasi.sh`** — 500 kelime kuralını ölçen PostToolUse kancası
- **`kapanis.sh`** — `durum: kapandı` olanı arşive taşıyan kapanış döngüsü
- **`denetci.sh`** — depo sınırı, vault kökü, derleyici kapsamı, yedek tazeliği ve
  hassas klasör dokunulmazlığı denetimi
- **`soru-sirasi.sh`** — boş kalan klasörler için kullanıcıya soru üretir
- **`yedek.sh`** — uzak yedek; koşullu hatırlatma ve sessiz düşmeyen hafıza bayrağı
- **`indeks-uret.py`** — indeks taslağı üretir, elle yazılan açıklamaları korur
- **`terfi.sh`** — dokunma kayıtlarından sıcak/soğuk raporu, refleks katmanı şişme kontrolü
- **`testler.sh`** — 47 testlik hook test takımı
- **`log-dondur.py`** ve **`gecmis-ayir.py`** — günlük ve dosya büyümesini sınırlayan döndürücüler
- **`graf_kontrol.py`** — kırık bağlantı ve yetim not taraması
- **Ofis protokolü** — proje klasöründe `AGENTS.md` symlink'i, `backlog.md` (yarım kalan iş) ve
  `reports/` (arka plan araştırmaları)
- **Windows desteği** — hook zincirinin PowerShell (`.ps1`) karşılıkları

## Lisans

MIT. Özgün eserin telif hakkı Avenox'a aittir; bu çataldaki değişiklikler için telif
hakkı MrMerkus'a aittir. Ayrıntı: `LICENSE`.
