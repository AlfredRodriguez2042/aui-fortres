#!/bin/bash
# Module: sudo-timeout
# Category: software
# Description: timestamp_timeout corto (2 min) y endurecimientos sudo

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="sudo-timeout"
MODULE_CATEGORY="software"
MODULE_DESC="sudo timestamp_timeout=2; passwd_tries=3; logging"

DROPIN="/etc/sudoers.d/20-fortress-timeout"

config() {
  cat <<'EOF'
Defaults timestamp_timeout=2
Defaults passwd_tries=3
Defaults badpass_message="ACCESO DENEGADO."
Defaults logfile="/var/log/sudo.log"
Defaults log_input
Defaults log_output
EOF
}

apply() {
  print_title "MODULE: sudo-timeout"
  mkdir -p /etc/sudoers.d
  config > "$DROPIN"
  chmod 0440 "$DROPIN"
  visudo -c -f "$DROPIN" || { print_danger "sudoers inválido"; rm -f "$DROPIN"; return 1; }
  mark_active "$MODULE_NAME"
  print_success "sudo-timeout aplicado (2 min, logging activo)."
}

rollback() {
  rm -f "$DROPIN"
  mark_inactive "$MODULE_NAME"
  print_success "sudo-timeout desactivado."
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
