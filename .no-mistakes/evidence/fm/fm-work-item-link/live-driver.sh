#!/usr/bin/env bash
set -eu
ROOT=$PWD
E=/home/farm/.no-mistakes/evidence/01M6K5KES5A58R7V98DKQ40SW9
BOX=$(mktemp -d /tmp/fm-lab.XXXXXX)
LAB="$BOX/home"
cleanup() { TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab kill-server 2>/dev/null || true; chmod -R u+w "$BOX"; rm -rf "$BOX"; }
trap cleanup EXIT
bin/fm-lab-home.sh create "$LAB"
mkdir -p "$LAB/tmux" "$ROOT/.live-work-item/codex"
export FM_HOME="$LAB" TMUX_TMPDIR="$LAB/tmux" CODEX_HOME="$ROOT/.live-work-item/codex"
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
printf 'manual\n' > "$LAB/config/backlog-backend"
printf 'codex\n' > "$LAB/config/crew-harness"
touch "$LAB/state/.last-watcher-beat"
P="$ROOT/.live-work-item/project"
printf 'max_trees = 4\nroot = "%s"\n' "$ROOT/.live-work-item" > "$P/treehouse.toml"
printf 'disposable\n' > "$P/README.md"
git -C "$P" add .
git -C "$P" -c user.name=Test -c user.email=test@example.com commit --allow-empty -qm initial
TMUX_TMPDIR="$LAB/tmux" tmux -L fm-lab new-session -d -s fm-lab-work-item -x 120 -y 40 -c "$ROOT"
export TMUX="$LAB/tmux/tmux-$(id -u)/fm-lab,$(tmux -L fm-lab display-message -p '#{pid}'),0"
for id in live-ship live-scout live-plain live-sm; do
 mkdir -p "$LAB/data/$id"
 printf '# Task\n## Captain\x27s intent\nExercise optional work item recording.\n\n## Firstmate spec\nWait for instructions. Do not modify anything.\n' > "$LAB/data/$id/brief.md"
done
run() { printf '\nCOMMAND: fm-spawn.sh'; printf ' %q' "$@"; printf '\n'; bash bin/fm-spawn.sh "$@"; }
run live-ship "$P" --mode local-only --yolo off --work-item 'https://example.com/card?a=42&title="雪"'
run live-scout "$P" --scout --work-item card-scout-42
run live-plain "$P" --mode local-only --yolo off
FM_SNAPSHOT_CREW_STATE_TIMEOUT=2 bash bin/fm-fleet-snapshot.sh --json > "$E/live-snapshot.json"
cat "$E/live-snapshot.json"
for id in live-ship live-scout live-plain; do
 T=$(sed -n 's/^window=//p' "$LAB/state/$id.meta")
 tmux -L fm-lab capture-pane -p -t "$T" > "$E/$id-pane.txt"
 cp "$LAB/state/$id.meta" "$E/$id-meta.txt"
done
# Stop only the disposable worker process, retaining its real endpoint for relaunch.
T=$(sed -n 's/^window=//p' "$LAB/state/live-ship.meta")
WT=$(sed -n 's/^worktree=//p' "$LAB/state/live-ship.meta")
tmux -L fm-lab respawn-pane -k -t "$T" -c "$WT" bash
run live-ship --relaunch
cp "$LAB/state/live-ship.meta" "$E/relaunch-meta.txt"
SM="$BOX/secondmate-home"
mkdir -p "$SM/bin" "$SM/data"
printf '# Firstmate\n' > "$SM/AGENTS.md"
printf 'live-sm\n' > "$SM/.fm-secondmate-home"
printf 'Wait for instructions. Do not change anything.\n' > "$SM/data/charter.md"
printf 'state/\ndata/\nconfig/\nprojects/\n.no-mistakes/\n' > "$SM/.gitignore"
git -C "$SM" init -q -b main
run live-sm "$SM" --secondmate --work-item sm-card-42
cp "$LAB/state/live-sm.meta" "$E/secondmate-meta.txt"
FM_SNAPSHOT_CREW_STATE_TIMEOUT=2 bash bin/fm-fleet-snapshot.sh --json > "$E/final-snapshot.json"
for bad in '' $'card\ninjected=yes' $'card\tid'; do
 if run invalid-id "$P" --scout --work-item "$bad"; then exit 11; fi
 test ! -f "$LAB/state/invalid-id.meta"
done
if run live-ship --relaunch --work-item replacement; then exit 12; fi
jq -e '.tasks | any(.id=="live-sm" and .work_item=="sm-card-42")' "$E/final-snapshot.json"
