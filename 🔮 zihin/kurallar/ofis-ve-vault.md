---
title: Ofis ve vault ayrımı
created: 2026-09-11
type: memory
tags: [kurallar, ofis]
---

# Ofis ve vault ayrımı

Bu dosya `~/ofis/<slug>/` altında çalışırken, özellikle oraya not veya hafıza dosyası
yazma isteği doğduğunda açılır.

- **kural:** Çalışma ofisi Obsidian'da ikinci bir vault olarak açık ama orası kullanıcının gözü
  için; oradaki tek işin projeyi yapmak. Vault'u yönetme, not doldurma, hafıza yazma.
  **neden:** kullanıcı o vault'u grafik arayüzden projeye hızlı bakmak ve kendi el atmak için
  istedi. Hafıza ve süreklilik vault'ta kalır, iki yere bölünmez. Ofiste kalan iş
  `backlog.md`'ye, projenin beyni `🏰 İş/<slug>/` altına yazılır.
- **kural:** Vault'ta bilgi ararken `CLAUDE.md` rota tablosundaki klasörden başla, oturum
  kökünden `grep -r` yapma. **neden:** kökten arama `ofis/` gürültüsüyle doldu, vault sonucu
  görünmedi: "sen neden ofisten bakıyon?"
