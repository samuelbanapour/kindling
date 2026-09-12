# lib/history.zsh — a history you can actually rely on.

# macOS ships an /etc/zshrc that sets HISTFILE, HISTSIZE and SAVEHIST, and so
# do several Linux distributions. It runs before ~/.zshrc, which means the
# usual `: ${HISTSIZE:=100000}` idiom silently does nothing here and you are
# left with the system's 1000-line history wondering where your commands went.
# So: assign, don't default — and give the user explicit variables to override.
#
# HISTFILE is the exception. If something already chose one, keep it: moving
# the file would hide the history you already have. Kindling's own XDG location is
# only used when nothing else has picked a path.
: ${KINDLING_HISTFILE:=${HISTFILE:-${XDG_STATE_HOME:-$HOME/.local/state}/kindling/history}}
HISTFILE=$KINDLING_HISTFILE
HISTSIZE=${KINDLING_HISTSIZE:-100000}
SAVEHIST=${KINDLING_SAVEHIST:-100000}
[[ -d ${HISTFILE:h} ]] || command mkdir -p "${HISTFILE:h}"

setopt extended_history        # record timestamp + duration
setopt inc_append_history      # write as commands run, not at shell exit
setopt share_history           # and pick up what other shells wrote
setopt hist_expire_dups_first
setopt hist_ignore_dups        # don't log a command identical to the last one
setopt hist_ignore_space       # a leading space keeps it out of history
setopt hist_find_no_dups
setopt hist_reduce_blanks
setopt hist_verify             # !! expands for review instead of running

# Commands that are noise, secrets, or both.
: ${HISTORY_IGNORE:='(ls|ll|la|cd|cd ..|pwd|exit|clear|c|h|history|* --help|* -h)'}

# Never persist a line that looks like it carries a credential.
_kindling_history_filter() {
  # zshaddhistory: return 1 to discard the line.
  local line=${1%%$'\n'}
  [[ $line == *(PASSWORD|SECRET|TOKEN|API_KEY|ACCESS_KEY)=* ]] && return 1
  return 0
}
autoload -Uz add-zsh-hook
add-zsh-hook zshaddhistory _kindling_history_filter

alias h='history'
# `hgrep <pattern>` — search history without the fc incantation.
hgrep() { fc -lim "*$**" 1 }
