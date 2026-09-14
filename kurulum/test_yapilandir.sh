#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
VAULT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

# Geçici çalışma alanı oluştur
TEMP_DIR="$(mktemp -d)"
cleanup() {
  rm -rf "${TEMP_DIR}"
}
trap cleanup EXIT

TEMP_VAULT="${TEMP_DIR}/vault"
mkdir -p "${TEMP_VAULT}"

# OUT dizinini .git hariç geçici vault dizinine kopyala
if command -v rsync >/dev/null 2>&1; then
  rsync -a --exclude='.git' "${VAULT_DIR}/" "${TEMP_VAULT}/"
else
  cp -a "${VAULT_DIR}/." "${TEMP_VAULT}/"
  rm -rf "${TEMP_VAULT}/.git"
fi

# Türkçe karakterler ("Işık", "Çağrı") içeren geçici sistem.json hazırla
TEMP_AYARLAR="${TEMP_DIR}/sistem.json"
cat > "${TEMP_AYARLAR}" << 'EOF'
{
  "sistem_adi": "Işık ve Çağrı Sistemi",
  "asistan_adi": "Işık",
  "kullanici": "Çağrı",
  "baglam": "Çağrı yazılım geliştirici; düşünme ortağı kuruyor."
}
EOF

# --dene modu testi
echo "==> 1. --dene modu test ediliyor..."
DENE_CIKTI="$(python3 "${TEMP_VAULT}/kurulum/yapilandir.py" --ayarlar "${TEMP_AYARLAR}" --hedef "${TEMP_VAULT}" --dene)"
if [[ ! "${DENE_CIKTI}" =~ "[DENE]" ]]; then
  echo "❌ --dene çıktısı beklenen biçimde değil!" >&2
  exit 1
fi
if ! grep -F -q '<ASİSTAN ADI>' "${TEMP_VAULT}/CLAUDE.md"; then
  echo "❌ --dene modu dosyayı yazarak değiştirdi!" >&2
  exit 1
fi
echo "✅ --dene modu simülasyonu başarılı (dosyalar değiştirilmedi)."

# 1. Çalıştırma
echo "==> 2. İlk çalıştırma yapılıyor..."
ILK_CIKTI="$(python3 "${TEMP_VAULT}/kurulum/yapilandir.py" --ayarlar "${TEMP_AYARLAR}" --hedef "${TEMP_VAULT}")"
echo "${ILK_CIKTI}"

# 2. Çalıştırma (idempotentlik testi)
echo "==> 3. İkinci çalıştırma yapılıyor (idempotens denetimi)..."
IKINCI_CIKTI="$(python3 "${TEMP_VAULT}/kurulum/yapilandir.py" --ayarlar "${TEMP_AYARLAR}" --hedef "${TEMP_VAULT}")"
echo "${IKINCI_CIKTI}"

# Doğrulama 1: İkinci çalıştırmada 0 dosya değiştiği doğrulanır
if [[ "${IKINCI_CIKTI}" =~ "Değiştirilen dosya sayısı: 0" ]]; then
  echo "✅ İkinci çalıştırmada 0 dosya değişti (idempotent)."
else
  echo "❌ İkinci çalıştırmada 0 dosya değişmesi beklenirken değişiklik algılandı!" >&2
  exit 1
fi

# Doğrulama 2: CLAUDE.md ve 🔮 zihin/Ruh.md içinde sözleşme yer tutucuları kalmamalı
CONTRACT_PLACEHOLDERS=(
  "<SİSTEM ADI>"
  "<ASİSTAN ADI>"
  "<KULLANICI>"
  "<DİL>"
  "<AD 1>"
  "<AD 2>"
  "<AD 3>"
  "<OFIS>"
  "<HAFIZA>"
  "<BİR İKİ CÜMLE — kim, ne yapıyor, bu beyni neden kuruyor>"
)

for ph in "${CONTRACT_PLACEHOLDERS[@]}"; do
  if grep -F -q -- "${ph}" "${TEMP_VAULT}/CLAUDE.md"; then
    echo "❌ CLAUDE.md içinde kalan yer tutucu tespit edildi: ${ph}" >&2
    exit 1
  fi
  if grep -F -q -- "${ph}" "${TEMP_VAULT}/🔮 zihin/Ruh.md"; then
    echo "❌ 🔮 zihin/Ruh.md içinde kalan yer tutucu tespit edildi: ${ph}" >&2
    exit 1
  fi
done
echo "✅ CLAUDE.md ve 🔮 zihin/Ruh.md içinde sözleşme yer tutucusu kalmadı."

# Doğrulama 3: <slug> CLAUDE.md içinde korunmuş olmalı
if grep -F -q '<slug>' "${TEMP_VAULT}/CLAUDE.md"; then
  echo "✅ <slug> yer tutucusu CLAUDE.md içinde korundu."
else
  echo "❌ <slug> yer tutucusu CLAUDE.md içinde bulunamadı!" >&2
  exit 1
fi

# Doğrulama 4: asistan_adi veya kullanici eksik olduğunda çıkış kodu 2 olmalı
EKSIK_AYARLAR="${TEMP_DIR}/eksik.json"
cat > "${EKSIK_AYARLAR}" << 'EOF'
{
  "sistem_adi": "Eksik Test"
}
EOF

set +e
python3 "${TEMP_VAULT}/kurulum/yapilandir.py" --ayarlar "${EKSIK_AYARLAR}" --hedef "${TEMP_VAULT}" 2>/dev/null
EKSIK_KOD=$?
set -e

if [[ "${EKSIK_KOD}" -eq 2 ]]; then
  echo "✅ Eksik zorunlu ayarlarda beklendiği gibi çıkış kodu 2 döndü."
else
  echo "❌ Eksik zorunlu ayarlarda çıkış kodu 2 bekleniyordu, alınan: ${EKSIK_KOD}" >&2
  exit 1
fi

echo "✅ Tüm testler başarıyla geçti."
exit 0
