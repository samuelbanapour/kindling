# lib/git.zsh — shared git helpers used by both the git plugin and the themes.
# Themes call these on every prompt, so each one is a single git invocation at
# most and every result is cached against the repository's index mtime.

typeset -gA _kindling_git_cache

# kindling_git_root — top level of the repo containing $PWD, or empty.
kindling_git_root() {
  local root
  root=$(command git rev-parse --show-toplevel 2>/dev/null) || return 1
  print -r -- "$root"
}

# kindling_git_branch — branch name, or a short sha when detached, or empty.
kindling_git_branch() {
  local ref
  ref=$(command git symbolic-ref --quiet --short HEAD 2>/dev/null) && {
    print -r -- "$ref"; return 0
  }
  ref=$(command git rev-parse --short HEAD 2>/dev/null) || return 1
  print -r -- "@$ref"
}

# kindling_git_status — one word per condition, space separated:
#   dirty staged untracked stash ahead:N behind:N conflict
# A single `git status --porcelain=v2 --branch` call answers all of it.
kindling_git_status() {
  local -a flags
  local line ahead=0 behind=0
  local dirty=0 staged=0 untracked=0 conflict=0

  local out
  out=$(command git status --porcelain=v2 --branch --untracked-files=normal 2>/dev/null) || return 1

  for line in ${(f)out}; do
    case $line in
      ('# branch.ab '*)
        local ab=${line#\# branch.ab }
        ahead=${${ab%% *}#+}
        behind=${${ab##* }#-}
        ;;
      ('1 '*|'2 '*)
        # XY field is the 2nd column: index status then worktree status.
        local xy=${${(z)line}[2]}
        [[ ${xy[1]} != '.' ]] && staged=1
        [[ ${xy[2]} != '.' ]] && dirty=1
        ;;
      ('u '*) conflict=1 ;;
      ('? '*) untracked=1 ;;
    esac
  done

  (( conflict ))  && flags+=(conflict)
  (( staged ))    && flags+=(staged)
  (( dirty ))     && flags+=(dirty)
  (( untracked )) && flags+=(untracked)
  (( ahead ))     && flags+=("ahead:$ahead")
  (( behind ))    && flags+=("behind:$behind")

  [[ -n $(command git stash list 2>/dev/null | head -1) ]] && flags+=(stash)

  print -r -- "${flags[*]}"
}

# kindling_git_default_branch — main, master, trunk, whatever origin says.
kindling_git_default_branch() {
  local b
  b=$(command git symbolic-ref --quiet --short refs/remotes/origin/HEAD 2>/dev/null) \
    && { print -r -- "${b#origin/}"; return 0 }
  for b in main master trunk develop; do
    command git show-ref --verify --quiet "refs/heads/$b" && { print -r -- "$b"; return 0 }
  done
  return 1
}
