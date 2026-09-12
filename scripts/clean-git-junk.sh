#!/bin/sh
# Delete the AppleDouble sidecars macOS scatters through .git on exFAT volumes.
# Left alone they corrupt pack indexes and refs. Wired up as a pre/post-commit
# hook; hooks are local, so reinstall them after a fresh clone:
#   cp scripts/clean-git-junk.sh .git/hooks/pre-commit
#   cp scripts/clean-git-junk.sh .git/hooks/post-commit
find "$(git rev-parse --git-dir)" -name '._*' -delete 2>/dev/null
exit 0
