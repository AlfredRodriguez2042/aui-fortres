#!/bin/bash
# Module: triple-state
# Category: hardware
# Description: Sistema de 3 USBs (normal/maintenance/panic) — v2, roadmap
#
# STUB. Requiere v1 (fido2-unlock + buskill + panic) estable durante 30 días
# antes de activar. Por ahora documentado pero no implementado.

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="triple-state"
MODULE_CATEGORY="hardware"
MODULE_DESC="3 USBs (blanco normal / rojo maint / negro panic) — v2 roadmap, stub"

config() {
  cat <<'EOF'
# STUB v2: no escribe config todavía.
# Diseño previsto:
# - USB blanco: perfil desktop + modo normal
# - USB rojo: perfil maintenance + ventana administrativa
# - USB negro: perfil panic + poweroff forzado
# Requiere v1.5 estable 30+ días antes de implementarse.
EOF
}

apply() {
  print_title "MODULE: triple-state (STUB v2)"
  print_warning "triple-state está en roadmap v2."
  print_info "Precondiciones para activar:"
  echo "  1. v1 (fido2-unlock + buskill + panic) estable 30+ días"
  echo "  2. 3 USB físicos distintos disponibles"
  echo "  3. Procedimiento documentado de qué USB tocar en cada situación"
  print_info ""
  print_info "Por ahora, aplicar los módulos individuales correspondientes (buskill, panic) por separado."
  return 1
}

rollback() {
  print_info "Nada que hacer (v2 no implementado)."
}

status() { echo "not-implemented"; }
describe() { echo "${MODULE_NAME}|${MODULE_CATEGORY}|${MODULE_DESC}"; }

case "${1:-help}" in
  apply)    apply ;;
  rollback) rollback ;;
  status)   status ;;
  describe) describe ;;
  config)   config ;;
  *) echo "Usage: $(basename "$0") {apply|rollback|status|describe|config}"; exit 1 ;;
esac
