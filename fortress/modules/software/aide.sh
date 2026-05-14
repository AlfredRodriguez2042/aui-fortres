#!/bin/bash
# Module: aide
# Category: software
# Description: File integrity baseline + check diario; hash firmable a backup

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="aide"
MODULE_CATEGORY="software"
MODULE_DESC="Baseline integrity + check diario + hash a backup inmutable"

config() {
  cat <<'EOF'
### /etc/systemd/system/aide-check.service
[Unit]
Description=AIDE integrity check
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/aide --check

### /etc/systemd/system/aide-check.timer
[Unit]
Description=Daily AIDE integrity check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF
}

apply() {
  print_title "MODULE: aide"
  ensure_pkg aide

  print_info "Inicializando baseline AIDE (puede tardar varios minutos)..."
  aide --init
  mv -f /var/lib/aide/aide.db.new.gz /var/lib/aide/aide.db.gz

  cat > /etc/systemd/system/aide-check.service <<'EOF'
[Unit]
Description=AIDE integrity check
After=local-fs.target

[Service]
Type=oneshot
ExecStart=/usr/bin/aide --check
EOF

  cat > /etc/systemd/system/aide-check.timer <<'EOF'
[Unit]
Description=Daily AIDE integrity check

[Timer]
OnCalendar=daily
Persistent=true
RandomizedDelaySec=1h

[Install]
WantedBy=timers.target
EOF

  systemctl daemon-reload
  systemctl enable --now aide-check.timer

  sha256sum /var/lib/aide/aide.db.gz > /var/lib/aide/aide.db.gz.sha256
  print_warning "Mover /var/lib/aide/aide.db.gz.sha256 a backup inmutable para verificar tampering desde live USB."

  mark_active "$MODULE_NAME"
  print_success "aide aplicado. Check diario habilitado."
}

rollback() {
  systemctl disable --now aide-check.timer 2>/dev/null
  rm -f /etc/systemd/system/aide-check.{service,timer}
  systemctl daemon-reload
  mark_inactive "$MODULE_NAME"
  print_success "aide desactivado (DB en /var/lib/aide se mantiene)."
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
