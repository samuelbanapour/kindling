# lib/termsupport.zsh — terminal title, tab title, and shell integration.

# _ember_set_title <window> <tab>
_ember_set_title() {
  emulate -L zsh
  setopt no_prompt_subst
  case $TERM in
    (cygwin|xterm*|putty*|rxvt*|konsole*|ansi|screen*|tmux*|alacritty*|foot*|ghostty*|wezterm*)
      print -Pn "\e]2;${2:q}\a"   # window
      print -Pn "\e]1;${1:q}\a"   # tab
      ;;
    (*)
      [[ -n ${terminfo[fsl]} && -n ${terminfo[tsl]} ]] && \
        print -Pn "${terminfo[tsl]}$1${terminfo[fsl]}"
      ;;
  esac
}

: ${EMBER_TITLE_IDLE:='%15<..<%~%<<'}          # truncated cwd
: ${EMBER_TITLE_BUSY:='%15<..<%~%<< | %1~'}

_ember_title_precmd() { _ember_set_title "$EMBER_TITLE_IDLE" "$EMBER_TITLE_IDLE" }

_ember_title_preexec() {
  emulate -L zsh
  setopt extended_glob
  # Strip a leading `sudo`/env assignment so the title shows the real command.
  local cmd=${2[(wr)^(*=*|sudo|ssh|-*)]}
  local line=${1[(w)1]}
  _ember_set_title "${cmd:-$line}" "%~ | ${cmd:-$line}"
}

autoload -Uz add-zsh-hook
if [[ ${EMBER_DISABLE_AUTO_TITLE:-0} -ne 1 ]]; then
  add-zsh-hook precmd  _ember_title_precmd
  add-zsh-hook preexec _ember_title_preexec
fi

# OSC 7: tell the terminal the working directory so new tabs/splits inherit it.
# Supported by iTerm2, WezTerm, Ghostty, Kitty, GNOME Terminal, Windows Terminal.
_ember_osc7() {
  emulate -L zsh
  local encoded="" char hex
  local LC_ALL=C
  for (( i = 1; i <= ${#PWD}; i++ )); do
    char=${PWD[i]}
    if [[ $char == [a-zA-Z0-9/_.~-] ]]; then
      encoded+=$char
    else
      # printf -v keeps this fork-free; it runs on every prompt.
      printf -v hex '%%%02X' "'$char"
      encoded+=$hex
    fi
  done
  printf '\e]7;file://%s%s\e\\' "${HOST}" "$encoded"
}
[[ -n $TERM && $TERM != dumb && $TERM != linux ]] && add-zsh-hook precmd _ember_osc7
