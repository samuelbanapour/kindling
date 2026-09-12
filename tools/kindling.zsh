# tools/kindling.zsh — the `kindling` management command.

kindling() {
  emulate -L zsh
  setopt local_options extended_glob

  local cmd=${1:-help}; shift

  case $cmd in
    (help|-h|--help)   _kindling_cmd_help "$@" ;;
    (list|ls)          _kindling_cmd_list "$@" ;;
    (enable|add)       _kindling_cmd_enable "$@" ;;
    (disable|rm)       _kindling_cmd_disable "$@" ;;
    (theme)            _kindling_cmd_theme "$@" ;;
    (off)              _kindling_cmd_off "$@" ;;
    (on)               _kindling_cmd_on "$@" ;;
    (reload)           _kindling_cmd_reload "$@" ;;
    (update|upgrade)   _kindling_cmd_update "$@" ;;
    (doctor)           _kindling_cmd_doctor "$@" ;;
    (profile|bench)    _kindling_cmd_profile "$@" ;;
    (new)              _kindling_cmd_new "$@" ;;
    (version|--version) print -- "kindling $KINDLING_VERSION" ;;
    (*)
      print -ru2 -- "kindling: unknown command '$cmd'"
      _kindling_cmd_help; return 1 ;;
  esac
}

_kindling_cmd_help() {
  print -- "kindling $KINDLING_VERSION — a zsh framework

usage: kindling <command> [args]

  list [plugins|themes]     show what's available and what's on
  enable <plugin>...        add plugins to ~/.zshrc and load them now
  disable <plugin>...       remove plugins from ~/.zshrc
  theme [name]              show or switch the prompt theme
  off                       stop loading Kindling (back to your previous setup)
  on                        start loading Kindling again
  reload                    re-exec the shell with a fresh config
  update                    pull the latest Kindling and rebuild caches
  doctor                    check the install for common problems
  profile                   time every unit loaded at startup
  new plugin|theme <name>   scaffold a custom unit in \$KINDLING_CUSTOM

  \$KINDLING         $KINDLING
  \$KINDLING_CUSTOM  $KINDLING_CUSTOM
  \$KINDLING_CACHE   $KINDLING_CACHE
  install        $KINDLING_INSTALL"
}

# --- listing -----------------------------------------------------------------

_kindling_all_plugins() {
  local -a found
  found=( "$KINDLING"/plugins/*/*.plugin.zsh(N:h:t) "$KINDLING_CUSTOM"/plugins/*/*.plugin.zsh(N:h:t) )
  print -l -- ${(iu)found}
}

_kindling_all_themes() {
  local -a found
  found=( "$KINDLING"/themes/*.theme.zsh(N:t:r:r) "$KINDLING_CUSTOM"/themes/*.theme.zsh(N:t:r:r) )
  print -l -- ${(iu)found}
}

_kindling_cmd_list() {
  local what=${1:-all}
  if [[ $what == (all|plugins) ]]; then
    print -- "plugins:"
    local p
    for p in $(_kindling_all_plugins); do
      if (( ${kindling_loaded_plugins[(I)$p]} )); then
        _kindling_mark "  %F{green}${KINDLING_GLYPH[on]}%f" "$p"
      else
        _kindling_mark "  %F{8}${KINDLING_GLYPH[off]}%f" "$p"
      fi
    done
  fi
  if [[ $what == (all|themes) ]]; then
    [[ $what == all ]] && print
    print -- "themes:"
    local t
    for t in $(_kindling_all_themes); do
      if [[ $t == $KINDLING_THEME ]]; then
        _kindling_mark "  %F{green}${KINDLING_GLYPH[on]}%f" "$t"
      else
        _kindling_mark "  %F{8}${KINDLING_GLYPH[off]}%f" "$t"
      fi
    done
  fi
}

# _kindling_mark <styled-marker> <text>...
# The marker goes through prompt expansion so %F{green} becomes a colour; the
# text never does. `setopt prompt_subst` is on for the interactive shell, which
# means `print -P` would expand a `$` or a `%` inside a path or a filename —
# that is user data, and it must be printed literally.
_kindling_mark() {
  print -Pn -- "$1"
  shift
  print -r -- " $*"
}

# --- enable / disable --------------------------------------------------------

: ${KINDLING_ZSHRC:="$HOME/.zshrc"}

# Rewrites the `kindling_plugins=(...)` line in .zshrc in place.
# <op> is add or remove.
_kindling_rewrite_plugins() {
  local op=$1; shift
  local -a wanted=("$@")
  local rc=$KINDLING_ZSHRC

  [[ -f $rc ]] || { print -ru2 -- "kindling: $rc not found"; return 1 }
  if ! command grep -q '^[[:space:]]*kindling_plugins=(' "$rc"; then
    print -ru2 -- "kindling: no kindling_plugins=(...) line in $rc — edit it by hand"
    return 1
  fi

  local -a current=("${kindling_plugins[@]}") next=()
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
  local backup="$rc.kindling-backup-$(date +%Y%m%d)"
  [[ -f $backup ]] || command cp -- "$rc" "$backup"

  local tmp="$rc.kindling.$$"
  command awk -v repl="kindling_plugins=(${next[*]})" '
    /^[[:space:]]*kindling_plugins=\(/ && !done { print repl; done = 1; next }
    { print }
  ' "$rc" >| "$tmp" && command mv -f "$tmp" "$rc"

  kindling_plugins=("${next[@]}")
  print -- "kindling_plugins=(${next[*]})"
}

_kindling_cmd_enable() {
  (( $# )) || { print -ru2 -- "usage: kindling enable <plugin>..."; return 1 }
  local p missing=0
  for p in "$@"; do
    _kindling_find_plugin "$p" >/dev/null || {
      print -ru2 -- "kindling: no such plugin '$p'"; missing=1
    }
  done
  (( missing )) && return 1

  _kindling_rewrite_plugins add "$@" || return 1

  # Load them into this session too, so `enable` takes effect immediately.
  local path_
  for p in "$@"; do
    if path_=$(_kindling_find_plugin "$p"); then
      fpath=("${path_:h}" $fpath)
      source "$path_" && kindling_loaded_plugins+=("$p")
    fi
  done
  print -- "enabled: $*"
}

_kindling_cmd_disable() {
  (( $# )) || { print -ru2 -- "usage: kindling disable <plugin>..."; return 1 }
  _kindling_rewrite_plugins remove "$@" || return 1
  print -- "disabled: $* (run 'kindling reload' to drop them from this shell)"
}

# --- theme -------------------------------------------------------------------

_kindling_cmd_theme() {
  if (( ! $# )); then print -- "$KINDLING_THEME"; return 0; fi

  local name=$1 file
  if ! file=$(_kindling_find_theme "$name"); then
    print -ru2 -- "kindling: no such theme '$name'"
    print -ru2 -- "available: $(_kindling_all_themes | paste -sd' ' -)"
    return 1
  fi

  # Tear down the current theme's hooks before installing the new one, or the
  # two will fight over PROMPT on every command.
  local fn
  for fn in ${(k)functions}; do
    [[ $fn == _kindling_${KINDLING_THEME}_* ]] || continue
    add-zsh-hook -d precmd  "$fn" 2>/dev/null
    add-zsh-hook -d preexec "$fn" 2>/dev/null
  done

  KINDLING_THEME=$name
  source "$file"

  if [[ -f $KINDLING_ZSHRC ]] && command grep -q '^[[:space:]]*KINDLING_THEME=' "$KINDLING_ZSHRC"; then
    local tmp="$KINDLING_ZSHRC.kindling.$$"
    command awk -v repl="KINDLING_THEME=$name" '
      /^[[:space:]]*KINDLING_THEME=/ && !done { print repl; done = 1; next }
      { print }
    ' "$KINDLING_ZSHRC" >| "$tmp" && command mv -f "$tmp" "$KINDLING_ZSHRC"
  fi
  print -- "theme: $name"
}

# --- the off switch ----------------------------------------------------------
#
# The .zshrc block Kindling installs is wrapped in a test for this file. That makes
# the framework removable without editing anything, which matters in two
# situations: you want your previous setup back, and Kindling has broken your shell
# badly enough that editing .zshrc from inside it is unpleasant. For the second,
# `touch ~/.kindling-off` from any shell — including a bare `zsh -f` — gets you out.

: ${KINDLING_SWITCH:="$HOME/.kindling-off"}
typeset -g KINDLING_SWITCH

_kindling_cmd_off() {
  if [[ -f $KINDLING_SWITCH ]]; then
    print -- "Kindling is already off. Turn it back on with: kindling on"
    return 0
  fi
  : >| "$KINDLING_SWITCH" || return 1
  print -- "Kindling off. Whatever your .zshrc loaded before it takes over again."
  print -- "Turn it back on with: kindling on"
  exec "${SHELL:-zsh}" -l
}

_kindling_cmd_on() {
  if [[ ! -f $KINDLING_SWITCH ]]; then
    print -- "Kindling is already on."
    return 0
  fi
  command rm -f -- "$KINDLING_SWITCH" || return 1
  print -- "Kindling on."
  exec "${SHELL:-zsh}" -l
}

# --- reload / update ---------------------------------------------------------

_kindling_cmd_reload() {
  # Drop the completion dump so a reload also picks up new completions.
  command rm -f -- "$KINDLING_COMPDUMP" "$KINDLING_COMPDUMP.zwc" 2>/dev/null
  exec "${SHELL:-zsh}" -l
}

_kindling_cmd_update() {
  # A package-managed copy must be updated through its package manager;
  # `git pull` in the Cellar would be undone by the next `brew upgrade`.
  case $KINDLING_INSTALL in
    (homebrew)
      print -- "Kindling was installed with Homebrew. Update it with:"
      print -- ""
      print -- "    brew update && brew upgrade kindling"
      print -- ""
      command rm -f -- "$KINDLING_COMPDUMP" "$KINDLING_COMPDUMP.zwc" 2>/dev/null
      print -- "caches cleared"
      return 0 ;;
    (readonly)
      print -ru2 -- "kindling: $KINDLING is not writable; update it the way it was installed"
      return 1 ;;
  esac

  if [[ -d $KINDLING/.git ]]; then
    print -- "updating $KINDLING"
    local before after
    before=$(command git -C "$KINDLING" rev-parse --short HEAD 2>/dev/null)
    command git -C "$KINDLING" pull --ff-only || {
      print -ru2 -- "kindling: update failed — resolve the state of $KINDLING by hand"
      return 1
    }
    after=$(command git -C "$KINDLING" rev-parse --short HEAD 2>/dev/null)
    if [[ $before == $after ]]; then
      print -- "already up to date ($after)"
    else
      print -- "updated $before -> $after"
      command git -C "$KINDLING" log --oneline "$before..$after" | head -20
    fi
  else
    # A copy made by install.sh. Point at the thing that can actually update it
    # rather than leaving the user to work it out.
    print -- "$KINDLING is an installed copy, not a checkout — nothing to pull."
    print -- "Update it by re-running the installer from wherever the repository is:"
    print -- ""
    print -- "    sh /path/to/kindling/install.sh --dir $KINDLING"
    print -- ""
  fi
  command rm -f -- "$KINDLING_COMPDUMP" "$KINDLING_COMPDUMP.zwc" 2>/dev/null
  print -- "caches cleared — run 'kindling reload'"
}

# --- doctor ------------------------------------------------------------------

_kindling_cmd_doctor() {
  local -i problems=0
  local ok="  %F{green}${KINDLING_GLYPH[ok]}%f"
  local bad="  %F{red}${KINDLING_GLYPH[fail]}%f"
  local warn="  %F{yellow}${KINDLING_GLYPH[warn]}%f"

  print -P -- "%Bember $KINDLING_VERSION%b"
  print -r  -- "  zsh ${ZSH_VERSION} (${ZSH_PATCHLEVEL:-unknown})"
  print

  print -P -- "%Bpaths%b"
  _kindling_mark "  " "installed: $KINDLING_INSTALL"
  local d
  for d in KINDLING KINDLING_CUSTOM KINDLING_CACHE; do
    if [[ -d ${(P)d} ]]; then
      _kindling_mark "$ok" "\$$d ${(P)d}"
    else
      _kindling_mark "$bad" "\$$d ${(P)d} (missing)"; (( problems++ ))
    fi
  done

  print
  print -P -- "%Brequirements%b"
  if is-at-least 5.1; then
    _kindling_mark "$ok" "zsh $ZSH_VERSION is recent enough"
  else
    _kindling_mark "$bad" "zsh $ZSH_VERSION is too old — 5.1 or newer is required"
    (( problems++ ))
  fi

  local c
  for c in git awk sed grep; do
    if (( $+commands[$c] )); then
      _kindling_mark "$ok" "$c"
    else
      _kindling_mark "$bad" "$c is missing"; (( problems++ ))
    fi
  done

  print
  print -P -- "%Bconfiguration%b"
  if [[ -f $KINDLING_ZSHRC ]] && command grep -q "kindling.zsh" "$KINDLING_ZSHRC"; then
    _kindling_mark "$ok" "$KINDLING_ZSHRC sources kindling.zsh"
  else
    _kindling_mark "$bad" "$KINDLING_ZSHRC does not source kindling.zsh"; (( problems++ ))
  fi

  # If the block is guarded, say so, and say how to use the guard. Someone
  # reading doctor output in a panic should not have to find this in a README.
  if [[ -f $KINDLING_ZSHRC ]] && command grep -q 'kindling-off' "$KINDLING_ZSHRC"; then
    _kindling_mark "$ok" "off switch installed (kindling off / kindling on)"
  else
    _kindling_mark "$warn" "no off switch in $KINDLING_ZSHRC; 'kindling off' will not work"
  fi

  # Two frameworks loading at once is the failure this is meant to catch.
  if [[ -f $KINDLING_ZSHRC ]] && command grep -q 'oh-my-zsh\.sh' "$KINDLING_ZSHRC"; then
    if command grep -q 'kindling-off.*oh-my-zsh\.sh' "$KINDLING_ZSHRC"; then
      _kindling_mark "$ok" "oh-my-zsh still installed; it loads when Kindling is off"
    else
      _kindling_mark "$bad" "oh-my-zsh also loads from $KINDLING_ZSHRC - both frameworks are running"
      (( problems++ ))
    fi
  fi

  # A group- or world-writable directory in fpath makes compinit refuse to
  # build a dump, and it does so quietly. It is the most common silent
  # breakage in any zsh framework, so name the offending directories.
  local -a insecure
  insecure=( ${^fpath}(N/W) ${^fpath}(N/f:g+w:) )
  if (( ${#insecure} )); then
    _kindling_mark "$warn" "group- or world-writable directories in \$fpath:"
    print -rl -- "      ${^insecure}"
    print -r  -- "      fix with: chmod g-w,o-w <dir>"
    (( problems++ ))
  else
    _kindling_mark "$ok" "\$fpath permissions are sane"
  fi

  if [[ -f $KINDLING_COMPDUMP ]]; then
    local size=$(command du -h "$KINDLING_COMPDUMP" 2>/dev/null | command awk '{print $1}')
    _kindling_mark "$ok" "completion dump present (${size:-?})"
    if [[ -f $KINDLING_COMPDUMP.zwc ]]; then
      _kindling_mark "$ok" "completion dump is compiled"
    else
      _kindling_mark "$warn" "completion dump is not compiled — it will be on next start"
    fi
  else
    _kindling_mark "$warn" "no completion dump yet — it builds on the next shell"
  fi

  print
  print -P -- "%Bloaded%b"
  print -r -- "  theme:   $KINDLING_THEME"
  print -r -- "  plugins: ${kindling_loaded_plugins[*]:-none}"
  local -a requested_missing
  local p
  for p in "${kindling_plugins[@]}"; do
    (( ${kindling_loaded_plugins[(I)$p]} )) || requested_missing+=("$p")
  done
  if (( ${#requested_missing} )); then
    _kindling_mark "$bad" "requested but not loaded: ${requested_missing[*]}"
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

_kindling_cmd_profile() {
  if (( ! ${#KINDLING_LOAD_MS} )); then
    print -- "No profile recorded. Startup timing is off by default because it"
    print -- "costs a clock read per unit. Turn it on and start a new shell:"
    print
    print -- "  KINDLING_PROFILE=1 zsh -i -c 'kindling profile'"
    return 1
  fi

  local -a rows
  local k total=0
  for k in ${(k)KINDLING_LOAD_MS}; do
    # Zero-padded to a fixed width so a plain reverse sort orders correctly.
    # zsh's numeric sort compares the digit runs inside a string, which gets
    # 1.9 and 1.1 the wrong way round.
    rows+=("$(printf '%012.4f' ${KINDLING_LOAD_MS[$k]})|$k")
    total=$(( total + KINDLING_LOAD_MS[$k] ))
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
    local block=${KINDLING_GLYPH[bar]} bar=""
    repeat $width bar+=$block
    printf '%8.1f ms  %-28s %s\n' "$ms" "$name" "$bar"
  done
}

# --- scaffolding -------------------------------------------------------------

_kindling_cmd_new() {
  local kind=$1 name=$2
  [[ -z $kind || -z $name ]] && {
    print -ru2 -- "usage: kindling new plugin|theme <name>"; return 1
  }

  case $kind in
    (plugin)
      local dir="$KINDLING_CUSTOM/plugins/$name"
      [[ -e $dir ]] && { print -ru2 -- "kindling: $dir already exists"; return 1 }
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
      print -- "enable it with: kindling enable $name" ;;

    (theme)
      local file="$KINDLING_CUSTOM/themes/$name.theme.zsh"
      [[ -e $file ]] && { print -ru2 -- "kindling: $file already exists"; return 1 }
      cat > "$file" <<THEME
# themes/$name — <one line describing the look>

setopt prompt_subst
autoload -Uz add-zsh-hook

_kindling_${name}_precmd() {
  local color=cyan
  (( KINDLING_LAST_STATUS != 0 )) && color=red

  # kindling_async keeps git off the critical path; the result shows up on the
  # next redraw. Drop it if this theme doesn't need git.
  kindling_async ${name}_git 'kindling_git_branch' "\$PWD"
  local branch=\${KINDLING_ASYNC_RESULT[${name}_git]}

  PROMPT="%F{blue}%~%f \${branch:+%F{green}\$branch%f }%F{\${color}}❯%f "
  RPROMPT=""
}
add-zsh-hook precmd _kindling_${name}_precmd
THEME
      print -- "created $file"
      print -- "try it with: kindling theme $name" ;;

    (*) print -ru2 -- "kindling: expected 'plugin' or 'theme', got '$kind'"; return 1 ;;
  esac
}

# --- completion --------------------------------------------------------------

_kindling_complete() {
  local -a subcmds
  subcmds=(
    'list:show available plugins and themes'
    'enable:turn a plugin on'
    'disable:turn a plugin off'
    'theme:show or switch the prompt theme'
    'off:stop loading Kindling'
    'on:start loading Kindling again'
    'reload:restart the shell'
    'update:pull the latest Kindling'
    'doctor:check the install'
    'profile:time startup'
    'new:scaffold a custom plugin or theme'
    'version:print the version'
    'help:show usage'
  )

  if (( CURRENT == 2 )); then
    _describe -t commands 'kindling command' subcmds
    return
  fi

  case ${words[2]} in
    (enable)  compadd -- $(_kindling_all_plugins) ;;
    (disable) compadd -- "${kindling_plugins[@]}" ;;
    (theme)   compadd -- $(_kindling_all_themes) ;;
    (list)    compadd -- plugins themes ;;
    (new)     (( CURRENT == 3 )) && compadd -- plugin theme ;;
  esac
}
compdef _kindling_complete kindling 2>/dev/null
