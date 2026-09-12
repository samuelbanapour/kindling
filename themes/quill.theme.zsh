# themes/quill — single line, generous spacing, git on the right.
#
#   ~/code/ember                                 main ~1 ⇡1
#   ❯ git status
#
# A blank line before each prompt makes long output much easier to scan back
# through, which is the whole point of this one.

setopt prompt_subst
autoload -Uz add-zsh-hook

: ${EMBER_QUILL_SYMBOL:='❯'}

_ember_quill_git() {
  local branch flags out
  branch=$(ember_git_branch) || return 0
  flags=$(ember_git_status) || return 0
  out="%F{242}${branch}%f"
  local f
  for f in ${=flags}; do
    case $f in
      (conflict)  out+=' %F{red}✖%f' ;;
      (dirty|staged) out+=' %F{yellow}●%f' ;;
      (untracked) out+=' %F{242}○%f' ;;
      (ahead:*)   out+=" %F{cyan}⇡${f#ahead:}%f" ;;
      (behind:*)  out+=" %F{cyan}⇣${f#behind:}%f" ;;
    esac
  done
  # Collapse the duplicate dot that dirty+staged would otherwise produce.
  print -rn -- "${out/ %F\{yellow\}●%f %F\{yellow\}●%f/ %F\{yellow\}●%f}"
}

_ember_quill_precmd() {
  ember_async quill_git '_ember_quill_git' "$PWD"

  local color=magenta
  (( EMBER_LAST_STATUS != 0 )) && color=red

  local venv=""
  [[ -n $VIRTUAL_ENV ]] && venv="%F{242}(${VIRTUAL_ENV:t})%f "

  PROMPT=$'\n'"%F{blue}%~%f"$'\n'"${venv}%F{${color}}${EMBER_QUILL_SYMBOL}%f "
  RPROMPT="${EMBER_ASYNC_RESULT[quill_git]}"
}
add-zsh-hook precmd _ember_quill_precmd
