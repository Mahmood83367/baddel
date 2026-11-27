#!/bin/bash
# Guards the rule that every published update has its own, higher version:
#
#   - VERSION must be a plain MAJOR.MINOR.PATCH or MAJOR.MINOR.PATCH-prerelease;
#   - if the tag v<VERSION> already exists on the remote, the commit being built
#     must be exactly the commit that tag points to. Anything else would be new
#     content under an already published version, so the check fails and
#     VERSION must be increased;
#   - VERSION must be higher than every existing release tag, unless it is one
#     of them (the release commit itself).
#
# usage: tools/check-version.sh [commit]     (default: HEAD)
set -euo pipefail
cd "$(dirname "$0")/.."
VERSION=$(tr -d '[:space:]' < VERSION)
COMMIT=$(git rev-parse "${1:-HEAD}")
REMOTE=${BADDEL_REMOTE:-origin}

if ! [[ "$VERSION" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]]; then
  echo "FAIL VERSION '$VERSION' is not MAJOR.MINOR.PATCH[-prerelease]"; exit 1
fi

TAGS=$(git ls-remote --tags "$REMOTE" 'refs/tags/v*')
# Annotated tags list the commit on the peeled "^{}" line; prefer it.
tag_commit() {
  local peeled plain
  peeled=$(awk -v r="refs/tags/$1^{}" '$2==r{print $1}' <<<"$TAGS")
  plain=$(awk -v r="refs/tags/$1" '$2==r{print $1}' <<<"$TAGS")
  echo "${peeled:-$plain}"
}

EXISTING=$(tag_commit "v$VERSION")
if [ -n "$EXISTING" ]; then
  if [ "$EXISTING" = "$COMMIT" ]; then
    echo "PASS v$VERSION is published from this exact commit"; exit 0
  fi
  echo "FAIL v$VERSION is already published from ${EXISTING:0:7}; this is ${COMMIT:0:7}. Increase VERSION."; exit 1
fi

# Not published yet: it must be newer than everything that is.
core() { echo "${1%%-*}"; }
for tag in $(awk '{print $2}' <<<"$TAGS" | sed -e 's#refs/tags/v##' -e 's#\^{}##' | sort -u); do
  [[ "$tag" =~ ^[0-9]+\.[0-9]+\.[0-9]+(-[0-9A-Za-z.-]+)?$ ]] || continue
  highest=$(printf '%s\n%s\n' "$(core "$tag")" "$(core "$VERSION")" | sort -t. -k1,1n -k2,2n -k3,3n | tail -1)
  if [ "$highest" != "$(core "$VERSION")" ] || { [ "$(core "$tag")" = "$(core "$VERSION")" ] && [ "$tag" = "$(core "$tag")" ]; }; then
    echo "FAIL VERSION $VERSION is not higher than the published v$tag"; exit 1
  fi
done
echo "PASS VERSION $VERSION is new and higher than every published version"
