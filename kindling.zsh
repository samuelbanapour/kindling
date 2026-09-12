# kindling.zsh — core loader for the Kindling zsh framework
#
# Usage (in ~/.zshrc):
#   export KINDLING="$HOME/.kindling"
#   kindling_plugins=(git node docker)
#   KINDLING_THEME=spark
#   source "$KINDLING/kindling.zsh"
#
# Everything below is plain zsh. No subshells on the hot path, no `eval` of
# external command output at startup, and a single compiled completion dump.

# --- guard against double-sourcing ------------------------------------------
(( ${+KINDLING_VERSION} )) && return 0
typeset -gr KINDLING_VERSION="1.0.1"

# --- resolve paths -----------------------------------------------------------
if [[ -z $KINDLING ]]; then
  # ${(%):-%N} is the path of the file currently being sourced.
  KINDLING="${${(%):-%N}:A:h}"
fi
typeset -g KINDLING

# --- how was this copy installed? -------------------------------------------
# A package manager owns its install directory: it replaces the whole thing on
# upgrade and may not let you write to it at all. Anything the user creates has
# to live elsewhere, or `brew upgrade kindling` would silently delete every plugin
# they had written. The packaging drops a marker file naming the manager.
if [[ -z $KINDLING_INSTALL ]]; then
  if [[ -r $KINDLING/.kindling-managed ]]; then
    KINDLING_INSTALL="$(<$KINDLING/.kindling-managed)"
  elif [[ -d $KINDLING/.git ]]; then
    KINDLING_INSTALL=git
  elif [[ ! -w $KINDLING ]]; then
    KINDLING_INSTALL=readonly
  else
    KINDLING_INSTALL=plain
  fi
fi
typeset -g KINDLING_INSTALL

if [[ -z $KINDLING_CUSTOM ]]; then
  case $KINDLING_INSTALL in
    (git|plain) KINDLING_CUSTOM="$KINDLING/custom" ;;
    (*)         KINDLING_CUSTOM="${XDG_DATA_HOME:-$HOME/.local/share}/kindling/custom" ;;
  esac
fi
: ${KINDLING_CACHE:="${XDG_CACHE_HOME:-$HOME/.cache}/kindling"}
: ${KINDLING_THEME:=spark}
typeset -g KINDLING_CUSTOM KINDLING_CACHE KINDLING_THEME

[[ -d $KINDLING_CACHE ]] || command mkdir -p "$KINDLING_CACHE"
[[ -d $KINDLING_CUSTOM/plugins ]] || command mkdir -p "$KINDLING_CUSTOM/plugins"
[[ -d $KINDLING_CUSTOM/themes ]] || command mkdir -p "$KINDLING_CUSTOM/themes"

# --- profiling ---------------------------------------------------------------
# KINDLING_PROFILE=1 records how long every unit takes to load; `kindling profile`
# reads it back. The cost when disabled is one integer test per unit.
typeset -gA KINDLING_LOAD_MS
typeset -g _kindling_epoch_supported=0
zmodload zsh/datetime 2>/dev/null && _kindling_epoch_supported=1

_kindling_now() {
  if (( _kindling_epoch_supported )); then
    print -r -- $(( EPOCHREALTIME * 1000 ))
  else
    print -r -- 0
  fi
}

# _kindling_source <label> <file> — source a file, timing it when profiling.
#
# Returns non-zero only when the file could not be read. The exit status of a
# sourced file is whatever its last command happened to return, which for a
# config file is noise: a plugin ending in `compdef _git g` or a `[[ ... ]] &&`
# guard would otherwise be reported as having failed to load.
_kindling_source() {
  local label=$1 file=$2
  [[ -r $file ]] || return 1
  if (( ${KINDLING_PROFILE:-0} )); then
    local start=$(_kindling_now)
    source "$file"
    KINDLING_LOAD_MS[$label]=$(( $(_kindling_now) - start ))
  else
    source "$file"
  fi
  return 0
}

# _kindling_warn <msg...> — non-fatal diagnostic, suppressed by KINDLING_QUIET.
_kindling_warn() {
  (( ${KINDLING_QUIET:-0} )) && return 0
  print -ru2 -- "kindling: $*"
}

# --- unit resolution ---------------------------------------------------------
# Custom units win over bundled ones, so a user can shadow `git` with their own.
# _kindling_find_plugin <name> -> prints path or returns 1
_kindling_find_plugin() {
  local name=$1 dir
  for dir in "$KINDLING_CUSTOM/plugins/$name" "$KINDLING/plugins/$name"; do
    [[ -r $dir/$name.plugin.zsh ]] && { print -r -- "$dir/$name.plugin.zsh"; return 0 }
  done
  return 1
}

_kindling_find_theme() {
  local name=$1 file
  for file in "$KINDLING_CUSTOM/themes/$name.theme.zsh" "$KINDLING/themes/$name.theme.zsh"; do
    [[ -r $file ]] && { print -r -- "$file"; return 0 }
  done
  return 1
}

# --- deferred loading --------------------------------------------------------
# Units registered with kindling_defer run right after the first prompt is drawn,
# so an expensive plugin never delays the shell becoming usable.
typeset -ga _kindling_deferred=()

kindling_defer() { _kindling_deferred+=("$1") }

_kindling_run_deferred() {
  local snippet
  for snippet in "${_kindling_deferred[@]}"; do
    eval "$snippet"
  done
  _kindling_deferred=()
  add-zsh-hook -d precmd _kindling_run_deferred
  # Redraw once so a deferred prompt segment shows up immediately.
  (( ${+functions[_kindling_prompt_refresh]} )) && _kindling_prompt_refresh
}

# kindling_lazy <cmd> [cmd...] -- <init code>
# Replaces each command with a stub. On first call the stub removes itself,
# runs the init code, and re-dispatches to the real command. This is how
# nvm/pyenv/rbenv stay off the startup path.
kindling_lazy() {
  local -a cmds
  while (( $# )) && [[ $1 != '--' ]]; do cmds+=("$1"); shift; done
  shift  # drop the --
  local init=$1 cmd
  for cmd in "${cmds[@]}"; do
    functions[$cmd]="
      unfunction ${cmds[*]} 2>/dev/null
      $init
      $cmd \"\$@\"
    "
  done
}

# --- core libraries ----------------------------------------------------------
autoload -Uz add-zsh-hook is-at-least

typeset -ga _kindling_lib_order=(
  options history directory completion keybindings termsupport aliases git async
)

typeset -g _kindling_lib
for _kindling_lib in "${_kindling_lib_order[@]}"; do
  _kindling_source "lib:$_kindling_lib" "$KINDLING/lib/$_kindling_lib.zsh" \
    || _kindling_warn "missing core library: $_kindling_lib"
done
unset _kindling_lib

# --- plugins -----------------------------------------------------------------
typeset -ga kindling_loaded_plugins=()
typeset -g _kindling_plugin _kindling_path

for _kindling_plugin in "${kindling_plugins[@]}"; do
  if _kindling_path=$(_kindling_find_plugin "$_kindling_plugin"); then
    # A plugin directory is prepended to fpath so it can ship completions.
    fpath=("${_kindling_path:h}" $fpath)
    if _kindling_source "plugin:$_kindling_plugin" "$_kindling_path"; then
      kindling_loaded_plugins+=("$_kindling_plugin")
    else
      _kindling_warn "plugin '$_kindling_plugin' failed to load"
    fi
  else
    _kindling_warn "plugin '$_kindling_plugin' not found (try: kindling list plugins)"
  fi
done
unset _kindling_plugin _kindling_path

# --- theme -------------------------------------------------------------------
if [[ $KINDLING_THEME != (none|off) ]]; then
  if _kindling_path=$(_kindling_find_theme "$KINDLING_THEME"); then
    _kindling_source "theme:$KINDLING_THEME" "$_kindling_path"
  else
    _kindling_warn "theme '$KINDLING_THEME' not found, falling back to 'spark'"
    _kindling_source "theme:spark" "$KINDLING/themes/spark.theme.zsh"
  fi
  unset _kindling_path
fi

# --- user overrides ----------------------------------------------------------
# Anything in custom/*.zsh loads last so it can override plugins and themes.
typeset -g _kindling_file
for _kindling_file in "$KINDLING_CUSTOM"/*.zsh(N); do
  _kindling_source "custom:${_kindling_file:t:r}" "$_kindling_file"
done
unset _kindling_file

# --- finalize ----------------------------------------------------------------
# Completion init runs once, after every plugin has had a chance to touch fpath.
_kindling_init_completion

(( ${#_kindling_deferred} )) && add-zsh-hook precmd _kindling_run_deferred

# `kindling` management command.
_kindling_source "tool:cli" "$KINDLING/tools/kindling.zsh"

return 0
