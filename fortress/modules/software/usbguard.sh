#!/bin/bash
# Module: usbguard
# Category: software
# Description: Whitelist USB por id+serial+interfaces (anti BadUSB)

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="usbguard"
MODULE_CATEGORY="software"
MODULE_DESC="Whitelist por id+serial+interfaces; anti BadUSB/rubber-ducky"

config() {
  cat <<'EOF'
# Acciones previstas:
pacman -S --needed usbguard

# Si /etc/usbguard/rules.conf no existe o está vacío:
usbguard generate-policy > /etc/usbguard/rules.conf
chmod 600 /etc/usbguard/rules.conf

# Importante: la policy inicial permite sólo los USB conectados al aplicar.
systemctl enable --now usbguard.service
EOF
}

apply() {
  print_title "MODULE: usbguard"
  ensure_pkg usbguard

  if [[ ! -s /etc/usbguard/rules.conf ]]; then
    print_info "Generando policy inicial con dispositivos USB conectados ACTUALMENTE..."
    print_warning "Asegúrate que tu teclado/mouse están conectados; sólo eso quedará whitelisted."
    pause_function
    usbguard generate-policy > /etc/usbguard/rules.conf
    chmod 600 /etc/usbguard/rules.conf
  fi

  systemctl enable --now usbguard.service
  mark_active "$MODULE_NAME"
  print_success "usbguard activo. Añadir USB nuevo: 'usbguard list-devices'; 'usbguard allow-device <id>'."
}

rollback() {
  systemctl disable --now usbguard.service 2>/dev/null
  mark_inactive "$MODULE_NAME"
  print_success "usbguard desactivado."
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
