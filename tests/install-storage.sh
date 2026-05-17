#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

TERM="${TERM:-xterm}"
source aui/install

printf '== storage helpers ==\n'
[[ "$(partition_path /dev/sda 1)" == "/dev/sda1" ]] || fail "sata partition path"
[[ "$(partition_path /dev/vda 2)" == "/dev/vda2" ]] || fail "virtio partition path"
[[ "$(partition_path /dev/nvme0n1 1)" == "/dev/nvme0n1p1" ]] || fail "nvme partition path"
[[ "$(partition_path /dev/mmcblk0 2)" == "/dev/mmcblk0p2" ]] || fail "mmc partition path"

printf '== plain root strategy ==\n'
reset_partition_state
state[partition_layout]="plain"
prepare_root_device /dev/sda2
[[ "${state[root_part]}" == "/dev/sda2" ]] || fail "plain root_part"
[[ "${state[root_device]}" == "/dev/sda2" ]] || fail "plain root_device"
[[ "${state[luks]}" -eq 0 ]] || fail "plain should not enable luks"

printf '== encrypted root strategy ==\n'
reset_partition_state
state[partition_layout]="luks"
TRIM=0
luks_format() {
  [[ "$1" == "/dev/sda2" ]] || fail "luks target"
  [[ "$3" == "cryptroot" ]] || fail "luks mapper name"
  printf '/dev/mapper/cryptroot\n'
}
read_input_text() { OPTION=n; }
prepare_root_device /dev/sda2
[[ "${state[root_part]}" == "/dev/sda2" ]] || fail "luks root_part"
[[ "${state[root_device]}" == "/dev/mapper/cryptroot" ]] || fail "luks root_device"
[[ "${state[luks_disk]}" == "/dev/sda2" ]] || fail "luks_disk"
[[ "${state[root_luks_mapper]}" == "cryptroot" ]] || fail "root_luks_mapper"

printf '== existing root confirmation ==\n'
reset_partition_state
state[partition_mode]="existing"
state[partition_layout]="plain"
state[root_part]="/dev/sda2"
confirm_existing_root_reformat <<<"/dev/sda2"
if confirm_existing_root_reformat <<<"/dev/sda3"; then
  fail "existing root confirmation accepted wrong partition"
fi

printf '== automatic root disk contract ==\n'
reset_partition_state
state[device]="/dev/nvme0n1"
log_file="$(mktemp /tmp/aui-storage.XXXXXX)"
select_esp_size() {
  state[esp_size_label]="1G"
  state[esp_end]="1025MiB"
}
wipefs() { printf 'wipefs %s\n' "$*" >> "$log_file"; }
parted() { printf 'parted %s\n' "$*" >> "$log_file"; }
partprobe() { :; }
udevadm() { :; }
wait_for_block() { :; }

guided_partition_root_disk <<<"/dev/nvme0n1"
[[ "${state[esp]}" == "/dev/nvme0n1p1" ]] || fail "automatic ESP path"
[[ "${state[root_part]}" == "/dev/nvme0n1p2" ]] || fail "automatic root path"
grep -Fq 'mklabel gpt' "$log_file" || fail "automatic mklabel"
grep -Fq 'mkpart EFI System fat32 1MiB 1025MiB' "$log_file" || fail "automatic ESP partition"
grep -Fq 'mkpart Linux root btrfs 1025MiB 100%' "$log_file" || fail "automatic root partition"

printf 'OK: install storage tests passed\n'
