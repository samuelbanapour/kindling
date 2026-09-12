# plugins/docker — short forms for the commands you run twenty times a day.

(( $+commands[docker] )) || return 0

alias d='docker'
alias dps='docker ps --format "table {{.Names}}\t{{.Status}}\t{{.Ports}}"'
alias dpsa='docker ps -a --format "table {{.Names}}\t{{.Status}}\t{{.Image}}"'
alias di='docker images'
alias dlog='docker logs --follow --tail 100'
alias dex='docker exec --interactive --tty'
alias drm='docker rm --force'
alias drmi='docker rmi'

# compose is a subcommand in v2 and a separate binary in v1. Asking docker
# which it is costs ~20ms — it talks to the daemon — so resolve it on first
# use and remember the answer, instead of paying for it in every shell.
typeset -g _ember_dc=""
dc() {
  if [[ -z $_ember_dc ]]; then
    if command docker compose version >/dev/null 2>&1; then
      _ember_dc="docker compose"
    elif (( $+commands[docker-compose] )); then
      _ember_dc="docker-compose"
    else
      print -ru2 -- "dc: no docker compose available"
      return 1
    fi
  fi
  ${=_ember_dc} "$@"
}

dcu() { dc up --detach "$@" }
dcd() { dc down "$@" }
dcl() { dc logs --follow --tail 100 "$@" }
dcr() { dc restart "$@" }
dcb() { dc build "$@" }

# dsh <container> — shell into a container, preferring bash then sh.
dsh() {
  local container=${1:-$(_ember_docker_pick)}
  [[ -z $container ]] && return 1
  docker exec -it "$container" bash 2>/dev/null ||
    docker exec -it "$container" sh
}

_ember_docker_pick() {
  if (( $+commands[fzf] )); then
    docker ps --format '{{.Names}}' | fzf --height 40% --reverse --prompt='container> '
  else
    docker ps --format '{{.Names}}' | head -1
  fi
}

# dip <container> — its IP address.
dip() {
  docker inspect -f '{{range .NetworkSettings.Networks}}{{.IPAddress}}{{end}}' "$1"
}

# dprune — reclaim disk, showing what it will cost before doing it.
dprune() {
  docker system df
  local reply
  read -q "reply?prune stopped containers, dangling images, unused networks? [y/N] " || { print; return 1 }
  print
  docker system prune --force
}
