#!/usr/bin/env bash
# Computes the target version for both VERSION files and optionally writes them.
#
# Required env vars (workflow mode):
#   REPO, BASE_REF, GH_TOKEN
#
# Optional overrides (test / dry-run mode — skip the GitHub API):
#   BASE_VERSION_OVERRIDE     base version for ./VERSION
#   BASE_TF_VERSION_OVERRIDE  base version for datadog-terraform-onboarding/VERSION
#   WORK_DIR                  repo root to read/write VERSION files (default: .)
#   DRY_RUN                   if "true", print what would be written but don't write
#
# Outputs are written to $GITHUB_OUTPUT when set, otherwise printed to stdout.
set -euo pipefail

WORK_DIR="${WORK_DIR:-.}"
DRY_RUN="${DRY_RUN:-false}"

pr_version=$(tr -d '[:space:]' < "$WORK_DIR/VERSION")
pr_tf_version=$(tr -d '[:space:]' < "$WORK_DIR/datadog-terraform-onboarding/VERSION")

if [[ -n "${BASE_VERSION_OVERRIDE:-}" ]]; then
  base_version="$BASE_VERSION_OVERRIDE"
else
  base_version=$(gh api "repos/${REPO}/contents/VERSION?ref=${BASE_REF}" \
    --jq '.content' | base64 -d | tr -d '[:space:]')
fi

if [[ -n "${BASE_TF_VERSION_OVERRIDE:-}" ]]; then
  base_tf_version="$BASE_TF_VERSION_OVERRIDE"
else
  base_tf_version=$(gh api "repos/${REPO}/contents/datadog-terraform-onboarding/VERSION?ref=${BASE_REF}" \
    --jq '.content' | base64 -d | tr -d '[:space:]')
fi

semver_re='^[0-9]+\.[0-9]+\.[0-9]+$'
[[ "$base_version"    =~ $semver_re ]] || { echo "invalid base_version: '$base_version'" >&2; exit 1; }
[[ "$base_tf_version" =~ $semver_re ]] || { echo "invalid base_tf_version: '$base_tf_version'" >&2; exit 1; }
[[ "$base_version" == "$base_tf_version" ]] || { echo "base versions have diverged: root=$base_version tf=$base_tf_version — fix manually before merging" >&2; exit 1; }

IFS='.' read -r major minor patch <<< "$base_version"
auto_bumped_version="${major}.${minor}.$((patch + 1))"

version_int() { IFS='.' read -r M m p <<< "$1"; echo $((M * 1000000 + m * 1000 + p)); }
base_int=$(version_int "$base_version")
base_tf_int=$(version_int "$base_tf_version")

# Detect valid manual bumps (strictly above the respective base).
root_manually_bumped=false
tf_manually_bumped=false
[[ $(version_int "$pr_version")    -gt $base_int    ]] && root_manually_bumped=true
[[ $(version_int "$pr_tf_version") -gt $base_tf_int ]] && tf_manually_bumped=true

# If a developer manually bumped one file, propagate that version to both so
# they stay in sync. Root takes priority over TF when both differ.
if [[ "$root_manually_bumped" == "true" ]]; then
  target_version="$pr_version"
elif [[ "$tf_manually_bumped" == "true" ]]; then
  target_version="$pr_tf_version"
else
  target_version="$auto_bumped_version"
fi

# Only overwrite a file if it doesn't already match the target.
bump_root=false
bump_tf=false
[[ "$pr_version"    != "$target_version" ]] && bump_root=true
[[ "$pr_tf_version" != "$target_version" ]] && bump_tf=true

skip=false
if [[ "$bump_root" == "false" && "$bump_tf" == "false" ]]; then
  echo "Both VERSION files already at ${target_version} — skipping." >&2
  skip=true
fi

# Write VERSION files unless this is a dry run.
if [[ "$skip" == "false" && "$DRY_RUN" != "true" ]]; then
  [[ "$bump_root" == "true" ]] && printf '%s\n' "$target_version" > "$WORK_DIR/VERSION"
  [[ "$bump_tf"   == "true" ]] && printf '%s\n' "$target_version" > "$WORK_DIR/datadog-terraform-onboarding/VERSION"
fi

# Emit outputs.
emit() {
  local key="$1" val="$2"
  if [[ -n "${GITHUB_OUTPUT:-}" ]]; then
    echo "${key}=${val}" >> "$GITHUB_OUTPUT"
  else
    echo "${key}=${val}"
  fi
}

emit "base_version"   "$base_version"
emit "bumped_version" "$target_version"
emit "bump_root"      "$bump_root"
emit "bump_tf"        "$bump_tf"
emit "skip"           "$skip"
