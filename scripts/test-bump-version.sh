#!/usr/bin/env bash
# Test harness for scripts/bump-version.sh.
# Runs several scenarios against a temp directory; no GitHub API calls needed.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUMP="$SCRIPT_DIR/bump-version.sh"

pass=0
fail=0

# ── helpers ──────────────────────────────────────────────────────────────────

make_tree() {
  local dir="$1" root_ver="$2" tf_ver="$3"
  mkdir -p "$dir/datadog-terraform-onboarding"
  printf '%s\n' "$root_ver" > "$dir/VERSION"
  printf '%s\n' "$tf_ver"   > "$dir/datadog-terraform-onboarding/VERSION"
}

run_case() {
  local label="$1" dir="$2" base="$3" base_tf="$4"
  BASE_VERSION_OVERRIDE="$base" \
  BASE_TF_VERSION_OVERRIDE="$base_tf" \
  WORK_DIR="$dir" \
  DRY_RUN=true \
  bash "$BUMP"
}

assert_eq() {
  local label="$1" got="$2" want="$3"
  if [[ "$got" == "$want" ]]; then
    echo "  PASS  $label"
    ((pass++)) || true
  else
    echo "  FAIL  $label — got='$got' want='$want'"
    ((fail++)) || true
  fi
}

parse_output() {
  local output="$1" key="$2"
  echo "$output" | grep "^${key}=" | cut -d= -f2
}

# ── tests ─────────────────────────────────────────────────────────────────────

TMP=$(mktemp -d)
trap 'rm -rf "$TMP"' EXIT

# 1. Neither file bumped → auto patch increment applied to both
DIR="$TMP/case1"; make_tree "$DIR" "1.5.2" "1.5.2"
out=$(run_case "auto-bump" "$DIR" "1.5.2" "1.5.2")
echo "Case 1: neither file manually bumped"
assert_eq "bumped_version" "$(parse_output "$out" bumped_version)" "1.5.3"
assert_eq "bump_root"      "$(parse_output "$out" bump_root)"      "true"
assert_eq "bump_tf"        "$(parse_output "$out" bump_tf)"        "true"
assert_eq "skip"           "$(parse_output "$out" skip)"           "false"

# 2. Root manually bumped (major) → TF synced to root's version
DIR="$TMP/case2"; make_tree "$DIR" "2.0.0" "1.5.2"
out=$(run_case "root-manual" "$DIR" "1.5.2" "1.5.2")
echo "Case 2: root bumped to 2.0.0, TF at 1.5.2"
assert_eq "bumped_version" "$(parse_output "$out" bumped_version)" "2.0.0"
assert_eq "bump_root"      "$(parse_output "$out" bump_root)"      "false"
assert_eq "bump_tf"        "$(parse_output "$out" bump_tf)"        "true"
assert_eq "skip"           "$(parse_output "$out" skip)"           "false"

# 3. TF manually bumped (minor) → root synced to TF's version
DIR="$TMP/case3"; make_tree "$DIR" "1.5.2" "1.6.0"
out=$(run_case "tf-manual" "$DIR" "1.5.2" "1.5.2")
echo "Case 3: TF bumped to 1.6.0, root at 1.5.2"
assert_eq "bumped_version" "$(parse_output "$out" bumped_version)" "1.6.0"
assert_eq "bump_root"      "$(parse_output "$out" bump_root)"      "true"
assert_eq "bump_tf"        "$(parse_output "$out" bump_tf)"        "false"
assert_eq "skip"           "$(parse_output "$out" skip)"           "false"

# 4. Both files already at the same manually-bumped version → skip
DIR="$TMP/case4"; make_tree "$DIR" "2.0.0" "2.0.0"
out=$(run_case "both-already-bumped" "$DIR" "1.5.2" "1.5.2")
echo "Case 4: both files already at 2.0.0"
assert_eq "skip"           "$(parse_output "$out" skip)"           "true"
assert_eq "bump_root"      "$(parse_output "$out" bump_root)"      "false"
assert_eq "bump_tf"        "$(parse_output "$out" bump_tf)"        "false"

# 5. Both files already at auto-bumped version → skip
DIR="$TMP/case5"; make_tree "$DIR" "1.5.3" "1.5.3"
out=$(run_case "both-already-auto" "$DIR" "1.5.2" "1.5.2")
echo "Case 5: both files already at auto-bumped 1.5.3"
assert_eq "skip"           "$(parse_output "$out" skip)"           "true"

# 6. Root and TF at different manual bumps → root wins
DIR="$TMP/case6"; make_tree "$DIR" "2.0.0" "1.9.0"
out=$(run_case "both-manual-different" "$DIR" "1.5.2" "1.5.2")
echo "Case 6: root=2.0.0, TF=1.9.0 (both manually bumped, root wins)"
assert_eq "bumped_version" "$(parse_output "$out" bumped_version)" "2.0.0"
assert_eq "bump_root"      "$(parse_output "$out" bump_root)"      "false"
assert_eq "bump_tf"        "$(parse_output "$out" bump_tf)"        "true"
assert_eq "skip"           "$(parse_output "$out" skip)"           "false"

# 7. Root and TF have independent bases, only TF bumped
DIR="$TMP/case7"; make_tree "$DIR" "1.2.0" "1.2.1"
out=$(run_case "tf-bumped-own-base" "$DIR" "1.2.0" "1.2.0")
echo "Case 7: TF bumped to 1.2.1 (above its own base 1.2.0), root at base"
assert_eq "bumped_version" "$(parse_output "$out" bumped_version)" "1.2.1"
assert_eq "bump_root"      "$(parse_output "$out" bump_root)"      "true"
assert_eq "bump_tf"        "$(parse_output "$out" bump_tf)"        "false"

# ── summary ───────────────────────────────────────────────────────────────────
echo ""
echo "Results: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
