#!/bin/sh
# Kindling installer. Deliberately POSIX sh: this has to run before zsh is
# necessarily the user's shell, and on systems where it isn't installed yet.
#
#   sh install.sh                 install into ~/.kindling
#   sh install.sh --dir ~/kindling   install somewhere else
#   sh install.sh --no-zshrc      install without touching ~/.zshrc
#   sh install.sh --dry-run       print what would happen and stop

set -eu

KINDLING_DIR="${KINDLING:-$HOME/.kindling}"
REPO="${KINDLING_REPO:-https://github.com/samuelbanapour/kindling.git}"
TOUCH_ZSHRC=1
DRY_RUN=0
REPLACE_OMZ=0
UNINSTALL=0
PURGE=0
SOURCE_DIR="$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)"

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
    --dir)       KINDLING_DIR=$2; shift 2 ;;
    --repo)      REPO=$2; shift 2 ;;
    --no-zshrc)  TOUCH_ZSHRC=0; shift ;;
    --replace-omz) REPLACE_OMZ=1; shift ;;
    --uninstall)   UNINSTALL=1; shift ;;
    --purge)       UNINSTALL=1; PURGE=1; shift ;;
    --dry-run)   DRY_RUN=1; shift ;;
    -h|--help)
      say "usage: sh install.sh [--dir <path>] [--repo <url>] [--no-zshrc]"
      say "                      [--replace-omz] [--dry-run]"
      say "       sh install.sh --uninstall [--purge] [--dry-run]"
      say ""
      say "  --replace-omz  make oh-my-zsh conditional so the two frameworks"
      say "                 don't both run. Reversible with \`kindling off\`;"
      say "                 oh-my-zsh is never removed"
      say "  --uninstall    remove Kindling's block from .zshrc and restore any"
      say "                 framework it made conditional"
      say "  --purge        --uninstall, and also delete the install directory"
      exit 0 ;;
    *) die "unknown option: $1" ;;
  esac
done

say ""
say "${BOLD}Kindling${RESET} — a zsh framework"
if [ "$DRY_RUN" = 1 ]; then
  say "${YELLOW}dry run — showing what would happen, changing nothing${RESET}"
fi
say ""

# --- uninstall ---------------------------------------------------------------
if [ "$UNINSTALL" = 1 ]; then
  ZSHRC="$HOME/.zshrc"
  step "Uninstalling Kindling"

  if [ ! -f "$ZSHRC" ]; then
    warn "no $ZSHRC to clean up"
  elif ! grep -q '# --- Kindling ---' "$ZSHRC" 2>/dev/null; then
    warn "$ZSHRC has no Kindling block; leaving it alone"
  else
    BACKUP="$ZSHRC.pre-uninstall.$(date +%Y%m%d%H%M%S)"
    run cp -- "$ZSHRC" "$BACKUP"
    did "back up $ZSHRC to $BACKUP"

    if [ "$DRY_RUN" = 0 ]; then
      TMP="$ZSHRC.kindling.$$"
      # Drop everything between the block markers, and undo the guard that was
      # put in front of another framework's loader.
      awk '
        /^# --- Kindling ---/      { skip = 1; next }
        /^# --- end Kindling ---/  { skip = 0; next }
        skip                    { next }
        /^[[:space:]]*# Kindling made this conditional/ { next }
        {
          # `[ -f "$HOME/.kindling-off" ] && source ...` -> `source ...`
          sub(/\[ -f "\$HOME\/\.kindling-off" \] && /, "")
          # Hold blank lines back rather than printing them straight away, so
          # the blank that preceded the removed block does not survive it.
          # They are emitted only once a non-blank line follows, which means
          # trailing blanks are dropped and the file ends exactly as it began.
          if ($0 ~ /^[[:space:]]*$/) { pending = pending $0 "\n"; next }
          if (pending != "") { printf "%s", pending; pending = "" }
          print
        }
      ' "$ZSHRC" > "$TMP" && mv -f "$TMP" "$ZSHRC"
    fi
    did "remove Kindling's block from $ZSHRC"
    did "restore any framework loader Kindling had made conditional"
  fi

  [ -f "$HOME/.kindling-off" ] && { run rm -f "$HOME/.kindling-off"; did "remove the off switch"; }

  if [ "$PURGE" = 1 ]; then
    [ -d "$KINDLING_DIR" ] && { run rm -rf "$KINDLING_DIR"; did "delete $KINDLING_DIR"; }
    for d in "${XDG_CACHE_HOME:-$HOME/.cache}/kindling" "${XDG_DATA_HOME:-$HOME/.local/share}/kindling"; do
      [ -d "$d" ] && { run rm -rf "$d"; did "delete $d"; }
    done
  else
    say ""
    say "  Left in place (use --purge to remove):"
    [ -d "$KINDLING_DIR" ] && say "    $KINDLING_DIR"
    say "    your plugins and themes, and your shell history"
  fi

  say ""
  if [ "$DRY_RUN" = 1 ]; then
    say "${YELLOW}Dry run finished. Nothing was changed.${RESET}"
  else
    say "${GREEN}Done.${RESET} Start a new shell: ${BOLD}exec zsh${RESET}"
  fi
  say ""
  exit 0
fi

# --- prerequisites -----------------------------------------------------------
step "Checking prerequisites"

command -v zsh >/dev/null 2>&1 || die "zsh is not installed. Install it, then run this again."

ZSH_VER=$(zsh -c 'printf %s "$ZSH_VERSION"')
ZSH_MAJOR=${ZSH_VER%%.*}
ZSH_REST=${ZSH_VER#*.}
ZSH_MINOR=${ZSH_REST%%.*}
if [ "$ZSH_MAJOR" -lt 5 ] || { [ "$ZSH_MAJOR" -eq 5 ] && [ "$ZSH_MINOR" -lt 1 ]; }; then
  die "zsh $ZSH_VER is too old; Kindling needs 5.1 or newer."
fi
ok "zsh $ZSH_VER"

for tool in awk sed grep; do
  command -v "$tool" >/dev/null 2>&1 || die "$tool is required but not installed"
done
ok "awk, sed, grep"

command -v git >/dev/null 2>&1 || warn "git not found — the git plugin and 'kindling update' will be inert"

# --- place the files ---------------------------------------------------------
step "Installing to $KINDLING_DIR"

# Running the installer from inside the directory you're installing to means
# there is nothing to copy and nothing to update: use the checkout in place.
# That keeps a single copy, so edits to the repo take effect in the next shell,
# which is what you want when you are working on Kindling rather than using it.
# This has to be decided before the "already exists" handling below, or that
# would try to pull the very checkout the installer is running from.
IN_PLACE=0
if [ "$SOURCE_DIR" = "$KINDLING_DIR" ]; then
  IN_PLACE=1
  ok "installing in place from $KINDLING_DIR (nothing copied)"
fi

if [ "$IN_PLACE" = 0 ] && [ -e "$KINDLING_DIR" ]; then
  if [ -d "$KINDLING_DIR/.git" ]; then
    warn "$KINDLING_DIR already exists — updating it instead"
    run git -C "$KINDLING_DIR" pull --ff-only || warn "could not fast-forward; leaving it as is"
  else
    # Never clobber an existing directory; move it aside and say where it went.
    BACKUP="$KINDLING_DIR.pre-kindling.$(date +%Y%m%d%H%M%S)"
    warn "$KINDLING_DIR exists and is not an Kindling checkout"
    warn "moving it to $BACKUP"
    run mv -- "$KINDLING_DIR" "$BACKUP"
  fi
fi

if [ "$IN_PLACE" = 0 ] && [ ! -e "$KINDLING_DIR" ]; then
  # Installing from a local copy (this repo) is the normal case when you ran
  # install.sh out of a clone; cloning is for the curl-to-sh path.
  if [ -f "$SOURCE_DIR/kindling.zsh" ]; then
    run mkdir -p "$KINDLING_DIR"
    run cp -R "$SOURCE_DIR/." "$KINDLING_DIR/"
    # An installed copy is not a checkout. Carrying .git across would make
    # Kindling report itself as a git install and send `kindling update` to `git
    # pull` in a directory with no remote, instead of telling the user to
    # re-run the installer. Also drop the AppleDouble sidecars that macOS
    # leaves on exFAT volumes, which otherwise travel with the copy.
    if [ "$DRY_RUN" = 0 ]; then
      rm -rf "$KINDLING_DIR/.git"
      find "$KINDLING_DIR" -name '._*' -delete 2>/dev/null || true
    fi
    did "copy the files from $SOURCE_DIR"
  elif command -v git >/dev/null 2>&1; then
    run git clone --depth 1 -- "$REPO" "$KINDLING_DIR" || die "clone failed"
    did "clone $REPO"
  else
    die "no local copy and no git available"
  fi
fi

run mkdir -p "$KINDLING_DIR/custom/plugins" "$KINDLING_DIR/custom/themes"
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
  say "  Running Kindling alongside oh-my-zsh does not work well: both set the"
  say "  prompt from a precmd hook, both run compinit, and both bind ZLE"
  say "  widgets. Kindling would load second and win, while you keep paying"
  say "  oh-my-zsh's startup cost for nothing."
  say ""
  say "  Pick one:"
  say ""
  say "    ${BOLD}sh install.sh --replace-omz${RESET}"
  say "      Make Kindling the active framework, reversibly. oh-my-zsh is left"
  say "      completely intact: the files stay, its line stays in your .zshrc,"
  say "      and it simply becomes conditional so it loads whenever Kindling is"
  say "      switched off. Afterwards ${BOLD}kindling off${RESET} returns you to"
  say "      oh-my-zsh and ${BOLD}kindling on${RESET} comes back. Nothing is deleted."
  say ""
  say "    ${BOLD}sh install.sh --no-zshrc${RESET}"
  say "      Install the files only and wire it up yourself later."
  say ""
  exit 1
fi

if [ "$TOUCH_ZSHRC" = 1 ]; then
  step "Configuring $ZSHRC"

  if [ -f "$ZSHRC" ] && grep -q 'kindling\.zsh' "$ZSHRC" 2>/dev/null; then
    ok "already sources kindling.zsh — leaving it alone"
  else
    if [ -f "$ZSHRC" ]; then
      BACKUP="$ZSHRC.pre-kindling.$(date +%Y%m%d%H%M%S)"
      run cp -- "$ZSHRC" "$BACKUP"
      did "back up your existing .zshrc to $BACKUP"

      if [ "$REPLACE_OMZ" = 1 ] && [ -n "$OMZ_LINE" ]; then
        # Make oh-my-zsh conditional instead of removing it. The line stays,
        # oh-my-zsh stays installed, and it loads again the moment Kindling is
        # switched off — so this is reversible without editing anything.
        if [ "$DRY_RUN" = 0 ]; then
          TMP="$ZSHRC.kindling.$$"
          # shellcheck disable=SC2016  # $HOME is written literally, on purpose:
          # it is expanded by the user's shell when their .zshrc runs, not here.
          sed 's|^\([[:space:]]*\)\(source[[:space:]].*oh-my-zsh\.sh.*\)$|\1# Kindling made this conditional; it loads whenever Kindling is switched off.\
\1[ -f "$HOME/.kindling-off" ] \&\& \2|' "$ZSHRC" > "$TMP" && mv -f "$TMP" "$ZSHRC"
        fi
        did "make oh-my-zsh conditional (line ${OMZ_LINE%%:*}) — it is not removed"
      fi

      # Append rather than replace: an existing .zshrc is the user's work and
      # must survive. The trade-off is that Kindling then loads last, so where
      # both define the same alias, Kindling's wins — which is why the note below
      # tells the user how to get the other precedence.
      if [ "$DRY_RUN" = 0 ]; then
        # shellcheck disable=SC2016  # Everything here is written verbatim into
        # the user's .zshrc; $HOME and $KINDLING must survive as literal text.
        {
          printf '\n# --- Kindling ---------------------------------------------------------------\n'
          printf '# `kindling off` creates ~/.kindling-off and this block stops loading, which\n'
          printf '# restores whatever your shell did before. `kindling on` removes it again.\n'
          printf '# If Kindling ever breaks your shell:  touch ~/.kindling-off\n'
          printf 'if [ ! -f "$HOME/.kindling-off" ]; then\n'
          printf '  export KINDLING="%s"\n' "$KINDLING_DIR"
          printf '  kindling_plugins=(git jump zline extract)\n'
          printf '  KINDLING_THEME=spark\n'
          printf '  # Guarded so a missing $KINDLING (an unmounted drive, a moved\n'
          printf '  # checkout) costs you a plain shell, not an error on every\n'
          printf '  # prompt and a broken login.\n'
          printf '  [ -r "$KINDLING/kindling.zsh" ] && source "$KINDLING/kindling.zsh"\n'
          printf 'fi\n'
          printf '# --- end Kindling -----------------------------------------------------------\n'
        } >> "$ZSHRC"
      fi
      did "append Kindling's block to your .zshrc"
      say "    Your own settings are above Kindling's block and were not touched."
      say "    Because Kindling loads last, it wins where you both set the same"
      say "    alias. Move those lines below the block to take them back."
    else
      if [ "$DRY_RUN" = 0 ]; then
        sed "s|\$HOME/.kindling|$KINDLING_DIR|" "$KINDLING_DIR/templates/zshrc.template" > "$ZSHRC"
      fi
      did "create a new .zshrc from the template"
    fi
  fi
else
  step "Skipping .zshrc (--no-zshrc)"
  say "  Add this to your .zshrc yourself:"
  say ""
  say "    export KINDLING=\"$KINDLING_DIR\""
  say "    kindling_plugins=(git jump zline extract)"
  say "    KINDLING_THEME=spark"
  say "    source \"\$KINDLING/kindling.zsh\""
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
    warn "a new interactive zsh reported errors; run 'kindling doctor' once you're in"
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
say "  ${BOLD}kindling list${RESET}      what's available"
say "  ${BOLD}kindling doctor${RESET}    check the install"
say "  ${BOLD}kindling help${RESET}      everything else"
say ""
