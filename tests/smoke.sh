#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

fail() {
  printf 'FAIL: %s\n' "$*" >&2
  exit 1
}

check_file() {
  [[ -f "$1" ]] || fail "missing file: $1"
}

check_contains() {
  local file="$1"
  local pattern="$2"
  grep -Eq "$pattern" "$file" || fail "$file does not match: $pattern"
}

check_not_contains() {
  local file="$1"
  local pattern="$2"
  ! grep -Eq "$pattern" "$file" || fail "$file should not match: $pattern"
}

printf '== bash syntax ==\n'
bash -n aui/install
bash -n aui/setup
bash -n aui/lib
for lib_file in aui/libs/*.sh; do
  bash -n "$lib_file"
done
bash -n fortress/fortress
bash -n fortress/lib/common.sh
bash -n fortress/modules/software/*.sh
bash -n fortress/modules/hardware/*.sh

printf '== expected files ==\n'
check_file aui/install
check_file aui/setup
check_file aui/lib
check_file aui/libs/ui.sh
check_file aui/libs/system.sh
check_file aui/libs/storage.sh
check_file aui/libs/install.sh
check_file aui/libs/setup.sh
check_file fortress/fortress

printf '== installer invariants ==\n'
check_contains aui/libs/install.sh 'select_partition_mode'
check_contains aui/libs/install.sh 'select_storage_strategy'
check_contains aui/libs/install.sh 'guided_partition_root_disk'
check_contains aui/libs/install.sh 'select_existing_root_partition'
check_contains aui/libs/install.sh 'select_existing_esp'
check_contains aui/libs/install.sh 'prepare_root_device'
check_contains aui/libs/install.sh 'partition_path'
check_contains aui/libs/install.sh 'mount_extra_partitions'
check_contains aui/libs/install.sh 'clear_luks_state'
check_contains aui/libs/storage.sh 'cryptsetup --batch-mode --type luks2'
check_contains aui/install 'cryptsetup close cryptroot'
check_contains aui/libs/install.sh 'state\[root_luks_mapper\]'
check_contains aui/libs/install.sh 'state\[luks_targets\]'
check_contains aui/libs/install.sh 'setup_lvm "\$\{state\[root_device\]\}" "lvm" "root"'
check_contains aui/libs/storage.sh '/dev/mapper/\$\{vg_name\}-\$\{lv_name\}'
check_contains aui/libs/storage.sh 'is_efi_system_partition'
check_contains aui/libs/storage.sh 'list_extra_candidates'
check_contains aui/install 'networkmanager iwd'
check_contains aui/install 'generate_loader_entries "\$MOUNTPOINT" "/boot" "linux-zen"'
check_contains aui/install 'systemd-boot EFI binary missing after bootctl'
check_contains aui/libs/storage.sh 'c12a7328-f81f-11d2-ba4b-00a0c93ec93b'
check_contains aui/install 'root=\$\{state\[root_device\]\} rw'
check_contains aui/install 'rootflags=subvol=@'
check_contains aui/install 'bootctl --esp-path=/boot install --graceful'
check_contains aui/libs/system.sh 'AUI-X requiere UEFI'
check_contains aui/libs/ui.sh 'normalize_yes_no'
check_contains aui/libs/ui.sh 'confirm_destructive_action'
check_contains aui/libs/ui.sh 'y\|yes'
check_contains aui/libs/ui.sh 'n\|no'
check_contains aui/install 'Only UEFI is supported'

printf '== install source contract ==\n'
TERM="${TERM:-xterm}" bash -c '
  source aui/install
  type main >/dev/null
  type step_bootloader >/dev/null
  type mount_extra_partitions >/dev/null
'

bash tests/install-storage.sh

printf '== yes/no normalization ==\n'
TERM="${TERM:-xterm}" bash -c '
  source aui/lib
  [[ "$(normalize_yes_no YES)" == y ]]
  [[ "$(normalize_yes_no yes)" == y ]]
  [[ "$(normalize_yes_no Y)" == y ]]
  [[ "$(normalize_yes_no NO)" == n ]]
  [[ "$(normalize_yes_no no)" == n ]]
  [[ "$(normalize_yes_no N)" == n ]]
'

printf '== setup invariants ==\n'
check_contains aui/setup 'nvidia-open-dkms'
check_contains aui/setup 'Target=linux-zen'
check_contains aui/setup 'Target=linux-lts'
check_contains aui/setup 'plasma-desktop'
check_contains aui/setup 'power-profiles-daemon'
check_contains aui/setup 'plasma-firewall'
check_contains aui/setup 'ttf-nerd-fonts-symbols'
check_contains aui/setup 'local user_groups=\(wheel storage\)'
check_contains aui/setup 'zsh-theme-powerlevel10k'
check_contains aui/setup 'zsh-autosuggestions'
check_contains aui/setup 'docker docker-compose docker-buildx'
check_contains aui/setup 'Multi-monitor automático sólo se ofrece para Plasma y GNOME'
check_contains aui/libs/setup.sh 'detect_aur_helper'
check_contains aui/libs/setup.sh 'write_zshrc_config'
check_not_contains aui/setup 'kde-applications-meta'
check_not_contains aui/setup 'xf86-video-nouveau'
check_not_contains aui/setup 'ttf-firacode-nerd'
check_not_contains aui/setup 'local user_groups=.*audio'

printf '== fortress invariants ==\n'
check_contains fortress/fortress 'harden-config'
check_contains fortress/lib/common.sh 'apply\|rollback\|status\|describe\|config'

printf 'OK: smoke tests passed\n'
