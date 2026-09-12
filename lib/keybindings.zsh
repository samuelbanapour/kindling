# lib/keybindings.zsh — emacs bindings plus the ones people expect from
# other shells and don't get by default.

bindkey -e

# Make sure terminfo-based keys work both inside and outside application mode.
autoload -Uz add-zle-hook-widget 2>/dev/null
if (( ${+terminfo[smkx]} && ${+terminfo[rmkx]} )); then
  _kindling_zle_line_init()   { echoti smkx }
  _kindling_zle_line_finish() { echoti rmkx }
  zle -N zle-line-init _kindling_zle_line_init
  zle -N zle-line-finish _kindling_zle_line_finish
fi

# _kindling_bind <terminfo-cap> <fallback-seq> <widget>
_kindling_bind() {
  local cap=$1 fallback=$2 widget=$3
  [[ -n ${terminfo[$cap]} ]] && bindkey -- "${terminfo[$cap]}" "$widget"
  [[ -n $fallback ]] && bindkey -- "$fallback" "$widget"
}

_kindling_bind khome '^[[H'  beginning-of-line
_kindling_bind kend  '^[[F'  end-of-line
_kindling_bind kdch1 '^[[3~' delete-char
_kindling_bind kich1 '^[[2~' overwrite-mode
_kindling_bind kpp   ''      up-line-or-history      # PageUp
_kindling_bind knp   ''      down-line-or-history    # PageDown

# Alt-Left / Alt-Right move by word in every terminal that matters.
bindkey '^[[1;3D' backward-word
bindkey '^[[1;3C' forward-word
bindkey '^[[1;5D' backward-word
bindkey '^[[1;5C' forward-word
bindkey '^[b'     backward-word
bindkey '^[f'     forward-word

# Up/Down search history for what you've already typed, rather than walking
# through every command blindly. This is the single highest-value binding here.
autoload -Uz up-line-or-beginning-search down-line-or-beginning-search
zle -N up-line-or-beginning-search
zle -N down-line-or-beginning-search
_kindling_bind kcuu1 '^[[A' up-line-or-beginning-search
_kindling_bind kcud1 '^[[B' down-line-or-beginning-search
bindkey '^P' up-line-or-beginning-search
bindkey '^N' down-line-or-beginning-search

bindkey '^[^?' backward-kill-word   # Alt-Backspace
bindkey '^U'   backward-kill-line   # kill to start, not the whole line
bindkey '^[.'  insert-last-word

# Edit the current command in $EDITOR with ^X^E.
autoload -Uz edit-command-line
zle -N edit-command-line
bindkey '^X^E' edit-command-line

# Paste stays literal — no surprise glob expansion or command substitution.
autoload -Uz bracketed-paste-magic
zle -N bracketed-paste bracketed-paste-magic
# ...but keep quoting out of the way of URLs pasted after a flag.
autoload -Uz url-quote-magic
zle -N self-insert url-quote-magic

# ^Z toggles: suspend a job, then ^Z again to bring it back.
_kindling_fg_toggle() {
  if [[ $#BUFFER -eq 0 ]]; then
    BUFFER='fg'; zle accept-line
  else
    zle push-input; zle clear-screen
  fi
}
zle -N _kindling_fg_toggle
bindkey '^Z' _kindling_fg_toggle

# Alt-S prefixes the line with sudo (press again to remove it).
_kindling_sudo_toggle() {
  [[ -z $BUFFER ]] && LBUFFER="$(fc -ln -1)"
  if [[ $BUFFER == sudo\ * ]]; then
    BUFFER=${BUFFER#sudo }; (( CURSOR -= 5 ))
  else
    BUFFER="sudo $BUFFER"; (( CURSOR += 5 ))
  fi
}
zle -N _kindling_sudo_toggle
bindkey '^[s' _kindling_sudo_toggle
