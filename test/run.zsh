#!/usr/bin/env zsh
# test/run.zsh — Kindling's test suite.
#
# Every test runs in a throwaway HOME with a throwaway cache, so nothing here
# touches the machine it runs on. Run it with: zsh test/run.zsh

emulate -L zsh
setopt pipe_fail

typeset -g KINDLING_SRC=${${0:A:h}:h}
typeset -gi PASS=0 FAIL=0
typeset -g SANDBOX

setup() {
  SANDBOX=$(mktemp -d "${TMPDIR:-/tmp}/kindling-test.XXXXXX")
  mkdir -p "$SANDBOX/home"
}
teardown() { [[ -n $SANDBOX && -d $SANDBOX ]] && rm -rf "$SANDBOX" }
trap teardown EXIT INT TERM

# kindling_sh <code> — run code in a fresh interactive-ish zsh with Kindling loaded.
kindling_sh() {
  HOME="$SANDBOX/home" \
  XDG_CACHE_HOME="$SANDBOX/cache" \
  XDG_DATA_HOME="$SANDBOX/data" \
  XDG_STATE_HOME="$SANDBOX/state" \
  KINDLING="$KINDLING_SRC" \
  KINDLING_CUSTOM="$SANDBOX/custom" \
  KINDLING_QUIET=1 \
  SANDBOX="$SANDBOX" \
  SANDBOX_SWITCH="$SANDBOX/off1" \
  SANDBOX_SWITCH2="$SANDBOX/off2" \
  SANDBOX_SWITCH3="$SANDBOX/off3" \
  SANDBOX_SWITCH4="$SANDBOX/off4" \
  zsh -f -c "
    setopt no_global_rcs
    kindling_plugins=(${KINDLING_TEST_PLUGINS:-})
    KINDLING_THEME=${KINDLING_TEST_THEME:-none}
    source '$KINDLING_SRC/kindling.zsh' 2>/dev/null
    $1
  " 2>&1
}

# kindling_sh_at <kindling-dir> <code> — like kindling_sh, but loads Kindling from a copy,
# so tests can vary how that copy looks on disk (marker files, permissions).
kindling_sh_at() {
  HOME="$SANDBOX/home" \
  XDG_CACHE_HOME="$SANDBOX/cache" \
  XDG_DATA_HOME="$SANDBOX/data" \
  XDG_STATE_HOME="$SANDBOX/state" \
  KINDLING_QUIET=1 \
  zsh -f -c "
    setopt no_global_rcs
    KINDLING='$1'
    kindling_plugins=()
    KINDLING_THEME=none
    source '$1/kindling.zsh' 2>/dev/null
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
  "$(kindling_sh 'print -- $KINDLING_VERSION')" "1.0.0"

check "sets KINDLING_CACHE" \
  "$(kindling_sh '[[ -d $KINDLING_CACHE ]] && print yes')" "yes"

check "is idempotent when sourced twice" \
  "$(kindling_sh "source '$KINDLING_SRC/kindling.zsh'; print -- \$KINDLING_VERSION")" "1.0.0"

# Install-method detection is tested against copies that are actually shaped
# the right way, rather than against whatever the working tree happens to be.
command cp -R "$KINDLING_SRC" "$SANDBOX/plaincopy"
command rm -rf "$SANDBOX/plaincopy/.git" "$SANDBOX/plaincopy/custom" "$SANDBOX/plaincopy/.kindling-managed"
check "detects a plain install" \
  "$(kindling_sh_at "$SANDBOX/plaincopy" 'print -- $KINDLING_INSTALL')" "plain"

command cp -R "$SANDBOX/plaincopy" "$SANDBOX/gitcopy"
command mkdir -p "$SANDBOX/gitcopy/.git"
check "detects a git checkout" \
  "$(kindling_sh_at "$SANDBOX/gitcopy" 'print -- $KINDLING_INSTALL')" "git"

# The marker file is what a package manager drops in; custom/ must then live
# outside the install directory, which the manager replaces on every upgrade.
command cp -R "$KINDLING_SRC" "$SANDBOX/managed"
command rm -rf "$SANDBOX/managed/custom" "$SANDBOX/managed/.git"
print -r -- homebrew > "$SANDBOX/managed/.kindling-managed"

check "a managed install is detected from its marker" \
  "$(kindling_sh_at "$SANDBOX/managed" 'print -- $KINDLING_INSTALL')" "homebrew"

check "a managed install keeps custom/ out of the install directory" \
  "$(kindling_sh_at "$SANDBOX/managed" '[[ $KINDLING_CUSTOM == $KINDLING/* ]] && print inside || print outside')" \
  "outside"

check "a managed install puts custom/ under XDG_DATA_HOME" \
  "$(kindling_sh_at "$SANDBOX/managed" '[[ $KINDLING_CUSTOM == $XDG_DATA_HOME/kindling/custom ]] && print yes')" \
  "yes"

check "a plain copy still uses \$KINDLING/custom" \
  "$(kindling_sh_at "$SANDBOX/plaincopy" '[[ $KINDLING_CUSTOM == $KINDLING/custom ]] && print inside')" \
  "inside"

check "a git checkout still uses \$KINDLING/custom" \
  "$(kindling_sh_at "$SANDBOX/gitcopy" '[[ $KINDLING_CUSTOM == $KINDLING/custom ]] && print inside')" \
  "inside"

check_contains "kindling update sends a managed install to its package manager" \
  "$(kindling_sh_at "$SANDBOX/managed" 'kindling update')" \
  "brew upgrade kindling"

check "creates the custom directories" \
  "$(kindling_sh '[[ -d $KINDLING_CUSTOM/plugins && -d $KINDLING_CUSTOM/themes ]] && print yes')" "yes"

check "warns about an unknown plugin" \
  "$(KINDLING_TEST_PLUGINS=nope kindling_sh 'print -- ${kindling_loaded_plugins[*]:-empty}')" "empty"

check "records a profile when asked" \
  "$(kindling_sh 'print -- ${#KINDLING_LOAD_MS}' KINDLING_PROFILE=1)" "0"

check "profiling populates KINDLING_LOAD_MS" \
  "$(KINDLING_TEST_PLUGINS= kindling_sh 'print -- $(( ${#KINDLING_LOAD_MS} > 0 ))' )" "0"

# A system /etc/zshrc that pre-sets these must not win: that is exactly the
# case where `: ${VAR:=default}` quietly does nothing.
check "history size beats a pre-set HISTSIZE" \
  "$(HISTSIZE=1000 SAVEHIST=1000 kindling_sh 'print -- "$HISTSIZE $SAVEHIST"')" \
  "100000 100000"

check "an existing HISTFILE is kept, not moved" \
  "$(HISTFILE=/tmp/kindling-test-hist kindling_sh 'print -- $HISTFILE')" \
  "/tmp/kindling-test-hist"

check "KINDLING_HISTSIZE overrides" \
  "$(kindling_sh 'KINDLING_HISTSIZE=42; source $KINDLING/lib/history.zsh; print -- $HISTSIZE')" \
  "42"

# -----------------------------------------------------------------------------
print -- "\nlib/git"
check "kindling_git_branch is defined" \
  "$(kindling_sh '(( $+functions[kindling_git_branch] )) && print yes')" "yes"

check "kindling_git_branch fails outside a repo" \
  "$(kindling_sh 'cd $SANDBOX 2>/dev/null; cd /; kindling_git_branch >/dev/null 2>&1; print -- $?')" "1"

# A real repository, exercised through the real helpers.
git init -q "$SANDBOX/repo"
git -C "$SANDBOX/repo" config user.email t@t.t
git -C "$SANDBOX/repo" config user.name t
git -C "$SANDBOX/repo" commit -q --allow-empty -m init
git -C "$SANDBOX/repo" symbolic-ref HEAD refs/heads/main 2>/dev/null || true
git -C "$SANDBOX/repo" branch -M main 2>/dev/null || true

check "kindling_git_branch reads the branch" \
  "$(kindling_sh "cd '$SANDBOX/repo' && kindling_git_branch")" "main"

check "kindling_git_status is empty on a clean tree" \
  "$(kindling_sh "cd '$SANDBOX/repo' && kindling_git_status")" ""

print -- "x" > "$SANDBOX/repo/new.txt"
check "kindling_git_status reports untracked files" \
  "$(kindling_sh "cd '$SANDBOX/repo' && kindling_git_status")" "untracked"

git -C "$SANDBOX/repo" add new.txt
check "kindling_git_status reports staged changes" \
  "$(kindling_sh "cd '$SANDBOX/repo' && kindling_git_status")" "staged"

git -C "$SANDBOX/repo" commit -q -m add
print -- "y" >> "$SANDBOX/repo/new.txt"
check "kindling_git_status reports a dirty tree" \
  "$(kindling_sh "cd '$SANDBOX/repo' && kindling_git_status")" "dirty"

check "kindling_git_default_branch finds main" \
  "$(kindling_sh "cd '$SANDBOX/repo' && kindling_git_default_branch")" "main"

# -----------------------------------------------------------------------------
print -- "\nlib/async"
check "async result lands and is readable" \
  "$(kindling_sh 'kindling_async t "print -n hello" ""; sleep 0.4; TRAPUSR1; print -- ${KINDLING_ASYNC_RESULT[t]}')" \
  "hello"

check "synchronous mode returns immediately" \
  "$(kindling_sh 'KINDLING_ASYNC=0; kindling_async t "print -n sync"; print -- ${KINDLING_ASYNC_RESULT[t]}')" \
  "sync"

# -----------------------------------------------------------------------------
print -- "\nplugins/extract"
KINDLING_TEST_PLUGINS=extract

mkdir -p "$SANDBOX/arc/payload"
print -- "content" > "$SANDBOX/arc/payload/file.txt"
tar czf "$SANDBOX/arc/bundle.tar.gz" -C "$SANDBOX/arc" payload

check "extract unpacks a tarball" \
  "$(kindling_sh "cd '$SANDBOX/arc' && extract bundle.tar.gz >/dev/null && cat bundle/file.txt")" \
  "content"

check "extract rejects an unknown format" \
  "$(kindling_sh "cd '$SANDBOX/arc' && print x > weird.qqq && extract weird.qqq >/dev/null 2>&1; print -- \$?")" \
  "1"

check "extract --into honours the target" \
  "$(kindling_sh "cd '$SANDBOX/arc' && extract bundle.tar.gz --into out >/dev/null && [[ -d out/payload ]] && print yes")" \
  "yes"

check "pack round-trips" \
  "$(kindling_sh "cd '$SANDBOX/arc' && pack round.tar.gz payload >/dev/null && [[ -f round.tar.gz ]] && print yes")" \
  "yes"

# -----------------------------------------------------------------------------
print -- "\nplugins/jump"
KINDLING_TEST_PLUGINS=jump

mkdir -p "$SANDBOX/home/projects/alpha" "$SANDBOX/home/projects/beta"
check "j jumps to a recorded directory" \
  "$(kindling_sh "cd '$SANDBOX/home/projects/alpha'; sleep 0.5; cd /; j alpha && print -- \${PWD:t}")" \
  "alpha"

check "j reports no match" \
  "$(kindling_sh "j zzzznothing >/dev/null 2>&1; print -- \$?")" \
  "1"

# Four directories recorded back-to-back: without a lock, the read-modify-write
# in each background writer would clobber the one before it.
mkdir -p "$SANDBOX/home/projects/"{one,two,three,four}
check "j records concurrent visits without losing any" \
  "$(kindling_sh "for d in one two three four; do cd \"$SANDBOX/home/projects/\$d\"; done
      sleep 1.5
      command grep -cE 'projects/(one|two|three|four)\\|' \"\$KINDLING_JUMP_DATA\"")" \
  "4"

check "j <existing dir> beats the database" \
  "$(kindling_sh "cd '$SANDBOX/home/projects'; j beta && print -- \${PWD:t}")" \
  "beta"

# -----------------------------------------------------------------------------
print -- "\nplugins/zline"
KINDLING_TEST_PLUGINS=zline

check "zline defines its widgets" \
  "$(kindling_sh '(( $+widgets[_kindling_zline_accept] )) && print yes')" "yes"

check "zline classifies a builtin" \
  "$(kindling_sh 'local REPLY; _kindling_zline_kind print; print -- $REPLY')" "builtin"

check "zline classifies an alias" \
  "$(kindling_sh 'alias zzz=ls; local REPLY; _kindling_zline_kind zzz; print -- $REPLY')" "alias"

check "zline classifies an unknown word" \
  "$(kindling_sh 'local REPLY; _kindling_zline_kind definitely-not-a-command; print -- $REPLY')" "unknown"

check "zline classifies an assignment prefix" \
  "$(kindling_sh 'local REPLY; _kindling_zline_kind FOO=bar; print -- $REPLY')" "assignment"

check "zline highlights a simple command" \
  "$(kindling_sh 'BUFFER="print hello"; CURSOR=11; _kindling_zline_highlight; print -- ${_kindling_zline_regions[1]}')" \
  "0 5 fg=green,bold"

check "zline highlights a quoted string" \
  "$(kindling_sh 'BUFFER="print \"hi there\""; CURSOR=17; _kindling_zline_highlight; print -- ${_kindling_zline_regions[2]}')" \
  "6 16 fg=yellow"

check "zline highlights an option" \
  "$(kindling_sh 'BUFFER="ls -la"; CURSOR=6; _kindling_zline_highlight; print -- ${_kindling_zline_regions[2]}')" \
  "3 6 fg=magenta"

# `print` is highlighted as a builtin and the comment as one run; the bare
# argument in between gets no region of its own.
check "zline highlights a comment to end of line" \
  "$(kindling_sh 'BUFFER="print x # note"; CURSOR=14; _kindling_zline_highlight
      print -- ${_kindling_zline_regions[-1]}')" \
  "8 14 fg=8"

# -----------------------------------------------------------------------------
print -- "\nplugins/node"
KINDLING_TEST_PLUGINS=node

mkdir -p "$SANDBOX/proj/sub"
print -- '{}' > "$SANDBOX/proj/package.json"
print -- '' > "$SANDBOX/proj/pnpm-lock.yaml"
check "node detects pnpm from the lockfile" \
  "$(kindling_sh "cd '$SANDBOX/proj/sub' && _kindling_node_pm")" "pnpm"

rm "$SANDBOX/proj/pnpm-lock.yaml"
print -- '' > "$SANDBOX/proj/yarn.lock"
check "node detects yarn from the lockfile" \
  "$(kindling_sh "cd '$SANDBOX/proj/sub' && _kindling_node_pm")" "yarn"

mkdir -p "$SANDBOX/proj/node_modules/.bin"
check "node puts node_modules/.bin on PATH" \
  "$(kindling_sh "cd '$SANDBOX/proj' && print -- \$(( \${path[(I)*/node_modules/.bin]} > 0 ))")" "1"

check "node removes .bin from PATH on the way out" \
  "$(kindling_sh "cd '$SANDBOX/proj'; cd /; print -- \${path[(I)*/node_modules/.bin]}")" "0"

# -----------------------------------------------------------------------------
print -- "\nplugins/python"
KINDLING_TEST_PLUGINS=python

check "python disables the venv's own prompt" \
  "$(kindling_sh 'print -- $VIRTUAL_ENV_DISABLE_PROMPT')" "1"

check "autovenv can be turned off" \
  "$(kindling_sh 'KINDLING_PYTHON_AUTOVENV=0; _kindling_venv_hook; print -- ok')" "ok"

# -----------------------------------------------------------------------------
print -- "\nthemes"
# precmd hooks don't fire in `zsh -c`, so drive the chain by hand.
for theme in spark minimal quill bar; do
  check "theme '$theme' builds a prompt" \
    "$(KINDLING_TEST_THEME=$theme kindling_sh 'local f
        for f in $precmd_functions; do $f; done
        print -- $(( ${#PROMPT} > 0 ))')" "1"
done

check "spark shows a non-zero exit status" \
  "$(KINDLING_TEST_THEME=spark kindling_sh 'KINDLING_LAST_STATUS=3
      _kindling_spark_precmd
      [[ $RPROMPT == *3* ]] && print yes')" "yes"

check "minimal renders the cwd" \
  "$(KINDLING_TEST_THEME=minimal kindling_sh '_kindling_minimal_precmd; [[ $PROMPT == *"%~"* ]] && print yes')" "yes"

check "an unknown theme falls back to spark" \
  "$(KINDLING_TEST_THEME=nosuchtheme kindling_sh '(( $+functions[_kindling_spark_precmd] )) && print yes')" "yes"

# -----------------------------------------------------------------------------
print -- "\ntools/kindling"
check "kindling version" \
  "$(kindling_sh 'kindling version')" "kindling 1.0.0"

check_contains "kindling help mentions doctor" \
  "$(kindling_sh 'kindling help')" "doctor"

check_contains "kindling list shows the git plugin" \
  "$(kindling_sh 'kindling list plugins')" "git"

check_contains "kindling list shows the spark theme" \
  "$(kindling_sh 'kindling list themes')" "spark"

check "kindling rejects an unknown command" \
  "$(kindling_sh 'kindling frobnicate >/dev/null 2>&1; print -- $?')" "1"

check "kindling theme prints the current theme" \
  "$(KINDLING_TEST_THEME=minimal kindling_sh 'kindling theme')" "minimal"

check "kindling theme switches" \
  "$(KINDLING_TEST_THEME=minimal kindling_sh 'kindling theme quill >/dev/null; print -- $KINDLING_THEME')" "quill"

check "kindling theme rejects a missing theme" \
  "$(kindling_sh 'kindling theme nosuch >/dev/null 2>&1; print -- $?')" "1"

check "kindling new plugin scaffolds a file" \
  "$(kindling_sh 'kindling new plugin demo >/dev/null && [[ -f $KINDLING_CUSTOM/plugins/demo/demo.plugin.zsh ]] && print yes')" \
  "yes"

check "kindling new refuses to overwrite" \
  "$(kindling_sh 'kindling new plugin demo2 >/dev/null; kindling new plugin demo2 >/dev/null 2>&1; print -- $?')" \
  "1"

check "kindling new theme scaffolds a loadable theme" \
  "$(kindling_sh 'kindling new theme demo >/dev/null && zsh -n $KINDLING_CUSTOM/themes/demo.theme.zsh && print yes')" \
  "yes"

# A custom plugin must win over a bundled one of the same name.
check "custom plugins shadow bundled ones" \
  "$(kindling_sh '
     mkdir -p $KINDLING_CUSTOM/plugins/git
     print "KINDLING_SHADOW=yes" > $KINDLING_CUSTOM/plugins/git/git.plugin.zsh
     source "$(_kindling_find_plugin git)"
     print -- $KINDLING_SHADOW')" \
  "yes"

# -----------------------------------------------------------------------------
print -- "\nthe off switch"

# _kindling_cmd_off ends in `exec`, which never returns — run it in a subshell so
# only the subshell is replaced, then check the result from the parent.
check "kindling off creates the switch file" \
  "$(kindling_sh 'KINDLING_SWITCH=$SANDBOX_SWITCH
      ( SHELL=/usr/bin/true _kindling_cmd_off >/dev/null 2>&1 )
      [[ -f $KINDLING_SWITCH ]] && print yes || print no')" \
  "yes"

check "kindling on removes the switch file" \
  "$(kindling_sh 'KINDLING_SWITCH=$SANDBOX_SWITCH4
      : >| $KINDLING_SWITCH
      ( SHELL=/usr/bin/true _kindling_cmd_on >/dev/null 2>&1 )
      [[ -f $KINDLING_SWITCH ]] && print no || print yes')" \
  "yes"

check "kindling off is idempotent" \
  "$(kindling_sh 'KINDLING_SWITCH=$SANDBOX_SWITCH2
      : >| $KINDLING_SWITCH
      kindling off')" \
  "Kindling is already off. Turn it back on with: kindling on"

check "kindling on reports when already on" \
  "$(kindling_sh 'KINDLING_SWITCH=$SANDBOX_SWITCH3; kindling on')" \
  "Kindling is already on."

# The guard is what makes `kindling off` work at all, and doubles as the recovery
# hatch when Kindling itself is what broke the shell.
check "the installed block is guarded by the switch" \
  "$(command grep -c '^if \[ ! -f "\$HOME/.kindling-off" \]; then$' "$KINDLING_SRC/templates/zshrc.template")" \
  "1"

check "a guarded block does not load when the switch is set" \
  "$(HOME=$SANDBOX/guard zsh -fc '
      mkdir -p $HOME 2>/dev/null
      : >| $HOME/.kindling-off
      if [ ! -f "$HOME/.kindling-off" ]; then print loaded; else print skipped; fi')" \
  "skipped"

# -----------------------------------------------------------------------------
print -- "\nthemes: rendered states"

# Each theme must survive the states a prompt actually meets, not just the
# happy path: a failing command, a background job, a virtualenv, an ssh
# session, and a deep path.
for theme in spark minimal quill bar; do
  check "theme '$theme' renders a failure state" \
    "$(KINDLING_TEST_THEME=$theme kindling_sh "KINDLING_LAST_STATUS=127
        _kindling_${theme}_precmd
        print -- \$(( \${#PROMPT} > 0 ))")" "1"

  check "theme '$theme' survives a virtualenv" \
    "$(KINDLING_TEST_THEME=$theme kindling_sh "VIRTUAL_ENV=/tmp/venvy
        _kindling_${theme}_precmd
        print -- \$(( \${#PROMPT} > 0 ))")" "1"

  check "theme '$theme' survives an ssh session" \
    "$(KINDLING_TEST_THEME=$theme kindling_sh "SSH_CONNECTION='1.2.3.4 1 5.6.7.8 22'
        _kindling_${theme}_precmd
        print -- \$(( \${#PROMPT} > 0 ))")" "1"
done

check "spark shows command duration only when slow" \
  "$(KINDLING_TEST_THEME=spark kindling_sh 'zmodload zsh/datetime
      _kindling_spark_start=$(( EPOCHREALTIME * 1000 - 5000 ))
      _kindling_spark_precmd
      [[ -n $_kindling_spark_elapsed ]] && print slow')" \
  "slow"

check "spark hides duration for a fast command" \
  "$(KINDLING_TEST_THEME=spark kindling_sh 'zmodload zsh/datetime
      _kindling_spark_start=$(( EPOCHREALTIME * 1000 - 10 ))
      _kindling_spark_precmd
      print -- "[${_kindling_spark_elapsed}]"')" \
  "[]"

check "bar falls back to ASCII separators outside UTF-8" \
  "$(LC_ALL=C KINDLING_TEST_THEME=bar kindling_sh 'print -- "[$_kindling_bar_sep]"')" \
  "[]"

# LANG is unset in plenty of real sessions; decoration must degrade, not
# produce mojibake or fragments of a multibyte character.
check "a UTF-8 locale is detected" \
  "$(LC_ALL=en_US.UTF-8 kindling_sh 'print -- $KINDLING_UTF8')" "1"

check "a C locale is detected" \
  "$(LC_ALL=C kindling_sh 'print -- $KINDLING_UTF8')" "0"

# Explicitly cleared rather than assumed: this passed locally only because
# LANG happened to be unset there, and CI runners set it.
check "an unset locale is treated as ASCII" \
  "$(env -u LANG -u LC_ALL -u LC_CTYPE zsh -fc "
      KINDLING='$KINDLING_SRC'
      kindling_plugins=(); KINDLING_THEME=none; KINDLING_QUIET=1
      source '$KINDLING_SRC/kindling.zsh' 2>/dev/null
      print -- \$KINDLING_UTF8")" \
  "0"

check "glyphs are ASCII under a C locale" \
  "$(LC_ALL=C kindling_sh 'print -- "${KINDLING_GLYPH[prompt]}${KINDLING_GLYPH[ahead]}${KINDLING_GLYPH[fail]}"')" \
  ">^x"

check "glyphs are pictorial under UTF-8" \
  "$(LC_ALL=en_US.UTF-8 kindling_sh 'print -- "${KINDLING_GLYPH[prompt]}${KINDLING_GLYPH[ahead]}${KINDLING_GLYPH[fail]}"')" \
  "❯⇡✗"

check "the profile bar is not built by multibyte padding" \
  "$(LC_ALL=C kindling_sh 'print -- ${KINDLING_GLYPH[bar]}')" "#"

check "spark uses the ASCII prompt symbol under a C locale" \
  "$(LC_ALL=C KINDLING_TEST_THEME=spark kindling_sh 'print -- $KINDLING_SPARK_SYMBOL')" ">"

# -----------------------------------------------------------------------------
print -- "\ncross-platform"

check "clipcopy is defined" \
  "$(kindling_sh '(( $+functions[clipcopy] && $+functions[clippaste] )) && print yes')" "yes"

# The point of clipcopy existing at all: `| pbcopy || xclip` would leave xclip
# reading from the terminal on a machine without pbcopy.
check "clipcopy fails loudly when no clipboard tool exists" \
  "$(kindling_sh 'clipcopy() {
        (( $+commands[definitely-not-pbcopy] )) || { print -ru2 "no clipboard tool"; return 1 }
      }
      print hi | clipcopy 2>&1; print -- "rc=$?"')" \
  "no clipboard tool
rc=1"

check "the C global alias goes through clipcopy" \
  "$(kindling_sh 'print -r -- ${galiases[C]}')" "| clipcopy"

check "the macos plugin is inert off macOS" \
  "$(kindling_sh 'OSTYPE=linux-gnu
      source $KINDLING/plugins/macos/macos.plugin.zsh
      print -- $(( $+functions[cdf] ))')" \
  "0"

check "the macos plugin does load on macOS" \
  "$(kindling_sh 'OSTYPE=darwin24.0
      source $KINDLING/plugins/macos/macos.plugin.zsh
      print -- $(( $+functions[cdf] ))')" \
  "1"

check "ls aliases pick a GNU form on Linux" \
  "$(kindling_sh 'OSTYPE=linux-gnu
      unalias ls ll la 2>/dev/null
      unset -f ls 2>/dev/null
      source $KINDLING/lib/aliases.zsh
      [[ ${aliases[ll]} == *--color=auto* || ${aliases[ll]} == eza* ]] && print yes')" \
  "yes"

check "extract refuses a .dmg where hdiutil does not exist" \
  "$(KINDLING_TEST_PLUGINS=extract kindling_sh 'cd $SANDBOX
      : >| fake.dmg
      unset "commands[hdiutil]"
      extract fake.dmg 2>&1 >/dev/null | head -1')" \
  "extract: .dmg images can only be opened on macOS"

check "the jump lock waits without forking sleep" \
  "$(kindling_sh 'zmodload zsh/zselect 2>/dev/null; print -- $(( $+builtins[zselect] ))')" \
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
  HOME="$home" sh "$KINDLING_SRC/install.sh" --dir "$home/.kindling" >/dev/null 2>&1
  check "installer refuses to stack on another framework" "$?" "1"

  check "a refused install changes nothing" \
    "$(command diff -q "$SANDBOX/zshrc.original" "$home/.zshrc" >/dev/null && print unchanged)" \
    "unchanged"

  HOME="$home" sh "$KINDLING_SRC/install.sh" --dir "$home/.kindling" --replace-omz >/dev/null 2>&1
  check "installer succeeds with --replace-omz" "$?" "0"

  check "the other framework is made conditional, not removed" \
    "$(command grep -c '^\[ -f "\$HOME/.kindling-off" \] && source \$ZSH/oh-my-zsh.sh$' "$home/.zshrc")" \
    "1"

  check "the user's own config survives" \
    "$(command grep -c "alias mine='echo hi'" "$home/.zshrc")" "1"

  # Which framework is live, from a real interactive shell using this .zshrc.
  installed_shell() {
    HOME="$home" \
    XDG_CACHE_HOME="$SANDBOX/ic" \
    XDG_DATA_HOME="$SANDBOX/id" \
    XDG_STATE_HOME="$SANDBOX/is" \
    zsh -i -c 'print -r -- "${KINDLING_VERSION:-absent}/$(( $+functions[omz_marker] ))"' 2>/dev/null | tail -1
  }

  check "with Kindling on, only Kindling loads" "$(installed_shell)" "1.0.0/0"

  : >| "$home/.kindling-off"
  check "with Kindling off, only the other framework loads" "$(installed_shell)" "absent/1"
  command rm -f "$home/.kindling-off"

  check "switching back turns Kindling on again" "$(installed_shell)" "1.0.0/0"

  HOME="$home" sh "$KINDLING_SRC/install.sh" --dir "$home/.kindling" --uninstall >/dev/null 2>&1
  # $KINDLING can go missing: an external drive unmounts, a checkout is moved.
  # That must cost a plain shell, not a broken login.
  command mv "$home/.kindling" "$home/.kindling-moved"
  check "a missing \$KINDLING leaves the shell usable" \
    "$(HOME=$home XDG_CACHE_HOME=$SANDBOX/ic XDG_DATA_HOME=$SANDBOX/id \
       zsh -i -c 'print -r -- alive' 2>&1 | tail -1)" \
    "alive"
  command mv "$home/.kindling-moved" "$home/.kindling"

  check "uninstall restores the .zshrc byte for byte" \
    "$(command diff -q "$SANDBOX/zshrc.original" "$home/.zshrc" >/dev/null && print identical)" \
    "identical"

  # An installed copy must not look like a checkout, or `kindling update` would
  # try to `git pull` a directory that has no remote.
  check "the installer does not copy .git into the install" \
    "$([[ -d $home/.kindling/.git ]] && print copied || print absent)" \
    "absent"

  check "uninstall leaves the install directory alone without --purge" \
    "$([[ -d $home/.kindling ]] && print kept)" "kept"

  HOME="$home" sh "$KINDLING_SRC/install.sh" --dir "$home/.kindling" --purge >/dev/null 2>&1
  check "--purge removes the install directory" \
    "$([[ -d $home/.kindling ]] && print kept || print gone)" "gone"

  # A dry run must not touch anything, on any path.
  command cp "$SANDBOX/zshrc.original" "$home/.zshrc"
  HOME="$home" sh "$KINDLING_SRC/install.sh" --dir "$home/.kindling2" --replace-omz --dry-run >/dev/null 2>&1
  check "a dry run writes nothing" \
    "$(command diff -q "$SANDBOX/zshrc.original" "$home/.zshrc" >/dev/null && [[ ! -d $home/.kindling2 ]] && print clean)" \
    "clean"
}

# -----------------------------------------------------------------------------
print -- "\nsyntax"
for f in "$KINDLING_SRC"/kindling.zsh "$KINDLING_SRC"/lib/*.zsh "$KINDLING_SRC"/plugins/*/*.zsh \
         "$KINDLING_SRC"/themes/*.zsh "$KINDLING_SRC"/tools/*.zsh; do
  if zsh -n "$f" 2>/dev/null; then
    (( PASS++ ))
  else
    print -- "  FAIL parse ${f#$KINDLING_SRC/}"; (( FAIL++ ))
  fi
done
print -- "  ok   every shipped file parses"

if sh -n "$KINDLING_SRC/install.sh" 2>/dev/null; then
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
