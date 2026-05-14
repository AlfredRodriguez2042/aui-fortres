#!/bin/bash
# Module: buskill
# Category: hardware
# Description: USB-out → flush firewall a panic + lock + poweroff forzado
#
# Requiere: módulo firewall aplicado (provee perfil panic).

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="buskill"
MODULE_CATEGORY="hardware"
MODULE_DESC="USB out → panic firewall + lock + poweroff forzado (udev → systemd unit)"

config() {
  local serial="${FORTRESS_BUSKILL_SERIAL:-<ID_SERIAL_SHORT>}"
  cat <<EOF
### /etc/udev/rules.d/99-aui-buskill.rules
ACTION=="remove", SUBSYSTEM=="usb", ENV{ID_SERIAL_SHORT}=="${serial}", \\
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="aui-buskill.service"

### /etc/systemd/system/aui-buskill.service
[Unit]
Description=AUI buskill — USB removed, system going down
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aui-buskill.sh

### /usr/local/bin/aui-buskill.sh
#!/bin/bash
set +e
logger -t aui-buskill "USB presence removed; activating buskill sequence"
nft -f /etc/nftables.d/panic.nft
conntrack -F 2>/dev/null
loginctl lock-sessions
umount -l -t cifs,nfs,nfs4,fuse.sshfs -a 2>/dev/null
swapoff -a
(sleep 30 && systemctl poweroff --force --no-wall) &
EOF
}

apply() {
  print_title "MODULE: buskill"
  "$FORTRESS_ROOT/modules/hardware/verify-recovery.sh" verify || return 1

  if ! is_active "firewall"; then
    print_danger "Módulo 'firewall' debe estar aplicado primero (provee perfil panic)."
    return 1
  fi

  print_warning "Inserta el USB de presencia AHORA y presiona Enter."
  pause_function

  local serial
  serial=$(udevadm info --query=property --name=/dev/disk/by-id/usb-* 2>/dev/null | grep ID_SERIAL_SHORT= | head -1 | cut -d= -f2)
  if [[ -z "$serial" ]]; then
    read -rp "No se pudo auto-detectar serial. Ingresa ID_SERIAL_SHORT del USB: " serial
  else
    read -rp "Serial detectado: $serial. Usar este? [Y/n]: " confirm
    [[ "$confirm" =~ ^[Nn]$ ]] && read -rp "Ingresa ID_SERIAL_SHORT: " serial
  fi
  [[ -z "$serial" ]] && { print_danger "Serial vacío"; return 1; }

  # Regla udev — dispatch a systemd unit (NO ejecuta workflows largos)
  cat > /etc/udev/rules.d/99-aui-buskill.rules <<EOF
ACTION=="remove", SUBSYSTEM=="usb", ENV{ID_SERIAL_SHORT}=="${serial}", \\
  TAG+="systemd", ENV{SYSTEMD_WANTS}+="aui-buskill.service"
EOF

  cat > /etc/systemd/system/aui-buskill.service <<'EOF'
[Unit]
Description=AUI buskill — USB removed, system going down
DefaultDependencies=no

[Service]
Type=oneshot
ExecStart=/usr/local/bin/aui-buskill.sh
EOF

  cat > /usr/local/bin/aui-buskill.sh <<'EOF'
#!/bin/bash
# Ejecutado por systemd cuando el USB de presencia es removido.
# Orden: panic firewall → flush conntrack → lock → umount shares → poweroff forzado.
set +e
logger -t aui-buskill "USB presence removed; activating buskill sequence"
nft -f /etc/nftables.d/panic.nft
conntrack -F 2>/dev/null
loginctl lock-sessions
umount -l -t cifs,nfs,nfs4,fuse.sshfs -a 2>/dev/null
swapoff -a
(sleep 30 && systemctl poweroff --force --no-wall) &
EOF
  chmod 700 /usr/local/bin/aui-buskill.sh

  systemctl daemon-reload
  udevadm control --reload-rules
  udevadm trigger

  mark_active "$MODULE_NAME"
  print_success "Buskill armado para USB $serial."
  print_info "Recomendado: probar 'systemctl start aui-buskill.service' como dry-run manual antes de confiar."
}

rollback() {
  rm -f /etc/udev/rules.d/99-aui-buskill.rules
  rm -f /etc/systemd/system/aui-buskill.service
  rm -f /usr/local/bin/aui-buskill.sh
  systemctl daemon-reload
  udevadm control --reload-rules
  mark_inactive "$MODULE_NAME"
  print_success "buskill desactivado."
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
