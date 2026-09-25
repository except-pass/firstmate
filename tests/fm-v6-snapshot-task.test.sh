#!/usr/bin/env bash
# V6 read-only fleet snapshot --task on a temp home.
#
# --task <id> --json prints one existing worker object, including id,
# spawn_gen, project, backend, paths.worktree, and endpoint.target.
# A missing id is a structured not-found and does not create metadata.
# --task does not refresh state/secondmate-summary-cache and does not take
# the session lock. Default --json stays schema fm-fleet-snapshot.v1.
# Pre-existing meta is the worker list. Ledger rows do not add, remove, or
# complete a worker.
set -euo pipefail

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

unset FM_HOME FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_ROOT_OVERRIDE \
  FM_PROJECTS_OVERRIDE FM_CONFIG_OVERRIDE TMUX || true

[ "$ROOT" != "/Users/wtg/repo/firstmate" ] || fail "refusing the primary checkout"
command -v jq >/dev/null 2>&1 || fail "jq is required"

TMP_ROOT=$(fm_test_tmproot fm-v6-snapshot-task)
case "$TMP_ROOT" in
  /Users/wtg/repo/firstmate|/Users/wtg/repo/firstmate/*)
    fail "suite temp root must not be the firstmate checkout" ;;
  /Users/wtg/.local/state/pm-build/tinstar-v6/firstmate-home|\
  /Users/wtg/.local/state/pm-build/tinstar-v6/firstmate-home/*)
    fail "suite temp root must not be the state-dir fixture" ;;
esac

SNAPSHOT="$ROOT/bin/fm-fleet-snapshot.sh"
FAKEBIN="$TMP_ROOT/fakebin"
TMUX_LOG="$TMP_ROOT/tmux.log"
mkdir -p "$FAKEBIN"
: > "$TMUX_LOG"

cat > "$FAKEBIN/tmux" <<'SH'
#!/usr/bin/env bash
set -u
printf '%s\n' "$*" >> "${TMUX_LOG:?}"
for arg in "$@"; do
  case "$arg" in
    firstmate|firstmate:*|serena-view|serena-view:*|kd-live|kd-live:*|tinstar-v6-build|tinstar-v6-build:*)
      printf 'refusing live session target: %s\n' "$arg" >&2
      exit 97
      ;;
  esac
done
if [ "${1:-}" = "display-message" ]; then
  printf '%%1\n'
fi
exit 0
SH

cat > "$FAKEBIN/fm-spawn.sh" <<'SH'
#!/usr/bin/env bash
printf 'snapshot must not spawn\n' >&2
exit 97
SH
cat > "$FAKEBIN/fm-send.sh" <<'SH'
#!/usr/bin/env bash
printf 'snapshot must not send\n' >&2
exit 97
SH
cat > "$FAKEBIN/fm-control.sh" <<'SH'
#!/usr/bin/env bash
printf 'snapshot must not control\n' >&2
exit 97
SH
cat > "$FAKEBIN/fm-teardown.sh" <<'SH'
#!/usr/bin/env bash
printf 'snapshot must not tear down\n' >&2
exit 97
SH
cat > "$FAKEBIN/no-mistakes" <<'SH'
#!/usr/bin/env bash
exit 0
SH
chmod +x "$FAKEBIN/tmux" "$FAKEBIN/fm-spawn.sh" "$FAKEBIN/fm-send.sh" \
  "$FAKEBIN/fm-control.sh" "$FAKEBIN/fm-teardown.sh" "$FAKEBIN/no-mistakes"

make_home() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/state" "$home/data" "$home/config" "$home/projects"
  printf '%s\n' "$home"
}

run_snap() {
  local home=$1
  shift
  PATH="$FAKEBIN:$PATH" \
    FM_HOME="$home" \
    FM_STATE_OVERRIDE="$home/state" \
    FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" \
    FM_PROJECTS_OVERRIDE="$home/projects" \
    FM_SNAPSHOT_NOW=2026-09-24T12:00:00Z \
    FM_SNAPSHOT_NOW_EPOCH=1758715200 \
    TMUX_LOG="$TMUX_LOG" \
    "$SNAPSHOT" "$@"
}

home_manifest() {
  local root=$1 rel
  (
    cd "$root" || exit 1
    find . -print | LC_ALL=C sort | while IFS= read -r rel; do
      if [ -f "$rel" ]; then
        cksum "$rel"
      else
        printf 'dir %s\n' "$rel"
      fi
    done
  )
}

write_worker() {  # <home> <id> <spawn_gen> <project> <window>
  local home=$1 id=$2 spawn_gen=$3 project=$4 window=$5 worktree busy_gen
  worktree="$home/projects/$id"
  mkdir -p "$worktree"
  fm_write_meta "$home/state/$id.meta" \
    "window=$window" \
    "worktree=$worktree" \
    "project=$project" \
    "harness=claude" \
    "kind=ship" \
    "mode=ship" \
    "yolo=off" \
    "backend=tmux" \
    "spawn_gen=$spawn_gen"
  printf 'working: still on the brief\n' > "$home/state/$id.status"
  busy_gen=$("$ROOT/bin/fm-busy-event.sh" arm "$home/state" "$id")
  "$ROOT/bin/fm-busy-event.sh" apply "$home/state" "$id" busy --gen "$busy_gen" \
    --source claude-hook --event user-prompt-submit
}

# --- one existing worker, from meta that was already on disk ----------------

home=$(make_home workers)
write_worker "$home" worker-a 4 alpha "v6fix:fm-worker-a"
write_worker "$home" worker-b 9 beta "v6fix:fm-worker-b"
printf '999999\n' > "$home/state/.lock"
printf 'sentinel-session\n' > "$home/state/.lock-session"
: > "$home/config/fleet-ledger"
cat > "$home/state/fleet-ledger.jsonl" <<'EOF'
{"v":1,"ts":1,"event":"task.cleaned_up","task":"worker-a"}
{"v":1,"ts":2,"event":"task.dispatched","task":"worker-a","kind":"ship","project":"alpha","harness":"grok","model":null}
{"v":1,"ts":2,"event":"task.dispatched","task":"worker-a","kind":"ship","project":"alpha","harness":"grok","model":null}
{"v":1,"ts":3,"event":"task.status","task":"worker-a","state":"done","key":null,"text":" false completion"}
{"v":1,"ts":4,"event":"task.dispatched","task":"worker-ghost","kind":"ship","project":"alpha","harness":"grok","model":null}
{"v":1,"ts":5,"event":"task.status","task":"worker-ghost","state":"done","key":null,"text":" false healthy"}
{"v":1,"ts":6,"event":"task.merged","task":"worker-ghost","via":"local"}
EOF

before=$(home_manifest "$home")
one=$(run_snap "$home" --task worker-a --json) || fail "--task worker-a should succeed"
after=$(home_manifest "$home")
assert_equals "$before" "$after" "--task must not write the temp home"
assert_absent "$home/state/secondmate-summary-cache" \
  "--task must not create the summary cache"
printf '%s' "$one" | jq -e '
  type == "object"
    and (has("tasks") | not)
    and (has("schema") | not)
    and (has("backlog") | not)
    and .id == "worker-a"
    and .spawn_gen == "4"
    and .project == "alpha"
    and .backend == "tmux"
    and (.paths.worktree.path | type) == "string"
    and .paths.worktree.present == true
    and .endpoint.target == "v6fix:fm-worker-a"
    and .endpoint.exists == true
    and .current_state.state == "working"
' >/dev/null || fail "worker-a task object is missing descriptor fields: $one"
worktree_path=$(printf '%s' "$one" | jq -r '.paths.worktree.path')
assert_equals "$home/projects/worker-a" "$worktree_path" \
  "paths.worktree is the pre-existing worktree"

# Cache that already exists is not refreshed.
mkdir -p "$home/state/secondmate-summary-cache"
printf 'sentinel\n' > "$home/state/secondmate-summary-cache/sentinel.json"
chmod 700 "$home/state/secondmate-summary-cache"
cache_before=$(cksum "$home/state/secondmate-summary-cache/sentinel.json")
lock_before=$(cksum "$home/state/.lock" "$home/state/.lock-session")
run_snap "$home" --json --task worker-b >/dev/null || fail "--task worker-b should succeed"
cache_after=$(cksum "$home/state/secondmate-summary-cache/sentinel.json")
lock_after=$(cksum "$home/state/.lock" "$home/state/.lock-session")
assert_equals "$cache_before" "$cache_after" "--task must not refresh the summary cache"
assert_equals "$lock_before" "$lock_after" "--task must not take the session lock"
assert_equals "sentinel-session" "$(cat "$home/state/.lock-session")" \
  "session lock sidecar stays untouched"

# Missing id is not an empty fleet document and creates no meta.
set +e
missing=$(run_snap "$home" --task worker-missing --json 2>"$TMP_ROOT/missing.err")
missing_code=$?
set -e
expect_code 1 "$missing_code" "a missing task exits 1"
printf '%s' "$missing" | jq -e '
  .schema == "fm-fleet-snapshot-task.v1"
    and .found == false
    and .id == "worker-missing"
    and .reason == "not-found"
    and (has("tasks") | not)
    and .schema != "fm-fleet-snapshot.v1"
' >/dev/null || fail "missing id must be a structured not-found: $missing"
assert_absent "$home/state/worker-missing.meta" "not-found must not create metadata"
assert_absent "$home/state/worker-ghost.meta" "a ledger-only id is not a worker"

# A symlink is not a worker record and is not followed.
ln -s worker-a.meta "$home/state/alias.meta"
set +e
alias_out=$(run_snap "$home" --task alias --json 2>"$TMP_ROOT/alias.err")
alias_code=$?
set -e
expect_code 1 "$alias_code" "a symlink meta is not a task record"
printf '%s' "$alias_out" | jq -e '.found == false and .reason == "not-found"' >/dev/null \
  || fail "symlink id must be not-found: $alias_out"
rm -f "$home/state/alias.meta"

set +e
bad_out=$(run_snap "$home" --task '../worker-a' --json 2>"$TMP_ROOT/bad.err")
bad_code=$?
set -e
expect_code 2 "$bad_code" "a path-like task id is refused"
[ -z "$bad_out" ] || fail "an invalid task id must not print a snapshot: $bad_out"
assert_absent "$TMP_ROOT/worker-a.meta" "an invalid id must not create metadata"

# Default --json keeps the fleet document. The ledger is not the worker list.
fleet=$(run_snap "$home" --json) || fail "default --json should succeed"
printf '%s' "$fleet" | jq -e --argjson keys '["backlog","contributions","fm_home","generated","main_inventory","roots","schema","scout_reports","secondmate_current","secondmate_guidance","secondmate_landed","tasks"]' '
  (. | keys) == $keys and .schema == "fm-fleet-snapshot.v1"
' >/dev/null || fail "default --json shape changed: $fleet"
ids=$(printf '%s' "$fleet" | jq -r '.tasks | map(.id) | join(",")')
assert_equals "worker-a,worker-b" "$ids" \
  "workers come from meta, once each, and not from the ledger"
printf '%s' "$fleet" | jq -e '
  .tasks[] | select(.id == "worker-a") | .current_state.state == "working"
' >/dev/null || fail "a ledger done row must not complete the worker"
printf '%s\n' "$one" > "$TMP_ROOT/one.json"
printf '%s\n' "$fleet" > "$TMP_ROOT/fleet.json"
jq -n -e --slurpfile task "$TMP_ROOT/one.json" --slurpfile fleet "$TMP_ROOT/fleet.json" '
  ($fleet[0].tasks[] | select(.id == "worker-a") | del(.backlog)) as $row
  | $task[0] == $row
' >/dev/null || fail "--task object must be the fleet task without the backlog join"

help_out=$("$SNAPSHOT" --help) || fail "--help should succeed"
assert_contains "$help_out" "--task" "help documents --task"
pass "one task object, not-found, unchanged fleet document, ledger is not the list"
