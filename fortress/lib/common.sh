#!/bin/bash
# fortress/lib/common.sh — Shared helpers para todos los módulos.
#
# Source-ed por:
#   - fortress/fortress (orchestrator)
#   - fortress/modules/**/*.sh
#
# NO depende de aui/lib. Los modulos son independientes del installer.

#shellcheck disable=SC2034,SC2154,SC2155

# =============================================================================
# COLORS & PRINTING
# =============================================================================
if [[ -t 1 ]]; then
  Bold=$(tput bold)
  Reset=$(tput sgr0)
  Red=$(tput setaf 1)
  Green=$(tput setaf 2)
  Yellow=$(tput setaf 3)
  Blue=$(tput setaf 4)
  Purple=$(tput setaf 5)
  Cyan=$(tput setaf 6)
  White=$(tput setaf 7)
  BRed="${Bold}${Red}"
  BGreen="${Bold}${Green}"
  BYellow="${Bold}${Yellow}"
  BBlue="${Bold}${Blue}"
  BPurple="${Bold}${Purple}"
  BCyan="${Bold}${Cyan}"
  BWhite="${Bold}${White}"
else
  Bold=""; Reset=""; Red=""; Green=""; Yellow=""; Blue=""; Purple=""; Cyan=""; White=""
  BRed=""; BGreen=""; BYellow=""; BBlue=""; BPurple=""; BCyan=""; BWhite=""
fi

print_line()    { printf "%$(tput cols 2>/dev/null || echo 80)s\n" | tr ' ' '-'; }
print_title()   { clear 2>/dev/null; print_line; echo -e "  ${Bold}$*${Reset}"; print_line; }
print_info()    { echo -e "  ${BBlue}[i]${Reset} $*"; }
print_success() { echo -e "  ${BGreen}[✓]${Reset} $*"; }
print_warning() { echo -e "  ${BYellow}[!]${Reset} $*"; }
print_danger()  { echo -e "  ${BRed}[✗]${Reset} $*"; }
pause_function() { read -rp "${BYellow}[enter to continue]${Reset} "; }
invalid_option() { print_warning "Opción inválida."; }

# =============================================================================
# CHECKS
# =============================================================================
check_root() {
  [[ "$(id -u)" -eq 0 ]] || { print_danger "Debe ejecutarse como root"; exit 1; }
}
check_archlinux() {
  [[ -f /etc/arch-release ]] || { print_danger "Sólo Arch Linux"; exit 1; }
}

# =============================================================================
# PATHS & STATE
# =============================================================================
FORTRESS_VAR="/var/lib/aui-fortress"
FORTRESS_BACKUPS="${FORTRESS_VAR}/backups"
FORTRESS_STATE="${FORTRESS_VAR}/state"

# Crear dirs sólo si tenemos permisos (silencia errors al sourcear como non-root para help/describe)
mkdir -p "$FORTRESS_BACKUPS" "$FORTRESS_STATE" 2>/dev/null || true

# =============================================================================
# BACKUP & RESTORE
# =============================================================================
# backup_file <src-path> <module-name>
# Hace una copia inmutable del archivo original ANTES de modificarlo.
# Idempotente: si el backup ya existe, no lo sobreescribe.
backup_file() {
  local src="$1"
  local module="$2"
  local hashed
  hashed=$(echo "$src" | tr '/' '_')
  local backup_dir="${FORTRESS_BACKUPS}/${module}"
  mkdir -p "$backup_dir"
  local backup="${backup_dir}/${hashed}"
  if [[ -f "$src" && ! -f "$backup" ]]; then
    cp -a "$src" "$backup"
  fi
  echo "$backup"
}

# restore_file <src-path> <module-name>
# Restaura el archivo desde el backup. Levanta chattr +i si está.
restore_file() {
  local src="$1"
  local module="$2"
  local hashed
  hashed=$(echo "$src" | tr '/' '_')
  local backup="${FORTRESS_BACKUPS}/${module}/${hashed}"
  if [[ -f "$backup" ]]; then
    chattr -i "$src" 2>/dev/null || true
    cp -a "$backup" "$src"
    return 0
  fi
  return 1
}

# =============================================================================
# STATE MANAGEMENT
# =============================================================================
mark_active()   { touch "${FORTRESS_STATE}/${1}.active"; }
mark_inactive() { rm -f  "${FORTRESS_STATE}/${1}.active"; }
is_active()     { [[ -f  "${FORTRESS_STATE}/${1}.active" ]]; }

# =============================================================================
# PACKAGE MANAGEMENT
# =============================================================================
ensure_pkg() {
  local pkg="$1"
  if ! pacman -Q "$pkg" >/dev/null 2>&1; then
    print_info "Installing $pkg..."
    pacman -S --needed --noconfirm "$pkg" || {
      print_danger "Falló instalación de $pkg"
      return 1
    }
  fi
}

# =============================================================================
# USER DETECTION
# =============================================================================
detect_username() {
  local u="${SUDO_USER:-$(logname 2>/dev/null || true)}"
  [[ -z "$u" ]] && u=$(awk -F: '$3>=1000 && $3<65534 {print $1; exit}' /etc/passwd 2>/dev/null)
  echo "$u"
}

# =============================================================================
# MODULE PROTOCOL
# =============================================================================
# Cada módulo en modules/<category>/<name>.sh debe exponer 5 subcomandos:
#
#   <module>.sh apply       Aplica el módulo (idempotente)
#   <module>.sh rollback    Revierte. Restaura archivos desde backup
#   <module>.sh status      Imprime "active" | "inactive"
#   <module>.sh describe    Imprime "<name>|<category>|<short-desc>"
#   <module>.sh config      Imprime config/acciones previstas sin escribir cambios
#
# El orchestrator (fortress/fortress) los descubre y dispatcha.
# Cada módulo es STANDALONE — ejecutable directamente sin el menú.

# Boilerplate sugerida para nuevos módulos:
#
# #!/bin/bash
# MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# # shellcheck source=../../lib/common.sh
# source "${FORTRESS_ROOT}/lib/common.sh"
#
# MODULE_NAME="..."
# MODULE_CATEGORY="software"  # o "hardware"
# MODULE_DESC="..."
#
# apply()    { ...; mark_active "$MODULE_NAME"; }
# rollback() { ...; mark_inactive "$MODULE_NAME"; }
# status()   { is_active "$MODULE_NAME" && echo active || echo inactive; }
# config()   { ...; }
#
# case "${1:-help}" in
#   apply)    check_root; check_archlinux; apply ;;
#   rollback) check_root; check_archlinux; rollback ;;
#   status)   status ;;
#   describe) echo "$MODULE_NAME|$MODULE_CATEGORY|$MODULE_DESC" ;;
#   config)   config ;;
#   *) echo "Usage: $(basename "$0") {apply|rollback|status|describe|config}"; exit 1 ;;
# esac
