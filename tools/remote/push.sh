#!/bin/sh
# push.sh <host> <repo-dir> [<dest>] [<commit>]
#
# Tar over ssh of a tracked tree: the files git tracks in <repo-dir> (the
# working tree, or the tree at <commit> if given), into <dest> on the host
# (default: the repository's basename under the remote home).  `target/`,
# model weights and witnesses are never tracked, so they never travel.
#
# Files are extracted with `-m`, so every pushed file gets the host's current
# time.  A pushed tree may be older than a build already on the host, and
# cargo decides freshness by mtime; without `-m` a changed source file with
# an old mtime would not be rebuilt.  The cost is a rebuild after every push.
set -eu
HOST=${1:?host alias}; REPO=${2:?repository directory}
DEST=${3:-$(basename "$(cd "$REPO" && pwd)")}
COMMIT=${4:-}
cd "$REPO"
if [ -n "$COMMIT" ]; then
  git archive --format=tar "$COMMIT"
else
  git ls-files -z | tar -cf - --null -T -
fi | ssh -o BatchMode=yes "$HOST" "mkdir -p '$DEST' && tar -C '$DEST' -xmf -"
echo "push.sh: $REPO${COMMIT:+@$COMMIT} -> $HOST:$DEST"
