# lib/completion.zsh — completion styles plus a cached, compiled compinit.

setopt always_to_end
setopt auto_menu
setopt complete_in_word
setopt path_dirs               # complete `foo/bar` against $PATH entries
unsetopt menu_complete         # don't insert the first match unasked
unsetopt flow_control

zmodload -i zsh/complist

: ${EMBER_COMPDUMP:="$EMBER_CACHE/zcompdump-${ZSH_VERSION}"}

# _ember_init_completion — called once by the loader after all plugins have
# adjusted fpath. compinit's security audit (-i) and dump rebuild are the two
# slowest parts of a typical zsh startup, so we only do the full check once a
# day and keep a zcompile'd dump around the rest of the time.
_ember_init_completion() {
  autoload -Uz compinit

  local dump=$EMBER_COMPDUMP
  # glob qualifier N.mh-24 => exists, plain file, modified < 24 hours ago
  if [[ -n ${dump}(#qN.mh-24) ]]; then
    compinit -C -d "$dump"        # -C: trust the dump, skip the audit
  else
    compinit -i -d "$dump"
    touch "$dump"
  fi

  # Compiling the dump roughly halves the time to read it back next launch.
  if [[ -s $dump && ( ! -s ${dump}.zwc || $dump -nt ${dump}.zwc ) ]]; then
    zcompile -R -- "${dump}.zwc" "$dump" 2>/dev/null
  fi

  (( ${+functions[bashcompinit]} )) || autoload -Uz bashcompinit
}

zstyle ':completion:*' menu select
zstyle ':completion:*' verbose yes
zstyle ':completion:*' use-cache yes
zstyle ':completion:*' cache-path "$EMBER_CACHE/zcompcache"
zstyle ':completion:*' list-colors ${(s.:.)LS_COLORS}
zstyle ':completion:*' special-dirs true
zstyle ':completion:*' squeeze-slashes true

# Case-insensitive, then partial-word, then substring — in that order, so the
# most literal interpretation of what you typed always wins.
zstyle ':completion:*' matcher-list \
  'm:{a-zA-Z}={A-Za-z}' \
  'r:|[._-]=* r:|=*' \
  'l:|=* r:|=*'

zstyle ':completion:*:descriptions' format '%F{cyan}%B%d%b%f'
zstyle ':completion:*:warnings'     format '%F{red}no matches for %d%f'
zstyle ':completion:*:corrections'  format '%F{yellow}%d (errors: %e)%f'
zstyle ':completion:*' group-name ''

# Never offer the current directory back to `cd ..`
zstyle ':completion:*:cd:*' ignore-parents parent pwd
# Don't suggest an argument that's already on the line.
zstyle ':completion:*:(rm|cp|mv|kill|diff):*' ignore-line other

# Processes, shown as you'd see them in ps.
zstyle ':completion:*:*:kill:*' menu yes select
zstyle ':completion:*:*:kill:*:processes' \
  command 'ps -u $USER -o pid,%cpu,tty,cputime,cmd'
zstyle ':completion:*:*:*:*:processes' force-list always

# Users: don't dump every system account into the menu.
zstyle ':completion:*:*:*:users' ignored-patterns \
  daemon nobody _'*' '_*' root sys bin

# Hosts from ssh config and known_hosts, which is what you actually ssh to.
() {
  local -a hosts
  [[ -r ~/.ssh/config ]] && hosts+=(${${${(@M)${(f)"$(<~/.ssh/config)"}:#Host *}#Host }:#*[*?]*})
  [[ -r ~/.ssh/known_hosts ]] && hosts+=(${${${(f)"$(<~/.ssh/known_hosts)"}%%[ ,]*}:#[|#]*})
  (( ${#hosts} )) && zstyle ':completion:*:*:(ssh|scp|sftp|rsync|ping):*' hosts $hosts
}
