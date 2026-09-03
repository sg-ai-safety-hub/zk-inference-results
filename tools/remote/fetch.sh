#!/bin/sh
# fetch.sh <host> <name> <dest>
#
# Tar the run's output directory `~/runs/<name>/out` back into <dest>.  Logs
# stay on the host; so do serialized proofs and witnesses, which the driver
# never writes under out/.
set -eu
HOST=${1:?host alias}; NAME=${2:?run name}; DEST=${3:?local destination}
mkdir -p "$DEST"
ssh -o BatchMode=yes "$HOST" "tar -C ~/runs/$NAME/out --exclude='*.log' -cf - ." | tar -C "$DEST" -xf -
echo "fetch.sh: $HOST:~/runs/$NAME/out -> $DEST ($(find "$DEST" -type f | wc -l | tr -d ' ') files)"
