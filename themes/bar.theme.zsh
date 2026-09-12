# themes/bar — filled segments, for terminals with a Nerd Font.
#
#    ~/code/ember  main ~1  ✗1
#   ❯
#
# Set EMBER_BAR_PLAIN=1 to use ASCII separators instead of powerline glyphs.

setopt prompt_subst
autoload -Uz add-zsh-hook

: ${EMBER_BAR_PLAIN:=0}
_ember_bar_pad=' '
# The powerline separator is only expressible in a UTF-8 locale; asking for it
# under LC_CTYPE=C is a parse-time error, not a rendering glitch, so check
# before reaching for it.
if (( EMBER_BAR_PLAIN )); then
  _ember_bar_sep=''
else
  _ember_bar_sep=${EMBER_GLYPH[sep]}
fi

# _ember_bar_segment <bg> <fg> <text>
# Draws a segment and remembers its background so the next separator can blend.
typeset -g _ember_bar_last_bg=""
_ember_bar_segment() {
  local bg=$1 fg=$2 text=$3 out=""
  [[ -z $text ]] && return
  if [[ -n $_ember_bar_last_bg && -n $_ember_bar_sep ]]; then
    out+="%K{${bg}}%F{${_ember_bar_last_bg}}${_ember_bar_sep}%f"
  else
    out+="%K{${bg}}"
  fi
  out+="%F{${fg}}${_ember_bar_pad}${text}${_ember_bar_pad}%f"
  _ember_bar_last_bg=$bg
  print -rn -- "$out"
}

_ember_bar_close() {
  [[ -z $_ember_bar_last_bg ]] && return
  if [[ -n $_ember_bar_sep ]]; then
    print -rn -- "%k%F{${_ember_bar_last_bg}}${_ember_bar_sep}%f"
  else
    print -rn -- "%k"
  fi
  _ember_bar_last_bg=""
}

_ember_bar_git() {
  local branch flags
  branch=$(ember_git_branch) || return 0
  flags=$(ember_git_status) || return 0
  local marks="" f
  for f in ${=flags}; do
    case $f in
      (conflict)  marks+=' !' ;;
      (staged)    marks+=' +' ;;
      (dirty)     marks+=' ~' ;;
      (untracked) marks+=' ?' ;;
      (stash)     marks+=' *' ;;
      (ahead:*)   marks+=" ^${f#ahead:}" ;;
      (behind:*)  marks+=" v${f#behind:}" ;;
    esac
  done
  # A clean branch gets a green segment, a dirty one yellow.
  local bg=green
  [[ $flags == *(dirty|untracked|conflict)* ]] && bg=yellow
  print -rn -- "${bg}|${branch}${marks}"
}

_ember_bar_precmd() {
  ember_async bar_git '_ember_bar_git' "$PWD"

  _ember_bar_last_bg=""
  local line=""

  [[ -n $SSH_CONNECTION ]] && line+=$(_ember_bar_segment 238 white '%n@%m')
  [[ -n $VIRTUAL_ENV ]] && line+=$(_ember_bar_segment 24 white "${VIRTUAL_ENV:t}")
  line+=$(_ember_bar_segment blue black '%~')

  local git=${EMBER_ASYNC_RESULT[bar_git]}
  [[ -n $git ]] && line+=$(_ember_bar_segment "${git%%|*}" black "${git#*|}")

  (( EMBER_LAST_STATUS != 0 )) && \
    line+=$(_ember_bar_segment red white "${EMBER_GLYPH[fail]} ${EMBER_LAST_STATUS}")

  line+=$(_ember_bar_close)

  PROMPT="${line}"$'\n'"%F{blue}${EMBER_GLYPH[prompt]}%f "
  RPROMPT=""
}
add-zsh-hook precmd _ember_bar_precmd
