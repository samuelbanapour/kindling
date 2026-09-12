# tools/ember.zsh — the `ember` management command.

ember() {
  emulate -L zsh
  setopt local_options extended_glob

  local cmd=${1:-help}; shift

  case $cmd in
    (help|-h|--help)   _ember_cmd_help "$@" ;;
    (list|ls)          _ember_cmd_list "$@" ;;
    (enable|add)       _ember_cmd_enable "$@" ;;
    (disable|rm)       _ember_cmd_disable "$@" ;;
    (theme)            _ember_cmd_theme "$@" ;;
    (off)              _ember_cmd_off "$@" ;;
    (on)               _ember_cmd_on "$@" ;;
    (reload)           _ember_cmd_reload "$@" ;;
    (update|upgrade)   _ember_cmd_update "$@" ;;
    (doctor)           _ember_cmd_doctor "$@" ;;
    (profile|bench)    _ember_cmd_profile "$@" ;;
    (new)              _ember_cmd_new "$@" ;;
    (version|--version) print -- "ember $EMBER_VERSION" ;;
    (*)
      print -ru2 -- "ember: unknown command '$cmd'"
      _ember_cmd_help; return 1 ;;
  esac
}

_ember_cmd_help() {
  print -- "ember $EMBER_VERSION — a zsh framework

usage: ember <command> [args]

  list [plugins|themes]     show what's available and what's on
  enable <plugin>...        add plugins to ~/.zshrc and load them now
  disable <plugin>...       remove plugins from ~/.zshrc
  theme [name]              show or switch the prompt theme
  off                       stop loading Ember (back to your previous setup)
  on                        start loading Ember again
  reload                    re-exec the shell with a fresh config
  update                    pull the latest Ember and rebuild caches
  doctor                    check the install for common problems
  profile                   time every unit loaded at startup
  new plugin|theme <name>   scaffold a custom unit in \$EMBER_CUSTOM

  \$EMBER         $EMBER
  \$EMBER_CUSTOM  $EMBER_CUSTOM
  \$EMBER_CACHE   $EMBER_CACHE
  install        $EMBER_INSTALL"
}

# --- listing -----------------------------------------------------------------

_ember_all_plugins() {
  local -a found
  found=( "$EMBER"/plugins/*/*.plugin.zsh(N:h:t) "$EMBER_CUSTOM"/plugins/*/*.plugin.zsh(N:h:t) )
  print -l -- ${(iu)found}
}

_ember_all_themes() {
  local -a found
  found=( "$EMBER"/themes/*.theme.zsh(N:t:r:r) "$EMBER_CUSTOM"/themes/*.theme.zsh(N:t:r:r) )
  print -l -- ${(iu)found}
}

_ember_cmd_list() {
  local what=${1:-all}
  if [[ $what == (all|plugins) ]]; then
    print -- "plugins:"
    local p
    for p in $(_ember_all_plugins); do
      if (( ${ember_loaded_plugins[(I)$p]} )); then
        _ember_mark "  %F{green}${EMBER_GLYPH[on]}%f" "$p"
      else
        _ember_mark "  %F{8}${EMBER_GLYPH[off]}%f" "$p"
      fi
    done
  fi
  if [[ $what == (all|themes) ]]; then
    [[ $what == all ]] && print
    print -- "themes:"
    local t
    for t in $(_ember_all_themes); do
      if [[ $t == $EMBER_THEME ]]; then
        _ember_mark "  %F{green}${EMBER_GLYPH[on]}%f" "$t"
      else
        _ember_mark "  %F{8}${EMBER_GLYPH[off]}%f" "$t"
      fi
    done
  fi
}

# _ember_mark <styled-marker> <text>...
# The marker goes through prompt expansion so %F{green} becomes a colour; the
# text never does. `setopt prompt_subst` is on for the interactive shell, which
# means `print -P` would expand a `$` or a `%` inside a path or a filename —
# that is user data, and it must be printed literally.
_ember_mark() {
  print -Pn -- "$1"
  shift
  print -r -- " $*"
}

# --- enable / disable --------------------------------------------------------

: ${EMBER_ZSHRC:="$HOME/.zshrc"}

# Rewrites the `ember_plugins=(...)` line in .zshrc in place.
# <op> is add or remove.
_ember_rewrite_plugins() {
  local op=$1; shift
  local -a wanted=("$@")
  local rc=$EMBER_ZSHRC

  [[ -f $rc ]] || { print -ru2 -- "ember: $rc not found"; return 1 }
  if ! command grep -q '^[[:space:]]*ember_plugins=(' "$rc"; then
    print -ru2 -- "ember: no ember_plugins=(...) line in $rc — edit it by hand"
    return 1
  fi

  local -a current=("${ember_plugins[@]}") next=()
  local p
  case $op in
    (add)
      next=("${current[@]}")
      for p in "${wanted[@]}"; do
        (( ${next[(I)$p]} )) || next+=("$p")
      done ;;
    (remove)
      for p in "${current[@]}"; do
        (( ${wanted[(I)$p]} )) || next+=("$p")
      done ;;
  esac

  # Back up once per day so a bad edit is always recoverable.
  local backup="$rc.ember-backup-$(date +%Y%m%d)"
  [[ -f $backup ]] || command cp -- "$rc" "$backup"

  local tmp="$rc.ember.$$"
  command awk -v repl="ember_plugins=(${next[*]})" '
    /^[[:space:]]*ember_plugins=\(/ && !done { print repl; done = 1; next }
    { print }
  ' "$rc" >| "$tmp" && command mv -f "$tmp" "$rc"

  ember_plugins=("${next[@]}")
  print -- "ember_plugins=(${next[*]})"
}

_ember_cmd_enable() {
  (( $# )) || { print -ru2 -- "usage: ember enable <plugin>..."; return 1 }
  local p missing=0
  for p in "$@"; do
    _ember_find_plugin "$p" >/dev/null || {
      print -ru2 -- "ember: no such plugin '$p'"; missing=1
    }
  done
  (( missing )) && return 1

  _ember_rewrite_plugins add "$@" || return 1

  # Load them into this session too, so `enable` takes effect immediately.
  local path_
  for p in "$@"; do
    if path_=$(_ember_find_plugin "$p"); then
      fpath=("${path_:h}" $fpath)
      source "$path_" && ember_loaded_plugins+=("$p")
    fi
  done
  print -- "enabled: $*"
}

_ember_cmd_disable() {
  (( $# )) || { print -ru2 -- "usage: ember disable <plugin>..."; return 1 }
  _ember_rewrite_plugins remove "$@" || return 1
  print -- "disabled: $* (run 'ember reload' to drop them from this shell)"
}

# --- theme -------------------------------------------------------------------

_ember_cmd_theme() {
  if (( ! $# )); then print -- "$EMBER_THEME"; return 0; fi

  local name=$1 file
  if ! file=$(_ember_find_theme "$name"); then
    print -ru2 -- "ember: no such theme '$name'"
    print -ru2 -- "available: $(_ember_all_themes | paste -sd' ' -)"
    return 1
  fi

  # Tear down the current theme's hooks before installing the new one, or the
  # two will fight over PROMPT on every command.
  local fn
  for fn in ${(k)functions}; do
    [[ $fn == _ember_${EMBER_THEME}_* ]] || continue
    add-zsh-hook -d precmd  "$fn" 2>/dev/null
    add-zsh-hook -d preexec "$fn" 2>/dev/null
  done

  EMBER_THEME=$name
  source "$file"

  if [[ -f $EMBER_ZSHRC ]] && command grep -q '^[[:space:]]*EMBER_THEME=' "$EMBER_ZSHRC"; then
    local tmp="$EMBER_ZSHRC.ember.$$"
    command awk -v repl="EMBER_THEME=$name" '
      /^[[:space:]]*EMBER_THEME=/ && !done { print repl; done = 1; next }
      { print }
    ' "$EMBER_ZSHRC" >| "$tmp" && command mv -f "$tmp" "$EMBER_ZSHRC"
  fi
  print -- "theme: $name"
}

# --- the off switch ----------------------------------------------------------
#
# The .zshrc block Ember installs is wrapped in a test for this file. That makes
# the framework removable without editing anything, which matters in two
# situations: you want your previous setup back, and Ember has broken your shell
# badly enough that editing .zshrc from inside it is unpleasant. For the second,
# `touch ~/.ember-off` from any shell — including a bare `zsh -f` — gets you out.

: ${EMBER_SWITCH:="$HOME/.ember-off"}
typeset -g EMBER_SWITCH

_ember_cmd_off() {
  if [[ -f $EMBER_SWITCH ]]; then
    print -- "Ember is already off. Turn it back on with: ember on"
    return 0
  fi
  : >| "$EMBER_SWITCH" || return 1
  print -- "Ember off. Whatever your .zshrc loaded before it takes over again."
  print -- "Turn it back on with: ember on"
  exec "${SHELL:-zsh}" -l
}

_ember_cmd_on() {
  if [[ ! -f $EMBER_SWITCH ]]; then
    print -- "Ember is already on."
    return 0
  fi
  command rm -f -- "$EMBER_SWITCH" || return 1
  print -- "Ember on."
  exec "${SHELL:-zsh}" -l
}

# --- reload / update ---------------------------------------------------------

_ember_cmd_reload() {
  # Drop the completion dump so a reload also picks up new completions.
  command rm -f -- "$EMBER_COMPDUMP" "$EMBER_COMPDUMP.zwc" 2>/dev/null
  exec "${SHELL:-zsh}" -l
}

_ember_cmd_update() {
  # A package-managed copy must be updated through its package manager;
  # `git pull` in the Cellar would be undone by the next `brew upgrade`.
  case $EMBER_INSTALL in
    (homebrew)
      print -- "Ember was installed with Homebrew. Update it with:"
      print -- ""
      print -- "    brew update && brew upgrade ember"
      print -- ""
      command rm -f -- "$EMBER_COMPDUMP" "$EMBER_COMPDUMP.zwc" 2>/dev/null
      print -- "caches cleared"
      return 0 ;;
    (readonly)
      print -ru2 -- "ember: $EMBER is not writable; update it the way it was installed"
      return 1 ;;
  esac

  if [[ -d $EMBER/.git ]]; then
    print -- "updating $EMBER"
    local before after
    before=$(command git -C "$EMBER" rev-parse --short HEAD 2>/dev/null)
    command git -C "$EMBER" pull --ff-only || {
      print -ru2 -- "ember: update failed — resolve the state of $EMBER by hand"
      return 1
    }
    after=$(command git -C "$EMBER" rev-parse --short HEAD 2>/dev/null)
    if [[ $before == $after ]]; then
      print -- "already up to date ($after)"
    else
      print -- "updated $before -> $after"
      command git -C "$EMBER" log --oneline "$before..$after" | head -20
    fi
  else
    print -- "$EMBER is not a git checkout; nothing to pull"
  fi
  command rm -f -- "$EMBER_COMPDUMP" "$EMBER_COMPDUMP.zwc" 2>/dev/null
  print -- "caches cleared — run 'ember reload'"
}

# --- doctor ------------------------------------------------------------------

_ember_cmd_doctor() {
  local -i problems=0
  local ok="  %F{green}${EMBER_GLYPH[ok]}%f"
  local bad="  %F{red}${EMBER_GLYPH[fail]}%f"
  local warn="  %F{yellow}${EMBER_GLYPH[warn]}%f"

  print -P -- "%Bember $EMBER_VERSION%b"
  print -r  -- "  zsh ${ZSH_VERSION} (${ZSH_PATCHLEVEL:-unknown})"
  print

  print -P -- "%Bpaths%b"
  _ember_mark "  " "installed: $EMBER_INSTALL"
  local d
  for d in EMBER EMBER_CUSTOM EMBER_CACHE; do
    if [[ -d ${(P)d} ]]; then
      _ember_mark "$ok" "\$$d ${(P)d}"
    else
      _ember_mark "$bad" "\$$d ${(P)d} (missing)"; (( problems++ ))
    fi
  done

  print
  print -P -- "%Brequirements%b"
  if is-at-least 5.1; then
    _ember_mark "$ok" "zsh $ZSH_VERSION is recent enough"
  else
    _ember_mark "$bad" "zsh $ZSH_VERSION is too old — 5.1 or newer is required"
    (( problems++ ))
  fi

  local c
  for c in git awk sed grep; do
    if (( $+commands[$c] )); then
      _ember_mark "$ok" "$c"
    else
      _ember_mark "$bad" "$c is missing"; (( problems++ ))
    fi
  done

  print
  print -P -- "%Bconfiguration%b"
  if [[ -f $EMBER_ZSHRC ]] && command grep -q "ember.zsh" "$EMBER_ZSHRC"; then
    _ember_mark "$ok" "$EMBER_ZSHRC sources ember.zsh"
  else
    _ember_mark "$bad" "$EMBER_ZSHRC does not source ember.zsh"; (( problems++ ))
  fi

  # If the block is guarded, say so, and say how to use the guard. Someone
  # reading doctor output in a panic should not have to find this in a README.
  if [[ -f $EMBER_ZSHRC ]] && command grep -q 'ember-off' "$EMBER_ZSHRC"; then
    _ember_mark "$ok" "off switch installed (ember off / ember on)"
  else
    _ember_mark "$warn" "no off switch in $EMBER_ZSHRC; 'ember off' will not work"
  fi

  # Two frameworks loading at once is the failure this is meant to catch.
  if [[ -f $EMBER_ZSHRC ]] && command grep -q 'oh-my-zsh\.sh' "$EMBER_ZSHRC"; then
    if command grep -q 'ember-off.*oh-my-zsh\.sh' "$EMBER_ZSHRC"; then
      _ember_mark "$ok" "oh-my-zsh still installed; it loads when Ember is off"
    else
      _ember_mark "$bad" "oh-my-zsh also loads from $EMBER_ZSHRC - both frameworks are running"
      (( problems++ ))
    fi
  fi

  # A group- or world-writable directory in fpath makes compinit refuse to
  # build a dump, and it does so quietly. It is the most common silent
  # breakage in any zsh framework, so name the offending directories.
  local -a insecure
  insecure=( ${^fpath}(N/W) ${^fpath}(N/f:g+w:) )
  if (( ${#insecure} )); then
    _ember_mark "$warn" "group- or world-writable directories in \$fpath:"
    print -rl -- "      ${^insecure}"
    print -r  -- "      fix with: chmod g-w,o-w <dir>"
    (( problems++ ))
  else
    _ember_mark "$ok" "\$fpath permissions are sane"
  fi

  if [[ -f $EMBER_COMPDUMP ]]; then
    local size=$(command du -h "$EMBER_COMPDUMP" 2>/dev/null | command awk '{print $1}')
    _ember_mark "$ok" "completion dump present (${size:-?})"
    if [[ -f $EMBER_COMPDUMP.zwc ]]; then
      _ember_mark "$ok" "completion dump is compiled"
    else
      _ember_mark "$warn" "completion dump is not compiled — it will be on next start"
    fi
  else
    _ember_mark "$warn" "no completion dump yet — it builds on the next shell"
  fi

  print
  print -P -- "%Bloaded%b"
  print -r -- "  theme:   $EMBER_THEME"
  print -r -- "  plugins: ${ember_loaded_plugins[*]:-none}"
  local -a requested_missing
  local p
  for p in "${ember_plugins[@]}"; do
    (( ${ember_loaded_plugins[(I)$p]} )) || requested_missing+=("$p")
  done
  if (( ${#requested_missing} )); then
    _ember_mark "$bad" "requested but not loaded: ${requested_missing[*]}"
    (( problems++ ))
  fi

  print
  if (( problems )); then
    print -P -- "%F{red}$problems problem(s) found%f"
    return 1
  fi
  print -P -- "%F{green}no problems found%f"
}

# --- profile -----------------------------------------------------------------

_ember_cmd_profile() {
  if (( ! ${#EMBER_LOAD_MS} )); then
    print -- "No profile recorded. Startup timing is off by default because it"
    print -- "costs a clock read per unit. Turn it on and start a new shell:"
    print
    print -- "  EMBER_PROFILE=1 zsh -i -c 'ember profile'"
    return 1
  fi

  local -a rows
  local k total=0
  for k in ${(k)EMBER_LOAD_MS}; do
    # Zero-padded to a fixed width so a plain reverse sort orders correctly.
    # zsh's numeric sort compares the digit runs inside a string, which gets
    # 1.9 and 1.1 the wrong way round.
    rows+=("$(printf '%012.4f' ${EMBER_LOAD_MS[$k]})|$k")
    total=$(( total + EMBER_LOAD_MS[$k] ))
  done

  print -P -- "%Bstartup: $(printf '%.1f' $total) ms across ${#rows} unit(s)%b"
  print
  local row ms name width
  for row in ${(O)rows}; do
    ms=${row%%|*}; name=${row#*|}
    # One block per 2ms, so the shape of the cost is visible at a glance.
    width=$(( ms / 2 ))
    (( width > 40 )) && width=40
    # Built by repetition rather than ${(l:n::char:)}: under LC_CTYPE=C that
    # padding counts a 3-byte block character as three, and emits a fragment
    # of one at the end.
    local block=${EMBER_GLYPH[bar]} bar=""
    repeat $width bar+=$block
    printf '%8.1f ms  %-28s %s\n' "$ms" "$name" "$bar"
  done
}

# --- scaffolding -------------------------------------------------------------

_ember_cmd_new() {
  local kind=$1 name=$2
  [[ -z $kind || -z $name ]] && {
    print -ru2 -- "usage: ember new plugin|theme <name>"; return 1
  }

  case $kind in
    (plugin)
      local dir="$EMBER_CUSTOM/plugins/$name"
      [[ -e $dir ]] && { print -ru2 -- "ember: $dir already exists"; return 1 }
      command mkdir -p "$dir"
      cat > "$dir/$name.plugin.zsh" <<PLUGIN
# plugins/$name — <one line describing what this is for>

# Bail out quietly if the tool this plugin wraps isn't installed.
# (( \$+commands[sometool] )) || return 0

alias ${name}h='print -- "hello from the $name plugin"'

${name}_example() {
  print -- "edit \$0 to make this do something"
}
PLUGIN
      print -- "created $dir/$name.plugin.zsh"
      print -- "enable it with: ember enable $name" ;;

    (theme)
      local file="$EMBER_CUSTOM/themes/$name.theme.zsh"
      [[ -e $file ]] && { print -ru2 -- "ember: $file already exists"; return 1 }
      cat > "$file" <<THEME
# themes/$name — <one line describing the look>

setopt prompt_subst
autoload -Uz add-zsh-hook

_ember_${name}_precmd() {
  local color=cyan
  (( EMBER_LAST_STATUS != 0 )) && color=red

  # ember_async keeps git off the critical path; the result shows up on the
  # next redraw. Drop it if this theme doesn't need git.
  ember_async ${name}_git 'ember_git_branch' "\$PWD"
  local branch=\${EMBER_ASYNC_RESULT[${name}_git]}

  PROMPT="%F{blue}%~%f \${branch:+%F{green}\$branch%f }%F{\${color}}❯%f "
  RPROMPT=""
}
add-zsh-hook precmd _ember_${name}_precmd
THEME
      print -- "created $file"
      print -- "try it with: ember theme $name" ;;

    (*) print -ru2 -- "ember: expected 'plugin' or 'theme', got '$kind'"; return 1 ;;
  esac
}

# --- completion --------------------------------------------------------------

_ember_complete() {
  local -a subcmds
  subcmds=(
    'list:show available plugins and themes'
    'enable:turn a plugin on'
    'disable:turn a plugin off'
    'theme:show or switch the prompt theme'
    'off:stop loading Ember'
    'on:start loading Ember again'
    'reload:restart the shell'
    'update:pull the latest Ember'
    'doctor:check the install'
    'profile:time startup'
    'new:scaffold a custom plugin or theme'
    'version:print the version'
    'help:show usage'
  )

  if (( CURRENT == 2 )); then
    _describe -t commands 'ember command' subcmds
    return
  fi

  case ${words[2]} in
    (enable)  compadd -- $(_ember_all_plugins) ;;
    (disable) compadd -- "${ember_plugins[@]}" ;;
    (theme)   compadd -- $(_ember_all_themes) ;;
    (list)    compadd -- plugins themes ;;
    (new)     (( CURRENT == 3 )) && compadd -- plugin theme ;;
  esac
}
compdef _ember_complete ember 2>/dev/null
