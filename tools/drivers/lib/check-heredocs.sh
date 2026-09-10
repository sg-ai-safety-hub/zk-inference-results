#!/bin/sh
# No backtick inside a job body.
#
#     tools/drivers/lib/check-heredocs.sh [file ...]
#
# Every driver writes its job with an unquoted heredoc, cat > "$JOB" <<JOBEOF,
# because the body is the driver's configuration and every variable in it has to
# be expanded while the job is written.  An unquoted heredoc substitutes command
# substitutions too, so a backticked name in a comment inside the body is run as
# a command on the machine that writes the job, and the shipped job carries that
# command's output where the comment's words were (issue #84).
#
# So: name the flag, the file or the variable plainly inside a body, and keep
# the delimiter unquoted -- the expansions are what the body is for.  This fails
# on any line of a job body that holds a backtick, in every driver and in the
# job bodies under lib/.
#
# With no arguments it checks every *.sh under tools/drivers.  CI runs it.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)

if [ $# -eq 0 ]; then
    # shellcheck disable=SC2046
    set -- $(find "$HERE/.." -name '*.sh' | sort)
fi

awk '
FNR == 1 { body = 0 }
body && $0 ~ /^[[:space:]]*JOBEOF[[:space:]]*$/ { body = 0; next }
body && index($0, "`") {
    printf "%s:%d: a backtick inside the job body is run where the job is written\n", FILENAME, FNR
    printf "  %s\n", $0
    bad = 1
    next
}
/<<-?[[:space:]]*JOBEOF([[:space:]]|$)/ { body = 1 }
END {
    if (bad) {
        print "name it plainly instead; the delimiter stays unquoted (issue #84)"
        exit 1
    }
}
' "$@"
