# themes/spark — the default. Two lines, so a long path never squeezes the
# place you type. Git information arrives asynchronously.
#
#   ~/code/ember  main +2 ~1 ?  ⇡1                          1.4s
#   ❯
#
# Customise with EMBER_SPARK_* variables; see the bottom of this file.

setopt prompt_subst
autoload -Uz add-zsh-hook

: ${EMBER_SPARK_SYMBOL:='❯'}
: ${EMBER_SPARK_SYMBOL_ROOT:='#'}
: ${EMBER_SPARK_COLOR_OK:=magenta}
: ${EMBER_SPARK_COLOR_ERR:=red}
: ${EMBER_SPARK_COLOR_PATH:=blue}
: ${EMBER_SPARK_COLOR_GIT:=green}
: ${EMBER_SPARK_SLOW_MS:=2000}     # show command duration above this
: ${EMBER_SPARK_PATH:='%~'}

typeset -g _ember_spark_git=""
typeset -g _ember_spark_start=0
typeset -g _ember_spark_elapsed=""

# --- git segment -------------------------------------------------------------

# Rendered in the background by ember_async. Everything it needs comes from
# lib/git.zsh, which answers the whole question in one `git status` call.
_ember_spark_render_git() {
  local branch flags
  branch=$(ember_git_branch) || return 0
  flags=$(ember_git_status) || return 0

  local -a marks
  local f
  for f in ${=flags}; do
    case $f in
      (conflict)  marks+=('%F{red}!%f') ;;
      (staged)    marks+=('%F{green}+%f') ;;
      (dirty)     marks+=('%F{yellow}~%f') ;;
      (untracked) marks+=('%F{blue}?%f') ;;
      (stash)     marks+=('%F{cyan}*%f') ;;
      (ahead:*)   marks+=("%F{cyan}⇡${f#ahead:}%f") ;;
      (behind:*)  marks+=("%F{cyan}⇣${f#behind:}%f") ;;
    esac
  done

  print -rn -- "%F{${EMBER_SPARK_COLOR_GIT}}${branch}%f"
  (( ${#marks} )) && print -rn -- " ${(j: :)marks}"
}

_ember_spark_git_update() {
  ember_async spark_git '_ember_spark_render_git' "$PWD"
}

# --- timing ------------------------------------------------------------------

_ember_spark_preexec() {
  _ember_spark_start=$(( EPOCHREALTIME * 1000 ))
}

_ember_spark_format_ms() {
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

_ember_spark_precmd() {
  # Set by lib/options.zsh's first-registered precmd hook; reading `$?` here
  # would only tell us how the previous hook in the chain exited.
  local -i last_status=$EMBER_LAST_STATUS

  if (( _ember_spark_start )); then
    local -i ms=$(( EPOCHREALTIME * 1000 - _ember_spark_start ))
    if (( ms >= EMBER_SPARK_SLOW_MS )); then
      _ember_spark_elapsed=$(_ember_spark_format_ms $ms)
    else
      _ember_spark_elapsed=""
    fi
    _ember_spark_start=0
  fi

  _ember_spark_git_update

  # --- left ---
  local -a left
  # An ssh session should never look like a local one.
  [[ -n $SSH_CONNECTION || -n $SSH_TTY ]] && left+=('%F{yellow}%n@%m%f')
  [[ -n $VIRTUAL_ENV ]] && left+=("%F{cyan}(${VIRTUAL_ENV:t})%f")
  left+=("%B%F{${EMBER_SPARK_COLOR_PATH}}${EMBER_SPARK_PATH}%f%b")

  local git=${EMBER_ASYNC_RESULT[spark_git]}
  [[ -n $git ]] && left+=("$git")

  # --- right ---
  local -a right
  (( last_status != 0 )) && right+=("%F{red}✗ ${last_status}%f")
  [[ -n $_ember_spark_elapsed ]] && right+=("%F{yellow}${_ember_spark_elapsed}%f")
  (( ${#jobstates} )) && right+=("%F{magenta}⚙ ${#jobstates}%f")

  local symbol_color=${EMBER_SPARK_COLOR_OK}
  (( last_status != 0 )) && symbol_color=${EMBER_SPARK_COLOR_ERR}
  local symbol=${EMBER_SPARK_SYMBOL}
  (( EUID == 0 )) && symbol=${EMBER_SPARK_SYMBOL_ROOT}

  PROMPT="${(j: :)left}"$'\n'"%F{${symbol_color}}${symbol}%f "
  RPROMPT="${(j: :)right}"
  PROMPT2="%F{${symbol_color}}…%f "
}

zmodload zsh/datetime
add-zsh-hook precmd  _ember_spark_precmd
add-zsh-hook preexec _ember_spark_preexec
