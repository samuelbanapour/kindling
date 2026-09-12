# plugins/jump — `j <fragment>` takes you to a directory you've used before.
#
# Ranking is frecency: a score combining how often you visit a directory with
# how recently. A place you went to 50 times last year loses to one you went to
# 5 times this morning.
#
#   j proj        jump to the best match for "proj"
#   j src app     both fragments must match, in order
#   j -l pat      list matches with scores instead of jumping
#   j -r          rank by frequency only
#   j --forget    remove the current directory from the database

: ${EMBER_JUMP_DATA:="${XDG_DATA_HOME:-$HOME/.local/share}/ember/jump.db"}
: ${EMBER_JUMP_MAX:=8000}      # total score before the database is aged down
typeset -g EMBER_JUMP_DATA EMBER_JUMP_MAX

[[ -d ${EMBER_JUMP_DATA:h} ]] || command mkdir -p "${EMBER_JUMP_DATA:h}"
[[ -f $EMBER_JUMP_DATA ]] || : >| "$EMBER_JUMP_DATA"

# Directories never worth recording.
: ${EMBER_JUMP_EXCLUDE:="$HOME:/tmp:/private/tmp"}

# Record the current directory. Runs in the background so a cd never blocks.
_ember_jump_add() {
  # emulate -L zsh restores `clobber`, which lib/options.zsh turns off for the
  # interactive shell. Without it the redirection below fails on a stale file.
  emulate -L zsh
  local dir=${PWD:A}
  [[ -z $dir || $dir == / ]] && return 0

  local excl
  for excl in ${(s.:.)EMBER_JUMP_EXCLUDE}; do
    [[ $dir == ${~excl} ]] && return 0
  done

  # $$ alone collides when two `cd`s land in the same second: the writers are
  # backgrounded, so both would target the same temporary file.
  local now=$EPOCHSECONDS tmp="$EMBER_JUMP_DATA.$$.$RANDOM"
  local lock="$EMBER_JUMP_DATA.lock"

  # Backgrounded and detached: recording a visit must never delay a `cd`.
  #
  # The update is a read-modify-write, so two `cd`s in quick succession would
  # both read the same starting file and the second would overwrite the first.
  # mkdir is atomic on every filesystem worth supporting, which makes it the
  # cheapest lock available here — and since all of this runs in the
  # background, waiting for it costs the shell nothing.
  #
  # `command mkdir` is not optional. lib/aliases.zsh defines `mkdir` as
  # `mkdir -p`, and `mkdir -p` succeeds on a directory that already exists —
  # which would make this lock succeed for everyone and guard nothing.
  (
    local -i tries=0
    while ! command mkdir "$lock" 2>/dev/null; do
      # A shell killed mid-update would leave the lock behind forever. After a
      # second, take it: losing one entry from a cache of visited directories
      # is not worth blocking every future `cd` over.
      if (( ++tries > 100 )); then
        command rmdir "$lock" 2>/dev/null
        break
      fi
      sleep 0.01
    done

    command awk -v dir="$dir" -v now="$now" -v max="$EMBER_JUMP_MAX" '
      BEGIN { FS = "|"; OFS = "|" }
      NF == 3 && !($1 in rank) { rank[$1] = $2; when[$1] = $3; order[++n] = $1 }
      END {
        if (dir in rank) { rank[dir] += 1 } else { rank[dir] = 1; order[++n] = dir }
        when[dir] = now
        for (i = 1; i <= n; i++) total += rank[order[i]]
        # Once the database gets heavy, age every entry down by 10% so that
        # old favourites decay instead of dominating forever. Entries that
        # decay below 1 fall out entirely.
        decay = (total > max) ? 0.9 : 1.0
        for (i = 1; i <= n; i++) {
          p = order[i]; r = rank[p] * decay
          if (r >= 0.98) printf "%s|%.4f|%d\n", p, r, when[p]
        }
      }
    ' "$EMBER_JUMP_DATA" >| "$tmp" 2>/dev/null &&
      command mv -f "$tmp" "$EMBER_JUMP_DATA" 2>/dev/null

    command rm -f -- "$tmp" 2>/dev/null
    command rmdir "$lock" 2>/dev/null
  ) &!
}

zmodload zsh/datetime 2>/dev/null
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _ember_jump_add

# _ember_jump_match <mode> <pattern>... — prints "score|path" lines, best last.
_ember_jump_match() {
  local mode=$1; shift
  command awk -v now="$EPOCHSECONDS" -v mode="$mode" -v q="${(j:|:)@}" '
    BEGIN { FS = "|"; n = split(q, pats, "|") }
    {
      path = $1; rank = $2; last = $3
      # Every fragment must appear, in the order given.
      pos = 0
      for (i = 1; i <= n; i++) {
        idx = index(tolower(substr(path, pos + 1)), tolower(pats[i]))
        if (idx == 0) next
        pos += idx
      }
      dt = now - last
      if (mode == "rank")        score = rank
      else if (mode == "recent") score = -dt
      else {
        # frecency: recent visits are worth several old ones
        if (dt < 3600)        score = rank * 4
        else if (dt < 86400)  score = rank * 2
        else if (dt < 604800) score = rank / 2
        else                  score = rank / 4
      }
      printf "%.4f|%s\n", score, path
    }
  ' "$EMBER_JUMP_DATA" 2>/dev/null | command sort -t'|' -k1,1g
}

j() {
  emulate -L zsh
  local mode=frecent list=0

  while [[ $1 == -* ]]; do
    case $1 in
      (-l|--list)   list=1; shift ;;
      (-r|--rank)   mode=rank; shift ;;
      (-t|--recent) mode=recent; shift ;;
      (--forget)
        command grep -v "^${PWD:A}|" "$EMBER_JUMP_DATA" >| "$EMBER_JUMP_DATA.tmp" &&
          command mv -f "$EMBER_JUMP_DATA.tmp" "$EMBER_JUMP_DATA"
        print -- "forgot ${PWD:A}"; return 0 ;;
      (--clear)
        : >| "$EMBER_JUMP_DATA"; print -- "jump database cleared"; return 0 ;;
      (-h|--help)
        print -- "usage: j [-l] [-r|-t] <fragment>...   j --forget | --clear"
        return 0 ;;
      (*) break ;;
    esac
  done

  # A real path always wins over a fuzzy match.
  if (( $# == 1 )) && [[ -d $1 ]]; then cd -- "$1"; return; fi

  (( $# )) || { cd -- "$HOME"; return }

  local -a results
  results=(${(f)"$(_ember_jump_match "$mode" "$@")"})
  results=(${results:#})

  if (( ! ${#results} )); then
    print -ru2 -- "j: no match for '$*'"
    return 1
  fi

  if (( list )); then
    local line
    for line in "${(Oa)results[@]}"; do
      printf '%8.1f  %s\n' "${line%%|*}" "${line#*|}"
    done
    return 0
  fi

  local best=${results[-1]#*|}
  if [[ ! -d $best ]]; then
    # Stale entry: drop it and try again.
    command grep -v "^${best}|" "$EMBER_JUMP_DATA" >| "$EMBER_JUMP_DATA.tmp" &&
      command mv -f "$EMBER_JUMP_DATA.tmp" "$EMBER_JUMP_DATA"
    j "$@"
    return
  fi
  cd -- "$best"
}

# ji — interactive picker over the whole database.
ji() {
  (( $+commands[fzf] )) || { j -l "$@"; return }
  local target
  target=$(_ember_jump_match frecent "$@" | command sort -t'|' -k1,1gr |
    command cut -d'|' -f2- | fzf --height 40% --reverse --prompt='jump> ') || return
  [[ -n $target ]] && cd -- "$target"
}

# Completion: offer matching directories for `j <tab>`.
_ember_jump_complete() {
  local -a matches
  matches=(${${(f)"$(_ember_jump_match frecent "${words[CURRENT]}")"}#*|})
  matches=(${matches:#})
  (( ${#matches} )) && compadd -U -Q -a matches
}
compdef _ember_jump_complete j 2>/dev/null

# Record the directory the shell started in — but after the first prompt, so
# the awk it forks never sits between you and a usable shell.
if (( $+functions[ember_defer] )); then
  ember_defer '_ember_jump_add'
else
  _ember_jump_add
fi
