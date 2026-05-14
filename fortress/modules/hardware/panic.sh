#!/bin/bash
# Module: panic
# Category: hardware
# Description: Script de emergencia (panic firewall + lock + poweroff forzado)
#
# Promesas calibradas:
#   - NO intenta luksClose root activo (no posible mientras está en uso)
#   - NO promete borrar RAM (kernel restringe; mitigación parcial: swapoff)
#   - Lo que SÍ hace: cortar red, vaciar conntrack, lock, swap off, poweroff forzado

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="panic"
MODULE_CATEGORY="hardware"
MODULE_DESC="Script de emergencia: cortar red + lock + swapoff + poweroff forzado"

config() {
  cat <<'EOF'
### /usr/local/bin/aui-panic.sh
#!/bin/bash
# Panic mode. Promesas calibradas:
# - Cortar red (firewall a panic, vaciar conntrack)
# - Lock sesiones
# - Swap off (reduce surface; no garantiza borrar RAM)
# - Poweroff forzado sin sync (sysrq-b si disponible)
#
# NO intenta luksClose del root activo (imposible mientras está montado).
# El disco queda cifrado en disco como siempre — eso ES la protección.
nft -f /etc/nftables.d/panic.nft 2>/dev/null
conntrack -F 2>/dev/null
loginctl lock-sessions 2>/dev/null
swapoff -a 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null || systemctl poweroff --force --no-wall
EOF
}

apply() {
  print_title "MODULE: panic"
  if ! is_active "firewall"; then
    print_danger "Módulo 'firewall' debe estar aplicado primero (provee perfil panic)."
    return 1
  fi

  cat > /usr/local/bin/aui-panic.sh <<'EOF'
#!/bin/bash
# Panic mode. Promesas calibradas:
# - Cortar red (firewall a panic, vaciar conntrack)
# - Lock sesiones
# - Swap off (reduce surface; no garantiza borrar RAM)
# - Poweroff forzado sin sync (sysrq-b si disponible)
#
# NO intenta luksClose del root activo (imposible mientras está montado).
# El disco queda cifrado en disco como siempre — eso ES la protección.
nft -f /etc/nftables.d/panic.nft 2>/dev/null
conntrack -F 2>/dev/null
loginctl lock-sessions 2>/dev/null
swapoff -a 2>/dev/null
echo b > /proc/sysrq-trigger 2>/dev/null || systemctl poweroff --force --no-wall
EOF
  chmod 700 /usr/local/bin/aui-panic.sh

  print_info "Script de panic: /usr/local/bin/aui-panic.sh"
  print_info "Invocar manualmente: sudo /usr/local/bin/aui-panic.sh"
  print_info "Para USB negro dedicado: añadir regla udev similar a buskill apuntando a este script."

  mark_active "$MODULE_NAME"
  print_success "panic disponible."
}

rollback() {
  rm -f /usr/local/bin/aui-panic.sh
  mark_inactive "$MODULE_NAME"
  print_success "panic desactivado."
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
