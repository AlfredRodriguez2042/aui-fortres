#!/bin/bash
# Module: tmpfs-noexec
# Category: software
# Description: noexec en /tmp, /dev/shm, /var/tmp vía fstab

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="tmpfs-noexec"
MODULE_CATEGORY="software"
MODULE_DESC="noexec,nosuid,nodev en /tmp, /dev/shm, /var/tmp (fstab + remount en caliente)"

config() {
  cat <<'EOF'
# Líneas que se añadirían a /etc/fstab si no existen:
tmpfs /tmp tmpfs rw,nosuid,nodev,noexec,size=4G 0 0
tmpfs /dev/shm tmpfs rw,nosuid,nodev,noexec,size=2G 0 0
tmpfs /var/tmp tmpfs rw,nosuid,nodev,noexec,size=1G 0 0

# Acciones en caliente:
mount -o remount,noexec,nosuid,nodev /tmp
mount -o remount,noexec,nosuid,nodev /dev/shm
mount -o remount,noexec,nosuid,nodev /var/tmp
EOF
}

apply() {
  print_title "MODULE: tmpfs-noexec"
  backup_file /etc/fstab "$MODULE_NAME" >/dev/null

  local mp size
  for mp in /tmp /dev/shm /var/tmp; do
    case "$mp" in
      /tmp)     size=4G ;;
      /dev/shm) size=2G ;;
      /var/tmp) size=1G ;;
    esac
    if ! grep -qE "^tmpfs[[:space:]]+${mp}[[:space:]]" /etc/fstab; then
      echo "tmpfs ${mp} tmpfs rw,nosuid,nodev,noexec,size=${size} 0 0" >> /etc/fstab
      print_info "  fstab + ${mp} noexec"
    fi
    mount -o remount,noexec,nosuid,nodev "$mp" 2>/dev/null || true
  done

  mark_active "$MODULE_NAME"
  print_success "tmpfs-noexec aplicado (en caliente + persistente)."
}

rollback() {
  restore_file /etc/fstab "$MODULE_NAME" || true
  for mp in /tmp /dev/shm /var/tmp; do
    mount -o remount,exec "$mp" 2>/dev/null || true
  done
  mark_inactive "$MODULE_NAME"
  print_success "tmpfs-noexec desactivado."
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
