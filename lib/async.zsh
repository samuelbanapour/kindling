# lib/async.zsh — run prompt work off the critical path.
#
# A git-aware prompt normally forks git on every single prompt, and in a large
# repository that is the difference between an instant prompt and a visible
# stall. Here the prompt renders immediately with whatever it knew last time,
# a worker computes the real answer in the background, and the prompt is
# redrawn in place when the answer lands.
#
# Set EMBER_ASYNC=0 to compute synchronously instead.

: ${EMBER_ASYNC:=1}
typeset -g EMBER_ASYNC

typeset -gA _ember_async_pid _ember_async_out _ember_async_ctx
typeset -gA EMBER_ASYNC_RESULT

zmodload zsh/system 2>/dev/null

# _ember_prompt_refresh — redraw the prompt without disturbing the line being
# edited. Safe to call from a trap.
_ember_prompt_refresh() {
  [[ -o zle ]] || return 0
  zle && zle reset-prompt 2>/dev/null
}

# ember_async <id> <code> [context]
#   Runs <code> in a background shell. Its stdout becomes
#   EMBER_ASYNC_RESULT[<id>] once it finishes. <context> is any string
#   identifying what the result is about — usually $PWD. A result whose
#   context no longer matches the current one is discarded, so a slow answer
#   for the directory you just left can never overwrite the right one.
ember_async() {
  local id=$1 code=$2 ctx=${3:-$PWD}

  if (( ! EMBER_ASYNC )); then
    EMBER_ASYNC_RESULT[$id]="$(eval "$code" 2>/dev/null)"
    return 0
  fi

  # Supersede a worker that's still running for the same id.
  if [[ -n ${_ember_async_pid[$id]} ]]; then
    kill -TERM ${_ember_async_pid[$id]} 2>/dev/null
    wait ${_ember_async_pid[$id]} 2>/dev/null
  fi

  local out="$EMBER_CACHE/async.$id.$$"
  _ember_async_out[$id]=$out
  _ember_async_ctx[$id]=$ctx

  # $$ inside the subshell is still the parent's pid, which is what we signal.
  local parent=$$
  {
    eval "$code" >| "$out" 2>/dev/null
    kill -USR1 $parent 2>/dev/null
  } &!
  _ember_async_pid[$id]=$!
}

# Collect every finished worker. USR1 is the wake-up; the actual handoff is
# through the files, so no data races on shell state.
TRAPUSR1() {
  local id out
  local -i changed=0
  for id in ${(k)_ember_async_out}; do
    out=${_ember_async_out[$id]}
    [[ -f $out ]] || continue
    if [[ -z ${_ember_async_ctx[$id]} || ${_ember_async_ctx[$id]} == $PWD ]]; then
      EMBER_ASYNC_RESULT[$id]="$(<$out)"
      changed=1
    fi
    command rm -f -- "$out"
    unset "_ember_async_out[$id]" "_ember_async_pid[$id]" "_ember_async_ctx[$id]"
  done
  (( changed )) && _ember_prompt_refresh
}

# Discard pending results when the directory changes — they're about the old one.
_ember_async_reset() {
  local id
  for id in ${(k)_ember_async_pid}; do
    kill -TERM ${_ember_async_pid[$id]} 2>/dev/null
  done
  _ember_async_pid=() _ember_async_out=() _ember_async_ctx=()
  EMBER_ASYNC_RESULT=()
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _ember_async_reset

# Clean up any files a killed shell left behind.
_ember_async_cleanup() { command rm -f -- "$EMBER_CACHE"/async.*.$$(N) }
add-zsh-hook zshexit _ember_async_cleanup
