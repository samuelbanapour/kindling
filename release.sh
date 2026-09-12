#!/bin/sh
# release.sh <version> — tag a release and print the formula fields to update.
#
#   sh release.sh 1.0.1
#
# Bump KINDLING_VERSION in kindling.zsh first. This refuses to tag if the
# source disagrees about the version or if the suite fails, then fetches the
# tarball GitHub generated for the tag and prints its checksum.
#
# Fetching matters: GitHub builds that archive itself, and its gzip output is
# not guaranteed to match a local `git archive`. Using a locally computed
# checksum produces a formula that fails for everyone but you.
set -eu

V=${1:-}
[ -n "$V" ] || { echo "usage: sh release.sh <version>" >&2; exit 1; }
OWNER=${OWNER:-samuelbanapour}
REPO=${REPO:-kindling}

SRC_V=$(sed -n 's/.*KINDLING_VERSION="\([^"]*\)".*/\1/p' kindling.zsh | head -1)
if [ "$SRC_V" != "$V" ]; then
  echo "kindling.zsh says $SRC_V, you asked for $V." >&2
  echo "Update KINDLING_VERSION in kindling.zsh first." >&2
  exit 1
fi

if [ -n "$(git status --porcelain)" ]; then
  echo "working tree is dirty; commit before tagging." >&2
  exit 1
fi

echo "==> Running the suite"
zsh test/run.zsh >/dev/null || { echo "tests fail; not tagging." >&2; exit 1; }

echo "==> Tagging v$V"
git tag -a "v$V" -m "Kindling $V"
git push origin HEAD "v$V"

echo "==> Fetching the tarball GitHub generated"
URL="https://github.com/$OWNER/$REPO/archive/refs/tags/v$V.tar.gz"
# The tag needs a moment to become fetchable.
SHA=""
i=0
while [ $i -lt 10 ]; do
  SHA=$(curl -fsSL "$URL" 2>/dev/null | shasum -a 256 | awk '{print $1}') || true
  [ -n "$SHA" ] && [ "$SHA" != "e3b0c44298fc1c149afbf4c8996fb92427ae41e4649b934ca495991b7852b855" ] && break
  i=$((i + 1))
  sleep 3
done
[ -n "$SHA" ] || { echo "could not fetch $URL" >&2; exit 1; }

cat <<OUT

Update Formula/kindling.rb in the tap with:

  url "$URL"
  sha256 "$SHA"

Then, from the tap:
  brew style   --formula Formula/kindling.rb
  brew install --build-from-source $OWNER/$REPO/$REPO
  brew test    $OWNER/$REPO/$REPO
  brew audit --strict --formula $OWNER/$REPO/$REPO
OUT
