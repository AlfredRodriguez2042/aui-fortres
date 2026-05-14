#!/bin/bash
# Module: verify-recovery
# Category: hardware
# Description: Precondición para módulos hardware. Verifica red de seguridad del install
#
# NO es un módulo aplicable; es un check que otros módulos invocan.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="verify-recovery"
MODULE_CATEGORY="hardware"
MODULE_DESC="Precondición: kernel-lts, rescue entry, header LUKS externo, RECOVERY.md"

config() {
  cat <<'EOF'
# Checks ejecutados:
pacman -Q linux-lts
test -f /boot/loader/entries/rescue.conf || test -f /boot/loader/entries/arch-lts.conf || grep -qi 'rescue\|lts' /boot/grub/grub.cfg
test ! -e /root/luks-header-*.bin
test -f /root/RECOVERY.md
test -f /var/lib/aui-x/etc-baseline.tar.zst
blkid -t TYPE=crypto_LUKS -o device
cryptsetup luksDump <luks-device> | grep 'Version:.*2'
EOF
}

verify() {
  print_title "VERIFY RECOVERY"
  local fail=0

  if pacman -Q linux-lts >/dev/null 2>&1; then
    print_success "linux-lts instalado"
  else
    print_danger "linux-lts NO instalado"; fail=1
  fi

  if [[ -f /boot/loader/entries/rescue.conf || -f /boot/loader/entries/arch-lts.conf ]]; then
    print_success "Rescue/LTS entry presente (systemd-boot)"
  elif grep -qi "rescue\|lts" /boot/grub/grub.cfg 2>/dev/null; then
    print_success "Rescue/LTS entry presente (GRUB)"
  else
    print_warning "No se detectó rescue entry"; fail=1
  fi

  if ls /root/luks-header-*.bin >/dev/null 2>&1; then
    print_danger "Header LUKS aún en /root — DEBE moverse a 2 USB externos cifrados primero"
    print_danger "  rm /root/luks-header-*.bin tras verificar checksum"
    fail=1
  else
    print_success "Header LUKS no presente en /root (asumido movido a externo)"
  fi

  [[ -f /root/RECOVERY.md ]] && print_success "RECOVERY.md presente" || print_warning "RECOVERY.md ausente"

  [[ -f /var/lib/aui-x/etc-baseline.tar.zst ]] && print_success "/etc baseline presente" || print_warning "/etc baseline ausente"

  local luks_dev
  luks_dev=$(blkid -t TYPE=crypto_LUKS -o device 2>/dev/null | head -1)
  if [[ -n "$luks_dev" ]]; then
    if cryptsetup luksDump "$luks_dev" 2>/dev/null | grep -q "Version:.*2"; then
      print_success "LUKS2 detectado en $luks_dev"
    else
      print_warning "$luks_dev es LUKS1; FIDO2 requiere LUKS2"; fail=1
    fi
  fi

  if (( fail )); then
    print_danger "verify-recovery FALLÓ. NO aplicar módulos hardware hasta resolver."
    return 1
  fi
  print_success "verify-recovery OK. Módulos hardware son seguros de aplicar."
}

# Otros módulos lo invocan así:
#   "$FORTRESS_ROOT/modules/hardware/verify-recovery.sh" verify || return 1

case "${1:-verify}" in
  verify|apply)    check_root; check_archlinux; verify ;;
  rollback) print_info "Nada que hacer (verify-recovery es read-only)" ;;
  status)   verify >/dev/null 2>&1 && echo active || echo inactive ;;
  describe) echo "${MODULE_NAME}|${MODULE_CATEGORY}|${MODULE_DESC}" ;;
  config)   config ;;
  *) echo "Usage: $(basename "$0") {verify|status|describe|config}"; exit 1 ;;
esac
