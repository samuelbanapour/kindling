#!/bin/sh
# Ember installer. Deliberately POSIX sh: this has to run before zsh is
# necessarily the user's shell, and on systems where it isn't installed yet.
#
#   sh install.sh                 install into ~/.ember
#   sh install.sh --dir ~/ember   install somewhere else
#   sh install.sh --no-zshrc      install without touching ~/.zshrc
#   sh install.sh --dry-run       print what would happen and stop

set -eu

EMBER_DIR="${EMBER:-$HOME/.ember}"
REPO="${EMBER_REPO:-https://github.com/ember-zsh/ember.git}"
TOUCH_ZSHRC=1
DRY_RUN=0
REPLACE_OMZ=0
SOURCE_DIR="$(CDPATH= cd -- "$(dirname -- "$0")" && pwd)"

# --- output helpers ----------------------------------------------------------
if [ -t 1 ] && [ "${NO_COLOR:-}" = "" ]; then
  BOLD=$(printf '\033[1m'); DIM=$(printf '\033[2m')
  RED=$(printf '\033[31m'); GREEN=$(printf '\033[32m')
  YELLOW=$(printf '\033[33m'); RESET=$(printf '\033[0m')
else
  BOLD=; DIM=; RED=; GREEN=; YELLOW=; RESET=
fi

say()  { printf '%s\n' "$*"; }
step() { printf '%s==>%s %s\n' "$BOLD" "$RESET" "$*"; }
# ok() reports something that is true right now — a check that passed. It reads
# the same in a dry run, because the check really did run.
ok()   { printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"; }
# did() reports a change to the system. In a dry run no change was made, so it
# must not claim one.
did()  {
  if [ "$DRY_RUN" = 1 ]; then
    printf '  %s·%s would: %s\n' "$DIM" "$RESET" "$*"
  else
    printf '  %s✓%s %s\n' "$GREEN" "$RESET" "$*"
  fi
}
warn() { printf '  %s!%s %s\n' "$YELLOW" "$RESET" "$*"; }
die()  { printf '  %s✗%s %s\n' "$RED" "$RESET" "$*" >&2; exit 1; }
run()  { if [ "$DRY_RUN" = 1 ]; then printf '  %s$ %s%s\n' "$DIM" "$*" "$RESET"; else "$@"; fi }

# --- arguments ---------------------------------------------------------------
while [ $# -gt 0 ]; do
  case $1 in
    --dir)       EMBER_DIR=$2; shift 2 ;;
    --repo)      REPO=$2; shift 2 ;;
    --no-zshrc)  TOUCH_ZSHRC=0; shift ;;
    --replace-omz) REPLACE_OMZ=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)
      say "usage: sh install.sh [--dir <path>] [--repo <url>] [--no-zshrc]"
      say "                      [--replace-omz] [--dry-run]"
      say ""
      say "  --replace-omz  comment out the oh-my-zsh loader before installing,"
      say "                 so the two frameworks don't both run"
      exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

say ""
say "${BOLD}Ember${RESET} — a zsh framework"
if [ "$DRY_RUN" = 1 ]; then
  say "${YELLOW}dry run — showing what would happen, changing nothing${RESET}"
fi
say ""

# --- prerequisites -----------------------------------------------------------
step "Checking prerequisites"

command -v zsh >/dev/null 2>&1 || die "zsh is not installed. Install it, then run this again."

ZSH_VER=$(zsh -c 'printf %s "$ZSH_VERSION"')
ZSH_MAJOR=${ZSH_VER%%.*}
ZSH_REST=${ZSH_VER#*.}
ZSH_MINOR=${ZSH_REST%%.*}
if [ "$ZSH_MAJOR" -lt 5 ] || { [ "$ZSH_MAJOR" -eq 5 ] && [ "$ZSH_MINOR" -lt 1 ]; }; then
  die "zsh $ZSH_VER is too old; Ember needs 5.1 or newer."
fi
ok "zsh $ZSH_VER"

for tool in awk sed grep; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
done
ok "awk, sed, grep"

command -v git >/dev/null 2>&1 || warn "git not found — the git plugin and 'ember update' will be inert"

# --- place the files ---------------------------------------------------------
step "Installing to $EMBER_DIR"

if [ -e "$EMBER_DIR" ]; then
  if [ -d "$EMBER_DIR/.git" ]; then
    warn "$EMBER_DIR already exists — updating it instead"
    run git -C "$EMBER_DIR" pull --ff-only || warn "could not fast-forward; leaving it as is"
  else
    # Never clobber an existing directory; move it aside and say where it went.
    BACKUP="$EMBER_DIR.pre-ember.$(date +%Y%m%d%H%M%S)"
    warn "$EMBER_DIR exists and is not an Ember checkout"
    warn "moving it to $BACKUP"
    run mv -- "$EMBER_DIR" "$BACKUP"
  fi
fi

if [ ! -e "$EMBER_DIR" ]; then
  # Installing from a local copy (this repo) is the normal case when you ran
  # install.sh out of a clone; cloning is for the curl-to-sh path.
  if [ -f "$SOURCE_DIR/ember.zsh" ]; then
    run mkdir -p "$EMBER_DIR"
    run cp -R "$SOURCE_DIR/." "$EMBER_DIR/"
    did "copy the files from $SOURCE_DIR"
  elif command -v git >/dev/null 2>&1; then
    run git clone --depth 1 -- "$REPO" "$EMBER_DIR" || die "clone failed"
    did "clone $REPO"
  else
    die "no local copy and no git available"
  fi
fi

run mkdir -p "$EMBER_DIR/custom/plugins" "$EMBER_DIR/custom/themes"
did "create custom/ for your own plugins and themes"

# --- .zshrc ------------------------------------------------------------------
ZSHRC="$HOME/.zshrc"

# Two frameworks in one .zshrc is not a supported configuration anywhere: both
# set PROMPT from precmd, both run compinit, both bind ZLE widgets. Whichever
# loads last silently wins, and the loser's cost is still paid on every shell.
# Detect it and make the user choose rather than quietly producing that.
OMZ_LINE=""
if [ -f "$ZSHRC" ]; then
  OMZ_LINE=$(grep -n 'oh-my-zsh\.sh' "$ZSHRC" 2>/dev/null | head -1 || true)
fi

if [ "$TOUCH_ZSHRC" = 1 ] && [ -n "$OMZ_LINE" ] && [ "$REPLACE_OMZ" = 0 ]; then
  step "Found another framework"
  warn "$ZSHRC loads oh-my-zsh (line ${OMZ_LINE%%:*})"
  say ""
  say "  Running Ember alongside oh-my-zsh does not work well: both set the"
  say "  prompt from a precmd hook, both run compinit, and both bind ZLE"
  say "  widgets. Ember would load second and win, while you keep paying"
  say "  oh-my-zsh's startup cost for nothing."
  say ""
  say "  Pick one:"
  say ""
  say "    ${BOLD}sh install.sh --replace-omz${RESET}"
  say "      comment out the oh-my-zsh loader, then install Ember."
  say "      Your .zshrc is backed up first and nothing else is touched,"
  say "      so undoing it is one uncommented line."
  say ""
  say "    ${BOLD}sh install.sh --no-zshrc${RESET}"
  say "      install the files only and wire it up yourself later."
  say ""
  exit 1
fi

if [ "$TOUCH_ZSHRC" = 1 ]; then
  step "Configuring $ZSHRC"

  if [ -f "$ZSHRC" ] && grep -q 'ember\.zsh' "$ZSHRC" 2>/dev/null; then
    ok "already sources ember.zsh — leaving it alone"
  else
    if [ -f "$ZSHRC" ]; then
      BACKUP="$ZSHRC.pre-ember.$(date +%Y%m%d%H%M%S)"
      run cp -- "$ZSHRC" "$BACKUP"
      did "back up your existing .zshrc to $BACKUP"

      if [ "$REPLACE_OMZ" = 1 ] && [ -n "$OMZ_LINE" ]; then
        # Comment out only the line that actually loads oh-my-zsh. ZSH_THEME
        # and plugins=() are inert without it, and leaving them makes going
        # back a matter of removing one `#`.
        if [ "$DRY_RUN" = 0 ]; then
          TMP="$ZSHRC.ember.$$"
          sed 's|^\([[:space:]]*source[[:space:]].*oh-my-zsh\.sh.*\)$|# disabled by the Ember installer: \1|' \
            "$ZSHRC" > "$TMP" && mv -f "$TMP" "$ZSHRC"
        fi
        did "comment out the oh-my-zsh loader (line ${OMZ_LINE%%:*})"
        say "    Undo it by deleting the '# disabled by the Ember installer:' prefix."
      fi

      # Append rather than replace: an existing .zshrc is the user's work and
      # must survive. The trade-off is that Ember then loads last, so where
      # both define the same alias, Ember's wins — which is why the note below
      # tells the user how to get the other precedence.
      if [ "$DRY_RUN" = 0 ]; then
        {
          printf '\n# --- Ember ---------------------------------------------------------------\n'
          printf 'export EMBER="%s"\n' "$EMBER_DIR"
          printf 'ember_plugins=(git jump zline extract)\n'
          printf 'EMBER_THEME=spark\n'
          printf 'source "$EMBER/ember.zsh"\n'
          printf '# --- end Ember -----------------------------------------------------------\n'
        } >> "$ZSHRC"
      fi
      did "append Ember's block to your .zshrc"
      say "    Your own settings are above Ember's block and were not touched."
      say "    Because Ember loads last, it wins where you both set the same"
      say "    alias. Move those lines below the block to take them back."
    else
      if [ "$DRY_RUN" = 0 ]; then
        sed "s|\$HOME/.ember|$EMBER_DIR|" "$EMBER_DIR/templates/zshrc.template" > "$ZSHRC"
      fi
      did "create a new .zshrc from the template"
    fi
  fi
else
  step "Skipping .zshrc (--no-zshrc)"
  say "  Add this to your .zshrc yourself:"
  say ""
  say "    export EMBER=\"$EMBER_DIR\""
  say "    ember_plugins=(git jump zline extract)"
  say "    EMBER_THEME=spark"
  say "    source \"\$EMBER/ember.zsh\""
fi

# --- default shell -----------------------------------------------------------
step "Checking your login shell"
CURRENT_SHELL=$(basename "${SHELL:-}")
if [ "$CURRENT_SHELL" = zsh ]; then
  ok "already zsh"
else
  warn "your login shell is $CURRENT_SHELL, not zsh"
  say "  Change it yourself with:  chsh -s \"\$(command -v zsh)\""
  say "  (that command asks for your password, so it isn't run for you)"
fi

# --- verify ------------------------------------------------------------------
if [ "$DRY_RUN" = 0 ]; then
  step "Verifying the install"
  if zsh -ic 'true' >/dev/null 2>&1; then
    ok "a new interactive zsh starts cleanly"
  else
    warn "a new interactive zsh reported errors; run 'ember doctor' once you're in"
  fi
fi

say ""
if [ "$DRY_RUN" = 1 ]; then
  say "${YELLOW}Dry run finished. Nothing was changed and nothing is installed.${RESET}"
  say "Run the same command again without ${BOLD}--dry-run${RESET} to install."
  say ""
  exit 0
fi
say "${GREEN}Done.${RESET} Start a new shell, or run: ${BOLD}exec zsh${RESET}"
say ""
say "  ${BOLD}ember list${RESET}      what's available"
say "  ${BOLD}ember doctor${RESET}    check the install"
say "  ${BOLD}ember help${RESET}      everything else"
say ""
