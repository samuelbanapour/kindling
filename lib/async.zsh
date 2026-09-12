# lib/async.zsh — run prompt work off the critical path.
#
# A git-aware prompt normally forks git on every single prompt, and in a large
# repository that is the difference between an instant prompt and a visible
# stall. Here the prompt renders immediately with whatever it knew last time,
# a worker computes the real answer in the background, and the prompt is
# redrawn in place when the answer lands.
#
# Set KINDLING_ASYNC=0 to compute synchronously instead.

: ${KINDLING_ASYNC:=1}
typeset -g KINDLING_ASYNC

typeset -gA _kindling_async_pid _kindling_async_out _kindling_async_ctx
typeset -gA KINDLING_ASYNC_RESULT

zmodload zsh/system 2>/dev/null

# _kindling_prompt_refresh — redraw the prompt without disturbing the line being
# edited. Safe to call from a trap.
_kindling_prompt_refresh() {
  [[ -o zle ]] || return 0
  zle && zle reset-prompt 2>/dev/null
}

# kindling_async <id> <code> [context]
#   Runs <code> in a background shell. Its stdout becomes
#   KINDLING_ASYNC_RESULT[<id>] once it finishes. <context> is any string
#   identifying what the result is about — usually $PWD. A result whose
#   context no longer matches the current one is discarded, so a slow answer
#   for the directory you just left can never overwrite the right one.
kindling_async() {
  local id=$1 code=$2 ctx=${3:-$PWD}

  if (( ! KINDLING_ASYNC )); then
    KINDLING_ASYNC_RESULT[$id]="$(eval "$code" 2>/dev/null)"
    return 0
  fi

  # Supersede a worker that's still running for the same id.
  if [[ -n ${_kindling_async_pid[$id]} ]]; then
    kill -TERM ${_kindling_async_pid[$id]} 2>/dev/null
    wait ${_kindling_async_pid[$id]} 2>/dev/null
  fi

  local out="$KINDLING_CACHE/async.$id.$$"
  _kindling_async_out[$id]=$out
  _kindling_async_ctx[$id]=$ctx

  # $$ inside the subshell is still the parent's pid, which is what we signal.
  local parent=$$
  {
    eval "$code" >| "$out" 2>/dev/null
    kill -USR1 $parent 2>/dev/null
  } &!
  _kindling_async_pid[$id]=$!
}

# Collect every finished worker. USR1 is the wake-up; the actual handoff is
# through the files, so no data races on shell state.
TRAPUSR1() {
  local id out
  local -i changed=0
  for id in ${(k)_kindling_async_out}; do
    out=${_kindling_async_out[$id]}
    [[ -f $out ]] || continue
    if [[ -z ${_kindling_async_ctx[$id]} || ${_kindling_async_ctx[$id]} == $PWD ]]; then
      KINDLING_ASYNC_RESULT[$id]="$(<$out)"
      changed=1
    fi
    command rm -f -- "$out"
    unset "_kindling_async_out[$id]" "_kindling_async_pid[$id]" "_kindling_async_ctx[$id]"
  done
  (( changed )) && _kindling_prompt_refresh
}

# Discard pending results when the directory changes — they're about the old one.
_kindling_async_reset() {
  local id
  for id in ${(k)_kindling_async_pid}; do
    kill -TERM ${_kindling_async_pid[$id]} 2>/dev/null
  done
  _kindling_async_pid=() _kindling_async_out=() _kindling_async_ctx=()
  KINDLING_ASYNC_RESULT=()
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _kindling_async_reset

# Clean up any files a killed shell left behind.
_kindling_async_cleanup() { command rm -f -- "$KINDLING_CACHE"/async.*.$$(N) }
add-zsh-hook zshexit _kindling_async_cleanup
