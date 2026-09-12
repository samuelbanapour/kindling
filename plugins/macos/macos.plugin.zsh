# plugins/macos — Finder, clipboard, and system bits. No-op elsewhere.

[[ $OSTYPE == darwin* ]] || return 0

# ofd — open the current directory (or an argument) in Finder.
ofd() { open "${1:-.}" }
alias o='open'

# cdf — cd to the directory of the frontmost Finder window.
cdf() {
  local target
  target=$(osascript -e 'tell application "Finder" to if (count of Finder windows) > 0 then get POSIX path of (target of front Finder window as text)') 2>/dev/null
  [[ -n $target ]] && cd -- "$target" || print -ru2 -- "no Finder window open"
}

# showfiles / hidefiles — toggle hidden files in Finder.
showfiles() { defaults write com.apple.finder AppleShowAllFiles -bool true;  killall Finder }
hidefiles() { defaults write com.apple.finder AppleShowAllFiles -bool false; killall Finder }

# Clipboard, named the way the rest of the world names them.
alias pbc='pbcopy'
alias pbp='pbpaste'
# cpwd — current directory onto the clipboard.
cpwd() { print -rn -- "$PWD" | pbcopy && print -- "copied: $PWD" }

# quicklook <file>
ql() { qlmanage -p "$@" >/dev/null 2>&1 & }

# Strip the quarantine attribute from something you downloaded deliberately.
unquarantine() {
  (( $# )) || { print -ru2 -- "usage: unquarantine <path>..."; return 1 }
  xattr -dr com.apple.quarantine "$@" && print -- "unquarantined: $*"
}

# Purge the .DS_Store files this platform scatters everywhere.
dsclean() {
  local -a found=( **/.DS_Store(N.D) )
  (( ${#found} )) || { print -- "no .DS_Store files here"; return 0 }
  print -- "removing ${#found} file(s)"
  command rm -f -- "${found[@]}"
}

# Homebrew, if present. Aliases only — no `brew shellenv` eval at startup,
# which would cost a fork on every shell.
if (( $+commands[brew] )); then
  alias bi='brew install'
  alias bu='brew uninstall'
  alias bs='brew search'
  alias binf='brew info'
  alias bup='brew update && brew upgrade && brew cleanup'
  alias bls='brew leaves'          # what you asked for, not every dependency
  alias bcl='brew cleanup --prune=all'
fi

# Wi-Fi network you're on, without digging through System Settings.
wifi() {
  local dev
  dev=$(networksetup -listallhardwareports |
    awk '/Wi-Fi|AirPort/{getline; print $2; exit}')
  [[ -z $dev ]] && { print -ru2 -- "no Wi-Fi interface found"; return 1 }
  networksetup -getairportnetwork "$dev"
}

# localip / publicip
localip()  { ipconfig getifaddr en0 2>/dev/null || ipconfig getifaddr en1 }
publicip() { curl -fsS --max-time 5 https://api.ipify.org && print }

# Keep the machine awake for a while: `caffeine 2h`, `caffeine` for indefinite.
caffeine() {
  if (( $# )); then
    local secs
    case $1 in
      (*h) secs=$(( ${1%h} * 3600 )) ;;
      (*m) secs=$(( ${1%m} * 60 )) ;;
      (*)  secs=$1 ;;
    esac
    print -- "staying awake for $1"
    caffeinate -dimsu -t "$secs"
  else
    print -- "staying awake until you press ^C"
    caffeinate -dimsu
  fi
}
