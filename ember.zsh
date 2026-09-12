# ember.zsh — core loader for the Ember zsh framework
#
# Usage (in ~/.zshrc):
#   export EMBER="$HOME/.ember"
#   ember_plugins=(git node docker)
#   EMBER_THEME=spark
#   source "$EMBER/ember.zsh"
#
# Everything below is plain zsh. No subshells on the hot path, no `eval` of
# external command output at startup, and a single compiled completion dump.

# --- guard against double-sourcing ------------------------------------------
(( ${+EMBER_VERSION} )) && return 0
typeset -gr EMBER_VERSION="1.0.0"

# --- resolve paths -----------------------------------------------------------
if [[ -z $EMBER ]]; then
  # ${(%):-%N} is the path of the file currently being sourced.
  EMBER="${${(%):-%N}:A:h}"
fi
typeset -g EMBER

# --- how was this copy installed? -------------------------------------------
# A package manager owns its install directory: it replaces the whole thing on
# upgrade and may not let you write to it at all. Anything the user creates has
# to live elsewhere, or `brew upgrade ember` would silently delete every plugin
# they had written. The packaging drops a marker file naming the manager.
if [[ -z $EMBER_INSTALL ]]; then
  if [[ -r $EMBER/.ember-managed ]]; then
    EMBER_INSTALL="$(<$EMBER/.ember-managed)"
  elif [[ -d $EMBER/.git ]]; then
    EMBER_INSTALL=git
  elif [[ ! -w $EMBER ]]; then
    EMBER_INSTALL=readonly
  else
    EMBER_INSTALL=plain
  fi
fi
typeset -g EMBER_INSTALL

if [[ -z $EMBER_CUSTOM ]]; then
  case $EMBER_INSTALL in
    (git|plain) EMBER_CUSTOM="$EMBER/custom" ;;
    (*)         EMBER_CUSTOM="${XDG_DATA_HOME:-$HOME/.local/share}/ember/custom" ;;
  esac
fi
: ${EMBER_CACHE:="${XDG_CACHE_HOME:-$HOME/.cache}/ember"}
: ${EMBER_THEME:=spark}
typeset -g EMBER_CUSTOM EMBER_CACHE EMBER_THEME

[[ -d $EMBER_CACHE ]] || command mkdir -p "$EMBER_CACHE"
[[ -d $EMBER_CUSTOM/plugins ]] || command mkdir -p "$EMBER_CUSTOM/plugins"
[[ -d $EMBER_CUSTOM/themes ]] || command mkdir -p "$EMBER_CUSTOM/themes"

# --- profiling ---------------------------------------------------------------
# EMBER_PROFILE=1 records how long every unit takes to load; `ember profile`
# reads it back. The cost when disabled is one integer test per unit.
typeset -gA EMBER_LOAD_MS
typeset -g _ember_epoch_supported=0
zmodload zsh/datetime 2>/dev/null && _ember_epoch_supported=1

_ember_now() {
  if (( _ember_epoch_supported )); then
    print -r -- $(( EPOCHREALTIME * 1000 ))
  else
    print -r -- 0
  fi
}

# _ember_source <label> <file> — source a file, timing it when profiling.
#
# Returns non-zero only when the file could not be read. The exit status of a
# sourced file is whatever its last command happened to return, which for a
# config file is noise: a plugin ending in `compdef _git g` or a `[[ ... ]] &&`
# guard would otherwise be reported as having failed to load.
_ember_source() {
  local label=$1 file=$2
  [[ -r $file ]] || return 1
  if (( ${EMBER_PROFILE:-0} )); then
    local start=$(_ember_now)
    source "$file"
    EMBER_LOAD_MS[$label]=$(( $(_ember_now) - start ))
  else
    source "$file"
  fi
  return 0
}

# _ember_warn <msg...> — non-fatal diagnostic, suppressed by EMBER_QUIET.
_ember_warn() {
  (( ${EMBER_QUIET:-0} )) && return 0
  print -ru2 -- "ember: $*"
}

# --- unit resolution ---------------------------------------------------------
# Custom units win over bundled ones, so a user can shadow `git` with their own.
# _ember_find_plugin <name> -> prints path or returns 1
_ember_find_plugin() {
  local name=$1 dir
  for dir in "$EMBER_CUSTOM/plugins/$name" "$EMBER/plugins/$name"; do
    [[ -r $dir/$name.plugin.zsh ]] && { print -r -- "$dir/$name.plugin.zsh"; return 0 }
  done
  return 1
}

_ember_find_theme() {
  local name=$1 file
  for file in "$EMBER_CUSTOM/themes/$name.theme.zsh" "$EMBER/themes/$name.theme.zsh"; do
    [[ -r $file ]] && { print -r -- "$file"; return 0 }
  done
  return 1
}

# --- deferred loading --------------------------------------------------------
# Units registered with ember_defer run right after the first prompt is drawn,
# so an expensive plugin never delays the shell becoming usable.
typeset -ga _ember_deferred=()

ember_defer() { _ember_deferred+=("$1") }

_ember_run_deferred() {
  local snippet
  for snippet in "${_ember_deferred[@]}"; do
    eval "$snippet"
  done
  _ember_deferred=()
  add-zsh-hook -d precmd _ember_run_deferred
  # Redraw once so a deferred prompt segment shows up immediately.
  (( ${+functions[_ember_prompt_refresh]} )) && _ember_prompt_refresh
}

# ember_lazy <cmd> [cmd...] -- <init code>
# Replaces each command with a stub. On first call the stub removes itself,
# runs the init code, and re-dispatches to the real command. This is how
# nvm/pyenv/rbenv stay off the startup path.
ember_lazy() {
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

typeset -ga _ember_lib_order=(
  options history directory completion keybindings termsupport aliases git async
)

typeset -g _ember_lib
for _ember_lib in "${_ember_lib_order[@]}"; do
  _ember_source "lib:$_ember_lib" "$EMBER/lib/$_ember_lib.zsh" \
    || _ember_warn "missing core library: $_ember_lib"
done
unset _ember_lib

# --- plugins -----------------------------------------------------------------
typeset -ga ember_loaded_plugins=()
typeset -g _ember_plugin _ember_path

for _ember_plugin in "${ember_plugins[@]}"; do
  if _ember_path=$(_ember_find_plugin "$_ember_plugin"); then
    # A plugin directory is prepended to fpath so it can ship completions.
    fpath=("${_ember_path:h}" $fpath)
    if _ember_source "plugin:$_ember_plugin" "$_ember_path"; then
      ember_loaded_plugins+=("$_ember_plugin")
    else
      _ember_warn "plugin '$_ember_plugin' failed to load"
    fi
  else
    _ember_warn "plugin '$_ember_plugin' not found (try: ember list plugins)"
  fi
done
unset _ember_plugin _ember_path

# --- theme -------------------------------------------------------------------
if [[ $EMBER_THEME != (none|off) ]]; then
  if _ember_path=$(_ember_find_theme "$EMBER_THEME"); then
    _ember_source "theme:$EMBER_THEME" "$_ember_path"
  else
    _ember_warn "theme '$EMBER_THEME' not found, falling back to 'spark'"
    _ember_source "theme:spark" "$EMBER/themes/spark.theme.zsh"
  fi
  unset _ember_path
fi

# --- user overrides ----------------------------------------------------------
# Anything in custom/*.zsh loads last so it can override plugins and themes.
typeset -g _ember_file
for _ember_file in "$EMBER_CUSTOM"/*.zsh(N); do
  _ember_source "custom:${_ember_file:t:r}" "$_ember_file"
done
unset _ember_file

# --- finalize ----------------------------------------------------------------
# Completion init runs once, after every plugin has had a chance to touch fpath.
_ember_init_completion

(( ${#_ember_deferred} )) && add-zsh-hook precmd _ember_run_deferred

# `ember` management command.
_ember_source "tool:cli" "$EMBER/tools/ember.zsh"

return 0
