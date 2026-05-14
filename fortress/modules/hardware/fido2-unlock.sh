#!/bin/bash
# Module: fido2-unlock
# Category: hardware
# Description: LUKS unlock con FIDO2 token (YubiKey con hmac-secret)
#
# Requiere: verify-recovery OK + LUKS2 + token FIDO2 con hmac-secret extension.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="fido2-unlock"
MODULE_CATEGORY="hardware"
MODULE_DESC="LUKS unlock con YubiKey/FIDO2 (systemd-cryptenroll). Slot 0 passphrase intacto."

config() {
  cat <<'EOF'
# Acciones previstas:
# 1. verify-recovery
# 2. detectar dispositivo LUKS2 existente
# 3. instalar libfido2 si falta
systemd-cryptenroll --fido2-device=auto <luks-device>

# Si /etc/crypttab.initramfs existe, añadir opción:
fido2-device=auto

# Regenerar initramfs:
mkinitcpio -P

# Slot 0 con passphrase manual queda intacto.
EOF
}

apply() {
  print_title "MODULE: fido2-unlock"
  "$FORTRESS_ROOT/modules/hardware/verify-recovery.sh" verify || {
    print_danger "verify-recovery falló; abortando enroll fido2"
    return 1
  }

  local luks_dev
  luks_dev=$(blkid -t TYPE=crypto_LUKS -o device | head -1)
  [[ -z "$luks_dev" ]] && { print_danger "No LUKS device"; return 1; }
  print_info "LUKS device: $luks_dev"

  ensure_pkg libfido2

  print_warning "Inserta el token FIDO2 (YubiKey, etc.) AHORA y presiona Enter."
  pause_function

  if ! fido2-token -L 2>/dev/null | grep -q .; then
    print_danger "No se detectó ningún token FIDO2."
    return 1
  fi

  print_warning "El token solicitará touch durante el enroll."
  systemd-cryptenroll --fido2-device=auto "$luks_dev" || {
    print_danger "Enroll FIDO2 falló."; return 1;
  }

  if [[ -f /etc/crypttab.initramfs ]] && ! grep -q "fido2-device" /etc/crypttab.initramfs; then
    sed -i 's|$|,fido2-device=auto|' /etc/crypttab.initramfs
  fi

  mkinitcpio -P

  mark_active "$MODULE_NAME"
  print_success "FIDO2 enrollado. Slot 0 (passphrase) SIGUE intacto como recovery."
  print_warning "Próximo reboot: el token será requerido para desbloquear el disco."
}

rollback() {
  local luks_dev
  luks_dev=$(blkid -t TYPE=crypto_LUKS -o device | head -1)
  [[ -n "$luks_dev" ]] && systemd-cryptenroll --wipe-slot=fido2 "$luks_dev" 2>/dev/null
  sed -i 's|,fido2-device=auto||' /etc/crypttab.initramfs 2>/dev/null
  mkinitcpio -P 2>/dev/null
  mark_inactive "$MODULE_NAME"
  print_success "FIDO2 unlock removido. Slot 0 passphrase intacto."
}

status() { is_active "$MODULE_NAME" && echo active || echo inactive; }
describe() { echo "${MODULE_NAME}|${MODULE_CATEGORY}|${MODULE_DESC}"; }

case "${1:-help}" in
  apply)    check_root; check_archlinux; apply ;;
  rollback) check_root; check_archlinux; rollback ;;
  status)   status ;;
  describe) describe ;;
  config)   config ;;
  *) echo "Usage: $(basename "$0") {apply|rollback|status|describe|config}"; exit 1 ;;
esac
