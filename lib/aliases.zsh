# lib/aliases.zsh — small, universal aliases only.
# Anything tool-specific belongs in a plugin so it can be opted out of.

# ls: prefer eza, then GNU coreutils, then BSD.
#
# Which `ls` this is gets decided from what's installed and which platform
# we're on. Running `ls --version` to find out would be more direct, but it is
# a fork in every single shell to answer a question whose answer never changes.
if (( $+commands[eza] )); then
  alias ls='eza --group-directories-first'
  alias ll='eza -lg --group-directories-first --git'
  alias la='eza -lga --group-directories-first --git'
  alias lt='eza --tree --level=2'
elif (( $+commands[gls] )); then           # coreutils from Homebrew
  alias ls='gls --color=auto --group-directories-first'
  alias ll='gls -lh --color=auto --group-directories-first'
  alias la='gls -lAh --color=auto --group-directories-first'
elif [[ $OSTYPE == (darwin|freebsd|openbsd|netbsd|dragonfly)* ]]; then
  export CLICOLOR=1                        # BSD ls colourises from the env
  alias ll='ls -lh'
  alias la='ls -lAh'
else
  alias ls='ls --color=auto --group-directories-first'
  alias ll='ls -lh --color=auto --group-directories-first'
  alias la='ls -lAh --color=auto --group-directories-first'
fi
alias l='ll'

alias grep='grep --color=auto'
alias mkdir='mkdir -p'
alias df='df -h'
alias du='du -h'
alias free='free -h'

# Safety rails on the three commands that eat data.
alias rm='rm -i'
alias cp='cp -i'
alias mv='mv -i'

alias please='sudo'
alias c='clear'
alias reload='exec ${SHELL} -l'
alias path='print -l $path'

# Global aliases: expand anywhere on the line, not just in command position.
alias -g G='| grep -i'
alias -g L='| less -R'
alias -g NE='2>/dev/null'
alias -g NUL='>/dev/null 2>&1'
alias -g C='| pbcopy 2>/dev/null || xclip -selection clipboard'

# Suffix aliases: `foo.md` opens in the right thing.
if (( $+commands[bat] )); then
  alias cat='bat --paging=never --style=plain'
  alias -s {md,markdown,txt,json,yaml,yml,toml}=bat
fi

# take <dir|url|archive> — the one alias worth being a function.
# Makes and enters a directory; clones a repo and enters it; extracts an
# archive and enters it.
take() {
  local arg=$1
  case $arg in
    (*.git|git@*|http(s|)://*.git)
      local name=${${arg##*/}%.git}
      git clone -- "$arg" && cd -- "$name" ;;
    (*.tar.gz|*.tgz|*.tar.bz2|*.tar.xz|*.tar|*.zip)
      # Unpacking lives in the extract plugin, which may not be enabled.
      if (( ! $+functions[extract] )); then
        print -ru2 -- "take: unpacking needs the extract plugin (ember enable extract)"
        return 1
      fi
      local dir=${${arg:t}%%.*}
      mkdir -p -- "$dir" && extract "$arg" --into "$dir" && cd -- "$dir" ;;
    (*)
      mkdir -p -- "$arg" && cd -- "$arg" ;;
  esac
}
