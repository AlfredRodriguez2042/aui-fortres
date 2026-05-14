#!/bin/bash
# Module: pam-u2f
# Category: hardware
# Description: FIDO2 segundo factor en sudo + SDDM

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="pam-u2f"
MODULE_CATEGORY="hardware"
MODULE_DESC="FIDO2 segundo factor en sudo + login (SDDM). pam_u2f con touch requerido."

config() {
  local user
  user=$(detect_username)
  cat <<EOF
# Acciones previstas:
pacman -S --needed pam-u2f

# Enroll para usuario detectado:
USER=${user:-<username>}
pamu2fcfg > ~/.config/Yubico/u2f_keys

# Línea insertada en /etc/pam.d/sudo y /etc/pam.d/sddm:
auth required pam_u2f.so cue
EOF
}

apply() {
  print_title "MODULE: pam-u2f"
  ensure_pkg pam-u2f

  local user
  user=$(detect_username)
  [[ -z "$user" ]] && { print_danger "No se detectó usuario; setear manualmente."; return 1; }

  print_info "Usuario: $user"
  print_warning "Inserta el FIDO2 token AHORA. Toca cuando parpadee."

  sudo -u "$user" mkdir -p "/home/$user/.config/Yubico"
  sudo -u "$user" pamu2fcfg > "/home/$user/.config/Yubico/u2f_keys" || {
    print_danger "Enroll U2F falló"; return 1
  }
  chown -R "$user":"$user" "/home/$user/.config/Yubico"

  local pam_file
  for pam_file in /etc/pam.d/sudo /etc/pam.d/sddm; do
    [[ -f "$pam_file" ]] || continue
    backup_file "$pam_file" "$MODULE_NAME" >/dev/null
    if ! grep -q "pam_u2f.so" "$pam_file"; then
      sed -i "1a auth required pam_u2f.so cue" "$pam_file"
      print_info "  Añadido pam_u2f.so a $pam_file"
    fi
  done

  mark_active "$MODULE_NAME"
  print_success "pam-u2f activo. Touch del token requerido para sudo y SDDM."
}

rollback() {
  local pam_file
  for pam_file in /etc/pam.d/sudo /etc/pam.d/sddm; do
    [[ -f "$pam_file" ]] || continue
    sed -i '/pam_u2f.so/d' "$pam_file"
  done
  mark_inactive "$MODULE_NAME"
  print_success "pam-u2f desactivado."
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
