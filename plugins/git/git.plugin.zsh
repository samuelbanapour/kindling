# plugins/git — aliases and workflow functions.
# Naming follows the common `g<verb>` convention so muscle memory carries over.

(( $+commands[git] )) || return 0

alias g='git'
alias gst='git status --short --branch'
alias gss='git status'

alias ga='git add'
alias gaa='git add --all'
alias gap='git add --patch'

alias gc='git commit --verbose'
alias gcm='git commit --message'
alias gca='git commit --verbose --all'
alias gcan='git commit --verbose --all --no-edit --amend'
alias gcf='git commit --fixup'

alias gco='git checkout'
alias gsw='git switch'
alias gswc='git switch --create'
alias gb='git branch'
alias gbd='git branch --delete'
alias gbD='git branch --delete --force'

alias gd='git diff'
alias gds='git diff --staged'
alias gdw='git diff --word-diff=color'

alias gl='git pull'
alias gp='git push'
alias gpf='git push --force-with-lease'   # never plain --force
alias gpu='git push --set-upstream origin $(git symbolic-ref --short HEAD)'

alias gf='git fetch --all --prune'
alias gr='git remote -v'

alias grb='git rebase'
alias grbi='git rebase --interactive'
alias grbc='git rebase --continue'
alias grba='git rebase --abort'

alias gsta='git stash push'
alias gstp='git stash pop'
alias gstl='git stash list'

alias glg="git log --graph --abbrev-commit --date=relative \
--format='%C(auto)%h%d %s %C(dim)(%an, %ar)%C(reset)'"
alias glo='git log --oneline --decorate --graph'

# gcd — jump to the repository root from anywhere inside it.
gcd() {
  local root
  root=$(ember_git_root) || { print -ru2 -- "not a git repository"; return 1 }
  cd -- "$root"
}

# gmain — switch to the repo's default branch and update it.
gmain() {
  local b
  b=$(ember_git_default_branch) || { print -ru2 -- "no default branch found"; return 1 }
  git switch "$b" && git pull --ff-only
}

# gwip / gunwip — park work in progress as a commit, then take it back.
gwip() {
  git add --all && git commit --no-verify --no-gpg-sign --message '--wip-- [skip ci]'
}
gunwip() {
  local subject
  subject=$(git log -1 --format=%s 2>/dev/null)
  [[ $subject == '--wip--'* ]] || { print -ru2 -- "HEAD is not a wip commit"; return 1 }
  git reset HEAD~1
}

# gclean — delete local branches whose upstream is gone. Prints first, asks second.
gclean() {
  local -a gone
  gone=(${(f)"$(git branch --format '%(refname:short) %(upstream:track)' |
    awk '$2 == "[gone]" { print $1 }')"})
  gone=(${gone:#})
  (( ${#gone} )) || { print -- "nothing to clean"; return 0 }
  print -- "branches with a deleted upstream:"
  print -l -- "  ${^gone}"
  local reply
  read -q "reply?delete ${#gone} branch(es)? [y/N] " || { print; return 1 }
  print
  git branch --delete --force -- "${gone[@]}"
}

# gundo — undo the last commit, keeping the changes staged.
gundo() { git reset --soft HEAD~${1:-1} }

# gcob — fuzzy-pick a branch to switch to (uses fzf when present).
gcob() {
  local branch
  if (( $+commands[fzf] )); then
    branch=$(git branch --all --sort=-committerdate --format='%(refname:short)' |
      grep -v '^origin/HEAD' | fzf --height 40% --reverse --prompt='branch> ') || return
  else
    git branch --sort=-committerdate
    read "branch?branch: " || return
  fi
  [[ -z $branch ]] && return
  git switch "${branch#origin/}" 2>/dev/null || git switch --track "$branch"
}

compdef _git g 2>/dev/null
