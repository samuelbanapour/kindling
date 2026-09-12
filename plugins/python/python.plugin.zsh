# plugins/python — virtualenv handling that stays out of your way.

alias py='python3'
alias pip='python3 -m pip'
alias serve='python3 -m http.server'
alias json='python3 -m json.tool'

# venv [name] — create (if needed) and activate a virtualenv in this project.
venv() {
  local name=${1:-.venv}
  [[ -d $name ]] || python3 -m venv "$name" || return
  source "$name/bin/activate"
}
alias deact='deactivate'

# Auto-activate on cd, and deactivate on the way out. Only ever touches a venv
# it activated itself, so a manually activated environment survives a cd.
typeset -g _ember_auto_venv=""

_ember_venv_hook() {
  emulate -L zsh
  [[ ${EMBER_PYTHON_AUTOVENV:-1} == 1 ]] || return 0

  # Declared up front: re-running `local` on a parameter that already has a
  # value makes zsh print it, which would spray the venv search across stdout.
  local dir=$PWD found="" candidate
  while [[ $dir != / ]]; do
    for candidate in "$dir/.venv" "$dir/venv" "$dir/env"; do
      [[ -f $candidate/bin/activate ]] && { found=$candidate; break 2 }
    done
    dir=${dir:h}
  done

  if [[ -n $found && $found != $_ember_auto_venv ]]; then
    [[ -n $VIRTUAL_ENV && -n $_ember_auto_venv ]] && deactivate 2>/dev/null
    source "$found/bin/activate"
    _ember_auto_venv=$found
  elif [[ -z $found && -n $_ember_auto_venv ]]; then
    deactivate 2>/dev/null
    _ember_auto_venv=""
  fi
}
autoload -Uz add-zsh-hook
add-zsh-hook chpwd _ember_venv_hook
_ember_venv_hook

# The theme renders the venv itself; stop the activate script duplicating it.
export VIRTUAL_ENV_DISABLE_PROMPT=1

# pyenv and poetry are both slow to initialize — defer them.
if (( $+commands[pyenv] )); then
  ember_lazy pyenv -- 'eval "$(command pyenv init -)"'
fi

# pyclean — drop __pycache__ and friends under the current tree.
pyclean() {
  local -a targets
  targets=( **/__pycache__(N/) **/*.py[co](N) **/.pytest_cache(N/) **/.ruff_cache(N/) )
  (( ${#targets} )) || { print -- "nothing to clean"; return 0 }
  print -l -- "${targets[@]}"
  local reply
  read -q "reply?remove ${#targets} item(s)? [y/N] " || { print; return 1 }
  print
  command rm -rf -- "${targets[@]}"
}
