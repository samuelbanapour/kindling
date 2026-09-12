# lib/options.zsh — baseline shell behaviour.
# Every option here is one a new user would otherwise have to discover.

setopt interactive_comments   # allow `# comment` at the prompt
setopt long_list_jobs         # verbose `jobs` output
setopt multios                # `cmd > a > b` writes both
setopt prompt_subst           # themes need $(...) in PROMPT
setopt no_beep
setopt no_flow_control        # free up ^S / ^Q for keybindings
setopt no_clobber             # `>` won't silently truncate; use `>|`
setopt rc_quotes              # '' inside single quotes is a literal '

unsetopt correct_all          # autocorrect for arguments is more noise than help
setopt correct                # ...but do correct command names

# Report timing for anything that runs longer than 10 seconds of CPU.
: ${REPORTTIME:=10}

# Treat these as word separators for ^W and friends. The default includes
# most punctuation, which makes deleting a path component impossible.
WORDCHARS='*?_-.[]~&;!#$%^(){}<>'

# Capture the exit status before any other precmd hook can clobber it.
# Registered from the first library loaded, so it always runs first and every
# theme can read EMBER_LAST_STATUS instead of racing for `$?`.
autoload -Uz add-zsh-hook
typeset -g EMBER_LAST_STATUS=0
typeset -ga EMBER_LAST_PIPESTATUS=(0)
_ember_capture_status() {
  EMBER_LAST_STATUS=$?
  EMBER_LAST_PIPESTATUS=("${pipestatus[@]}")
  return $EMBER_LAST_STATUS
}
add-zsh-hook precmd _ember_capture_status
