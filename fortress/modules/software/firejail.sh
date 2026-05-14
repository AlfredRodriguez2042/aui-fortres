#!/bin/bash
# Module: firejail
# Category: software
# Description: Sandboxing on-demand (no fuerza wrapping automático)

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="firejail"
MODULE_CATEGORY="software"
MODULE_DESC="Sandboxing on-demand para apps (firejail firefox, firejail discord, etc)"

config() {
  cat <<'EOF'
# Acciones previstas:
pacman -S --needed firejail

# No se fuerza wrapping automático ni se reemplazan launchers.
# Uso manual esperado:
firejail <app>
EOF
}

apply() {
  print_title "MODULE: firejail"
  ensure_pkg firejail
  print_info "firejail instalado. Uso: firejail <app>. No se fuerza wrapping automático."
  mark_active "$MODULE_NAME"
  print_success "firejail disponible."
}

rollback() {
  pacman -Rns --noconfirm firejail 2>/dev/null || true
  mark_inactive "$MODULE_NAME"
  print_success "firejail desactivado."
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
