#!/bin/bash
# Module: auditd
# Category: software
# Description: File watches (no syscalls, evita ruido)

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="auditd"
MODULE_CATEGORY="software"
MODULE_DESC="File watches en archivos sensibles; rotación agresiva"

config() {
  cat <<'EOF'
-w /etc/ssh/ -p wa -k ssh_config
-w /etc/pam.d/ -p wa -k pam_config
-w /etc/sudoers -p wa -k sudo_config
-w /etc/sudoers.d/ -p wa -k sudo_config
-w /etc/nftables.d/ -p wa -k firewall_config
-w /etc/nftables.conf -p wa -k firewall_config
-w /var/lib/aui-fortress/ -p wa -k fortress_state
-w /etc/passwd -p wa -k users
-w /etc/shadow -p wa -k users
-w /etc/group -p wa -k users
-w /etc/gshadow -p wa -k users
EOF
}

apply() {
  print_title "MODULE: auditd"
  ensure_pkg audit

  mkdir -p /etc/audit/rules.d
  config > /etc/audit/rules.d/99-fortress.rules

  if [[ -f /etc/audit/auditd.conf ]]; then
    backup_file /etc/audit/auditd.conf "$MODULE_NAME" >/dev/null
    sed -i 's/^max_log_file = .*/max_log_file = 50/' /etc/audit/auditd.conf
    sed -i 's/^num_logs = .*/num_logs = 10/' /etc/audit/auditd.conf
    sed -i 's/^space_left_action = .*/space_left_action = rotate/' /etc/audit/auditd.conf
  fi

  systemctl enable --now auditd
  augenrules --load 2>/dev/null || true

  mark_active "$MODULE_NAME"
  print_success "auditd activo (file watches; sin syscall audit para evitar ruido)."
}

rollback() {
  systemctl disable --now auditd 2>/dev/null
  rm -f /etc/audit/rules.d/99-fortress.rules
  restore_file /etc/audit/auditd.conf "$MODULE_NAME" || true
  mark_inactive "$MODULE_NAME"
  print_success "auditd desactivado."
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
