# Bağlam eşikleri — tek kaynak (kullanıcı, 26 Eylül). İnsan okunur karşılığı
# ~/ofis/bilinmezligin-dehasi/KRITERLER.md "Bağlam eşikleri"; testler.sh ikisi
# ayrışırsa kırmızı verir. Ortam değişkeni yalnız test içindir.
: "${BAGLAM_HEDEF:=12000}"    # niyet: üstü haber verir, kırpmaz
: "${BAGLAM_TURUNCU:=16000}"  # turuncu bölge: denetçi uyarır, açılış belirgin uyarır
: "${BAGLAM_TAVAN:=24000}"    # kırmızı: açılış kırpar, test ve denetçi hata verir

# 12000 → 12.000
binlik() { printf '%s' "$1" | sed ':a;s/\([0-9]\)\([0-9]\{3\}\)\($\|\.\)/\1.\2\3/;ta'; }
