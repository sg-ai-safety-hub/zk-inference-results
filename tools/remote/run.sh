#!/bin/sh
# run.sh <host> <name> <cmd>
#
# Acquire the host lock, start <cmd> detached under `setsid nohup`, and exit.
# Never waits in a foreground ssh: a foreground ssh that times out kills the
# remote job.  On the host:
#   ~/runs/<name>.status   `running <utc time> pid <pid>`, then `done exit=<rc> <utc time>`
#   ~/runs/<name>.log      stdout and stderr of <cmd>; it stays on the host
# The lock is released by the job itself when <cmd> exits.
set -eu
HOST=${1:?host alias}; NAME=${2:?run name}; CMD=${3:?command}
HERE=$(cd "$(dirname "$0")" && pwd)
"$HERE/lock.sh" "$HOST" acquire "$NAME"
# The wrapper records the status, runs the command, records the exit code and
# frees the lock.  Single quotes around $CMD are the caller's responsibility.
ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs && setsid nohup sh -c '
  S=\$HOME/runs/$NAME.status
  echo \"running \$(date -u +%Y-%m-%dT%H:%M:%SZ) pid \$\$\" > \$S
  sh -c \"$CMD\"; rc=\$?
  echo \"done exit=\$rc \$(date -u +%Y-%m-%dT%H:%M:%SZ)\" >> \$S
  rm -f \$HOME/.zk-run.lock
' > ~/runs/$NAME.log 2>&1 < /dev/null &"
echo "run.sh: $NAME started on $HOST"
echo "poll:   ssh $HOST cat '~/runs/$NAME.status'"
echo "tail:   ssh $HOST tail -20 '~/runs/$NAME.log'"
