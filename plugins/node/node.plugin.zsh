# plugins/node — package-manager aliases that follow the project you're in,
# plus lazy nvm so a version manager never costs you startup time.

# npm/yarn/pnpm/bun all spell the same operations differently. `n` dispatches
# to whichever one this project actually uses, detected from its lockfile.
_kindling_node_pm() {
  local dir=$PWD
  while [[ $dir != / ]]; do
    [[ -f $dir/bun.lockb || -f $dir/bun.lock ]] && { print -r -- bun; return }
    [[ -f $dir/pnpm-lock.yaml ]] && { print -r -- pnpm; return }
    [[ -f $dir/yarn.lock ]]      && { print -r -- yarn; return }
    [[ -f $dir/package-lock.json ]] && { print -r -- npm; return }
    [[ -f $dir/package.json ]]   && { print -r -- npm; return }
    dir=${dir:h}
  done
  print -r -- npm
}

# n <subcommand> [args] — `n i`, `n add foo`, `n run build`, `n test`.
n() {
  local pm=$(_kindling_node_pm)
  case $1 in
    (i|install) shift; "$pm" install "$@" ;;
    (a|add)     shift
                case $pm in
                  (npm) command npm install "$@" ;;
                  (*)   "$pm" add "$@" ;;
                esac ;;
    (rm|remove) shift
                case $pm in
                  (npm) command npm uninstall "$@" ;;
                  (*)   "$pm" remove "$@" ;;
                esac ;;
    (x|exec)    shift
                case $pm in
                  (npm) command npx "$@" ;;
                  (yarn) yarn dlx "$@" 2>/dev/null || yarn "$@" ;;
                  (*)   "$pm" dlx "$@" ;;
                esac ;;
    (r|run)     shift; "$pm" run "$@" ;;
    ('')        print -r -- "$pm" ;;
    (*)         "$pm" "$@" ;;
  esac
}

alias ni='n i'
alias na='n add'
alias nr='n run'
alias nrd='n run dev'
alias nrb='n run build'
alias nrt='n run test'
alias nx='n x'

# nls — the scripts this project defines, without opening package.json.
nls() {
  local pkg=package.json dir=$PWD
  while [[ $dir != / && ! -f $dir/package.json ]]; do dir=${dir:h}; done
  [[ -f $dir/package.json ]] || { print -ru2 -- "no package.json found"; return 1 }
  if (( $+commands[jq] )); then
    jq -r '.scripts | to_entries[] | "\(.key)\t\(.value)"' "$dir/package.json" |
      column -t -s $'\t'
  else
    node -e 'const s=require(process.argv[1]).scripts||{};
      for (const [k,v] of Object.entries(s)) console.log(k.padEnd(16), v);' "$dir/package.json"
  fi
}

# Put the project's binaries on PATH while you're inside it.
_kindling_node_path() {
  local bin=$PWD/node_modules/.bin
  path=(${path:#*/node_modules/.bin})
  [[ -d $bin ]] && path=("$bin" $path)
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _kindling_node_path
_kindling_node_path

# nvm costs ~400ms to source. Load it the first time something needs it.
if [[ -s ${NVM_DIR:-$HOME/.nvm}/nvm.sh ]]; then
  export NVM_DIR=${NVM_DIR:-$HOME/.nvm}
  kindling_lazy nvm node npm npx -- '
    source "$NVM_DIR/nvm.sh"
    [[ -s "$NVM_DIR/bash_completion" ]] && source "$NVM_DIR/bash_completion"
  '
  # Respect .nvmrc on cd, but only once nvm is actually loaded.
  _kindling_nvmrc() {
    [[ -f .nvmrc ]] || return 0
    (( $+functions[nvm] )) || return 0
    local want=$(<.nvmrc)
    [[ $(nvm current) == *${want#v}* ]] || nvm use --silent 2>/dev/null
  }
  add-zsh-hook chpwd _kindling_nvmrc
fi
