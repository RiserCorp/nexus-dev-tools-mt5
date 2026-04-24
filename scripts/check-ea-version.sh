#!/usr/bin/env bash
#
# check-ea-version.sh
# -------------------
# CI guard: ensures every changed `.mq5` file in this PR has a `#property
# version "X.Y[.Z]"` value STRICTLY GREATER than the one on the base branch.
#
# Why this matters
# ----------------
# MetaTrader 5 caches compiled `.ex5` artefacts based on `#property version`.
# A downgraded or unchanged version on a behavioural change leads to silent
# drift: users can keep running the previous binary, server-side telemetry
# and changelogs no longer match the deployed code, and bug reports become
# impossible to triangulate. Bumping is cheap, this script makes forgetting
# to bump a hard CI failure.
#
# Behaviour
# ---------
#   - Iterates over every `.mq5` file changed against the base ref
#     (env: BASE_REF, defaults to `origin/main`).
#   - Extracts `#property version "X.Y[.Z]"` from both versions of the file.
#   - Fails if the new version is missing, identical, or lower than the old.
#   - Skips deleted files.
#   - Skips Dev/Test files matched by the SKIP_PATTERN env var
#     (default: regex `Dev\.mq5$|Test\.mq5$`) — these are intentionally
#     excluded from CI in the canonical EA repo.
#
# Exit codes
#   0 — every changed `.mq5` has a strictly greater version (or none changed).
#   1 — at least one `.mq5` is missing the bump.
#   2 — usage / environment error (missing git, missing base ref, etc.).
#
# Requirements
#   bash 4+, git, sort -V (GNU coreutils — available on every GitHub runner).

set -euo pipefail

BASE_REF="${BASE_REF:-origin/main}"
SKIP_PATTERN="${SKIP_PATTERN:-Dev\.mq5$|Test\.mq5$}"

# Ensure we have a git directory (hard error rather than silent skip).
if ! git rev-parse --git-dir >/dev/null 2>&1; then
  echo "::error:: not inside a git working tree" >&2
  exit 2
fi

# Make sure the base ref is reachable. On GitHub Actions PR builds, only the
# PR head is fetched by default — we need an explicit fetch to compare against
# main. The workflow file does this once before invoking the script, but we
# fail loudly here if it didn't.
if ! git rev-parse --verify "$BASE_REF" >/dev/null 2>&1; then
  echo "::error:: base ref '$BASE_REF' not found — fetch it before running this script" >&2
  exit 2
fi

# Extract `#property version "X.Y[.Z]"` from a file's contents on stdin.
# Returns the captured value on stdout, or empty if the directive is absent.
# The regex tolerates both 2-segment ("1.07") and 3-segment ("1.1.1") forms,
# which both repos use today — uniformising is a separate decision.
extract_version() {
  grep -m1 -E '^#property[[:space:]]+version[[:space:]]+"[^"]+"' \
    | sed -E 's/^#property[[:space:]]+version[[:space:]]+"([^"]+)".*$/\1/' \
    || true
}

# Strict semver comparison via `sort -V`. `sort -V` happens to do the right
# thing on both 2- and 3-segment versions (1.07 < 1.08 < 1.1.0 < 1.1.1).
# Returns 0 when $1 > $2, 1 otherwise.
version_gt() {
  [ "$1" = "$2" ] && return 1
  [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | head -n1)" = "$2" ]
}

# Collect changed `.mq5` files between the base ref and HEAD. The diff is
# limited to status A (added), M (modified), R (renamed) — D (deleted) is
# ignored because there's nothing to version-check on a deletion.
mapfile -t changed < <(
  git diff --name-only --diff-filter=AMR "$BASE_REF"...HEAD -- '*.mq5'
)

if [ "${#changed[@]}" -eq 0 ]; then
  echo "No .mq5 files changed in this PR — nothing to check."
  exit 0
fi

failures=0
checked=0
skipped=0

for file in "${changed[@]}"; do
  if [[ "$file" =~ $SKIP_PATTERN ]]; then
    echo "→ $file: skipped (matches SKIP_PATTERN='$SKIP_PATTERN')"
    skipped=$((skipped + 1))
    continue
  fi

  # New version: from the working tree (HEAD).
  new_version="$(<"$file" extract_version)"

  # Old version: from BASE_REF. If the file is brand-new, `git show` exits
  # with non-zero — that's fine, we treat the old version as empty and the
  # check below reduces to "new version must be present".
  old_version="$(git show "$BASE_REF:$file" 2>/dev/null | extract_version || true)"

  if [ -z "$new_version" ]; then
    echo "::error file=$file::missing '#property version \"X.Y[.Z]\"' directive"
    failures=$((failures + 1))
    continue
  fi

  if [ -z "$old_version" ]; then
    echo "✓ $file: new file, version=$new_version"
    checked=$((checked + 1))
    continue
  fi

  if version_gt "$new_version" "$old_version"; then
    echo "✓ $file: $old_version → $new_version"
    checked=$((checked + 1))
  else
    echo "::error file=$file::version not bumped: '$old_version' (base) vs '$new_version' (head). Bump '#property version' before merging."
    failures=$((failures + 1))
  fi
done

echo
echo "Summary: checked=$checked skipped=$skipped failed=$failures"

exit $((failures > 0 ? 1 : 0))
