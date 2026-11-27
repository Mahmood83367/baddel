#!/bin/bash
# Tests tools/check-version.sh against made-up sets of published tags.
set -u
cd "$(dirname "$0")/.."
WORK=$(mktemp -d); trap 'rm -rf "$WORK"' EXIT
HEAD_SHA=$(git rev-parse HEAD)
OTHER=1111111111111111111111111111111111111111
failures=0

# name  mode(ci|release)  VERSION  expected(pass|fail)  tag=commit ...
check() {
  local name=$1 mode=$2 version=$3 expected=$4; shift 4
  : > "$WORK/tags"
  for entry in "$@"; do printf '%s\trefs/tags/v%s\n' "${entry#*=}" "${entry%%=*}" >> "$WORK/tags"; done
  echo "$version" > "$WORK/VERSION"
  local flag=""; [ "$mode" = "release" ] && flag="--release"
  local out status actual=pass
  out=$(BADDEL_TAGS_FILE="$WORK/tags" BADDEL_VERSION_FILE="$WORK/VERSION" tools/check-version.sh $flag 2>&1)
  status=$?
  [ "$status" -ne 0 ] && actual=fail
  if [ "$actual" = "$expected" ]; then echo "ok   [$mode] $name"; else echo "FAIL [$mode] $name -> $out"; failures=$((failures + 1)); fi
}

for mode in ci release; do
  check "first version ever"                               $mode 0.1.0            pass
  check "higher minor"                                     $mode 0.2.0            pass 0.1.0=$OTHER
  check "lower than published"                             $mode 0.0.9            fail 0.1.0=$OTHER
  check "pre-release of an already released version"       $mode 0.1.0-rc.1       fail 0.1.0=$OTHER
  check "release after its own previews"                   $mode 0.2.0            pass 0.2.0-preview.1=$OTHER 0.2.0-preview.10=$OTHER
  check "preview.11 after preview.10"                      $mode 0.2.0-preview.11 pass 0.2.0-preview.2=$OTHER 0.2.0-preview.10=$OTHER
  check "DOWNGRADE preview.2 after preview.10"             $mode 0.2.0-preview.2  fail 0.2.0-preview.10=$OTHER
  check "DOWNGRADE preview.9 after preview.10"             $mode 0.2.0-preview.9  fail 0.2.0-preview.1=$OTHER 0.2.0-preview.10=$OTHER
  check "numeric identifiers sort before alphabetic"       $mode 0.2.0-1          fail 0.2.0-alpha=$OTHER
  check "alpha before beta"                                $mode 0.2.0-alpha      fail 0.2.0-beta=$OTHER
  check "beta after alpha"                                 $mode 0.2.0-beta       pass 0.2.0-alpha=$OTHER
  check "longer pre-release is higher"                     $mode 0.2.0-alpha.1    pass 0.2.0-alpha=$OTHER
  check "0.10.0 is higher than 0.9.0"                      $mode 0.10.0           pass 0.9.0=$OTHER
  check "0.9.0 is lower than 0.10.0"                       $mode 0.9.0            fail 0.10.0=$OTHER
  check "published from this exact commit"                 $mode 0.2.0            pass 0.1.0=$OTHER 0.2.0=$HEAD_SHA
  check "tags that are not versions are ignored"           $mode 0.2.0            pass nightly=$OTHER 0.1.0=$OTHER
  check "not a version"                                    $mode 0.2              fail
  check "leading v is not allowed in VERSION"              $mode v0.2.0           fail
done
# The one difference between the modes: a version already published elsewhere.
check "already published: ordinary CI still passes"        ci      0.1.0 pass 0.1.0=$OTHER
check "already published: a release is refused"            release 0.1.0 fail 0.1.0=$OTHER
check "already published preview: a release is refused"    release 0.2.0-preview.10 fail 0.2.0-preview.10=$OTHER

# An annotated tag lists its commit on the peeled line.
printf '%s\trefs/tags/v0.3.0\n%s\trefs/tags/v0.3.0^{}\n' 2222222222222222222222222222222222222222 "$HEAD_SHA" > "$WORK/tags"
echo "0.3.0" > "$WORK/VERSION"
if BADDEL_TAGS_FILE="$WORK/tags" BADDEL_VERSION_FILE="$WORK/VERSION" tools/check-version.sh --release >/dev/null 2>&1; then
  echo "ok   [release] annotated tag on this commit"
else
  echo "FAIL [release] annotated tag on this commit"; failures=$((failures + 1))
fi

[ "$failures" -eq 0 ] && echo "All version-guard tests passed." || { echo "$failures test(s) failed."; exit 1; }
