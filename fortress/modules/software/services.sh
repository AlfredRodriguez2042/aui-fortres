#!/bin/bash
# Module: services
# Category: software
# Description: Deshabilita servicios no necesarios (avahi, cups)

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="services"
MODULE_CATEGORY="software"
MODULE_DESC="Disable + mask servicios no necesarios (avahi, cups)"

SERVICES=(avahi-daemon cups cups-browsed)

config() {
  cat <<'EOF'
# Servicios que se deshabilitarían y enmascararían si existen:
systemctl disable --now avahi-daemon
systemctl mask avahi-daemon
systemctl disable --now cups
systemctl mask cups
systemctl disable --now cups-browsed
systemctl mask cups-browsed

# Verificación posterior:
ss -tulnp | grep -vE '127\.0\.0\.1|::1'
EOF
}

apply() {
  print_title "MODULE: services"
  local s
  for s in "${SERVICES[@]}"; do
    if systemctl list-unit-files "${s}.service" >/dev/null 2>&1; then
      systemctl disable --now "$s" 2>/dev/null || true
      systemctl mask "$s" 2>/dev/null || true
      print_info "  $s → disabled + masked"
    fi
  done
  print_info "Servicios escuchando (debería estar vacío fuera de loopback):"
  ss -tulnp 2>/dev/null | grep -vE '127\.0\.0\.1|::1' | tail -n +2 || true
  mark_active "$MODULE_NAME"
  print_success "services aplicado."
}

rollback() {
  local s
  for s in "${SERVICES[@]}"; do
    systemctl unmask "$s" 2>/dev/null || true
  done
  mark_inactive "$MODULE_NAME"
  print_success "services desactivado (re-habilitar manualmente si se necesitan)."
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
