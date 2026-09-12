# plugins/zline — line-editor upgrades: inline history suggestions and
# as-you-type syntax highlighting.
#
# These live in one plugin on purpose. Both features need to own
# `region_highlight`, and the usual pairing of two independent plugins for the
# job ends with one of them clobbering the other's colours. Here a single
# update pass computes both, so they compose correctly and the line is
# redrawn once per keystroke instead of twice.
#
# Toggles:
#   EMBER_ZLINE_SUGGEST=0     disable inline suggestions
#   EMBER_ZLINE_HIGHLIGHT=0   disable syntax highlighting
#   EMBER_ZLINE_MAX=300       skip both on lines longer than this

: ${EMBER_ZLINE_SUGGEST:=1}
: ${EMBER_ZLINE_HIGHLIGHT:=1}
: ${EMBER_ZLINE_MAX:=300}

# Styles are zle highlight specs; override any of them before loading.
: ${EMBER_ZLINE_STYLE_SUGGEST:='fg=8'}
: ${EMBER_ZLINE_STYLE_COMMAND:='fg=green'}
: ${EMBER_ZLINE_STYLE_BUILTIN:='fg=green,bold'}
: ${EMBER_ZLINE_STYLE_ALIAS:='fg=cyan'}
: ${EMBER_ZLINE_STYLE_UNKNOWN:='fg=red'}
: ${EMBER_ZLINE_STYLE_STRING:='fg=yellow'}
: ${EMBER_ZLINE_STYLE_OPTION:='fg=magenta'}
: ${EMBER_ZLINE_STYLE_PATH:='underline'}
: ${EMBER_ZLINE_STYLE_COMMENT:='fg=8'}
: ${EMBER_ZLINE_STYLE_OPERATOR:='fg=blue'}

typeset -g _ember_zline_suggestion=""
typeset -ga _ember_zline_regions=()

# --- suggestions -------------------------------------------------------------

# The most recent history entry that starts with the current buffer.
_ember_zline_fetch() {
  emulate -L zsh
  setopt extended_glob
  _ember_zline_suggestion=""
  (( ${EMBER_ZLINE_SUGGEST:-0} )) || return
  [[ -z $BUFFER || $#BUFFER -gt $EMBER_ZLINE_MAX ]] && return

  # Escape glob metacharacters so a buffer like `foo[` is matched literally.
  local prefix=${BUFFER//(#m)[\\*?[\]<>()|^~#]/\\$MATCH}
  # $history is ordered newest-first, so (r) returns the latest match.
  local found=${history[(r)${prefix}*]}
  [[ -z $found || $found == $BUFFER ]] && return
  _ember_zline_suggestion=${found#$BUFFER}
}

# --- highlighting ------------------------------------------------------------

# _ember_zline_kind <word> — sets REPLY to how a word in command position
# resolves. Sets a variable rather than printing: this runs on every keystroke
# and a command substitution here would mean a fork per character typed.
_ember_zline_kind() {
  local word=${1//[\'\"]/}
  REPLY=unknown
  [[ -z $word ]] && return
  if [[ $word == */* ]]; then
    [[ -x ${~word} ]] && REPLY=command
    return
  fi
  if (( $+aliases[$word] || $+galiases[$word] )); then REPLY=alias
  elif (( $+builtins[$word] )) || [[ -n ${reswords[(r)$word]} ]]; then REPLY=builtin
  elif (( $+functions[$word] )); then REPLY=command
  elif (( $+commands[$word] )); then REPLY=command
  elif [[ $word == [A-Za-z_][A-Za-z0-9_]#=* ]]; then REPLY=assignment
  fi
}

# Walk the buffer once, filling _ember_zline_regions with zle highlight specs.
# Offsets are 0-based with an exclusive end, which is what zle expects.
_ember_zline_highlight() {
  emulate -L zsh
  setopt extended_glob
  _ember_zline_regions=()

  local buf=$BUFFER
  local -i n=$#buf i=1 start
  local ch quote word REPLY
  local -i expect_command=1

  while (( i <= n )); do
    ch=${buf[i]}

    if [[ $ch == [[:space:]] ]]; then (( i++ )); continue; fi

    # A comment swallows the rest of the line.
    if [[ $ch == '#' && ( $i == 1 || ${buf[i-1]} == [[:space:]] ) ]]; then
      _ember_zline_regions+=("$(( i - 1 )) $n $EMBER_ZLINE_STYLE_COMMENT")
      break
    fi

    # Control operators return us to command position.
    if [[ ${buf[i,i+1]} == ('&&'|'||'|';;') ]]; then
      _ember_zline_regions+=("$(( i - 1 )) $(( i + 1 )) $EMBER_ZLINE_STYLE_OPERATOR")
      (( i += 2 )); expect_command=1; continue
    fi
    if [[ $ch == ('|'|';'|'&'|'('|')'|'{'|'}') ]]; then
      _ember_zline_regions+=("$(( i - 1 )) $i $EMBER_ZLINE_STYLE_OPERATOR")
      (( i++ )); expect_command=1; continue
    fi
    if [[ $ch == ('>'|'<') ]]; then
      _ember_zline_regions+=("$(( i - 1 )) $i $EMBER_ZLINE_STYLE_OPERATOR")
      (( i++ )); continue
    fi

    # A quoted string runs to its matching quote, or to the end of an
    # unterminated line — which still highlights, showing you it's open.
    if [[ $ch == ("'"|'"') ]]; then
      quote=$ch; start=$i; (( i++ ))
      while (( i <= n )) && [[ ${buf[i]} != $quote ]]; do
        [[ ${buf[i]} == '\' ]] && (( i++ ))
        (( i++ ))
      done
      (( i <= n )) && (( i++ ))
      _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_STRING")
      expect_command=0
      continue
    fi

    start=$i
    while (( i <= n )) && [[ ${buf[i]} != [[:space:]\;\|\&\<\>\(\)] ]]; do (( i++ )); done
    word=${buf[start,i-1]}

    if (( expect_command )); then
      _ember_zline_kind "$word"
      case $REPLY in
        (builtin)  _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_BUILTIN") ;;
        (alias)    _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_ALIAS") ;;
        (command)  _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_COMMAND") ;;
        (assignment)
          # `FOO=bar cmd ...` — the assignment is a prefix, not the command.
          _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_OPERATOR")
          continue ;;
        (*)
          # Don't shout at a command that is still being typed at the cursor.
          if (( i - 1 == CURSOR )) && (( CURSOR == n )); then
            :
          else
            _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_UNKNOWN")
          fi ;;
      esac
      expect_command=0
    elif [[ $word == -* ]]; then
      _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_OPTION")
    elif [[ -e ${~word} ]]; then
      _ember_zline_regions+=("$(( start - 1 )) $(( i - 1 )) $EMBER_ZLINE_STYLE_PATH")
    fi
  done
}

# --- the single update pass --------------------------------------------------

_ember_zline_update() {
  region_highlight=()

  if (( ${EMBER_ZLINE_HIGHLIGHT:-0} && $#BUFFER <= EMBER_ZLINE_MAX )); then
    _ember_zline_highlight
    region_highlight+=("${_ember_zline_regions[@]}")
  fi

  _ember_zline_fetch
  POSTDISPLAY=$_ember_zline_suggestion
  if [[ -n $POSTDISPLAY ]]; then
    region_highlight+=("$#BUFFER $(( $#BUFFER + $#POSTDISPLAY )) $EMBER_ZLINE_STYLE_SUGGEST")
  fi
}

_ember_zline_clear() {
  POSTDISPLAY=""
  _ember_zline_suggestion=""
  region_highlight=()
}

# --- accepting a suggestion --------------------------------------------------

_ember_zline_accept() {
  if [[ -n $_ember_zline_suggestion ]]; then
    BUFFER="$BUFFER$_ember_zline_suggestion"
    CURSOR=$#BUFFER
    _ember_zline_update
  else
    zle .forward-char
  fi
}
(( $+builtins[zle] )) && zle -N _ember_zline_accept

# Take just the next word of the suggestion — useful when the rest is wrong.
_ember_zline_accept_word() {
  emulate -L zsh
  setopt extended_glob
  if [[ -n $_ember_zline_suggestion ]]; then
    local word=${(M)_ember_zline_suggestion##[[:space:]]#[^[:space:]]##}
    BUFFER="$BUFFER${word:-$_ember_zline_suggestion}"
    CURSOR=$#BUFFER
    _ember_zline_update
  else
    zle .forward-word
  fi
}
(( $+builtins[zle] )) && zle -N _ember_zline_accept_word

# --- widget wrapping ---------------------------------------------------------

# Widgets after which the line changed and the display must be recomputed.
typeset -ga _ember_zline_modify_widgets=(
  self-insert delete-char backward-delete-char kill-word backward-kill-word
  kill-line backward-kill-line kill-whole-line yank yank-pop
  vi-delete vi-delete-char transpose-chars quoted-insert
  up-line-or-beginning-search down-line-or-beginning-search
  up-line-or-history down-line-or-history history-search-backward
  history-search-forward insert-last-word bracketed-paste
)
# Widgets that only move the cursor: the suggestion stays, highlighting stands.
typeset -ga _ember_zline_clear_widgets=(
  accept-line accept-and-hold push-line push-line-or-edit send-break
)

_ember_zline_wrap() {
  local widget=$1 action=$2 fn="_ember_zline_w_$1"
  # Nothing to wrap if the widget doesn't exist in this shell.
  (( $+widgets[$widget] )) || return 0
  # Already wrapped (e.g. plugin sourced twice).
  [[ ${widgets[$widget]} == user:_ember_zline_w_* ]] && return 0

  local invoke
  if [[ ${widgets[$widget]} == builtin ]]; then
    invoke="zle .$widget -- \"\$@\""
  else
    zle -A "$widget" "_ember_zline_orig_$widget"
    invoke="zle _ember_zline_orig_$widget -- \"\$@\""
  fi

  functions[$fn]="
    $invoke
    local rc=\$?
    _ember_zline_$action
    return \$rc
  "
  zle -N "$widget" "$fn"
}

# Widgets and key bindings only exist in an interactive shell. The functions
# above are defined unconditionally so they can be tested and reused.
if [[ ! -o interactive ]]; then
  return 0
fi

() {
  local w
  for w in "${_ember_zline_modify_widgets[@]}"; do _ember_zline_wrap "$w" update; done
  for w in "${_ember_zline_clear_widgets[@]}"; do _ember_zline_wrap "$w" clear; done
}

# Right arrow / ^F / End accept the whole suggestion; Alt-Right takes one word.
bindkey '^[[C' _ember_zline_accept
bindkey '^F'   _ember_zline_accept
[[ -n ${terminfo[kcuf1]} ]] && bindkey -- "${terminfo[kcuf1]}" _ember_zline_accept
[[ -n ${terminfo[kend]}  ]] && bindkey -- "${terminfo[kend]}"  _ember_zline_accept
bindkey '^[[1;3C' _ember_zline_accept_word
bindkey '^[[1;5C' _ember_zline_accept_word

# Start each line clean.
autoload -Uz add-zsh-hook
add-zsh-hook precmd _ember_zline_clear
