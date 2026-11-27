#!/bin/bash
# Guards the release-version rules. VERSION is the single source of truth.
#
#   tools/check-version.sh [commit]             ordinary check, used by CI on
#                                               every pull request and push
#   tools/check-version.sh --release [commit]   strict check, used when a
#                                               release is tagged and published
#
# Both modes: VERSION must be a semantic version, and must not be lower than
# any published version. Versions are ordered as semantic versions, including
# the pre-release part: 0.2.0-preview.2 < 0.2.0-preview.10 < 0.2.0 < 0.2.1.
#
# Ordinary mode also accepts a VERSION that is already published. Changes that
# do not publish anything (documentation, fixes waiting for the next release)
# must be able to pass CI; the output says the version has to be raised before
# the next release.
#
# Release mode is strict: the tag v<VERSION> must either not exist yet, in
# which case VERSION must be higher than every published version, or it must
# point at exactly the commit being released. New content can therefore never
# be published under an existing version.
#
# The published versions are the v* tags of the remote. For tests, set
# BADDEL_TAGS_FILE to a file in `git ls-remote --tags` format instead.
set -euo pipefail
cd "$(dirname "$0")/.."
MODE=ci
if [ "${1:-}" = "--release" ]; then MODE=release; shift; fi
VERSION=$(tr -d '[:space:]' < "${BADDEL_VERSION_FILE:-VERSION}")
COMMIT=$(git rev-parse "${1:-HEAD}")
if [ -n "${BADDEL_TAGS_FILE:-}" ]; then
  TAGS=$(cat "$BADDEL_TAGS_FILE")
else
  TAGS=$(git ls-remote --tags "${BADDEL_REMOTE:-origin}" 'refs/tags/v*')
fi

MODE="$MODE" VERSION="$VERSION" COMMIT="$COMMIT" TAGS="$TAGS" python3 - <<'PY'
import os, re, sys

SEMVER = re.compile(r'^(\d+)\.(\d+)\.(\d+)(?:-([0-9A-Za-z-]+(?:\.[0-9A-Za-z-]+)*))?$')

def key(text):
    """Sort key implementing semantic-version precedence."""
    match = SEMVER.match(text)
    if not match:
        return None
    core = tuple(int(part) for part in match.group(1, 2, 3))
    if match.group(4) is None:
        # A release sorts after every pre-release of the same core.
        return (core, 1, ())
    identifiers = tuple(
        (0, int(part), '') if part.isdigit() else (1, 0, part)   # numeric before alphanumeric
        for part in match.group(4).split('.'))
    return (core, 0, identifiers)

mode, version, commit = os.environ['MODE'], os.environ['VERSION'], os.environ['COMMIT']
mine = key(version)
if mine is None:
    sys.exit(f"FAIL VERSION '{version}' is not MAJOR.MINOR.PATCH[-prerelease]")

# tag -> commit; an annotated tag's commit is on its peeled "^{}" line.
published = {}
for line in os.environ['TAGS'].splitlines():
    parts = line.split()
    if len(parts) != 2 or not parts[1].startswith('refs/tags/v'):
        continue
    name = parts[1][len('refs/tags/v'):]
    peeled = name.endswith('^{}')
    name = name[:-3] if peeled else name
    if key(name) is None:
        continue
    if peeled or name not in published:
        published[name] = parts[0]

lower = sorted((name for name in published if key(name) > mine), key=key)
if lower:
    sys.exit(f"FAIL VERSION {version} is lower than the published v{lower[-1]}")

same = [name for name in published if key(name) == mine]
if same:
    if published[same[0]] == commit:
        print(f"PASS v{version} is published from this exact commit")
    elif mode == 'release':
        sys.exit(f"FAIL v{version} is already published from {published[same[0]][:7]}; this is {commit[:7]}. "
                 "Increase VERSION before releasing.")
    else:
        print(f"PASS VERSION {version} is not lower than any published version")
        print(f"NOTE v{version} is already published. Increase VERSION before the next release.")
else:
    print(f"PASS VERSION {version} is new and higher than every published version")
PY
