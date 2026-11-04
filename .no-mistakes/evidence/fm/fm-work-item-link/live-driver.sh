#!/bin/bash
ROOT=$PWD
export FM_HOME="$ROOT/.w/h"
export FM_SPAWN_NO_GUARD=1
unset FM_ROOT_OVERRIDE FM_STATE_OVERRIDE FM_DATA_OVERRIDE FM_CONFIG_OVERRIDE FM_PROJECTS_OVERRIDE
for id in linked plain scout; do
 mkdir -p "$FM_HOME/data/$id"
 printf '# Task\n## Captain\x27s intent\nExercise work item recording.\n\n## Firstmate spec\nWait without changing files.\n' > "$FM_HOME/data/$id/brief.md"
done
bin/fm-spawn.sh linked "$ROOT/.w/project" --mode local-only --yolo off --work-item 'https://example.invalid/card/42?q=a=b&label=hello world' 'sleep 300'
bin/fm-spawn.sh plain "$ROOT/.w/project" --mode local-only --yolo off 'sleep 300'
bin/fm-spawn.sh scout "$ROOT/.w/project" --scout --work-item 'notion:opaque-card-42' 'sleep 300'
bin/fm-fleet-snapshot.sh --json > "$ROOT/.w/snapshot.json"
touch "$ROOT/.w/finished"
sleep 300
