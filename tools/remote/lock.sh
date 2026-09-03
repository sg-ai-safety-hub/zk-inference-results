#!/bin/sh
# lock.sh <host> acquire|release <name>
#
# One run per host at a time.  The lock is one file in the remote home,
# `~/.zk-run.lock`, holding the run name, the local user, the time and the host
# pid of the job when there is one.  `acquire` refuses if the file exists and
# prints who holds it; `release` removes it only if it names <name>.
set -eu
HOST=${1:?host alias}; OP=${2:?acquire|release}; NAME=${3:?run name}
LOCK='$HOME/.zk-run.lock'
case "$OP" in
  acquire)
    # noclobber makes the create-if-absent atomic on the host
    if ! ssh -o BatchMode=yes "$HOST" "set -C; echo '$NAME $(id -un)@local $(date -u +%Y-%m-%dT%H:%M:%SZ)' > $LOCK" 2>/dev/null; then
      echo "lock.sh: $HOST is busy: $(ssh -o BatchMode=yes "$HOST" "cat $LOCK")" >&2
      exit 1
    fi
    echo "lock.sh: $HOST locked for $NAME"
    ;;
  release)
    HELD=$(ssh -o BatchMode=yes "$HOST" "cat $LOCK 2>/dev/null || true")
    case "$HELD" in
      "") echo "lock.sh: $HOST holds no lock" ;;
      "$NAME "*) ssh -o BatchMode=yes "$HOST" "rm -f $LOCK"; echo "lock.sh: $HOST released ($NAME)" ;;
      *) echo "lock.sh: $HOST is locked by another run, not released: $HELD" >&2; exit 1 ;;
    esac
    ;;
  *) echo "lock.sh: unknown operation $OP" >&2; exit 2 ;;
esac
