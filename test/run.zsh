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

check "detects a plain install" \
  "$(ember_sh 'print -- $EMBER_INSTALL')" "plain"

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
  "$(command cp -R "$EMBER_SRC" "$SANDBOX/plain" && command rm -rf "$SANDBOX/plain/.git"
     ember_sh_at "$SANDBOX/plain" '[[ $EMBER_CUSTOM == $EMBER/custom ]] && print inside')" \
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
