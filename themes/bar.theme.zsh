# themes/bar — filled segments, for terminals with a Nerd Font.
#
#    ~/code/kindling  main ~1  ✗1
#   ❯
#
# Set KINDLING_BAR_PLAIN=1 to use ASCII separators instead of powerline glyphs.

setopt prompt_subst
autoload -Uz add-zsh-hook

: ${KINDLING_BAR_PLAIN:=0}
_kindling_bar_pad=' '
# The powerline separator is only expressible in a UTF-8 locale; asking for it
# under LC_CTYPE=C is a parse-time error, not a rendering glitch, so check
# before reaching for it.
if (( KINDLING_BAR_PLAIN )); then
  _kindling_bar_sep=''
else
  _kindling_bar_sep=${KINDLING_GLYPH[sep]}
fi

# _kindling_bar_segment <bg> <fg> <text>
# Draws a segment and remembers its background so the next separator can blend.
typeset -g _kindling_bar_last_bg=""
_kindling_bar_segment() {
  local bg=$1 fg=$2 text=$3 out=""
  [[ -z $text ]] && return
  if [[ -n $_kindling_bar_last_bg && -n $_kindling_bar_sep ]]; then
    out+="%K{${bg}}%F{${_kindling_bar_last_bg}}${_kindling_bar_sep}%f"
  else
    out+="%K{${bg}}"
  fi
  out+="%F{${fg}}${_kindling_bar_pad}${text}${_kindling_bar_pad}%f"
  _kindling_bar_last_bg=$bg
  print -rn -- "$out"
}

_kindling_bar_close() {
  [[ -z $_kindling_bar_last_bg ]] && return
  if [[ -n $_kindling_bar_sep ]]; then
    print -rn -- "%k%F{${_kindling_bar_last_bg}}${_kindling_bar_sep}%f"
  else
    print -rn -- "%k"
  fi
  _kindling_bar_last_bg=""
}

_kindling_bar_git() {
  local branch flags
  branch=$(kindling_git_branch) || return 0
  flags=$(kindling_git_status) || return 0
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

_kindling_bar_precmd() {
  kindling_async bar_git '_kindling_bar_git' "$PWD"

  _kindling_bar_last_bg=""
  local line=""

  [[ -n $SSH_CONNECTION ]] && line+=$(_kindling_bar_segment 238 white '%n@%m')
  [[ -n $VIRTUAL_ENV ]] && line+=$(_kindling_bar_segment 24 white "${VIRTUAL_ENV:t}")
  line+=$(_kindling_bar_segment blue black '%~')

  local git=${KINDLING_ASYNC_RESULT[bar_git]}
  [[ -n $git ]] && line+=$(_kindling_bar_segment "${git%%|*}" black "${git#*|}")

  (( KINDLING_LAST_STATUS != 0 )) && \
    line+=$(_kindling_bar_segment red white "${KINDLING_GLYPH[fail]} ${KINDLING_LAST_STATUS}")

  line+=$(_kindling_bar_close)

  PROMPT="${line}"$'\n'"%F{blue}${KINDLING_GLYPH[prompt]}%f "
  RPROMPT=""
}
add-zsh-hook precmd _kindling_bar_precmd
