# themes/quill — single line, generous spacing, git on the right.
#
#   ~/code/kindling                                 main ~1 ⇡1
#   ❯ git status
#
# A blank line before each prompt makes long output much easier to scan back
# through, which is the whole point of this one.

setopt prompt_subst
autoload -Uz add-zsh-hook

: ${KINDLING_QUILL_SYMBOL:=${KINDLING_GLYPH[prompt]}}

_kindling_quill_git() {
  local branch flags out
  branch=$(kindling_git_branch) || return 0
  flags=$(kindling_git_status) || return 0
  out="%F{242}${branch}%f"
  local f
  for f in ${=flags}; do
    case $f in
      (conflict)  out+=" %F{red}${KINDLING_GLYPH[conflict]}%f" ;;
      (dirty|staged) out+=" %F{yellow}${KINDLING_GLYPH[on]}%f" ;;
      (untracked) out+=" %F{242}${KINDLING_GLYPH[off]}%f" ;;
      (ahead:*)   out+=" %F{cyan}${KINDLING_GLYPH[ahead]}${f#ahead:}%f" ;;
      (behind:*)  out+=" %F{cyan}${KINDLING_GLYPH[behind]}${f#behind:}%f" ;;
    esac
  done
  # Collapse the duplicate dot that dirty+staged would otherwise produce.
  local dot=${KINDLING_GLYPH[on]}
  print -rn -- "${out/ %F\{yellow\}${dot}%f %F\{yellow\}${dot}%f/ %F\{yellow\}${dot}%f}"
}

_kindling_quill_precmd() {
  kindling_async quill_git '_kindling_quill_git' "$PWD"

  local color=magenta
  (( KINDLING_LAST_STATUS != 0 )) && color=red

  local venv=""
  [[ -n $VIRTUAL_ENV ]] && venv="%F{242}(${VIRTUAL_ENV:t})%f "

  PROMPT=$'\n'"%F{blue}%~%f"$'\n'"${venv}%F{${color}}${KINDLING_QUILL_SYMBOL}%f "
  RPROMPT="${KINDLING_ASYNC_RESULT[quill_git]}"
}
add-zsh-hook precmd _kindling_quill_precmd
