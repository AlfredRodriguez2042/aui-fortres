# -------------------------------------------------------------------
# Partitioning / filesystem helpers
# -------------------------------------------------------------------

is_efi_system_partition() {
  local dev="$1" pt ptn
  pt=$(lsblk -no PARTTYPE "$dev" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
  ptn=$(lsblk -no PARTTYPENAME "$dev" 2>/dev/null | head -1 | tr '[:upper:]' '[:lower:]')
  [[ "$pt" == "c12a7328-f81f-11d2-ba4b-00a0c93ec93b" ]] ||
    [[ "$pt" == "0xef" ]] ||
    [[ "$ptn" == *"efi system"* ]]
}

luks_format() {
  local part="$1" trim="$2" mapper_name="${3:-cryptroot}"
  wipefs -a "$part" || return 1
  cryptsetup --batch-mode --type luks2 \
    --cipher aes-xts-plain64 --key-size 512 --hash sha512 \
    --pbkdf argon2id --pbkdf-memory 524288 --pbkdf-parallel 4 --iter-time 5000 \
    --use-urandom --verify-passphrase luksFormat "$part" || return 1

  local open_args=(open --type luks)
  [[ $trim -eq 1 ]] && open_args+=(--allow-discards)
  cryptsetup "${open_args[@]}" "$part" "$mapper_name" || return 1
  echo "/dev/mapper/$mapper_name"
}

luks_open() {
  local part="$1" mapper="$2" trim="$3"
  local open_args=(open --type luks)
  [[ $trim -eq 1 ]] && open_args+=(--allow-discards)
  cryptsetup "${open_args[@]}" "$part" "$mapper"
}

setup_lvm() {
  local pv_dev="$1" vg_name="$2" lv_name="$3" size="${4:-100%FREE}"
  pvcreate "$pv_dev" >&2 || return 1
  vgcreate "$vg_name" "$pv_dev" >&2 || return 1
  if [[ "$size" == "100%FREE" ]]; then
    lvcreate -l 100%FREE "$vg_name" -n "$lv_name" >&2 || return 1
  else
    lvcreate -L "$size" "$vg_name" -n "$lv_name" >&2 || return 1
  fi
  echo "/dev/mapper/${vg_name}-${lv_name}"
}

format_and_mount_root() {
  local part="$1" fs="$2" mountpoint="$3" trim="$4"
  local mkfs_args=()

  case "$fs" in
    btrfs) mkfs_args=(-f) ;;
    ext4) [[ $trim -eq 1 ]] && mkfs_args=(-E discard) ;;
    *) print_error "Unsupported root filesystem: $fs"; return 1 ;;
  esac

  mkfs."$fs" "${mkfs_args[@]}" "$part" || return 1
  [[ "$fs" != "btrfs" ]] && fsck "$part" || true
  mkdir -p "$mountpoint" || return 1

  if [[ "$fs" == "btrfs" ]]; then
    mount -t btrfs "$part" "$mountpoint" || return 1
    btrfs subvolume create "$mountpoint/@" || { umount "$mountpoint"; return 1; }
    btrfs subvolume create "$mountpoint/@home" || { umount "$mountpoint"; return 1; }
    btrfs subvolume create "$mountpoint/@var_log" || { umount "$mountpoint"; return 1; }
    btrfs subvolume create "$mountpoint/@snapshots" || { umount "$mountpoint"; return 1; }
    umount "$mountpoint"

    local opts="noatime,compress=zstd,space_cache=v2"
    [[ $trim -eq 1 ]] && opts+=",discard=async"
    mount -t btrfs -o "subvol=@,${opts}" "$part" "$mountpoint" || return 1
    mkdir -p "$mountpoint"/{home,var/log,.snapshots}
    mount -t btrfs -o "subvol=@home,${opts}" "$part" "$mountpoint/home" || return 1
    mount -t btrfs -o "subvol=@var_log,${opts}" "$part" "$mountpoint/var/log" || return 1
    mount -t btrfs -o "subvol=@snapshots,${opts}" "$part" "$mountpoint/.snapshots" || return 1
  else
    mount -t "$fs" "$part" "$mountpoint" || return 1
  fi
}

mount_vfat() {
  local part="$1" mountpoint="$2"
  mkdir -p "$mountpoint" || return 1
  mount -t vfat "$part" "$mountpoint"
}

list_extra_candidates() {
  local mnt="$1" root_dev="$2" esp_dev="$3" luks_disk="$4" excluded_devices="${5:-}"
  local candidates=()
  local parts=() part excluded skip

  mapfile -t parts < <(lsblk -lnpo NAME,TYPE | awk '$2=="part" || $2=="lvm" || $2=="crypt"{print $1}')
  for part in "${parts[@]}"; do
    skip=0
    for excluded in $excluded_devices; do
      [[ "$part" == "$excluded" ]] && { skip=1; break; }
    done
    [[ $skip -eq 1 ]] && continue
    [[ "$part" == "$root_dev" ]] && continue
    [[ "$part" == "$esp_dev" ]] && continue
    [[ -n "$luks_disk" && "$part" == "$luks_disk" ]] && continue
    is_efi_system_partition "$part" && continue
    findmnt -R -n -o SOURCE "$mnt" 2>/dev/null | grep -Fxq "$part" && continue
    candidates+=("$part")
  done

  printf "%s\n" "${candidates[@]}"
}

format_and_mount_extra() {
  local part="$1" fs="$2" mountpoint="$3" trim="$4"
  local mkfs_args=()

  case "$fs" in
    ext4)
      mkfs_args=(-F)
      [[ $trim -eq 1 ]] && mkfs_args+=(-E discard)
      ;;
    btrfs)
      mkfs_args=(-f)
      ;;
    vfat)
      mkfs_args=(-F32)
      ;;
    *)
      print_error "Unsupported filesystem for extra partition: $fs"
      return 1
      ;;
  esac

  mkfs."$fs" "${mkfs_args[@]}" "$part" || return 1
  mkdir -p "$mountpoint" || return 1
  mount -t "$fs" "$part" "$mountpoint"
}

mount_extra() {
  local part="$1" mountpoint="$2"
  mkdir -p "$mountpoint" || return 1
  mount "$part" "$mountpoint"
}

