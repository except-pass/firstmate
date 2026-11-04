#!/bin/bash
export FM_HOME="$PWD/.w/h" FM_SPAWN_NO_GUARD=1
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
mkdir -p "$FM_HOME/data/restart"
cp "$FM_HOME/data/linked/brief.md" "$FM_HOME/data/restart/brief.md"
bin/fm-spawn.sh restart "$PWD/.w/project" --scout --work-item 'card:keep-me' 'sleep 1'
sleep 2
bin/fm-spawn.sh restart --relaunch --harness 'sleep 60'
printf 'relaunch_rc=%s\n' "$?"
for value in '' $'bad\nwindow=evil' $'bad\tcard'; do
 bin/fm-spawn.sh reject "$PWD/.w/project" --scout --work-item "$value" 'sleep 1'
 printf 'refusal_rc=%s record_exists=' "$?"; test -f "$FM_HOME/state/reject.meta" && echo yes || echo no
done
bin/fm-spawn.sh linked --relaunch --work-item card:override
printf 'override_rc=%s\n' "$?"
bin/fm-fleet-snapshot.sh --json > .w/snapshot-after.json
touch .w/more-finished
