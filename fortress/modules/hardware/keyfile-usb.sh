#!/bin/bash
# Module: keyfile-usb
# Category: hardware
# Description: LUKS keyfile en USB externo. Fallback automático a passphrase si USB ausente.
#
# Sintaxis sd-encrypt en crypttab.initramfs:
#   name  device  /<path-en-usb>:LABEL=<label>  keyfile-timeout=10s

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="keyfile-usb"
MODULE_CATEGORY="hardware"
MODULE_DESC="LUKS keyfile en USB externo con LABEL. Fallback auto a passphrase si USB ausente."

config() {
  cat <<'EOF'
# Acciones previstas:
# 1. verify-recovery
# 2. generar keyfile aleatorio en USB con LABEL elegido
# 3. añadir keyfile como slot LUKS:
cryptsetup luksAddKey <luks-device> /mnt/usb-key-stage/<keyfile>

# Línea a añadir manualmente a /etc/crypttab.initramfs:
cryptroot UUID=<luks-uuid> <keyfile-path>:LABEL=<usb-label> keyfile-timeout=<timeout>

# Regenerar initramfs:
mkinitcpio -P

# Si el USB está ausente, sd-encrypt cae a passphrase manual.
EOF
}

apply() {
  print_title "MODULE: keyfile-usb"
  "$FORTRESS_ROOT/modules/hardware/verify-recovery.sh" verify || return 1

  read -rp "Label del filesystem en el USB (ej: KURO_KEYDEV): " usb_label
  [[ -z "$usb_label" ]] && { print_danger "Label vacío"; return 1; }

  read -rp "Path del keyfile dentro del USB (default: /arch.key): " kf_path
  kf_path="${kf_path:-/arch.key}"
  kf_path="${kf_path#/}"  # remove leading slash for internal use

  read -rp "keyfile-timeout (default 10s): " kf_timeout
  kf_timeout="${kf_timeout:-10s}"

  local luks_dev
  luks_dev=$(blkid -t TYPE=crypto_LUKS -o device | head -1)
  [[ -z "$luks_dev" ]] && { print_danger "No LUKS device"; return 1; }

  local usb_dev
  usb_dev=$(blkid -L "$usb_label" 2>/dev/null)
  [[ -z "$usb_dev" ]] && { print_danger "USB con LABEL=$usb_label no encontrado. Insértalo primero."; return 1; }

  local mnt="/mnt/usb-key-stage"
  mkdir -p "$mnt"
  mount "$usb_dev" "$mnt" || { print_danger "Mount falló"; return 1; }

  print_info "Generando keyfile aleatorio (4 KB)..."
  dd if=/dev/urandom of="$mnt/$kf_path" bs=512 count=8 iflag=fullblock 2>/dev/null
  chmod 0400 "$mnt/$kf_path"

  print_info "Añadiendo slot LUKS (te pedirá passphrase del slot 0)..."
  cryptsetup luksAddKey "$luks_dev" "$mnt/$kf_path" || {
    umount "$mnt"; print_danger "Add keyfile falló"; return 1
  }
  umount "$mnt"
  rmdir "$mnt" 2>/dev/null

  local luks_uuid
  luks_uuid=$(blkid -s UUID -o value "$luks_dev")

  print_info "Añade a /etc/crypttab.initramfs (sintaxis sd-encrypt EXACTA):"
  echo ""
  echo "  cryptroot UUID=${luks_uuid} ${kf_path}:LABEL=${usb_label} keyfile-timeout=${kf_timeout}"
  echo ""
  print_warning "Tras editar /etc/crypttab.initramfs ejecuta: mkinitcpio -P"

  mark_active "$MODULE_NAME"
  print_success "Keyfile escrito en USB ($usb_label:/${kf_path}). Si USB ausente: prompt de passphrase auto."
}

rollback() {
  print_warning "Rollback manual requerido:"
  print_warning "  1. cryptsetup luksRemoveKey <luks-device> con el keyfile o passphrase"
  print_warning "  2. Editar /etc/crypttab.initramfs y quitar la línea del keyfile"
  print_warning "  3. mkinitcpio -P"
  mark_inactive "$MODULE_NAME"
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
