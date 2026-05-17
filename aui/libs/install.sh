#!/bin/bash

# -------------------------------------------------------------------
# Phase 1 installer helpers
# -------------------------------------------------------------------

install_live_deps() {
  local live_deps=()
  command -v nano      &>/dev/null || live_deps+=(nano)
  command -v reflector &>/dev/null || live_deps+=(reflector)
  command -v parted    &>/dev/null || live_deps+=(parted)
  command -v mkfs.vfat &>/dev/null || live_deps+=(dosfstools)
  command -v mkfs.btrfs &>/dev/null || live_deps+=(btrfs-progs)
  command -v mkfs.ext4 &>/dev/null || live_deps+=(e2fsprogs)
  command -v cryptsetup &>/dev/null || live_deps+=(cryptsetup)
  command -v pvcreate  &>/dev/null || live_deps+=(lvm2)

  if [[ ${#live_deps[@]} -gt 0 ]]; then
    pacman -Sy --noconfirm --needed "${live_deps[@]}" || {
      echo "FATAL: could not install live tools: ${live_deps[*]}" >&2
      exit 1
    }
  fi

  EDITOR="nano"
}

select_keymap() {
  print_title "KEYMAP"
  PS3="$prompt1"
  print_info "Console keymap (editable post-install in /etc/vconsole.conf)."
  select KEYMAP in us la-latin1 es br-abnt2 pt-latin1 uk de-latin1 fr-latin1 it dvorak; do
    [[ -n "$KEYMAP" ]] && { loadkeys "$KEYMAP" && break; } || invalid_option
  done
  state[keymap]="$KEYMAP"
}

configure_mirrorlist() {
  print_title "MIRRORLIST"
  [[ -f /etc/pacman.d/mirrorlist ]] && cp /etc/pacman.d/mirrorlist /etc/pacman.d/mirrorlist.bak
  reflector --protocol https --latest 20 --fastest 10 --sort rate --save /etc/pacman.d/mirrorlist ||
    print_warning "reflector failed — using current mirrorlist"
  print_success "Mirrorlist generated."
}

configure_keymap() {
  echo "KEYMAP=${state[keymap]}" > "$MOUNTPOINT/etc/vconsole.conf"
}

clear_luks_state() {
  state[luks]=0
  state[luks_disk]=""
  state[luks_targets]=""
  state[luks_mappers]=""
  state[root_luks_mapper]=""
  state[luks_devices]=""
}

select_device() {
  mapfile -t devices_list < <(lsblk -d | awk '{print "/dev/" $1}' | grep -E 'sd|hd|vd|nvme|mmcblk')
  if [[ ${#devices_list[@]} -eq 0 ]]; then
    print_error "No disks detected."
    return 1
  fi
  devices_list+=("Back")
  PS3="$prompt1"
  echo -e "Attached devices:\n"
  lsblk -lnp -I 2,3,8,9,22,34,56,57,58,65,66,67,68,69,70,71,72,91,128,129,130,131,132,133,134,135,259 | awk '{print $1,$4,$6,$7}' | column -t
  echo -e "\nSelect device to partition (or 'Back' to abort):\n"
  select device in "${devices_list[@]}"; do
    [[ "$device" == "Back" ]] && return 1
    [[ -n "$device" ]] && break
    invalid_option
  done
  state[device]="$device"
}

reset_partition_state() {
  clear_luks_state
  state[lvm]=0
  state[partition_layout]=""
  state[partition_mode]=""
  state[root_part]=""
  state[root_device]=""
  state[filesystem]=""
  state[esp]=""
  state[extra_mounts]=""
}

partition_path() {
  local disk="$1" num="$2"
  case "$disk" in
    *[0-9]) printf "%sp%s\n" "$disk" "$num" ;;
    *)      printf "%s%s\n" "$disk" "$num" ;;
  esac
}

wait_for_block() {
  local dev="$1" i
  for i in {1..30}; do
    [[ -b "$dev" ]] && return 0
    partprobe "${state[device]:-}" 2>/dev/null || true
    udevadm settle 2>/dev/null || true
    sleep 0.2
  done
  [[ -b "$dev" ]]
}

describe_partition() {
  local dev="$1"
  lsblk -no NAME,SIZE,FSTYPE,LABEL,MOUNTPOINT "$dev" 2>/dev/null | awk '{$1=$1; print}'
}

select_partition_mode() {
  local opts=("Automatic root disk (erase one disk)" "Existing partitions (reinstall/preserve disks)" "Back")
  PS3="$prompt1"
  print_title "PARTITION MODE"
  print_info "Automatic only touches one selected root disk. Existing partitions lets you reuse root/ESP and preserve /home or data disks."
  select OPT in "${opts[@]}"; do
    case "$OPT" in
      "Automatic root disk"*) state[partition_mode]="automatic"; return 0 ;;
      "Existing partitions"*) state[partition_mode]="existing"; return 0 ;;
      "Back") return 1 ;;
      *) invalid_option ;;
    esac
  done
}

select_storage_strategy() {
  local opts=("Encrypted root (LUKS)" "Plain root (no encryption)" "Back")
  PS3="$prompt1"
  print_title "STORAGE STRATEGY"
  select OPT in "${opts[@]}"; do
    case "$OPT" in
      "Encrypted root"*) state[partition_layout]="luks"; return 0 ;;
      "Plain root"*) state[partition_layout]="plain"; return 0 ;;
      "Back") return 1 ;;
      *) invalid_option ;;
    esac
  done
}

select_esp_size() {
  local opts=("1G (recommended)" "600M" "Back")
  PS3="$prompt1"
  echo "Select EFI System Partition size:"
  select OPT in "${opts[@]}"; do
    case "$OPT" in
      "1G"*) state[esp_size_label]="1G"; state[esp_end]="1025MiB"; return 0 ;;
      "600M") state[esp_size_label]="600M"; state[esp_end]="601MiB"; return 0 ;;
      "Back") return 1 ;;
      *) invalid_option ;;
    esac
  done
}

guided_partition_root_disk() {
  local disk="${state[device]}" confirm esp root

  select_esp_size || return 1
  print_danger "DESTRUCTIVE: $disk will be erased and repartitioned."
  print_danger "Only this selected root disk is touched. Other disks are preserved."
  read -rp "Type '$disk' to confirm erase: " confirm
  if [[ "$confirm" != "$disk" ]]; then
    print_warning "Confirmation did not match. Aborting automatic partitioning."
    return 1
  fi

  wipefs -af "$disk" || { print_error "wipefs failed on $disk"; return 1; }
  parted -s "$disk" mklabel gpt || return 1
  parted -s -a optimal "$disk" mkpart "EFI System" fat32 1MiB "${state[esp_end]}" || return 1
  parted -s "$disk" set 1 esp on || return 1
  parted -s -a optimal "$disk" mkpart "Linux root" btrfs "${state[esp_end]}" 100% || return 1
  partprobe "$disk" 2>/dev/null || true
  udevadm settle 2>/dev/null || true

  esp=$(partition_path "$disk" 1)
  root=$(partition_path "$disk" 2)
  wait_for_block "$esp" || { print_error "ESP partition did not appear: $esp"; return 1; }
  wait_for_block "$root" || { print_error "Root partition did not appear: $root"; return 1; }

  state[esp]="$esp"
  state[root_part]="$root"
  print_success "Automatic layout created: $esp (${state[esp_size_label]} ESP), $root (root)."
}

select_existing_root_partition() {
  local parts=() part
  mapfile -t parts < <(lsblk -lnpo NAME,TYPE | awk '$2=="part"{print $1}')
  local candidates=()
  for part in "${parts[@]}"; do
    is_efi_system_partition "$part" && continue
    candidates+=("$part")
  done
  if [[ ${#candidates[@]} -eq 0 ]]; then
    print_error "No root partition candidates found."
    return 1
  fi
  candidates+=("Cancel")
  PS3="$prompt1"
  print_title "EXISTING ROOT PARTITION"
  for part in "${candidates[@]}"; do
    [[ "$part" == "Cancel" ]] && continue
    printf "  %s  %s\n" "$part" "$(describe_partition "$part")"
  done
  echo ""
  select part in "${candidates[@]}"; do
    [[ "$part" == "Cancel" ]] && return 1
    [[ -n "$part" ]] && { state[root_part]="$part"; return 0; }
    invalid_option
  done
}

select_existing_esp() {
  local parts=() part candidates=()
  mapfile -t parts < <(lsblk -lnpo NAME,TYPE | awk '$2=="part"{print $1}')
  for part in "${parts[@]}"; do
    is_efi_system_partition "$part" && candidates+=("$part")
  done
  if [[ ${#candidates[@]} -eq 0 ]]; then
    print_error "No EFI System Partition found."
    return 1
  fi
  candidates+=("Cancel")
  PS3="$prompt1"
  print_title "EFI SYSTEM PARTITION"
  for part in "${candidates[@]}"; do
    [[ "$part" == "Cancel" ]] && continue
    printf "  %s  %s\n" "$part" "$(describe_partition "$part")"
  done
  echo ""
  select part in "${candidates[@]}"; do
    [[ "$part" == "Cancel" ]] && return 1
    [[ -n "$part" ]] && { state[esp]="$part"; return 0; }
    invalid_option
  done
}

prepare_root_device() {
  local root_part="$1" mapper_path new_root
  state[root_part]="$root_part"

  if [[ "${state[partition_layout]}" == "luks" ]]; then
    state[luks]=1
    state[luks_disk]="$root_part"
    state[root_luks_mapper]="cryptroot"
    state[luks_targets]="$root_part"
    state[luks_mappers]="cryptroot"
    print_danger "Encrypting $root_part will destroy any existing filesystem/data on it."
    mapper_path=$(luks_format "$root_part" "$TRIM" "${state[root_luks_mapper]}") || {
      print_error "LUKS format failed for $root_part"
      return 1
    }
    state[luks_devices]="$mapper_path"
    state[root_device]="$mapper_path"

    read_input_text "Use LVM on top of the encrypted root?"
    if [[ $OPTION == y ]]; then
      new_root=$(setup_lvm "${state[root_device]}" "lvm" "root") || {
        print_error "LVM setup failed"
        return 1
      }
      state[root_device]="$new_root"
      state[lvm]=1
    fi
  else
    clear_luks_state
    state[root_device]="$root_part"
  fi
}

confirm_existing_root_reformat() {
  local confirm
  [[ "${state[partition_mode]}" != "existing" ]] && return 0

  print_danger "DESTRUCTIVE: ${state[root_part]} will be formatted as the new root."
  if [[ "${state[partition_layout]}" == "luks" ]]; then
    print_danger "It will first be overwritten with LUKS encryption."
  fi
  read -rp "Type '${state[root_part]}' to confirm root reinstall: " confirm
  if [[ "$confirm" != "${state[root_part]}" ]]; then
    print_warning "Confirmation did not match. Root partition was not touched."
    return 1
  fi
}

mount_selected_esp() {
  local format_mode="${1:-ask}" esp="${state[esp]}"
  if [[ "$format_mode" == "always" ]]; then
    mkfs.vfat -F32 "$esp" || { print_error "mkfs.vfat failed"; return 1; }
  else
    read_input_text "Format $esp as FAT32?"
    if [[ $OPTION == y ]]; then
      mkfs.vfat -F32 "$esp" || { print_error "mkfs.vfat failed"; return 1; }
    fi
  fi
  mkdir -p "$MOUNTPOINT/boot"
  mount_vfat "$esp" "$MOUNTPOINT/boot" || { print_error "ESP mount failed"; return 1; }
}

run_partition_strategy() {
  confirm_existing_root_reformat || return 1
  prepare_root_device "${state[root_part]}" || return 1
  choose_filesystem || return 1

  print_info "Formatting and mounting root"
  format_and_mount_root "${state[root_device]}" "${state[filesystem]}" "$MOUNTPOINT" "$TRIM" || {
    print_error "Root format/mount failed"
    return 1
  }

  if [[ "${state[partition_mode]}" == "automatic" ]]; then
    mount_selected_esp always || return 1
  else
    mount_selected_esp ask || return 1
  fi

  mount_extra_partitions || return 1
}

# -------------------------------------------------------------------
# Paso 2: Particionado completo (orquestador)
# -------------------------------------------------------------------
step_partitioning() {
  umount_partitions
  reset_partition_state

  select_partition_mode || return 1
  select_storage_strategy || return 1

  case "${state[partition_mode]}" in
    automatic)
      select_device || return 1
      guided_partition_root_disk || return 1
      ;;
    existing)
      select_existing_root_partition || return 1
      select_existing_esp || return 1
      ;;
    *)
      print_error "Unknown partition mode: ${state[partition_mode]}"
      return 1
      ;;
  esac

  run_partition_strategy
}

choose_extra_filesystem() {
  local fss=("ext4" "btrfs" "vfat" "Back")
  PS3="$prompt1"
  select fs in "${fss[@]}"; do
    [[ "$fs" == "Back" ]] && return 1
    [[ -n "$fs" ]] && { extra_fs="$fs"; return 0; }
    invalid_option
  done
}

mount_extra_partitions() {
  local candidates part mount_dir target format_choice extra_fs

  while true; do
    mapfile -t candidates < <(list_extra_candidates "$MOUNTPOINT" "${state[root_device]}" "${state[esp]}" "${state[luks_disk]}" "${state[luks_targets]} ${state[luks_devices]}")
    if [[ ${#candidates[@]} -eq 0 ]]; then
      print_info "No extra partitions available to mount."
      return 0
    fi

    read_input_text "Mount another existing partition/disk now?"
    [[ $OPTION == y ]] || return 0

    candidates+=("Cancel")
    PS3="$prompt1"
    echo "Select extra partition:"
    select part in "${candidates[@]}"; do
      [[ "$part" == "Cancel" ]] && return 0
      [[ -n "$part" ]] && break
      invalid_option
    done

    while true; do
      read -rp "Mount point inside the new system [e.g. /home, /home/media, /data]: " mount_dir
      if [[ "$mount_dir" == /* && "$mount_dir" != "/" && "$mount_dir" != "/boot" && "$mount_dir" != "/boot/efi" ]]; then
        break
      fi
      print_warning "Use an absolute mount point below /, but not /, /boot, or /boot/efi."
    done

    target="$MOUNTPOINT$mount_dir"
    if findmnt -n "$target" &>/dev/null; then
      read_input_text "$mount_dir is already mounted by the root layout. Replace that mount?"
      [[ $OPTION == y ]] || continue
      umount "$target" || { print_error "Could not unmount $target"; return 1; }
    fi

    read_input_text "Format $part before mounting? This erases data."
    format_choice="$OPTION"
    if [[ "$format_choice" == y ]]; then
      choose_extra_filesystem || continue
      format_and_mount_extra "$part" "$extra_fs" "$target" "$TRIM" || {
        print_error "Could not format and mount $part on $mount_dir"
        return 1
      }
    else
      mount_extra "$part" "$target" || {
        print_error "Could not mount $part on $mount_dir"
        return 1
      }
    fi

    state[extra_mounts]="${state[extra_mounts]}${part}:${mount_dir} "
    print_success "$part mounted on $mount_dir"
  done
}

choose_filesystem() {
  local fss=("btrfs" "ext4" "Back")
  PS3="$prompt1"
  print_info "btrfs (recommended): snapshots, zstd compress."
  print_info "ext4: conservative, no snapshots."
  select fs in "${fss[@]}"; do
    [[ "$fs" == "Back" ]] && return 1
    [[ -n "$fs" ]] && { state[filesystem]="$fs"; return 0; }
    invalid_option
  done
}

configure_efi_nvram() {
  local esp_dev="$1"
  local disk part_num bm_out bootnum current_order new_order entry

  if [[ ! -d /sys/firmware/efi/efivars ]]; then
    print_warning "efivarfs not available; boot will rely on /EFI/BOOT/BOOTX64.EFI fallback."
    return 0
  fi

  disk=$(lsblk -no PKNAME "$esp_dev" 2>/dev/null | head -1)
  part_num=$(lsblk -no PARTN "$esp_dev" 2>/dev/null | head -1)
  if [[ -z "$disk" || -z "$part_num" ]]; then
    print_warning "Could not resolve disk/partition for $esp_dev; fallback BOOTX64.EFI is present."
    return 0
  fi

  arch_chroot "efibootmgr --create --disk /dev/${disk} --part ${part_num} --label 'Linux Boot Manager' --loader '\\EFI\\systemd\\systemd-bootx64.efi'" \
    || print_warning "efibootmgr could not create/update NVRAM entry; fallback BOOTX64.EFI is present."

  bm_out=$(arch_chroot "efibootmgr -v 2>/dev/null" 2>/dev/null || true)
  bootnum=$(awk '
    BEGIN { IGNORECASE=1 }
    /Linux Boot Manager/ && /EFI\\systemd\\systemd-bootx64\.efi/ {
      sub(/^Boot/, "", $1)
      sub(/\*.*/, "", $1)
      boot=$1
    }
    END { print boot }
  ' <<< "$bm_out")

  if [[ -z "$bootnum" ]]; then
    print_warning "NVRAM entry is not visible in efibootmgr; fallback BOOTX64.EFI is present."
    return 0
  fi

  arch_chroot "efibootmgr --bootnext ${bootnum}" \
    || print_warning "Could not set BootNext=${bootnum}; firmware should still see fallback BOOTX64.EFI."

  current_order=$(awk -F': ' '/^BootOrder:/ {print $2; exit}' <<< "$bm_out")
  if [[ -n "$current_order" && "$current_order" != "$bootnum"* ]]; then
    new_order="$bootnum"
    for entry in ${current_order//,/ }; do
      [[ "$entry" == "$bootnum" ]] && continue
      new_order="${new_order},${entry}"
    done
    arch_chroot "efibootmgr --bootorder ${new_order}" \
      || print_warning "Could not move Linux Boot Manager first in BootOrder."
  fi

  print_success "NVRAM entry checked: Boot${bootnum} (Linux Boot Manager)"
}
