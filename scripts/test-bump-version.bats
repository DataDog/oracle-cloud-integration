#!/usr/bin/env bats

BUMP="$(cd "$(dirname "$BATS_TEST_FILENAME")" && pwd)/bump-version.sh"

setup() {
  TMP_DIR="$(mktemp -d)"
  mkdir -p "$TMP_DIR/datadog-terraform-onboarding"
}

teardown() {
  rm -rf "$TMP_DIR"
}

make_tree() {
  printf '%s\n' "$1" > "$TMP_DIR/VERSION"
  printf '%s\n' "$2" > "$TMP_DIR/datadog-terraform-onboarding/VERSION"
}

run_bump() {
  run env \
    BASE_VERSION_OVERRIDE="$1" \
    BASE_TF_VERSION_OVERRIDE="$2" \
    WORK_DIR="$TMP_DIR" \
    DRY_RUN=true \
    bash "$BUMP"
}

field() { printf '%s\n' "$output" | grep "^${1}=" | cut -d= -f2; }

# ── tests ────────────────────────────────────────────────────────────────────

@test "neither file bumped: auto patch increment applied to both" {
  make_tree "1.5.2" "1.5.2"
  run_bump  "1.5.2" "1.5.2"
  [ "$status" -eq 0 ]
  [ "$(field bumped_version)" = "1.5.3" ]
  [ "$(field bump_root)"      = "true"  ]
  [ "$(field bump_tf)"        = "true"  ]
  [ "$(field skip)"           = "false" ]
}

@test "root manually bumped to major: TF synced to root version" {
  make_tree "2.0.0" "1.5.2"
  run_bump  "1.5.2" "1.5.2"
  [ "$status" -eq 0 ]
  [ "$(field bumped_version)" = "2.0.0"  ]
  [ "$(field bump_root)"      = "false"  ]
  [ "$(field bump_tf)"        = "true"   ]
  [ "$(field skip)"           = "false"  ]
}

@test "TF manually bumped to minor: root synced to TF version" {
  make_tree "1.5.2" "1.6.0"
  run_bump  "1.5.2" "1.5.2"
  [ "$status" -eq 0 ]
  [ "$(field bumped_version)" = "1.6.0"  ]
  [ "$(field bump_root)"      = "true"   ]
  [ "$(field bump_tf)"        = "false"  ]
  [ "$(field skip)"           = "false"  ]
}

@test "both files already at same manually-bumped version: skip" {
  make_tree "2.0.0" "2.0.0"
  run_bump  "1.5.2" "1.5.2"
  [ "$status" -eq 0 ]
  [ "$(field skip)"      = "true"  ]
  [ "$(field bump_root)" = "false" ]
  [ "$(field bump_tf)"   = "false" ]
}

@test "both files already at auto-bumped version: skip" {
  make_tree "1.5.3" "1.5.3"
  run_bump  "1.5.2" "1.5.2"
  [ "$status" -eq 0 ]
  [ "$(field skip)" = "true" ]
}

@test "both files manually bumped to different versions: root wins" {
  make_tree "2.0.0" "1.9.0"
  run_bump  "1.5.2" "1.5.2"
  [ "$status" -eq 0 ]
  [ "$(field bumped_version)" = "2.0.0"  ]
  [ "$(field bump_root)"      = "false"  ]
  [ "$(field bump_tf)"        = "true"   ]
  [ "$(field skip)"           = "false"  ]
}

@test "TF bumped above its own base while root stays at base" {
  make_tree "1.2.0" "1.2.1"
  run_bump  "1.2.0" "1.2.0"
  [ "$status" -eq 0 ]
  [ "$(field bumped_version)" = "1.2.1"  ]
  [ "$(field bump_root)"      = "true"   ]
  [ "$(field bump_tf)"        = "false"  ]
}

@test "diverged base versions: script fails fast with a clear error" {
  make_tree "1.5.2" "1.5.5"
  run_bump  "1.5.2" "1.5.5"
  [ "$status" -ne 0 ]
  [[ "$output" == *"diverged"* ]]
}
