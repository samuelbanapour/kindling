# themes/spark — the default. Two lines, so a long path never squeezes the
# place you type. Git information arrives asynchronously.
#
#   ~/code/kindling  main +2 ~1 ?  ⇡1                          1.4s
#   ❯
#
# Customise with KINDLING_SPARK_* variables; see the bottom of this file.

setopt prompt_subst
autoload -Uz add-zsh-hook

: ${KINDLING_SPARK_SYMBOL:=${KINDLING_GLYPH[prompt]}}
: ${KINDLING_SPARK_SYMBOL_ROOT:='#'}
: ${KINDLING_SPARK_COLOR_OK:=magenta}
: ${KINDLING_SPARK_COLOR_ERR:=red}
: ${KINDLING_SPARK_COLOR_PATH:=blue}
: ${KINDLING_SPARK_COLOR_GIT:=green}
: ${KINDLING_SPARK_SLOW_MS:=2000}     # show command duration above this
: ${KINDLING_SPARK_PATH:='%~'}

typeset -g _kindling_spark_git=""
typeset -g _kindling_spark_start=0
typeset -g _kindling_spark_elapsed=""

# --- git segment -------------------------------------------------------------

# Rendered in the background by kindling_async. Everything it needs comes from
# lib/git.zsh, which answers the whole question in one `git status` call.
_kindling_spark_render_git() {
  local branch flags
  branch=$(kindling_git_branch) || return 0
  flags=$(kindling_git_status) || return 0

  local -a marks
  local f
  for f in ${=flags}; do
    case $f in
      (conflict)  marks+=('%F{red}!%f') ;;
      (staged)    marks+=('%F{green}+%f') ;;
      (dirty)     marks+=('%F{yellow}~%f') ;;
      (untracked) marks+=('%F{blue}?%f') ;;
      (stash)     marks+=('%F{cyan}*%f') ;;
      (ahead:*)   marks+=("%F{cyan}${KINDLING_GLYPH[ahead]}${f#ahead:}%f") ;;
      (behind:*)  marks+=("%F{cyan}${KINDLING_GLYPH[behind]}${f#behind:}%f") ;;
    esac
  done

  print -rn -- "%F{${KINDLING_SPARK_COLOR_GIT}}${branch}%f"
  (( ${#marks} )) && print -rn -- " ${(j: :)marks}"
}

_kindling_spark_git_update() {
  kindling_async spark_git '_kindling_spark_render_git' "$PWD"
}

# --- timing ------------------------------------------------------------------

_kindling_spark_preexec() {
  _kindling_spark_start=$(( EPOCHREALTIME * 1000 ))
}

_kindling_spark_format_ms() {
  local -i ms=$1
  if (( ms < 60000 )); then
    printf '%.1fs' $(( ms / 1000.0 ))
  elif (( ms < 3600000 )); then
    printf '%dm%ds' $(( ms / 60000 )) $(( (ms % 60000) / 1000 ))
  else
    printf '%dh%dm' $(( ms / 3600000 )) $(( (ms % 3600000) / 60000 ))
  fi
}

# --- prompt ------------------------------------------------------------------

_kindling_spark_precmd() {
  # Set by lib/options.zsh's first-registered precmd hook; reading `$?` here
  # would only tell us how the previous hook in the chain exited.
  local -i last_status=$KINDLING_LAST_STATUS

  if (( _kindling_spark_start )); then
    local -i ms=$(( EPOCHREALTIME * 1000 - _kindling_spark_start ))
    if (( ms >= KINDLING_SPARK_SLOW_MS )); then
      _kindling_spark_elapsed=$(_kindling_spark_format_ms $ms)
    else
      _kindling_spark_elapsed=""
    fi
    _kindling_spark_start=0
  fi

  _kindling_spark_git_update

  # --- left ---
  local -a left
  # An ssh session should never look like a local one.
  [[ -n $SSH_CONNECTION || -n $SSH_TTY ]] && left+=('%F{yellow}%n@%m%f')
  [[ -n $VIRTUAL_ENV ]] && left+=("%F{cyan}(${VIRTUAL_ENV:t})%f")
  left+=("%B%F{${KINDLING_SPARK_COLOR_PATH}}${KINDLING_SPARK_PATH}%f%b")

  local git=${KINDLING_ASYNC_RESULT[spark_git]}
  [[ -n $git ]] && left+=("$git")

  # --- right ---
  local -a right
  (( last_status != 0 )) && right+=("%F{red}${KINDLING_GLYPH[fail]} ${last_status}%f")
  [[ -n $_kindling_spark_elapsed ]] && right+=("%F{yellow}${_kindling_spark_elapsed}%f")
  (( ${#jobstates} )) && right+=("%F{magenta}${KINDLING_GLYPH[job]} ${#jobstates}%f")

  local symbol_color=${KINDLING_SPARK_COLOR_OK}
  (( last_status != 0 )) && symbol_color=${KINDLING_SPARK_COLOR_ERR}
  local symbol=${KINDLING_SPARK_SYMBOL}
  (( EUID == 0 )) && symbol=${KINDLING_SPARK_SYMBOL_ROOT}

  PROMPT="${(j: :)left}"$'\n'"%F{${symbol_color}}${symbol}%f "
  RPROMPT="${(j: :)right}"
  PROMPT2="%F{${symbol_color}}${KINDLING_GLYPH[continue]}%f "
}

zmodload zsh/datetime
add-zsh-hook precmd  _kindling_spark_precmd
add-zsh-hook preexec _kindling_spark_preexec
