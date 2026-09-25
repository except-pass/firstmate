#!/usr/bin/env bash
# V6 inbox turn protocol on a temp home.
#
# Two request ids are two notes. Replaying the first id does not create a
# third note. One reply succeeds and a second reply on that note exits 1.
# receipts --after returns that first reply body matched by note id, and the
# next turn is a new request id. ready on a temp home with no watcher does
# not report can_receive true, including when a pane could exist. Exit 3
# (saved but not announced) stays distinct from exit 1 (nothing saved).
set -euo pipefail

# shellcheck source=tests/lib.sh
# shellcheck disable=SC1091
. "$(dirname "${BASH_SOURCE[0]}")/lib.sh"

unset FM_HOME FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_ROOT_OVERRIDE \
  FM_PROJECTS_OVERRIDE FM_CONFIG_OVERRIDE TMUX || true

[ "$ROOT" != "/Users/wtg/repo/firstmate" ] || fail "refusing the primary checkout"

TMP_ROOT=$(fm_test_tmproot fm-v6-inbox-turn)
case "$TMP_ROOT" in
  /Users/wtg/repo/firstmate|/Users/wtg/repo/firstmate/*)
    fail "suite temp root must not be the firstmate checkout" ;;
  /Users/wtg/.local/state/pm-build/tinstar-v6/firstmate-home|\
  /Users/wtg/.local/state/pm-build/tinstar-v6/firstmate-home/*)
    fail "suite temp root must not be the state-dir fixture" ;;
esac

INBOX_BIN="$ROOT/bin/fm-inbox.sh"

make_home() {
  local home="$TMP_ROOT/$1"
  mkdir -p "$home/state" "$home/data" "$home/config"
  printf '%s\n' "$home"
}

run_inbox() {
  local home=$1
  shift
  FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" FM_DATA_OVERRIDE="$home/data" \
    FM_CONFIG_OVERRIDE="$home/config" "$INBOX_BIN" "$@"
}

json_get() {
  python3 -c 'import json,sys
v=json.load(sys.stdin)
for k in sys.argv[1:]:
    if isinstance(v, list) and k.lstrip("-").isdigit():
        v=v[int(k)]
    else:
        v=v[k]
print(v)' "$@"
}

count_notes() {
  find "$1/state/inbox" -maxdepth 1 -name '*.note' 2>/dev/null | wc -l | tr -d ' '
}

count_replies() {
  find "$1/state/inbox/.replies" -maxdepth 1 -type f ! -name '.*' 2>/dev/null \
    | wc -l | tr -d ' '
}

# --- two turns, one replay, one reply, then a new request id ----------------

home=$(make_home turns)
first=$(run_inbox "$home" note --request-id req-turn-1 --json "turn-one-body") \
  || fail "first request id should create a note"
assert_equals "fm-inbox-note.v1" "$(printf '%s' "$first" | json_get schema)" \
  "note JSON uses the note schema"
assert_equals "created" "$(printf '%s' "$first" | json_get outcome)" \
  "first request id is created"
first_id=$(printf '%s' "$first" | json_get id)
second=$(run_inbox "$home" note --request-id req-turn-2 --json "turn-two-body") \
  || fail "second request id should create a second note"
assert_equals "created" "$(printf '%s' "$second" | json_get outcome)" \
  "second request id is created"
second_id=$(printf '%s' "$second" | json_get id)
[ "$first_id" != "$second_id" ] || fail "two request ids must be two note ids"
assert_equals "2" "$(count_notes "$home")" "two request ids write two notes"

replay=$(run_inbox "$home" note --request-id req-turn-1 --json "turn-one-body") \
  || fail "replaying the first request id should succeed"
assert_equals "replay" "$(printf '%s' "$replay" | json_get outcome)" \
  "repeating the first request id is a replay"
assert_equals "$first_id" "$(printf '%s' "$replay" | json_get id)" \
  "replay returns the original note id"
assert_equals "2" "$(count_notes "$home")" \
  "replay must not create a third note"

reply=$(run_inbox "$home" reply --json "$first_id" "reply-body-turn-1") \
  || fail "the first reply should succeed"
assert_equals "fm-inbox-reply.v1" "$(printf '%s' "$reply" | json_get schema)" \
  "reply JSON uses the reply schema"
assert_equals "created" "$(printf '%s' "$reply" | json_get outcome)" \
  "the first reply is created"
assert_equals "$first_id" "$(printf '%s' "$reply" | json_get id)" \
  "the reply is bound to the first note id"
assert_equals "1" "$(count_replies "$home")" "one reply file exists"

set +e
second_reply=$(run_inbox "$home" reply --json "$first_id" "reply-body-turn-1-again" 2>&1)
second_reply_code=$?
set -e
expect_code 1 "$second_reply_code" "a second reply on the same note exits 1"
assert_contains "$second_reply" "already recorded" \
  "the second reply names the existing record"
assert_equals "1" "$(count_replies "$home")" \
  "the refused second reply does not write another reply"

receipts=$(run_inbox "$home" receipts --after 000000000000) \
  || fail "receipts --after a cursor before the first reply should succeed"
assert_equals "fm-inbox-receipts.v1" "$(printf '%s' "$receipts" | json_get schema)" \
  "receipts JSON uses the receipts schema"
matched=$(printf '%s' "$receipts" | python3 -c 'import json,sys
doc=json.load(sys.stdin)
want=sys.argv[1]
hits=[r for r in doc["replies"] if r["id"]==want]
print(len(hits))
if hits:
    print(hits[0]["body"])
    print(hits[0]["cursor"])
' "$first_id")
assert_equals "1" "$(printf '%s\n' "$matched" | sed -n '1p')" \
  "receipts --after returns one reply for the first note id"
assert_equals "reply-body-turn-1" "$(printf '%s\n' "$matched" | sed -n '2p')" \
  "that reply body is the first reply"
first_cursor=$(printf '%s\n' "$matched" | sed -n '3p')
note_reply=$(printf '%s' "$receipts" | python3 -c 'import json,sys
doc=json.load(sys.stdin)
want=sys.argv[1]
rows=[n for n in doc["pending"] if n["id"]==want]
print(rows[0]["body"] if rows else "")
print(rows[0]["reply"]["body"] if rows and rows[0].get("reply") else "")
print(rows[0]["request_id"] if rows else "")
' "$first_id")
assert_equals "turn-one-body" "$(printf '%s\n' "$note_reply" | sed -n '1p')" \
  "the pending note still carries the first turn body"
assert_equals "reply-body-turn-1" "$(printf '%s\n' "$note_reply" | sed -n '2p')" \
  "the pending note reply matches the first note id"
assert_equals "req-turn-1" "$(printf '%s\n' "$note_reply" | sed -n '3p')" \
  "the pending note keeps the first request id"

after_own=$(run_inbox "$home" receipts --after "$first_cursor") \
  || fail "receipts --after the first reply cursor should succeed"
assert_equals "0" "$(printf '%s' "$after_own" | python3 -c 'import json,sys; print(len(json.load(sys.stdin)["replies"]))')" \
  "a cursor on the first reply does not return that reply again"

third=$(run_inbox "$home" note --request-id req-turn-3 --json "turn-three-body") \
  || fail "the next turn should use a new request id"
assert_equals "created" "$(printf '%s' "$third" | json_get outcome)" \
  "a new request id is created"
third_id=$(printf '%s' "$third" | json_get id)
[ "$third_id" != "$first_id" ] && [ "$third_id" != "$second_id" ] \
  || fail "the next turn must be a new note"
assert_equals "3" "$(count_notes "$home")" "the next turn writes a third note"
assert_equals "1" "$(count_replies "$home")" \
  "the next turn does not add a reply"
pass "two request ids, one replay, one reply, and a new turn stay correlated"

# --- ready does not treat a possible pane as receivable ---------------------

home=$(make_home ready-empty)
fakebin=$(fm_fakebin "$home")
cat > "$fakebin/tmux" <<'SH'
#!/usr/bin/env bash
echo "ready consulted tmux" >&2
exit 97
SH
chmod +x "$fakebin/tmux"
ready=$(PATH="$fakebin:$PATH" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
  FM_DATA_OVERRIDE="$home/data" FM_CONFIG_OVERRIDE="$home/config" \
  "$INBOX_BIN" ready) || fail "ready should succeed on an empty temp home"
assert_equals "fm-primary-ready.v1" "$(printf '%s' "$ready" | json_get schema)" \
  "ready uses the readiness schema"
can=$(printf '%s' "$ready" | json_get can_receive)
[ "$can" != "True" ] || fail "an empty temp home must not report can_receive true"
assert_equals "False" "$can" "a free lock with no watcher is not receivable"

fm_write_meta "$home/state/pane-worker.meta" \
  "window=v6fix:fm-pane-worker" \
  "worktree=$home/projects/pane-worker" \
  "project=alpha" \
  "harness=grok" \
  "kind=ship" \
  "mode=ship" \
  "spawn_gen=1"
mkdir -p "$home/projects/pane-worker"
ready_pane=$(PATH="$fakebin:$PATH" FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
  FM_DATA_OVERRIDE="$home/data" FM_CONFIG_OVERRIDE="$home/config" \
  "$INBOX_BIN" ready) || fail "ready should succeed when a pane could exist"
can_pane=$(printf '%s' "$ready_pane" | json_get can_receive)
[ "$can_pane" != "True" ] || fail "a possible pane must not make can_receive true"
assert_equals "False" "$can_pane" \
  "ready stays not receivable without a held lock and a healthy wake consumer"
pass "ready does not report can_receive true from an empty home or a pane"

# --- exit 3 is saved-but-unannounced; exit 1 saves nothing ------------------

isolated="$TMP_ROOT/isolated"
mkdir -p "$isolated/bin"
cp "$INBOX_BIN" "$isolated/bin/fm-inbox.sh"
chmod +x "$isolated/bin/fm-inbox.sh"
home=$(make_home exit-3)
set +e
saved_out=$(FM_HOME="$home" FM_STATE_OVERRIDE="$home/state" \
  FM_DATA_OVERRIDE="$home/data" FM_CONFIG_OVERRIDE="$home/config" \
  "$isolated/bin/fm-inbox.sh" note --request-id saved-1 --json "kept" 2>/dev/null)
saved_code=$?
set -e
expect_code 3 "$saved_code" "a saved-but-unannounced note exits 3"
assert_equals "created" "$(printf '%s' "$saved_out" | json_get outcome)" \
  "exit 3 still created the note"
assert_equals "True" "$(printf '%s' "$saved_out" | json_get saved)" \
  "exit 3 saved the note"
assert_equals "False" "$(printf '%s' "$saved_out" | json_get announced)" \
  "exit 3 did not announce the note"
assert_equals "1" "$(count_notes "$home")" "exit 3 leaves the note on disk"

home=$(make_home exit-1)
set +e
empty_out=$(run_inbox "$home" note --request-id empty-1 --json "   " 2>&1)
empty_code=$?
set -e
expect_code 1 "$empty_code" "a note that saves nothing exits 1"
assert_contains "$empty_out" "empty" "the exit 1 refusal says the note was empty"
assert_equals "0" "$(count_notes "$home")" "exit 1 does not leave a note"
assert_absent "$home/state/inbox/.requests/empty-1" \
  "exit 1 does not reserve the request id"
pass "exit 3 and exit 1 stay distinguishable"
