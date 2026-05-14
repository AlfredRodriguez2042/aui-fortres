#!/bin/bash
# Module: apparmor
# Category: software
# Description: MAC framework + perfiles base en modo complain

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="apparmor"
MODULE_CATEGORY="software"
MODULE_DESC="AppArmor MAC + perfiles base (modo complain inicial)"

config() {
  cat <<'EOF'
# Paquetes/servicios:
pacman -S --needed apparmor
systemctl enable --now apparmor.service

# Si AppArmor no está activo como LSM:
# añadir al kernel cmdline:
lsm=landlock,lockdown,yama,integrity,apparmor,bpf

# Perfiles comunes se pasan a complain inicialmente:
aa-complain /etc/apparmor.d/usr.bin.firefox
aa-complain /etc/apparmor.d/usr.bin.chromium
EOF
}

apply() {
  print_title "MODULE: apparmor"
  ensure_pkg apparmor

  if ! grep -q apparmor /sys/kernel/security/lsm 2>/dev/null; then
    print_warning "AppArmor LSM no está activo en este kernel."
    print_info "Para activarlo: añadir 'lsm=landlock,lockdown,yama,integrity,apparmor,bpf' al kernel cmdline en bootloader y reboot."
  fi

  systemctl enable --now apparmor.service

  # Modo complain para apps comunes (no enforce de entrada para evitar bloqueos)
  if command -v aa-complain >/dev/null 2>&1; then
    for profile in /etc/apparmor.d/usr.bin.firefox /etc/apparmor.d/usr.bin.chromium; do
      [[ -f "$profile" ]] && aa-complain "$profile" 2>/dev/null || true
    done
  fi

  mark_active "$MODULE_NAME"
  print_success "apparmor activo. Perfiles en complain; promover a enforce con 'aa-enforce' tras 1 semana sin denials."
}

rollback() {
  systemctl disable --now apparmor.service 2>/dev/null
  mark_inactive "$MODULE_NAME"
  print_success "apparmor desactivado."
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
