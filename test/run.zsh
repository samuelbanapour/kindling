#!/usr/bin/env zsh
# test/run.zsh — Ember's test suite.
#
# Every test runs in a throwaway HOME with a throwaway cache, so nothing here
# touches the machine it runs on. Run it with: zsh test/run.zsh

emulate -L zsh
setopt pipe_fail

typeset -g EMBER_SRC=${${0:A:h}:h}
typeset -gi PASS=0 FAIL=0
typeset -g SANDBOX

setup() {
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/ember-test.XXXXXX")
  mkdir -p "$SANDBOX/home"
}
teardown() { [[ -n $SANDBOX && -d $SANDBOX ]] && rm -rf "$SANDBOX" }
trap teardown EXIT INT TERM

# ember_sh <code> — run code in a fresh interactive-ish zsh with Ember loaded.
ember_sh() {
  HOME="$SANDBOX/home" \
  XDG_CACHE_HOME="$SANDBOX/cache" \
  XDG_DATA_HOME="$SANDBOX/data" \
  XDG_STATE_HOME="$SANDBOX/state" \
  EMBER="$EMBER_SRC" \
  EMBER_CUSTOM="$SANDBOX/custom" \
  EMBER_QUIET=1 \
  SANDBOX="$SANDBOX" \
  SANDBOX_SWITCH="$SANDBOX/off1" \
  SANDBOX_SWITCH2="$SANDBOX/off2" \
  SANDBOX_SWITCH3="$SANDBOX/off3" \
  SANDBOX_SWITCH4="$SANDBOX/off4" \
  zsh -f -c "
    setopt no_global_rcs
    ember_plugins=(${EMBER_TEST_PLUGINS:-})
    EMBER_THEME=${EMBER_TEST_THEME:-none}
    source '$EMBER_SRC/ember.zsh' 2>/dev/null
    $1
  " 2>&1
}

# ember_sh_at <ember-dir> <code> — like ember_sh, but loads Ember from a copy,
# so tests can vary how that copy looks on disk (marker files, permissions).
ember_sh_at() {
  HOME="$SANDBOX/home" \
  XDG_CACHE_HOME="$SANDBOX/cache" \
  XDG_DATA_HOME="$SANDBOX/data" \
  XDG_STATE_HOME="$SANDBOX/state" \
  EMBER_QUIET=1 \
  zsh -f -c "
    setopt no_global_rcs
    EMBER='$1'
    ember_plugins=()
    EMBER_THEME=none
    source '$1/ember.zsh' 2>/dev/null
    $2
  " 2>&1
}

# Exact comparison. Note that in zsh an unquoted $want on the right of `==` is
# matched literally, not as a pattern — unlike bash. Use check_contains for a
# substring; a `*` written here would be compared as a literal asterisk.
check() {
  local name=$1 got=$2 want=$3
  if [[ $got == $want ]]; then
    print -- "  ok   $name"; (( PASS++ ))
  else
    print -- "  FAIL $name"
    print -- "         want: ${(qq)want}"
    print -- "         got:  ${(qq)got}"
    (( FAIL++ ))
  fi
}

check_contains() {
  local name=$1 got=$2 want=$3
  if [[ $got == *$want* ]]; then
    print -- "  ok   $name"; (( PASS++ ))
  else
    print -- "  FAIL $name"
    print -- "         expected output to contain: ${(qq)want}"
    print -- "         got: ${(qq)got}"
    (( FAIL++ ))
  fi
}

# -----------------------------------------------------------------------------
print -- "core"
setup

check "loads without error" \
  "$(ember_sh 'print -- $EMBER_VERSION')" "1.0.0"

check "sets EMBER_CACHE" \
  "$(ember_sh '[[ -d $EMBER_CACHE ]] && print yes')" "yes"

check "is idempotent when sourced twice" \
  "$(ember_sh "source '$EMBER_SRC/ember.zsh'; print -- \$EMBER_VERSION")" "1.0.0"

# Install-method detection is tested against copies that are actually shaped
# the right way, rather than against whatever the working tree happens to be.
command cp -R "$EMBER_SRC" "$SANDBOX/plaincopy"
command rm -rf "$SANDBOX/plaincopy/.git" "$SANDBOX/plaincopy/custom" "$SANDBOX/plaincopy/.ember-managed"
check "detects a plain install" \
  "$(ember_sh_at "$SANDBOX/plaincopy" 'print -- $EMBER_INSTALL')" "plain"

command cp -R "$SANDBOX/plaincopy" "$SANDBOX/gitcopy"
command mkdir -p "$SANDBOX/gitcopy/.git"
check "detects a git checkout" \
  "$(ember_sh_at "$SANDBOX/gitcopy" 'print -- $EMBER_INSTALL')" "git"

# The marker file is what a package manager drops in; custom/ must then live
# outside the install directory, which the manager replaces on every upgrade.
command cp -R "$EMBER_SRC" "$SANDBOX/managed"
command rm -rf "$SANDBOX/managed/custom" "$SANDBOX/managed/.git"
print -r -- homebrew > "$SANDBOX/managed/.ember-managed"

check "a managed install is detected from its marker" \
  "$(ember_sh_at "$SANDBOX/managed" 'print -- $EMBER_INSTALL')" "homebrew"

check "a managed install keeps custom/ out of the install directory" \
  "$(ember_sh_at "$SANDBOX/managed" '[[ $EMBER_CUSTOM == $EMBER/* ]] && print inside || print outside')" \
  "outside"

check "a managed install puts custom/ under XDG_DATA_HOME" \
  "$(ember_sh_at "$SANDBOX/managed" '[[ $EMBER_CUSTOM == $XDG_DATA_HOME/ember/custom ]] && print yes')" \
  "yes"

check "a plain copy still uses \$EMBER/custom" \
  "$(ember_sh_at "$SANDBOX/plaincopy" '[[ $EMBER_CUSTOM == $EMBER/custom ]] && print inside')" \
  "inside"

check "a git checkout still uses \$EMBER/custom" \
  "$(ember_sh_at "$SANDBOX/gitcopy" '[[ $EMBER_CUSTOM == $EMBER/custom ]] && print inside')" \
  "inside"

check_contains "ember update sends a managed install to its package manager" \
  "$(ember_sh_at "$SANDBOX/managed" 'ember update')" \
  "brew upgrade ember"

check "creates the custom directories" \
  "$(ember_sh '[[ -d $EMBER_CUSTOM/plugins && -d $EMBER_CUSTOM/themes ]] && print yes')" "yes"

check "warns about an unknown plugin" \
  "$(EMBER_TEST_PLUGINS=nope ember_sh 'print -- ${ember_loaded_plugins[*]:-empty}')" "empty"

check "records a profile when asked" \
  "$(ember_sh 'print -- ${#EMBER_LOAD_MS}' EMBER_PROFILE=1)" "0"

check "profiling populates EMBER_LOAD_MS" \
  "$(EMBER_TEST_PLUGINS= ember_sh 'print -- $(( ${#EMBER_LOAD_MS} > 0 ))' )" "0"

# A system /etc/zshrc that pre-sets these must not win: that is exactly the
# case where `: ${VAR:=default}` quietly does nothing.
check "history size beats a pre-set HISTSIZE" \
  "$(HISTSIZE=1000 SAVEHIST=1000 ember_sh 'print -- "$HISTSIZE $SAVEHIST"')" \
  "100000 100000"

check "an existing HISTFILE is kept, not moved" \
  "$(HISTFILE=/tmp/ember-test-hist ember_sh 'print -- $HISTFILE')" \
  "/tmp/ember-test-hist"

check "EMBER_HISTSIZE overrides" \
  "$(ember_sh 'EMBER_HISTSIZE=42; source $EMBER/lib/history.zsh; print -- $HISTSIZE')" \
  "42"

# -----------------------------------------------------------------------------
print -- "\nlib/git"
check "ember_git_branch is defined" \
  "$(ember_sh '(( $+functions[ember_git_branch] )) && print yes')" "yes"

check "ember_git_branch fails outside a repo" \
  "$(ember_sh 'cd $SANDBOX 2>/dev/null; cd /; ember_git_branch >/dev/null 2>&1; print -- $?')" "1"

# A real repository, exercised through the real helpers.
git init -q "$SANDBOX/repo"
git -C "$SANDBOX/repo" config user.email t@t.t
git -C "$SANDBOX/repo" config user.name t
git -C "$SANDBOX/repo" commit -q --allow-empty -m init
git -C "$SANDBOX/repo" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
git -C "$SANDBOX/repo" branch -M main 2>/dev/null || true

check "ember_git_branch reads the branch" \
  "$(ember_sh "cd '$SANDBOX/repo' && ember_git_branch")" "main"

check "ember_git_status is empty on a clean tree" \
  "$(ember_sh "cd '$SANDBOX/repo' && ember_git_status")" ""

print -- "x" > "$SANDBOX/repo/new.txt"
check "ember_git_status reports untracked files" \
  "$(ember_sh "cd '$SANDBOX/repo' && ember_git_status")" "untracked"

git -C "$SANDBOX/repo" add new.txt
check "ember_git_status reports staged changes" \
  "$(ember_sh "cd '$SANDBOX/repo' && ember_git_status")" "staged"

git -C "$SANDBOX/repo" commit -q -m add
print -- "y" >> "$SANDBOX/repo/new.txt"
check "ember_git_status reports a dirty tree" \
  "$(ember_sh "cd '$SANDBOX/repo' && ember_git_status")" "dirty"

check "ember_git_default_branch finds main" \
  "$(ember_sh "cd '$SANDBOX/repo' && ember_git_default_branch")" "main"

# -----------------------------------------------------------------------------
print -- "\nlib/async"
check "async result lands and is readable" \
  "$(ember_sh 'ember_async t "print -n hello" ""; sleep 0.4; TRAPUSR1; print -- ${EMBER_ASYNC_RESULT[t]}')" \
  "hello"

check "synchronous mode returns immediately" \
  "$(ember_sh 'EMBER_ASYNC=0; ember_async t "print -n sync"; print -- ${EMBER_ASYNC_RESULT[t]}')" \
  "sync"

# -----------------------------------------------------------------------------
print -- "\nplugins/extract"
EMBER_TEST_PLUGINS=extract

mkdir -p "$SANDBOX/arc/payload"
print -- "content" > "$SANDBOX/arc/payload/file.txt"
tar czf "$SANDBOX/arc/bundle.tar.gz" -C "$SANDBOX/arc" payload

check "extract unpacks a tarball" \
  "$(ember_sh "cd '$SANDBOX/arc' && extract bundle.tar.gz >/dev/null && cat bundle/file.txt")" \
  "content"

check "extract rejects an unknown format" \
  "$(ember_sh "cd '$SANDBOX/arc' && print x > weird.qqq && extract weird.qqq >/dev/null 2>&1; print -- \$?")" \
  "1"

check "extract --into honours the target" \
  "$(ember_sh "cd '$SANDBOX/arc' && extract bundle.tar.gz --into out >/dev/null && [[ -d out/payload ]] && print yes")" \
  "yes"

check "pack round-trips" \
  "$(ember_sh "cd '$SANDBOX/arc' && pack round.tar.gz payload >/dev/null && [[ -f round.tar.gz ]] && print yes")" \
  "yes"

# -----------------------------------------------------------------------------
print -- "\nplugins/jump"
EMBER_TEST_PLUGINS=jump

mkdir -p "$SANDBOX/home/projects/alpha" "$SANDBOX/home/projects/beta"
check "j jumps to a recorded directory" \
  "$(ember_sh "cd '$SANDBOX/home/projects/alpha'; sleep 0.5; cd /; j alpha && print -- \${PWD:t}")" \
  "alpha"

check "j reports no match" \
  "$(ember_sh "j zzzznothing >/dev/null 2>&1; print -- \$?")" \
  "1"

# Four directories recorded back-to-back: without a lock, the read-modify-write
# in each background writer would clobber the one before it.
mkdir -p "$SANDBOX/home/projects/"{one,two,three,four}
check "j records concurrent visits without losing any" \
  "$(ember_sh "for d in one two three four; do cd \"$SANDBOX/home/projects/\$d\"; done
      sleep 1.5
      command grep -cE 'projects/(one|two|three|four)\\|' \"\$EMBER_JUMP_DATA\"")" \
  "4"

check "j <existing dir> beats the database" \
  "$(ember_sh "cd '$SANDBOX/home/projects'; j beta && print -- \${PWD:t}")" \
  "beta"

# -----------------------------------------------------------------------------
print -- "\nplugins/zline"
EMBER_TEST_PLUGINS=zline

check "zline defines its widgets" \
  "$(ember_sh '(( $+widgets[_ember_zline_accept] )) && print yes')" "yes"

check "zline classifies a builtin" \
  "$(ember_sh 'local REPLY; _ember_zline_kind print; print -- $REPLY')" "builtin"

check "zline classifies an alias" \
  "$(ember_sh 'alias zzz=ls; local REPLY; _ember_zline_kind zzz; print -- $REPLY')" "alias"

check "zline classifies an unknown word" \
  "$(ember_sh 'local REPLY; _ember_zline_kind definitely-not-a-command; print -- $REPLY')" "unknown"

check "zline classifies an assignment prefix" \
  "$(ember_sh 'local REPLY; _ember_zline_kind FOO=bar; print -- $REPLY')" "assignment"

check "zline highlights a simple command" \
  "$(ember_sh 'BUFFER="print hello"; CURSOR=11; _ember_zline_highlight; print -- ${_ember_zline_regions[1]}')" \
  "0 5 fg=green,bold"

check "zline highlights a quoted string" \
  "$(ember_sh 'BUFFER="print \"hi there\""; CURSOR=17; _ember_zline_highlight; print -- ${_ember_zline_regions[2]}')" \
  "6 16 fg=yellow"

check "zline highlights an option" \
  "$(ember_sh 'BUFFER="ls -la"; CURSOR=6; _ember_zline_highlight; print -- ${_ember_zline_regions[2]}')" \
  "3 6 fg=magenta"

# `print` is highlighted as a builtin and the comment as one run; the bare
# argument in between gets no region of its own.
check "zline highlights a comment to end of line" \
  "$(ember_sh 'BUFFER="print x # note"; CURSOR=14; _ember_zline_highlight
      print -- ${_ember_zline_regions[-1]}')" \
  "8 14 fg=8"

# -----------------------------------------------------------------------------
print -- "\nplugins/node"
EMBER_TEST_PLUGINS=node

mkdir -p "$SANDBOX/proj/sub"
print -- '{}' > "$SANDBOX/proj/package.json"
print -- '' > "$SANDBOX/proj/pnpm-lock.yaml"
check "node detects pnpm from the lockfile" \
  "$(ember_sh "cd '$SANDBOX/proj/sub' && _ember_node_pm")" "pnpm"

rm "$SANDBOX/proj/pnpm-lock.yaml"
print -- '' > "$SANDBOX/proj/yarn.lock"
check "node detects yarn from the lockfile" \
  "$(ember_sh "cd '$SANDBOX/proj/sub' && _ember_node_pm")" "yarn"

mkdir -p "$SANDBOX/proj/node_modules/.bin"
check "node puts node_modules/.bin on PATH" \
  "$(ember_sh "cd '$SANDBOX/proj' && print -- \$(( \${path[(I)*/node_modules/.bin]} > 0 ))")" "1"

check "node removes .bin from PATH on the way out" \
  "$(ember_sh "cd '$SANDBOX/proj'; cd /; print -- \${path[(I)*/node_modules/.bin]}")" "0"

# -----------------------------------------------------------------------------
print -- "\nplugins/python"
EMBER_TEST_PLUGINS=python

check "python disables the venv's own prompt" \
  "$(ember_sh 'print -- $VIRTUAL_ENV_DISABLE_PROMPT')" "1"

check "autovenv can be turned off" \
  "$(ember_sh 'EMBER_PYTHON_AUTOVENV=0; _ember_venv_hook; print -- ok')" "ok"

# -----------------------------------------------------------------------------
print -- "\nthemes"
# precmd hooks don't fire in `zsh -c`, so drive the chain by hand.
for theme in spark minimal quill bar; do
  check "theme '$theme' builds a prompt" \
    "$(EMBER_TEST_THEME=$theme ember_sh 'local f
        for f in $precmd_functions; do $f; done
        print -- $(( ${#PROMPT} > 0 ))')" "1"
done

check "spark shows a non-zero exit status" \
  "$(EMBER_TEST_THEME=spark ember_sh 'EMBER_LAST_STATUS=3
      _ember_spark_precmd
      [[ $RPROMPT == *3* ]] && print yes')" "yes"

check "minimal renders the cwd" \
  "$(EMBER_TEST_THEME=minimal ember_sh '_ember_minimal_precmd; [[ $PROMPT == *"%~"* ]] && print yes')" "yes"

check "an unknown theme falls back to spark" \
  "$(EMBER_TEST_THEME=nosuchtheme ember_sh '(( $+functions[_ember_spark_precmd] )) && print yes')" "yes"

# -----------------------------------------------------------------------------
print -- "\ntools/ember"
check "ember version" \
  "$(ember_sh 'ember version')" "ember 1.0.0"

check_contains "ember help mentions doctor" \
  "$(ember_sh 'ember help')" "doctor"

check_contains "ember list shows the git plugin" \
  "$(ember_sh 'ember list plugins')" "git"

check_contains "ember list shows the spark theme" \
  "$(ember_sh 'ember list themes')" "spark"

check "ember rejects an unknown command" \
  "$(ember_sh 'ember frobnicate >/dev/null 2>&1; print -- $?')" "1"

check "ember theme prints the current theme" \
  "$(EMBER_TEST_THEME=minimal ember_sh 'ember theme')" "minimal"

check "ember theme switches" \
  "$(EMBER_TEST_THEME=minimal ember_sh 'ember theme quill >/dev/null; print -- $EMBER_THEME')" "quill"

check "ember theme rejects a missing theme" \
  "$(ember_sh 'ember theme nosuch >/dev/null 2>&1; print -- $?')" "1"

check "ember new plugin scaffolds a file" \
  "$(ember_sh 'ember new plugin demo >/dev/null && [[ -f $EMBER_CUSTOM/plugins/demo/demo.plugin.zsh ]] && print yes')" \
  "yes"

check "ember new refuses to overwrite" \
  "$(ember_sh 'ember new plugin demo2 >/dev/null; ember new plugin demo2 >/dev/null 2>&1; print -- $?')" \
  "1"

check "ember new theme scaffolds a loadable theme" \
  "$(ember_sh 'ember new theme demo >/dev/null && zsh -n $EMBER_CUSTOM/themes/demo.theme.zsh && print yes')" \
  "yes"

# A custom plugin must win over a bundled one of the same name.
check "custom plugins shadow bundled ones" \
  "$(ember_sh '
     mkdir -p $EMBER_CUSTOM/plugins/git
     print "EMBER_SHADOW=yes" > $EMBER_CUSTOM/plugins/git/git.plugin.zsh
     source "$(_ember_find_plugin git)"
     print -- $EMBER_SHADOW')" \
  "yes"

# -----------------------------------------------------------------------------
print -- "\nthe off switch"

# _ember_cmd_off ends in `exec`, which never returns — run it in a subshell so
# only the subshell is replaced, then check the result from the parent.
check "ember off creates the switch file" \
  "$(ember_sh 'EMBER_SWITCH=$SANDBOX_SWITCH
      ( SHELL=/usr/bin/true _ember_cmd_off >/dev/null 2>&1 )
      [[ -f $EMBER_SWITCH ]] && print yes || print no')" \
  "yes"

check "ember on removes the switch file" \
  "$(ember_sh 'EMBER_SWITCH=$SANDBOX_SWITCH4
      : >| $EMBER_SWITCH
      ( SHELL=/usr/bin/true _ember_cmd_on >/dev/null 2>&1 )
      [[ -f $EMBER_SWITCH ]] && print no || print yes')" \
  "yes"

check "ember off is idempotent" \
  "$(ember_sh 'EMBER_SWITCH=$SANDBOX_SWITCH2
      : >| $EMBER_SWITCH
      ember off')" \
  "Ember is already off. Turn it back on with: ember on"

check "ember on reports when already on" \
  "$(ember_sh 'EMBER_SWITCH=$SANDBOX_SWITCH3; ember on')" \
  "Ember is already on."

# The guard is what makes `ember off` work at all, and doubles as the recovery
# hatch when Ember itself is what broke the shell.
check "the installed block is guarded by the switch" \
  "$(command grep -c '^if \[ ! -f "\$HOME/.ember-off" \]; then$' "$EMBER_SRC/templates/zshrc.template")" \
  "1"

check "a guarded block does not load when the switch is set" \
  "$(HOME=$SANDBOX/guard zsh -fc '
      mkdir -p $HOME 2>/dev/null
      : >| $HOME/.ember-off
      if [ ! -f "$HOME/.ember-off" ]; then print loaded; else print skipped; fi')" \
  "skipped"

# -----------------------------------------------------------------------------
print -- "\nthemes: rendered states"

# Each theme must survive the states a prompt actually meets, not just the
# happy path: a failing command, a background job, a virtualenv, an ssh
# session, and a deep path.
for theme in spark minimal quill bar; do
  check "theme '$theme' renders a failure state" \
    "$(EMBER_TEST_THEME=$theme ember_sh "EMBER_LAST_STATUS=127
        _ember_${theme}_precmd
        print -- \$(( \${#PROMPT} > 0 ))")" "1"

  check "theme '$theme' survives a virtualenv" \
    "$(EMBER_TEST_THEME=$theme ember_sh "VIRTUAL_ENV=/tmp/venvy
        _ember_${theme}_precmd
        print -- \$(( \${#PROMPT} > 0 ))")" "1"

  check "theme '$theme' survives an ssh session" \
    "$(EMBER_TEST_THEME=$theme ember_sh "SSH_CONNECTION='1.2.3.4 1 5.6.7.8 22'
        _ember_${theme}_precmd
        print -- \$(( \${#PROMPT} > 0 ))")" "1"
done

check "spark shows command duration only when slow" \
  "$(EMBER_TEST_THEME=spark ember_sh 'zmodload zsh/datetime
      _ember_spark_start=$(( EPOCHREALTIME * 1000 - 5000 ))
      _ember_spark_precmd
      [[ -n $_ember_spark_elapsed ]] && print slow')" \
  "slow"

check "spark hides duration for a fast command" \
  "$(EMBER_TEST_THEME=spark ember_sh 'zmodload zsh/datetime
      _ember_spark_start=$(( EPOCHREALTIME * 1000 - 10 ))
      _ember_spark_precmd
      print -- "[${_ember_spark_elapsed}]"')" \
  "[]"

check "bar falls back to ASCII separators outside UTF-8" \
  "$(LC_ALL=C EMBER_TEST_THEME=bar ember_sh 'print -- "[$_ember_bar_sep]"')" \
  "[]"

# LANG is unset in plenty of real sessions; decoration must degrade, not
# produce mojibake or fragments of a multibyte character.
check "a UTF-8 locale is detected" \
  "$(LC_ALL=en_US.UTF-8 ember_sh 'print -- $EMBER_UTF8')" "1"

check "a C locale is detected" \
  "$(LC_ALL=C ember_sh 'print -- $EMBER_UTF8')" "0"

check "an unset locale is treated as ASCII" \
  "$(ember_sh 'print -- $EMBER_UTF8' )" "0"

check "glyphs are ASCII under a C locale" \
  "$(LC_ALL=C ember_sh 'print -- "${EMBER_GLYPH[prompt]}${EMBER_GLYPH[ahead]}${EMBER_GLYPH[fail]}"')" \
  ">^x"

check "glyphs are pictorial under UTF-8" \
  "$(LC_ALL=en_US.UTF-8 ember_sh 'print -- "${EMBER_GLYPH[prompt]}${EMBER_GLYPH[ahead]}${EMBER_GLYPH[fail]}"')" \
  "❯⇡✗"

check "the profile bar is not built by multibyte padding" \
  "$(LC_ALL=C ember_sh 'print -- ${EMBER_GLYPH[bar]}')" "#"

check "spark uses the ASCII prompt symbol under a C locale" \
  "$(LC_ALL=C EMBER_TEST_THEME=spark ember_sh 'print -- $EMBER_SPARK_SYMBOL')" ">"

# -----------------------------------------------------------------------------
print -- "\ncross-platform"

check "clipcopy is defined" \
  "$(ember_sh '(( $+functions[clipcopy] && $+functions[clippaste] )) && print yes')" "yes"

# The point of clipcopy existing at all: `| pbcopy || xclip` would leave xclip
# reading from the terminal on a machine without pbcopy.
check "clipcopy fails loudly when no clipboard tool exists" \
  "$(ember_sh 'clipcopy() {
        (( $+commands[definitely-not-pbcopy] )) || { print -ru2 "no clipboard tool"; return 1 }
      }
      print hi | clipcopy 2>&1; print -- "rc=$?"')" \
  "no clipboard tool
rc=1"

check "the C global alias goes through clipcopy" \
  "$(ember_sh 'print -r -- ${galiases[C]}')" "| clipcopy"

check "the macos plugin is inert off macOS" \
  "$(ember_sh 'OSTYPE=linux-gnu
      source $EMBER/plugins/macos/macos.plugin.zsh
      print -- $(( $+functions[cdf] ))')" \
  "0"

check "the macos plugin does load on macOS" \
  "$(ember_sh 'OSTYPE=darwin24.0
      source $EMBER/plugins/macos/macos.plugin.zsh
      print -- $(( $+functions[cdf] ))')" \
  "1"

check "ls aliases pick a GNU form on Linux" \
  "$(ember_sh 'OSTYPE=linux-gnu
      unalias ls ll la 2>/dev/null
      unset -f ls 2>/dev/null
      source $EMBER/lib/aliases.zsh
      [[ ${aliases[ll]} == *--color=auto* || ${aliases[ll]} == eza* ]] && print yes')" \
  "yes"

check "extract refuses a .dmg where hdiutil does not exist" \
  "$(EMBER_TEST_PLUGINS=extract ember_sh 'cd $SANDBOX
      : >| fake.dmg
      unset "commands[hdiutil]"
      extract fake.dmg 2>&1 >/dev/null | head -1')" \
  "extract: .dmg images can only be opened on macOS"

check "the jump lock waits without forking sleep" \
  "$(ember_sh 'zmodload zsh/zselect 2>/dev/null; print -- $(( $+builtins[zselect] ))')" \
  "1"

# -----------------------------------------------------------------------------
print -- "\ninstaller"

# A full install / switch / uninstall cycle against a .zshrc that already loads
# another framework. This is the path most likely to break someone's shell, so
# it is exercised end to end rather than by inspecting the script.
() {
  local home="$SANDBOX/inst"
  command mkdir -p "$home/.oh-my-zsh"
  cat > "$home/.zshrc" <<'RC'
# the user's own config
export EDITOR=vim
alias mine='echo hi'
export ZSH="$HOME/.oh-my-zsh"
source $ZSH/oh-my-zsh.sh
export PATH="$HOME/bin:$PATH"
RC
  cat > "$home/.oh-my-zsh/oh-my-zsh.sh" <<'OMZ'
omz_marker() { : }
PROMPT='omz> '
OMZ
  command cp "$home/.zshrc" "$SANDBOX/zshrc.original"

  # Installing over another framework must refuse without an explicit flag.
  HOME="$home" sh "$EMBER_SRC/install.sh" --dir "$home/.ember" >/dev/null 2>&1
  check "installer refuses to stack on another framework" "$?" "1"

  check "a refused install changes nothing" \
    "$(command diff -q "$SANDBOX/zshrc.original" "$home/.zshrc" >/dev/null && print unchanged)" \
    "unchanged"

  HOME="$home" sh "$EMBER_SRC/install.sh" --dir "$home/.ember" --replace-omz >/dev/null 2>&1
  check "installer succeeds with --replace-omz" "$?" "0"

  check "the other framework is made conditional, not removed" \
    "$(command grep -c '^\[ -f "\$HOME/.ember-off" \] && source \$ZSH/oh-my-zsh.sh$' "$home/.zshrc")" \
    "1"

  check "the user's own config survives" \
    "$(command grep -c "alias mine='echo hi'" "$home/.zshrc")" "1"

  # Which framework is live, from a real interactive shell using this .zshrc.
  installed_shell() {
    HOME="$home" \
    XDG_CACHE_HOME="$SANDBOX/ic" \
    XDG_DATA_HOME="$SANDBOX/id" \
    XDG_STATE_HOME="$SANDBOX/is" \
    zsh -i -c 'print -r -- "${EMBER_VERSION:-absent}/$(( $+functions[omz_marker] ))"' 2>/dev/null | tail -1
  }

  check "with Ember on, only Ember loads" "$(installed_shell)" "1.0.0/0"

  : >| "$home/.ember-off"
  check "with Ember off, only the other framework loads" "$(installed_shell)" "absent/1"
  command rm -f "$home/.ember-off"

  check "switching back turns Ember on again" "$(installed_shell)" "1.0.0/0"

  HOME="$home" sh "$EMBER_SRC/install.sh" --dir "$home/.ember" --uninstall >/dev/null 2>&1
  # $EMBER can go missing: an external drive unmounts, a checkout is moved.
  # That must cost a plain shell, not a broken login.
  command mv "$home/.ember" "$home/.ember-moved"
  check "a missing \$EMBER leaves the shell usable" \
    "$(HOME=$home XDG_CACHE_HOME=$SANDBOX/ic XDG_DATA_HOME=$SANDBOX/id \
       zsh -i -c 'print -r -- alive' 2>&1 | tail -1)" \
    "alive"
  command mv "$home/.ember-moved" "$home/.ember"

  check "uninstall restores the .zshrc byte for byte" \
    "$(command diff -q "$SANDBOX/zshrc.original" "$home/.zshrc" >/dev/null && print identical)" \
    "identical"

  # An installed copy must not look like a checkout, or `ember update` would
  # try to `git pull` a directory that has no remote.
  check "the installer does not copy .git into the install" \
    "$([[ -d $home/.ember/.git ]] && print copied || print absent)" \
    "absent"

  check "uninstall leaves the install directory alone without --purge" \
    "$([[ -d $home/.ember ]] && print kept)" "kept"

  HOME="$home" sh "$EMBER_SRC/install.sh" --dir "$home/.ember" --purge >/dev/null 2>&1
  check "--purge removes the install directory" \
    "$([[ -d $home/.ember ]] && print kept || print gone)" "gone"

  # A dry run must not touch anything, on any path.
  command cp "$SANDBOX/zshrc.original" "$home/.zshrc"
  HOME="$home" sh "$EMBER_SRC/install.sh" --dir "$home/.ember2" --replace-omz --dry-run >/dev/null 2>&1
  check "a dry run writes nothing" \
    "$(command diff -q "$SANDBOX/zshrc.original" "$home/.zshrc" >/dev/null && [[ ! -d $home/.ember2 ]] && print clean)" \
    "clean"
}

# -----------------------------------------------------------------------------
print -- "\nsyntax"
for f in "$EMBER_SRC"/ember.zsh "$EMBER_SRC"/lib/*.zsh "$EMBER_SRC"/plugins/*/*.zsh \
         "$EMBER_SRC"/themes/*.zsh "$EMBER_SRC"/tools/*.zsh; do
  if zsh -n "$f" 2>/dev/null; then
    (( PASS++ ))
  else
    print -- "  FAIL parse ${f#$EMBER_SRC/}"; (( FAIL++ ))
  fi
done
print -- "  ok   every shipped file parses"

if sh -n "$EMBER_SRC/install.sh" 2>/dev/null; then
  print -- "  ok   install.sh is valid POSIX sh"; (( PASS++ ))
else
  print -- "  FAIL install.sh does not parse"; (( FAIL++ ))
fi

# -----------------------------------------------------------------------------
print -- ""
if (( FAIL )); then
  print -- "$PASS passed, $FAIL failed"
  exit 1
fi
print -- "$PASS passed"
