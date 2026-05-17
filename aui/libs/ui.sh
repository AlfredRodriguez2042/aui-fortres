#!/bin/bash

# -------------------------------------------------------------------
# AUI-X UI, prompts, and small input helpers
# -------------------------------------------------------------------

_aui_tput() { tput "$@" 2>/dev/null || true; }

checklist=(0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0 0)

Bold=$(_aui_tput bold)
Underline=$(_aui_tput sgr 0 1)
Reset=$(_aui_tput sgr0)
Red=$(_aui_tput setaf 1)
Green=$(_aui_tput setaf 2)
Yellow=$(_aui_tput setaf 3)
Blue=$(_aui_tput setaf 4)
Purple=$(_aui_tput setaf 5)
Cyan=$(_aui_tput setaf 6)
White=$(_aui_tput setaf 7)

BRed=${Bold}${Red}
BGreen=${Bold}${Green}
BYellow=${Bold}${Yellow}
BBlue=${Bold}${Blue}
BPurple=${Bold}${Purple}
BCyan=${Bold}${Cyan}
BWhite=${Bold}${White}

prompt1="Enter your option: "
prompt2="Enter n° of options (ex: 1 2 3 or 1-3): "
prompt3="You have to manually enter the following commands, then press ${BYellow}ctrl+d${Reset} or type ${BYellow}exit${Reset}:"

AUTOMATIC_MODE=${AUTOMATIC_MODE:-0}
if [[ -f /usr/bin/vim ]]; then
  EDITOR="vim"
elif [[ -z ${EDITOR:-} ]]; then
  EDITOR="nano"
fi

EFI_MOUNTPOINT="/boot"
ROOT_MOUNTPOINT="/dev/sda1"
BOOT_MOUNTPOINT="/dev/sda"
MOUNTPOINT="${MOUNTPOINT:-/mnt}"

ARCHI=$(uname -m)
UEFI=0
LVM=0
LUKS=0
LUKS_DISK="sda2"
KERNEL_PRIMARY="linux-zen"
AUI_DIR=$(pwd)
LOG="${AUI_DIR}/$(basename "$0").log"
XPINGS=0
TRIM=0

# -------------------------------------------------------------------
# Output / input helpers
# -------------------------------------------------------------------

error_msg() {
  echo -e "$1"
  exit 1
}

_term_cols() {
  local cols
  cols=$(tput cols 2>/dev/null || true)
  [[ "$cols" =~ ^[0-9]+$ && $cols -gt 0 ]] && printf "%s" "$cols" || printf "%s" 80
}

print_line() {
  printf "%$(_term_cols)s\n" | tr ' ' '-'
}

print_title() {
  clear 2>/dev/null || true
  print_line
  echo -e "# ${Bold}$1${Reset}"
  print_line
  echo ""
}

print_info() {
  local cols width
  cols=$(_term_cols)
  ((cols > 20)) && width=$((cols - 18)) || width=$cols
  echo -e "${Bold}$1${Reset}\n" | fold -sw "$width" | sed 's/^/\t/'
}

print_warning() {
  local cols width
  cols=$(_term_cols)
  ((cols > 1)) && width=$((cols - 1)) || width=80
  echo -e "${BYellow}$1${Reset}\n" | fold -sw "$width"
}

print_danger() {
  local cols width
  cols=$(_term_cols)
  ((cols > 1)) && width=$((cols - 1)) || width=80
  echo -e "${BRed}$1${Reset}\n" | fold -sw "$width"
}

print_success() {
  local cols width
  cols=$(_term_cols)
  ((cols > 1)) && width=$((cols - 1)) || width=80
  echo -e "${BGreen}OK: $1${Reset}\n" | fold -sw "$width"
}

print_error() {
  local cols width
  cols=$(_term_cols)
  ((cols > 1)) && width=$((cols - 1)) || width=80
  echo -e "${BRed}ERROR: $1${Reset}\n" | fold -sw "$width" >&2
}

normalize_yes_no() {
  local answer
  answer=$(printf "%s" "${1:-}" | tr '[:upper:]' '[:lower:]')
  case "$answer" in
    y|yes) printf "%s" "y" ;;
    n|no) printf "%s" "n" ;;
    "") printf "%s" "" ;;
    *) return 1 ;;
  esac
}

read_confirm() {
  local prompt="${1}"
  local default="${2:-n}"
  local auto_answer="${3:-}"
  local label answer

  default=$(normalize_yes_no "$default") || error_msg "Invalid default confirmation value: $default"
  [[ "$default" == "y" ]] && label="[Y/n]" || label="[y/N]"

  if [[ $AUTOMATIC_MODE -eq 1 ]]; then
    answer=$(normalize_yes_no "${auto_answer:-$default}") || error_msg "Invalid automatic confirmation value: ${auto_answer}"
    OPTION="${answer:-$default}"
    return 0
  fi

  while true; do
    printf "%s" "${prompt} ${label}: "
    read -r OPTION
    echo ""
    [[ -z "$OPTION" ]] && { OPTION="$default"; return 0; }
    answer=$(normalize_yes_no "$OPTION") && { OPTION="$answer"; return 0; }
    print_warning "Responde yes/no (y/n), en mayusculas o minusculas."
  done
}

read_input_text() {
  read_confirm "$1" "n" "${2:-}"
}

confirm_destructive_action() {
  local prompt="$1"
  local default="${2:-n}"
  local auto_answer="${3:-}"

  read_confirm "$prompt" "$default" "$auto_answer"
  [[ "$OPTION" == "y" ]]
}

read_input_options() {
  local raw line i
  local packages=()

  if [[ $AUTOMATIC_MODE -eq 1 ]]; then
    raw="${1:-}"
  else
    printf "%s" "$prompt2"
    read -r raw
  fi

  for line in ${raw//,/ }; do
    if [[ "$line" =~ ^[0-9]+-[0-9]+$ ]]; then
      for ((i = ${line%-*}; i <= ${line#*-}; i++)); do
        packages+=("$i")
      done
    elif [[ -n "$line" ]]; then
      packages+=("$line")
    fi
  done

  OPTIONS=("${packages[@]}")
}

read_size() {
  local prompt="$1" default="$2" min_gb="$3"
  local -n out_ref="$4"
  local input num unit normalized gb

  while true; do
    printf "%s [ej: %s, minimo sugerido %sG]: " "$prompt" "$default" "$min_gb"
    read -r input
    input="${input:-$default}"
    input="${input// /}"

    if [[ "$input" =~ ^([0-9]+)([GgMm][Bb]?)?$ ]]; then
      num="${BASH_REMATCH[1]}"
      unit="${BASH_REMATCH[2]^^}"
      unit="${unit%B}"
      [[ -z "$unit" ]] && unit="G"
      normalized="${num}${unit}"
      [[ "$unit" == "G" ]] && gb="$num" || gb=$((num / 1024))

      if ((gb < min_gb)); then
        print_warning "${normalized} es menor que el sugerido ${min_gb}G; se acepta como placeholder."
      fi

      out_ref="$normalized"
      return 0
    fi

    print_warning "Formato invalido: '$input'. Usa por ejemplo: 30, 30G, 500M."
  done
}

checkbox() {
  [[ "$1" -eq 1 ]] && echo -e "${BBlue}[${Reset}${Bold}X${BBlue}]${Reset}" || echo -e "${BBlue}[ ${BBlue}]${Reset}"
}

mainmenu_item() {
  local done="$1" label="$2" value="${3:-}" state=""
  [[ "$done" == 1 && -n "$value" ]] && state="${BGreen}[${Reset}${value}${BGreen}]${Reset}"
  echo -e "$(checkbox "$done") ${Bold}${label}${Reset} ${state}"
}

invalid_option() {
  print_line
  echo "Invalid option. Try another one."
  pause_function
}

pause_function() {
  print_line
  if [[ $AUTOMATIC_MODE -eq 0 ]]; then
    read -e -sn 1 -p "Press enter to continue..."
  fi
}
