# -------------------------------------------------------------------
# Environment checks
# -------------------------------------------------------------------

check_dependency() {
  command -v "$1" &>/dev/null || error_msg "Missing dependency: $1"
}

check_boot_system() {
  local vendor
  vendor=$(cat /sys/class/dmi/id/sys_vendor 2>/dev/null || true)

  if [[ "$vendor" == "Apple Inc." || "$vendor" == "Apple Computer, Inc." ]]; then
    modprobe -r -q efivars || true
  else
    modprobe -q efivarfs || true
  fi

  if [[ -d /sys/firmware/efi ]]; then
    if ! mount | grep -q /sys/firmware/efi/efivars; then
      mount -t efivarfs efivarfs /sys/firmware/efi/efivars
    fi
    UEFI=1
    echo "UEFI Mode detected"
  else
    error_msg "ERROR! AUI-X requiere UEFI. Arranca el ISO en modo UEFI y vuelve a ejecutar el installer."
  fi
}

check_trim() {
  TRIM=0
  if lsblk -dn -o DISC-GRAN 2>/dev/null | awk '$1 != "" && $1 != "0" && $1 != "0B" {found=1} END {exit found ? 0 : 1}'; then
    TRIM=1
  fi
}

check_root() {
  [[ "$(id -u)" == "0" ]] || error_msg "ERROR! You must execute the script as the 'root' user."
}

check_archlinux() {
  [[ -e /etc/arch-release ]] || error_msg "ERROR! You must execute the script on Arch Linux."
}

check_connection() {
  local connection_opts wired_dev wireless_dev
  XPINGS=$((XPINGS + 1))

  ping -q -w 1 -c 1 "$(ip r | awk '/default/ {print $3; exit}')" &>/dev/null && return 0

  wired_dev=$(ip link | awk -F': ' '/: (ens|eno|enp)/ {print $2; exit}')
  wireless_dev=$(ip link | awk -F': ' '/: wlp/ {print $2; exit}')
  print_warning "ERROR! Connection not Found."
  print_info "Network Setup"
  connection_opts=("Wired Automatic" "Wired Manual" "Wireless" "Configure Proxy" "Skip")
  PS3="$prompt1"

  select CONNECTION_TYPE in "${connection_opts[@]}"; do
    case "$REPLY" in
      1)
        systemctl start dhcpcd@"${wired_dev}".service
        break
        ;;
      2)
        systemctl stop dhcpcd@"${wired_dev}".service
        printf "%s" "IP Address: "
        read -r IP_ADDR
        printf "%s" "Submask: "
        read -r SUBMASK
        printf "%s" "Gateway: "
        read -r GATEWAY
        ip link set "${wired_dev}" up
        ip addr add "${IP_ADDR}/${SUBMASK}" dev "${wired_dev}"
        ip route add default via "${GATEWAY}"
        "$EDITOR" /etc/resolv.conf
        break
        ;;
      3)
        wifi-menu "${wireless_dev}"
        break
        ;;
      4)
        printf "%s" "Enter your proxy e.g. protocol://address:port: "
        read -r OPTION
        export http_proxy=$OPTION
        export https_proxy=$OPTION
        export ftp_proxy=$OPTION
        echo "proxy = $OPTION" >~/.curlrc
        break
        ;;
      5)
        break
        ;;
      *)
        invalid_option
        ;;
    esac
  done

  if [[ $XPINGS -gt 2 ]]; then
    print_warning "Can't establish connection. exiting..."
    exit 1
  fi
  [[ $REPLY -ne 5 ]] && check_connection
}

# -------------------------------------------------------------------
# Installed-system configuration helpers
# -------------------------------------------------------------------

arch_chroot() {
  if [[ $# -eq 0 ]]; then
    print_error "arch_chroot called without command"
    return 2
  fi

  if [[ $# -eq 1 ]]; then
    arch-chroot "$MOUNTPOINT" /bin/bash -c "$1"
  else
    arch-chroot "$MOUNTPOINT" "$@"
  fi
}

write_zen_tuning() {
  local mnt="$1"
  mkdir -p "$mnt"/etc/sysctl.d "$mnt"/etc/udev/rules.d "$mnt"/etc/modprobe.d \
           "$mnt"/etc/systemd "$mnt"/etc/systemd/resolved.conf.d \
           "$mnt"/etc/NetworkManager/conf.d

  cat > "$mnt"/etc/sysctl.d/99-zen-net.conf <<'EOF'
net.core.default_qdisc = fq
net.ipv4.tcp_congestion_control = bbr
net.ipv4.tcp_fastopen = 3
net.ipv4.tcp_mtu_probing = 1
net.core.netdev_max_backlog = 16384
net.core.somaxconn = 8192
net.ipv4.tcp_rfc1337 = 1
net.ipv4.tcp_syncookies = 1
net.ipv4.conf.all.rp_filter = 1
net.ipv4.conf.default.rp_filter = 1
net.ipv4.conf.all.accept_redirects = 0
net.ipv4.conf.default.accept_redirects = 0
net.ipv4.conf.all.send_redirects = 0
net.ipv4.conf.all.accept_source_route = 0
net.ipv4.conf.default.accept_source_route = 0
net.ipv4.conf.all.log_martians = 1
net.ipv6.conf.all.use_tempaddr = 2
net.ipv6.conf.default.use_tempaddr = 2
net.ipv6.conf.all.accept_redirects = 0
net.ipv6.conf.default.accept_redirects = 0
net.ipv6.conf.all.accept_source_route = 0
net.ipv6.conf.default.accept_source_route = 0
EOF

  cat > "$mnt"/etc/sysctl.d/99-zen-vm.conf <<'EOF'
vm.swappiness = 180
vm.page-cluster = 0
vm.watermark_boost_factor = 0
vm.watermark_scale_factor = 125
vm.vfs_cache_pressure = 50
vm.dirty_bytes = 268435456
vm.dirty_background_bytes = 67108864
fs.inotify.max_user_watches = 524288
fs.inotify.max_user_instances = 8192
kernel.split_lock_mitigate = 0
EOF

  cat > "$mnt"/etc/udev/rules.d/60-ioschedulers.rules <<'EOF'
ACTION=="add|change", KERNEL=="nvme[0-9]n[0-9]", ATTR{queue/scheduler}="none"
ACTION=="add|change", KERNEL=="sd[a-z]|mmcblk[0-9]*", ATTR{queue/rotational}=="0", ATTR{queue/scheduler}="mq-deadline"
ACTION=="add|change", KERNEL=="sd[a-z]", ATTR{queue/rotational}=="1", ATTR{queue/scheduler}="bfq"
EOF

  cat > "$mnt"/etc/modprobe.d/zen-tuning.conf <<'EOF'
blacklist pcspkr
blacklist snd_pcsp
options snd_hda_intel power_save=1 power_save_controller=Y
EOF

  cat > "$mnt"/etc/systemd/zram-generator.conf <<'EOF'
[zram0]
zram-size = min(ram / 2, 8192)
compression-algorithm = zstd
swap-priority = 100
fs-type = swap
EOF

  cat > "$mnt"/etc/systemd/resolved.conf.d/10-aui-x.conf <<'EOF'
[Resolve]
DNSSEC=allow-downgrade
DNSOverTLS=opportunistic
Cache=yes
FallbackDNS=1.1.1.1 9.9.9.9 2606:4700:4700::1111 2620:fe::fe
EOF

  cat > "$mnt"/etc/nftables.conf <<'EOF'
#!/usr/bin/nft -f
flush ruleset

table inet filter {
    chain input {
        type filter hook input priority filter; policy drop;
        iif lo accept
        iif != lo ip daddr 127.0.0.0/8 drop
        iif != lo ip6 daddr ::1 drop
        ct state established,related accept
        ct state invalid drop
        ip protocol icmp icmp type { echo-request, destination-unreachable, time-exceeded, parameter-problem } accept
        ip6 nexthdr icmpv6 icmpv6 type {
            destination-unreachable, packet-too-big, time-exceeded, parameter-problem,
            echo-request, nd-router-advert, nd-neighbor-solicit, nd-neighbor-advert,
            mld-listener-query, mld-listener-report, mld-listener-reduction
        } accept
        udp dport 546 ct state new accept
        counter drop
    }

    chain forward {
        type filter hook forward priority filter; policy drop;
    }

    chain output {
        type filter hook output priority filter; policy accept;
    }
}
EOF
  chmod 0644 "$mnt"/etc/nftables.conf

  cat > "$mnt"/etc/NetworkManager/conf.d/dns.conf <<'EOF'
[main]
dns=systemd-resolved
rc-manager=symlink
EOF

  cat > "$mnt"/etc/NetworkManager/conf.d/wifi-backend.conf <<'EOF'
[device]
wifi.backend=iwd
EOF
}

generate_loader_entries() {
  local mnt="$1" esp="$2" kernel_primary="$3" cmdline="$4" ucode_lines="$5"
  local esp_rel="${esp#/}"

  mkdir -p "$mnt/$esp_rel/loader/entries"
  cat > "$mnt/$esp_rel/loader/loader.conf" <<EOF
default  arch.conf
timeout  3
console-mode max
editor   no
EOF

  cat > "$mnt/$esp_rel/loader/entries/arch.conf" <<EOF
title    Arch Linux (${kernel_primary})
linux    /vmlinuz-${kernel_primary}
${ucode_lines}initrd   /initramfs-${kernel_primary}.img
options  ${cmdline}
EOF

  if arch-chroot "$mnt" pacman -Q linux-lts &>/dev/null; then
    cat > "$mnt/$esp_rel/loader/entries/arch-lts.conf" <<EOF
title    Arch Linux (linux-lts) - RECOVERY
linux    /vmlinuz-linux-lts
${ucode_lines}initrd   /initramfs-linux-lts.img
options  ${cmdline}
EOF
  fi

  cat > "$mnt/$esp_rel/loader/entries/rescue.conf" <<EOF
title    Arch Linux RESCUE (single user, LTS)
linux    /vmlinuz-linux-lts
${ucode_lines}initrd   /initramfs-linux-lts.img
options  ${cmdline} systemd.unit=rescue.target
EOF
}

is_package_installed() {
  local pkg
  for pkg in $1; do
    pacman -Q "$pkg" &>/dev/null && return 0
  done
  return 1
}

contains_element() {
  local match="$1" item
  shift
  for item in "$@"; do
    [[ "$item" == "$match" ]] && return 0
  done
  return 1
}

setlocale() {
  local locale_list=()

  mapfile -t locale_list < <(grep UTF-8 /etc/locale.gen | sed 's/\..*$//' | sed '/@/d' | awk '{print $1}' | uniq | sed 's/#//g')
  PS3="$prompt1"
  echo "Select locale:"
  select LOCALE in "${locale_list[@]}"; do
    if [[ -n "${LOCALE:-}" ]]; then
      LOCALE_UTF8="${LOCALE}.UTF-8"
      break
    fi
    invalid_option
  done
}

settimezone() {
  local zones=()
  local subzones=()

  mapfile -t zones < <(timedatectl list-timezones | sed 's/\/.*$//' | uniq)
  PS3="$prompt1"
  echo "Select zone:"
  select ZONE in "${zones[@]}"; do
    if [[ -n "${ZONE:-}" ]]; then
      mapfile -t subzones < <(timedatectl list-timezones | grep "^${ZONE}/" | sed 's/^.*\///')
      PS3="$prompt1"
      echo "Select subzone:"
      select SUBZONE in "${subzones[@]}"; do
        [[ -n "${SUBZONE:-}" ]] && break
        invalid_option
      done
      break
    fi
    invalid_option
  done
}
