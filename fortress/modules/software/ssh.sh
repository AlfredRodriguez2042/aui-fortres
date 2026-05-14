#!/bin/bash
# Module: ssh
# Category: software
# Description: Endurece sshd_config; servicio queda OFF por default

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="ssh"
MODULE_CATEGORY="software"
MODULE_DESC="sshd_config endurecido (PermitRoot no, Password no, AllowUsers); servicio off"

DROPIN="/etc/ssh/sshd_config.d/10-fortress.conf"

config() {
  local user
  user="${FORTRESS_SSH_USER:-$(detect_username)}"
  cat <<EOF
PermitRootLogin no
PasswordAuthentication no
PubkeyAuthentication yes
ChallengeResponseAuthentication no
KbdInteractiveAuthentication no
X11Forwarding no
AllowTcpForwarding no
AllowAgentForwarding no
GatewayPorts no
PermitTunnel no
MaxAuthTries 3
LoginGraceTime 30
ClientAliveInterval 300
ClientAliveCountMax 2
${user:+AllowUsers $user}
EOF
}

apply() {
  print_title "MODULE: ssh hardening"
  ensure_pkg openssh

  local user
  user=$(detect_username)
  [[ -z "$user" ]] && read -rp "Username permitido por SSH (vacío = sin AllowUsers): " user

  mkdir -p /etc/ssh/sshd_config.d
  FORTRESS_SSH_USER="$user" config > "$DROPIN"

  sshd -t || { print_danger "sshd_config inválido; rollback automático"; rollback; return 1; }

  systemctl disable ssh.service 2>/dev/null
  systemctl disable sshd.service 2>/dev/null

  mark_active "$MODULE_NAME"
  print_success "ssh aplicado (config endurecida; servicio off — encender manualmente)."
}

rollback() {
  rm -f "$DROPIN"
  mark_inactive "$MODULE_NAME"
  print_success "ssh desactivado."
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
