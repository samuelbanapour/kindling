# lib/directory.zsh — navigation.

setopt auto_cd                 # `Documents` cds into it
setopt auto_pushd              # every cd pushes onto the stack
setopt pushd_ignore_dups
setopt pushd_minus             # `cd -2` works the way you'd guess
setopt pushd_silent
setopt cdable_vars
setopt extended_glob           # ^, ~, # in globs — plugins below rely on this
setopt glob_dots               # globs match dotfiles
setopt numeric_glob_sort

DIRSTACKSIZE=20

alias -- -='cd -'
alias ..='cd ..'
alias ...='cd ../..'
alias ....='cd ../../..'
alias .....='cd ../../../..'

# `d` lists the stack; `1`..`9` jump to an entry.
alias d='dirs -v | head -10'
for _i in {1..9}; do alias "$_i"="cd -$_i"; done
unset _i

# mkcd <dir> — make it and go there.
mkcd() { command mkdir -p -- "$1" && cd -- "$1" }

# up [n] — climb n directories (default 1).
up() {
  local n=${1:-1} path=""
  repeat $n path+="../"
  cd -- "${path:-.}"
}
