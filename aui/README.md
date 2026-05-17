# AUI-X

Installer simple para Arch Linux en UEFI.

El flujo esta dividido en dos fases:

- `install`: se ejecuta desde el live ISO de Arch y deja el sistema base booteable.
- `setup`: se ejecuta despues del primer boot y configura usuario, escritorio, drivers y herramientas opcionales.

## Requisitos

- Arch ISO reciente.
- Arrancar el ISO en modo UEFI.
- Conexion a internet en el live ISO.
- Ejecutar como root.
- Disco recomendado: 30G o mas para una prueba minima; mas espacio si vas a instalar KDE, drivers, juegos o herramientas de trabajo.

Si usas una VM, asegurate de arrancar desde el disco instalado despues de terminar `install`, no desde el ISO.

## Como se usa

Desde el live ISO:

```bash
pacman -Sy git
git clone <repo-url> /root/aui-x
cd /root/aui-x
bash aui/install
```

Ejecuta los pasos del menu en orden y al final reinicia.

Despues del primer boot:

```bash
cd /root/aui-x
bash aui/setup
```

## Que hace `install`

- Selecciona keymap.
- Configura mirrors con `reflector`.
- Prepara particiones para UEFI:
  - ESP en `/boot`.
  - root con el resto del disco.
- Permite elegir root cifrado con LUKS o root sin cifrado.
- En root cifrado usa LUKS directo: `/dev/mapper/cryptroot`.
- Instala sistema base con `linux-zen` y `linux-lts`.
- Genera `fstab`.
- Configura hostname, timezone, locale y mkinitcpio.
- Instala systemd-boot.
- Crea entrada fallback EFI.
- Valida artefactos criticos antes de permitir reboot.
- Crea password de root.
- Opcionalmente instala `paru`.
- Copia el repo a `/root/aui-x`.

## Que hace `setup`

- Configura pacman con multilib y descargas paralelas.
- Crea usuario con sudo.
- Instala drivers GPU segun hardware detectado.
- Instala escritorio opcional:
  - KDE Plasma minimal.
  - GNOME.
  - Hyprland, Sway o i3 si los eliges manualmente.
- Habilita audio PipeWire para el usuario.
- Instala fonts basicas.
- Configura soporte multi-monitor solo para Plasma/GNOME.
- Instala Bluetooth si detecta hardware.
- Opcionalmente instala zsh, Powerlevel10k, Docker + Compose v2 y VPN.

## Layout recomendado

Para una instalacion automatica en un disco:

```text
/dev/sdX1  ESP  600M o 1G  /boot
/dev/sdX2  root resto      LUKS opcional
```

Si eliges LUKS:

```text
/dev/sdX2 -> /dev/mapper/cryptroot -> btrfs/ext4
```

Con btrfs, el installer crea subvolumes para:

```text
@
@home
@var_log
@snapshots
```

## Notas importantes

- Solo UEFI esta soportado.
- `/boot` debe ser la ESP.
- LVM ya no se usa en el flujo root por default.
- Fortress/hardening no forma parte de `install` ni `setup`.
- Si algo critico de boot queda mal, el installer debe frenar antes de reiniciar.

## Pruebas rapidas

Desde el repo:

```bash
bash tests/smoke.sh
bash tests/install-storage.sh
```
