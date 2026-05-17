#!/bin/bash

# -------------------------------------------------------------------
# Phase 2 setup helpers
# -------------------------------------------------------------------

detect_aur_helper() {
  if command -v paru >/dev/null 2>&1; then
    AUR_HELPER="paru"
  elif command -v yay >/dev/null 2>&1; then
    AUR_HELPER="yay"
  else
    AUR_HELPER=""
  fi
}

detect_gpu() {
  local nvidia_line amd_line intel_line
  GPU_ARCH=""
  nvidia_line=$(lspci -nn | grep -iE 'VGA|3D|Display' | grep -i nvidia | head -1)
  amd_line=$(lspci -nn | grep -iE 'VGA|3D|Display' | grep -iE 'AMD|ATI' | head -1)
  intel_line=$(lspci -nn | grep -iE 'VGA|3D|Display' | grep -i intel | head -1)

  if [[ -n "$nvidia_line" ]]; then
    GPU_VENDOR="nvidia"
    # Extract device ID and classify by architecture
    local dev_hex dev_int
    dev_hex=$(echo "$nvidia_line" | grep -oP '10de:[0-9a-f]{4}' | head -1 | cut -d: -f2)
    if [[ -n "$dev_hex" ]]; then
      dev_int=$((16#$dev_hex))
      # Blackwell (RTX 50): 0x2b00 - 0x2fff aprox
      # Ada Lovelace (RTX 40): 0x2600 - 0x26ff, 0x27xx
      # Ampere (RTX 30): 0x2200 - 0x25ff
      # Turing (RTX 20 / GTX 16): 0x1e00 - 0x21ff
      # Older: pre-Turing
      if (( dev_int >= 0x2b00 )); then
        GPU_ARCH="blackwell"
      elif (( dev_int >= 0x2600 && dev_int < 0x2b00 )); then
        GPU_ARCH="ada"
      elif (( dev_int >= 0x2200 && dev_int < 0x2600 )); then
        GPU_ARCH="ampere"
      elif (( dev_int >= 0x1e00 && dev_int < 0x2200 )); then
        GPU_ARCH="turing"
      else
        GPU_ARCH="pre-turing"
      fi
    else
      GPU_ARCH="unknown"
    fi
  elif [[ -n "$amd_line" ]]; then
    GPU_VENDOR="amd"
  elif [[ -n "$intel_line" ]]; then
    GPU_VENDOR="intel"
  else
    GPU_VENDOR="none"
  fi
}

write_zshrc_config() {
  local username="$1" user_home="$2"
  local user_group zshrc backup

  user_group=$(id -gn "$username") || return 1
  zshrc="$user_home/.zshrc"
  backup="$user_home/.zshrc.aui-x.bak"
  if [[ -f "$zshrc" && ! -f "$backup" ]]; then
    cp "$zshrc" "$backup"
    chown "$username:$user_group" "$backup"
  fi

  cat > "$zshrc" <<'EOF'
# Enable Powerlevel10k instant prompt. Keep this close to the top.
if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then
  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"
fi

[[ -r /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme ]] && \
  source /usr/share/zsh-theme-powerlevel10k/powerlevel10k.zsh-theme
[[ -f ~/.p10k.zsh ]] && source ~/.p10k.zsh

HISTFILE="${HOME}/.zsh_history"
HISTSIZE=5000
SAVEHIST=5000
setopt appendhistory sharehistory histignoredups

if command -v dircolors >/dev/null 2>&1; then
  [[ -r ~/.dircolors ]] && eval "$(dircolors -b ~/.dircolors)" || eval "$(dircolors -b)"
fi

alias ls='ls --color=auto'
alias ll='ls -alF'
alias la='ls -A'
alias l='ls -CF'
alias catp='/usr/bin/cat'
command -v bat >/dev/null 2>&1 && alias cat='bat'
command -v eza >/dev/null 2>&1 && alias tree='eza --tree'

[[ -r /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-autosuggestions/zsh-autosuggestions.zsh
[[ -r /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh ]] && \
  source /usr/share/zsh/plugins/zsh-syntax-highlighting/zsh-syntax-highlighting.zsh
EOF
  chown "$username:$user_group" "$zshrc"
}
