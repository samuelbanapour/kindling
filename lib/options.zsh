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

# --- can this terminal actually render non-ASCII? ----------------------------
# LANG is unset more often than you would think: ssh sessions that don't
# forward it, cron, minimal containers, and any terminal whose "set locale on
# startup" box is unchecked. Drawing a U+276F prompt character there produces
# mojibake, and padding a string with one produces broken bytes, because zsh
# counts a multibyte character as three under LC_CTYPE=C.
#
# The test avoids the (#i) glob flag on purpose: extended_glob is not set yet
# at this point in the load order, so (#i) would be matched as literal text and
# every UTF-8 locale would be reported as ASCII.
typeset -g _kindling_locale=${LC_ALL:-${LC_CTYPE:-${LANG:-}}}
if [[ ${_kindling_locale:l} == *utf*8* ]]; then
  typeset -g KINDLING_UTF8=1
else
  typeset -g KINDLING_UTF8=0
fi
unset _kindling_locale

# Decorative characters, resolved once. A function returning these through
# command substitution would fork — per glyph, per prompt — which is precisely
# the cost this framework exists to avoid.
typeset -gA KINDLING_GLYPH
if (( KINDLING_UTF8 )); then
  KINDLING_GLYPH=(
    prompt '❯'  continue '…'  ok '✓'     fail '✗'    warn '!'
    ahead  '⇡'  behind   '⇣'  job '⚙'    conflict '✖'
    on     '●'  off      '○'  bar '█'    sep $'\ue0b0'
  )
else
  KINDLING_GLYPH=(
    prompt '>'  continue '...' ok '+'    fail 'x'    warn '!'
    ahead  '^'  behind   'v'   job '&'   conflict '!'
    on     '*'  off      '-'   bar '#'   sep ''
  )
fi

# Capture the exit status before any other precmd hook can clobber it.
# Registered from the first library loaded, so it always runs first and every
# theme can read KINDLING_LAST_STATUS instead of racing for `$?`.
autoload -Uz add-zsh-hook
typeset -g KINDLING_LAST_STATUS=0
typeset -ga KINDLING_LAST_PIPESTATUS=(0)
_kindling_capture_status() {
  KINDLING_LAST_STATUS=$?
  KINDLING_LAST_PIPESTATUS=("${pipestatus[@]}")
  return $KINDLING_LAST_STATUS
}
add-zsh-hook precmd _kindling_capture_status
