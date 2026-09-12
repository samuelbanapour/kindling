# themes/minimal — one line, one color, no forks.
#
#   ~/code/kindling ❯
#
# Nothing here runs a subprocess, so the prompt cost is effectively zero.
# Git state is deliberately absent: use `gst` when you want it.

setopt prompt_subst

: ${KINDLING_MINIMAL_SYMBOL:=${KINDLING_GLYPH[prompt]}}

_kindling_minimal_precmd() {
  local color=cyan
  (( KINDLING_LAST_STATUS != 0 )) && color=red
  PROMPT="%F{8}%~%f %F{${color}}${KINDLING_MINIMAL_SYMBOL}%f "
  RPROMPT=""
}
autoload -Uz add-zsh-hook
add-zsh-hook precmd _kindling_minimal_precmd
