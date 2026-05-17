#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage:
  ARCHISO=/path/to/archlinux.iso tests/qemu-uefi.sh

Optional env:
  DISK=./tmp/aui-x-test.qcow2
  DISK_SIZE=40G
  RAM=4096
  CPUS=4

Notes:
  - This boots an Arch ISO in UEFI mode with a disposable qcow2 disk.
  - Inside the ISO, run the installer against /dev/vda.
  - For systemd-boot tests, mount the ESP at /boot.
  - After install, shut down, rerun with BOOT_DISK_ONLY=1 to verify the installed disk boots.
EOF
}

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$repo_root"

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
  usage
  exit 0
fi

disk="${DISK:-$repo_root/tmp/aui-x-test.qcow2}"
disk_size="${DISK_SIZE:-40G}"
ram="${RAM:-4096}"
cpus="${CPUS:-4}"
archiso="${ARCHISO:-}"
boot_disk_only="${BOOT_DISK_ONLY:-0}"

ovmf_code="/usr/share/edk2/x64/OVMF_CODE.4m.fd"
ovmf_vars_src="/usr/share/edk2/x64/OVMF_VARS.4m.fd"
ovmf_vars="$repo_root/tmp/OVMF_VARS.aui-x.fd"

[[ -r "$ovmf_code" ]] || { echo "Missing OVMF code: $ovmf_code" >&2; exit 1; }
[[ -r "$ovmf_vars_src" ]] || { echo "Missing OVMF vars: $ovmf_vars_src" >&2; exit 1; }

mkdir -p "$(dirname "$disk")" "$repo_root/tmp"

if [[ ! -f "$disk" ]]; then
  qemu-img create -f qcow2 "$disk" "$disk_size"
fi

if [[ ! -f "$ovmf_vars" ]]; then
  cp "$ovmf_vars_src" "$ovmf_vars"
fi

qemu_args=(
  -enable-kvm
  -machine q35,accel=kvm
  -cpu host
  -smp "$cpus"
  -m "$ram"
  -drive "if=pflash,format=raw,readonly=on,file=$ovmf_code"
  -drive "if=pflash,format=raw,file=$ovmf_vars"
  -drive "file=$disk,format=qcow2,if=virtio"
  -nic user,model=virtio-net-pci
  -display gtk
)

if [[ "$boot_disk_only" != "1" ]]; then
  [[ -r "$archiso" ]] || { usage >&2; echo "ARCHISO is required for installer boot." >&2; exit 1; }
  qemu_args+=(
    -cdrom "$archiso"
    -boot order=d
  )
else
  qemu_args+=(
    -boot order=c
  )
fi

exec qemu-system-x86_64 "${qemu_args[@]}"
