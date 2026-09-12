# themes/minimal — one line, one color, no forks.
#
#   ~/code/ember ❯
#
# Nothing here runs a subprocess, so the prompt cost is effectively zero.
# Git state is deliberately absent: use `gst` when you want it.

setopt prompt_subst

: ${EMBER_MINIMAL_SYMBOL:='❯'}

_ember_minimal_precmd() {
  local color=cyan
  (( EMBER_LAST_STATUS != 0 )) && color=red
  PROMPT="%F{8}%~%f %F{${color}}${EMBER_MINIMAL_SYMBOL}%f "
  RPROMPT=""
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _ember_minimal_precmd
