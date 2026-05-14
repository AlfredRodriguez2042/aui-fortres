#!/bin/bash
# Module: firewall
# Category: software
# Description: nftables con 6 perfiles (install/desktop/vpn-strict/gaming/maintenance/panic)
#
# Standalone. Ejecutable directo: ./firewall.sh apply

MODULE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
FORTRESS_ROOT="$(cd "${MODULE_DIR}/../.." && pwd)"
# shellcheck source=../../lib/common.sh
source "${FORTRESS_ROOT}/lib/common.sh"

MODULE_NAME="firewall"
MODULE_CATEGORY="software"
MODULE_DESC="nftables 6 perfiles (desktop default, panic, vpn-strict, gaming, maintenance, install)"
NFTABLES_DIR="${NFTABLES_DIR:-/etc/nftables.d}"

_write_profile_desktop() {
  cat > "${NFTABLES_DIR}/desktop.nft" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset

table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    ct state invalid drop

    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept
    ip6 saddr fe80::/10 udp dport 546 accept

    ip6 nexthdr icmpv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, mld-listener-query, mld-listener-report, mld2-listener-report } limit rate 10/second accept
    ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem } accept

    ip protocol icmp icmp type echo-request limit rate 5/second accept

    log prefix "DROP_IN: " level info limit rate 5/minute
    drop
  }
  chain forward {
    type filter hook forward priority 0; policy drop;
  }
  chain output {
    type filter hook output priority 0; policy drop;
    oif "lo" accept
    ct state established,related accept

    udp sport 68 udp dport 67 accept
    udp sport 546 udp dport 547 accept

    ip6 nexthdr icmpv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert, packet-too-big, mld-listener-report } accept
    ip protocol icmp limit rate 5/second accept

    udp dport 53 accept
    tcp dport 53 accept
    tcp dport { 80, 443 } accept
    udp dport 443 accept
    udp dport 123 accept

    log prefix "DROP_OUT: " level info limit rate 5/minute
    drop
  }
}
EOF
}

_write_profile_panic() {
  cat > "${NFTABLES_DIR}/panic.nft" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input  { type filter hook input  priority 0; policy drop; iif "lo" accept; drop; }
  chain forward{ type filter hook forward priority 0; policy drop; }
  chain output { type filter hook output priority 0; policy drop; oif "lo" accept; drop; }
}
EOF
}

_write_profile_vpn_strict() {
  cat > "${NFTABLES_DIR}/vpn-strict.nft" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    iif "tun0" accept
    ct state established,related accept
    ct state invalid drop
    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept
    ip6 saddr fe80::/10 udp dport 546 accept
    ip6 nexthdr icmpv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, mld-listener-query, mld-listener-report, mld2-listener-report } limit rate 10/second accept
    ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem } accept
    log prefix "DROP_VPN_IN: " level info limit rate 5/minute
    drop
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output {
    type filter hook output priority 0; policy drop;
    oif "lo" accept
    oif "tun0" accept
    ct state established,related accept
    udp sport 68 udp dport 67 accept
    udp sport 546 udp dport 547 accept
    ip6 nexthdr icmpv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert, packet-too-big } accept
    udp dport 53 accept
    tcp dport 53 accept
    udp dport 443 accept
    tcp dport 443 accept
    log prefix "DROP_VPN_OUT: " level info limit rate 5/minute
    drop
  }
}
EOF
}

_write_profile_maintenance() {
  cat > "${NFTABLES_DIR}/maintenance.nft" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input  { type filter hook input  priority 0; policy accept; }
  chain forward{ type filter hook forward priority 0; policy drop; }
  chain output { type filter hook output priority 0; policy accept; }
}
EOF
}

_write_profile_install() {
  cat > "${NFTABLES_DIR}/install.nft" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input  { type filter hook input  priority 0; policy drop; iif "lo" accept; ct state established,related accept; }
  chain forward{ type filter hook forward priority 0; policy drop; }
  chain output { type filter hook output priority 0; policy accept; }
}
EOF
}

# gaming = desktop + Steam/Discord ranges en output
_write_profile_gaming() {
  cat > "${NFTABLES_DIR}/gaming.nft" <<'EOF'
#!/usr/sbin/nft -f
flush ruleset
table inet filter {
  chain input {
    type filter hook input priority 0; policy drop;
    iif "lo" accept
    ct state established,related accept
    ct state invalid drop
    udp sport 67 udp dport 68 accept
    udp sport 547 udp dport 546 accept
    ip6 nexthdr icmpv6 icmpv6 type { nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert, mld-listener-query, mld-listener-report, mld2-listener-report } limit rate 10/second accept
    ip6 nexthdr icmpv6 icmpv6 type { destination-unreachable, packet-too-big, time-exceeded, parameter-problem } accept
    ip protocol icmp icmp type echo-request limit rate 5/second accept
    drop
  }
  chain forward { type filter hook forward priority 0; policy drop; }
  chain output {
    type filter hook output priority 0; policy drop;
    oif "lo" accept
    ct state established,related accept
    udp sport 68 udp dport 67 accept
    udp sport 546 udp dport 547 accept
    ip6 nexthdr icmpv6 icmpv6 type { nd-router-solicit, nd-neighbor-solicit, nd-neighbor-advert, packet-too-big } accept
    ip protocol icmp limit rate 5/second accept
    udp dport 53 accept
    tcp dport 53 accept
    tcp dport { 80, 443 } accept
    udp dport 443 accept
    udp dport 123 accept
    # Steam
    tcp dport { 27015-27050, 4380, 27036 } accept
    udp dport { 27000-27050, 3478, 4379-4380, 27031-27036 } accept
    # Discord voice
    udp dport 50000-65535 accept
    drop
  }
}
EOF
}

config() {
  local tmp
  tmp=$(mktemp -d)
  NFTABLES_DIR="$tmp"
  _write_profile_desktop
  _write_profile_panic
  _write_profile_vpn_strict
  _write_profile_maintenance
  _write_profile_install
  _write_profile_gaming

  local profile
  for profile in desktop panic vpn-strict maintenance install gaming; do
    echo "### /etc/nftables.d/${profile}.nft"
    cat "${tmp}/${profile}.nft"
    echo ""
  done
  rm -rf "$tmp"
}

apply() {
  print_title "MODULE: firewall"
  ensure_pkg nftables

  if systemctl is-active --quiet ufw 2>/dev/null || systemctl is-active --quiet firewalld 2>/dev/null; then
    print_danger "Otro firewall activo (ufw/firewalld). Detener antes."
    return 1
  fi

  mkdir -p "$NFTABLES_DIR"
  _write_profile_desktop
  _write_profile_panic
  _write_profile_vpn_strict
  _write_profile_maintenance
  _write_profile_install
  _write_profile_gaming

  ln -sf "${NFTABLES_DIR}/desktop.nft" /etc/nftables.conf
  nft -c -f /etc/nftables.conf || { print_danger "Sintaxis nftables inválida"; return 1; }

  systemctl enable --now nftables
  systemctl restart nftables

  mark_active "$MODULE_NAME"
  print_success "firewall activo. Perfil default: desktop."
  print_info "Cambiar perfil: ln -sf /etc/nftables.d/<profile>.nft /etc/nftables.conf && systemctl reload nftables"
}

rollback() {
  systemctl disable --now nftables 2>/dev/null
  rm -f /etc/nftables.conf
  rm -rf /etc/nftables.d
  mark_inactive "$MODULE_NAME"
  print_success "firewall desactivado."
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
