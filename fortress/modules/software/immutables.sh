#!/bin/bash
# Module: immutables
# Category: software
# Description: chattr +i en archivos estáticos (NO resolv.conf)

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="immutables"
MODULE_CATEGORY="software"
MODULE_DESC="chattr +i en /etc/hosts, /etc/fstab, /etc/ssh/sshd_config (NO resolv.conf)"

FILES=(/etc/hosts /etc/fstab /etc/ssh/sshd_config /etc/pam.d/system-auth)

config() {
  cat <<'EOF'
# Archivos estáticos que recibirían chattr +i si existen:
chattr +i /etc/hosts
chattr +i /etc/fstab
chattr +i /etc/ssh/sshd_config
chattr +i /etc/pam.d/system-auth

# Explicitamente NO se toca /etc/resolv.conf.
EOF
}

apply() {
  print_title "MODULE: immutables"
  local f
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] && chattr +i "$f" && print_info "  +i $f"
  done
  print_warning "NO se aplica a /etc/resolv.conf (rompería NetworkManager)."
  mark_active "$MODULE_NAME"
  print_success "immutables aplicado."
}

rollback() {
  local f
  for f in "${FILES[@]}"; do
    [[ -f "$f" ]] && chattr -i "$f" 2>/dev/null || true
  done
  mark_inactive "$MODULE_NAME"
  print_success "immutables desactivado."
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
