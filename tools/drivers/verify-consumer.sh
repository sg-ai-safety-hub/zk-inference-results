#!/bin/sh
# verify-consumer: the reference segment's proof replayed on four cores and no
# card, and a corrupted copy of it refused.
#
#   tools/drivers/verify-consumer.sh <host> <artifact-dir> <verifier-binary> <cores>
#
# zk-results #112. Every verification this repository records ran on the run
# host's cores beside the card, on all of them: `verify.headline.c4096.secs_total`
# and the c16384 rows are that machine's sixteen. The paper says a proof can be
# checked later on a consumer machine, and nothing here had ever timed one on a
# machine of that size. This run is that measurement. It makes no proof, reads
# no card, builds nothing and takes no host lock -- it is CPU work beside
# whatever else the machine is doing, and the one thing it asks of the machine
# is room under the memory cap, which it waits for rather than takes.
#
# What it needs. Four arguments and nothing else.
#
#   * <host> is an ssh alias. The run is detached, as every run here is, and the
#     status file says when it is done; the driver is then run again with the
#     same four arguments to fetch it.
#   * <artifact-dir> is the kept proof of the reference segment on that host --
#     one Llama-3.1-8B layer-16 segment, S = 512 output positions against a
#     C = 16,384 key prefix, the five reductions on and no skip in effect --
#     holding the statement, the published claims and the proof under `ser/`,
#     with the calibration the verifier derives the shape root from and the
#     prompt ids beside them. The digests are pinned below, so a directory whose
#     files hash to anything else is refused before a second of work is spent on
#     it, and a directory that carries no `SHA256SUMS` is given this one.
#   * <verifier-binary> is `zk-prover` built on the reference (SIMD) backend at
#     the commit the proof was made at. The binary says which commit it was
#     built from, and which backend, in the provenance block of every document
#     it prints; the first replay's own block is read before the second one
#     starts, so the binary is checked by what it says about itself and not by
#     the path it was handed. A `cuda` build is refused: this measurement is
#     about a machine that has no card.
#   * <cores> is how many cores to pin to. They are the first <cores> of
#     `/sys/fs/cgroup/cpuset.cpus.effective`, so the pinning holds inside a
#     container whose cpus are not numbered from zero, and `rayon` reads the
#     affinity mask, so the binary reports that many threads in its own `env`
#     block. The run refuses if it reports any other number.
#
# What it measures. The replay the artifact's README gives, three times:
#
#   zk-prover boundary-grid --dir ser --tags <tag> --allow-gaps --verify \
#       --prompt prompt.json --verify-calibration calibration.json
#
# `--verify` runs verify_composed over the statement, the claims and the proof,
# and derives the statement's shape root from its own parameters and the
# published calibration rather than taking the prover's word for it. Each
# repetition is a process of its own under `/usr/bin/time -v`, so each gives two
# kinds of number: the verifier's own seconds, which is what the sixteen-core
# record is comparable with, and the process's wall-clock time, user and system
# seconds and peak resident set size, which is what says whether a machine of a
# given size can hold the replay at all. Three repetitions and not one, because
# the median of three on a machine that is doing other work is a number, and one
# reading is an anecdote.
#
# The negative control. A copy of the three serialized documents under a scratch
# directory, with one byte inside the proof body changed -- a hex digit in the
# middle of the file, named by offset and by what it was and became in the run's
# own record -- replayed with the same command. It has to be refused. A control
# that is accepted fails the run and records nothing: a verification nobody can
# see fail says nothing about the ones that passed.
#
# What it does not do. It takes no lock and it frees none. The machine may be
# running a card job of its own while this runs, and the wrapper that starts a
# locked run removes the lock file when it exits, which would free that job's.
# Instead the job waits for room: before each replay it reads the cgroup's
# `memory.current` against `memory.max` and sleeps while less than the reserve
# below is free, so a replay is never the process that pushes a shared cap over.
# It records what was held before each replay, because a machine doing other
# work is what these seconds were measured on.
#
# Host time, from the run this driver recorded: see REPRODUCE.md.
set -eu
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
HOST=${1:?host alias}
ART=${2:?the artifact directory on the host}
BIN=${3:?the verifier binary on the host}
CORES=${4:?how many cores to pin to}
NAME=verify-consumer

# ---- the configuration: here and in the manifest, nowhere else ---------------
LABEL=verifier             # this run proves nothing; it checks a proof another run made
DRV_KIND=verifier          # what lib/manifest.py is told, because no output can say it
# The commit the proof was made at, which is the commit the binary has to be.
# runs/2026-09-13-reference-digest-plain-h100 proved this segment at it, and the
# proof digest below is that run's own: full-digest.json carries it.
COMMIT=a8586d205b87d7019af5b5005d0a46680a74242e
PROVER=$COMMIT
# No harness ran: nothing here reads a weight, a dump or a corpus. The manifest
# wants a commit all the same, and the one that made the binary is the honest
# answer for a run whose only program is that binary.
HARNESS=$COMMIT
TAG=llama31-8b-l16-s512-c16384
REPS=3
# The replay peaks at about 29 GiB. The reserve is that with room to spare, so
# a job of this repository that is already holding the machine is never the one
# the kernel kills.
RESERVE_GIB=45
# The artifact's own digests, with the paths the host keeps the files at: the
# three serialized documents under ser/, the two files the command names beside
# them, and the prover's and the verifier's reports of the proof these bytes
# are. The kept directory also holds a README, which no host needs and which is
# therefore not in this table.
SUMS="f4d5d5f60ca07b27e29bfad3afade4d6d1db3c0343b1a3bdd838a27e1588d08f  ser/$TAG.claims.json
38827f5bec298f22100955fc317cdc45157d2bc9d7149d5c1021adfb45a00a06  ser/$TAG.fixed.json
c5c75572ca078b6c551edd62d72ed96d7f0357958e1bbc805f803328ee270054  ser/$TAG.proof.json
92d767b39c166fff9be7d726beba9d51a0d7f7db092b49a5bfaab4eb670ffde3  calibration.json
1ab07e7b72256d3580f6e8267b9bcbb589522f0833c93a3f6d639e806aa3552f  prompt.json
ddf273ec13fe177f3a2581cd85b17eb69fe8e022a2c7e42024dfec8af6b09bfe  compose-simd.json
c04e32997e28d888537b7d05479c95633df1a07679dc2af7f4d31284a5494714  verify.json"

. "$HERE/lib/driver.sh"

case "$CORES" in
  ''|*[!0-9]*) echo "$NAME: <cores> is a count of cores, not $CORES" >&2; exit 2 ;;
esac

# ---- finish, or say where the run is -----------------------------------------
# Only the finished-and-clean path is the shared one: the other two print this
# driver's own four arguments and not another driver's three.
ST=$(drv_status)
case "$ST" in
  *"done exit=0"*) drv_finish "$ST" ;;
  *"done exit="*)
    echo "$NAME on $HOST failed: $ST"
    echo "log:     ssh $HOST tail -40 '~/runs/$NAME.log'"
    echo "restart: ssh $HOST rm -f '~/runs/$NAME.status' && $0 $HOST $ART $BIN $CORES"
    exit 1 ;;
  running*)
    echo "$NAME on $HOST: $ST"
    echo "poll: ssh $HOST cat '~/runs/$NAME.status'"
    exit 0 ;;
esac

# ---- start -------------------------------------------------------------------
JOB=$(mktemp)
cat > "$JOB" <<JOBEOF
#!/bin/sh
# generated by $NAME.sh; runs detached on the host and holds no lock
set -eu
R=\$HOME/runs/$NAME
OUT=\$R/out
NEG=\$R/neg
ART=$ART
BIN=$BIN
TAG=$TAG
mkdir -p \$OUT
st() { echo "\$(date -u +%H:%M:%S) \$*"; }

[ -d \$ART ] || { st "no artifact directory at \$ART"; exit 5; }
[ -x \$BIN ] || { st "no verifier binary at \$BIN"; exit 5; }
[ -f \$ART/ser/\$TAG.proof.json ] || { st "no proof at \$ART/ser/\$TAG.proof.json"; exit 5; }

# ---- the machine: the cores this is pinned to, and the cap it runs under -----
CPUS=\$(python3 - $CORES <<'CPUPY'
import sys
n = int(sys.argv[1])
cpus = []
for part in open("/sys/fs/cgroup/cpuset.cpus.effective").read().strip().split(","):
    if "-" in part:
        lo, hi = part.split("-")
        cpus += list(range(int(lo), int(hi) + 1))
    elif part:
        cpus.append(int(part))
if len(cpus) < n:
    sys.exit("the cpuset offers %d cpu(s) and %d were asked for" % (len(cpus), n))
print(",".join(str(c) for c in cpus[:n]))
CPUPY
)
MEMMAX=\$(cat /sys/fs/cgroup/memory.max)
NCPU=\$(nproc)
MODEL=\$(lscpu | sed -n 's/^Model name:[[:space:]]*//p' | head -1)
st "cores \$CPUS of \$NCPU; cap \$MEMMAX bytes; \$MODEL"

# ---- the artifact: what these bytes are --------------------------------------
cat > \$R/SHA256SUMS <<'SUMSEOF'
$SUMS
SUMSEOF
if ( cd \$ART && sha256sum -c \$R/SHA256SUMS ) > \$R/sums.txt 2>&1; then
    st "artifact: \$(grep -c ': OK' \$R/sums.txt) file(s) hash to what the driver pins"
else
    st "artifact: the directory does not hash to what the driver pins"
    cat \$R/sums.txt
    exit 6
fi
[ -f \$ART/SHA256SUMS ] || cp \$R/SHA256SUMS \$ART/SHA256SUMS

# ---- the replay, three times -------------------------------------------------
# The README's command, run from the artifact directory so that what the
# verifier records as its arguments is the command a reader of the README types.
GRID="boundary-grid --dir ser --tags \$TAG --allow-gaps --verify --prompt prompt.json --verify-calibration calibration.json"
i=1
while [ \$i -le $REPS ]; do
    waited=0
    while : ; do
        CUR=\$(cat /sys/fs/cgroup/memory.current)
        FREE=\$(( (MEMMAX - CUR) / 1073741824 ))
        if [ \$FREE -ge $RESERVE_GIB ]; then break; fi
        waited=\$((waited + 1))
        if [ \$waited -gt 40 ]; then
            st "the cap has had less than $RESERVE_GIB GiB free for twenty minutes; not taking it"
            exit 7
        fi
        st "waiting: \$FREE GiB free under the cap, $RESERVE_GIB wanted"
        sleep 30
    done
    st "replay \$i of $REPS: \$CUR bytes held under the cap before it starts"
    echo \$CUR > \$R/held-\$i.bytes
    set +e
    ( cd \$ART && taskset -c \$CPUS /usr/bin/time -v -o \$R/rep-\$i.time \
        \$BIN \$GRID > \$R/rep-\$i.json 2> \$R/rep-\$i.err )
    rc=\$?
    set -e
    if [ \$rc != 0 ]; then
        st "replay \$i exited \$rc; the honest proof has to verify"
        tail -5 \$R/rep-\$i.err
        exit 8
    fi
    cp \$R/rep-\$i.json \$OUT/verify-\$i.json
    st "replay \$i: \$(head -1 \$R/rep-\$i.err)"
    if [ \$i = 1 ]; then
        # What the binary says about itself, before two more replays of it.
        python3 - \$OUT/verify-1.json $COMMIT $CORES <<'PROVPY'
import json, sys
d = json.load(open(sys.argv[1]))
p, env = d["provenance"], d["env"]
want, cores = sys.argv[2], int(sys.argv[3])
bad = []
if p.get("commit") != want:
    bad.append("the binary was built at %s and the proof was made at %s"
               % (p.get("commit"), want))
if p.get("dirty"):
    bad.append("the binary was built from a tree with uncommitted changes")
if p.get("backend") != "simd":
    bad.append("the binary is the %s backend; this run is about a machine with no card"
               % p.get("backend"))
if env.get("threads") != cores:
    bad.append("the binary reports %s thread(s) and the run pinned %d core(s)"
               % (env.get("threads"), cores))
if bad:
    sys.exit("verify-consumer: " + "; ".join(bad))
print("verify-consumer: %s on the %s backend, %d thread(s)"
      % (p["commit"][:12], p["backend"], env["threads"]))
PROVPY
    fi
    i=\$((i + 1))
done

# ---- the negative control ----------------------------------------------------
# A copy of the three documents with one byte of the proof body changed. The
# statement, the claims, the calibration and the prompt are the artifact's own,
# so the one difference between this replay and the three above is that byte.
rm -rf \$NEG
mkdir -p \$NEG/ser
cp \$ART/ser/\$TAG.fixed.json \$ART/ser/\$TAG.claims.json \$NEG/ser/
cp \$ART/prompt.json \$ART/calibration.json \$NEG/
python3 - \$ART/ser/\$TAG.proof.json \$NEG/ser/\$TAG.proof.json \$R/bend.json <<'BENDPY'
"""One byte of the proof body, changed in place.

Not whitespace and not a delimiter. The proof serializes its commitments and
its field elements as decimal numbers, and this changes the last digit of the
first three-digit number at or after the middle of the file: the number stays
between 100 and 199, which is a value every numeric field of a proof can hold,
so the file keeps its length and stays readable and what the verifier refuses
is the proof and not the JSON.
"""
import hashlib, json, re, sys

src, dst, rec = sys.argv[1], sys.argv[2], sys.argv[3]
data = open(src, "rb").read()
before = hashlib.sha256(data).hexdigest()
b = bytearray(data)
m = re.compile(rb"(?<=,)1[0-9][0-9](?=,)").search(b, len(b) // 2)
if m is None:
    sys.exit("verify-consumer: no three-digit number in the second half of the proof")
off = m.end() - 1
was = bytes(b[m.start():m.end()]).decode()
old = chr(b[off])
new = "0" if old != "0" else "1"
b[off] = ord(new)
now = bytes(b[m.start():m.end()]).decode()
open(dst, "wb").write(b)
json.dump({"bytes": len(b), "offset": off, "byte_before": old, "byte_after": new,
           "number_before": was, "number_after": now,
           "sha256_before": before, "sha256_after": hashlib.sha256(b).hexdigest(),
           "what": "one digit of one number in the proof body, changed in place; the "
                   "file keeps its length and every other byte"},
          open(rec, "w"), indent=1, sort_keys=True)
print("verify-consumer: byte %d of %d, the number %s became %s" % (off, len(b), was, now))
BENDPY
set +e
( cd \$NEG && taskset -c \$CPUS /usr/bin/time -v -o \$R/neg.time \
    \$BIN \$GRID > \$R/neg.json 2> \$R/neg.err )
nrc=\$?
set -e
st "control: exit \$nrc -- \$(head -1 \$R/neg.err)"
if [ \$nrc = 0 ]; then
    st "the corrupted proof was accepted; that is a failed run and not a record"
    exit 9
fi
if [ -s \$R/neg.json ]; then cp \$R/neg.json \$OUT/verify-control.json; fi

# ---- the run's own records ---------------------------------------------------
python3 - \$R \$OUT $CORES \$CPUS \$MEMMAX \$NCPU \$nrc "\$MODEL" <<'RECPY'
"""measurement.json, negative-control.json and config.json.

Every number here is read out of a file some program wrote: the seconds and the
peak resident set size come from the /usr/bin/time report of each process, the
verifier's own seconds from its own document, and nothing is transcribed by
hand.
"""
import json, pathlib, statistics, sys

r, out, cores, cpus, memmax, ncpu, nrc, model = sys.argv[1:9]
r, out = pathlib.Path(r), pathlib.Path(out)
cores, ncpu, nrc, memmax = int(cores), int(ncpu), int(nrc), int(memmax)


def timed(path):
    """The fields of one /usr/bin/time -v report this run is about."""
    f = {}
    for line in path.read_text().splitlines():
        if ": " not in line:
            continue
        # the key of the elapsed row carries colons of its own, so the split is
        # on the last colon and space and not on the first colon
        k, v = line.strip().rsplit(": ", 1)
        f[k.strip()] = v.strip()
    hms = f["Elapsed (wall clock) time (h:mm:ss or m:ss)"].split(":")
    secs = 0.0
    for part in hms:
        secs = secs * 60 + float(part)
    return {"wall_secs": secs,
            "user_secs": float(f["User time (seconds)"]),
            "sys_secs": float(f["System time (seconds)"]),
            "peak_rss_bytes": int(f["Maximum resident set size (kbytes)"]) * 1024,
            "cpu_pct": f["Percent of CPU this job got"]}


reps = []
for p in sorted(out.glob("verify-[0-9].json")):
    n = int(p.stem.split("-")[1])
    d = json.loads(p.read_text())
    res = d["result"]
    ch = res["verified"]["chunks"][0]
    row = timed(r / ("rep-%d.time" % n))
    row.update({"repetition": n, "tag": ch["tag"], "accepts": ch["accepts"],
                "verify_secs": ch["verify_secs"],
                "verifier_wall_secs": ch["wall_secs"],
                "shape_root_secs": res["shape_roots"]["secs"],
                "shape_roots_derived": res["shape_roots"]["derivations"]["derived"],
                "shape_roots_reused": res["shape_roots"]["derivations"]["reused"],
                "threads": d["env"]["threads"],
                "held_before_bytes": int((r / ("held-%d.bytes" % n)).read_text().strip())})
    reps.append(row)

med = lambda k: statistics.median([x[k] for x in reps])
measurement = {
    "repetitions": len(reps),
    "cores": cores,
    "reps": reps,
    "secs_per_segment_median": med("verify_secs"),
    "process_wall_secs_median": med("wall_secs"),
    "user_secs_median": med("user_secs"),
    "sys_secs_median": med("sys_secs"),
    "shape_root_secs_median": med("shape_root_secs"),
    "peak_rss_bytes_median": med("peak_rss_bytes"),
    "note": "one segment of the reference proof, replayed three times on the cores "
            "named in config.json. secs_per_segment_median is the verifier's own "
            "seconds, which is the scope the c4096 and c16384 verify rows are in; the "
            "process figures are what the same replay costs a machine, the proof read "
            "off disk and parsed included. The shape root is derived from the published "
            "calibration once per distinct cell and is most of both.",
}
(out / "measurement.json").write_text(json.dumps(measurement, indent=1, sort_keys=True) + "\n")

bend = json.loads((r / "bend.json").read_text())
refusal = [ln for ln in (r / "neg.err").read_text().splitlines() if ln.strip()]
control = {"exit_code": nrc, "refused": nrc != 0, "bend": bend,
           "refusal": refusal, "time": timed(r / "neg.time")}
cj = r / "neg.json"
if cj.exists() and cj.stat().st_size:
    res = json.loads(cj.read_text())["result"]
    ch = res["verified"]["chunks"][0]
    control["verdict"] = {"accepts": ch["accepts"], "why": ch["why"],
                          "verify_secs": ch["verify_secs"],
                          "failures": res["failures"], "all_chain": res["all_chain"]}
control["note"] = ("the same command over a copy of the same three documents with one "
                   "byte of the proof changed; the verifier's report of it is "
                   "verify-control.json")
(out / "negative-control.json").write_text(json.dumps(control, indent=1, sort_keys=True) + "\n")

sums = {}
for line in (r / "SHA256SUMS").read_text().splitlines():
    if line.strip():
        h, name = line.split()
        sums[name] = h
config = {
    "driver": "$NAME", "label": "$LABEL",
    "machine": {"cpu_model": model, "cpus_in_cpuset": ncpu, "cores_used": cores,
                "cpus_pinned": cpus, "memory_max_bytes": memmax,
                "note": "the cores are the first of the cpuset the run is confined to; "
                        "the cap is the cgroup's, which is what the replay has to fit, "
                        "and is not the memory the machine has"},
    "artifact": {"segment": "Llama-3.1-8B layer 16, S = 512, C = 16,384, b10-final",
                 "sha256": sums,
                 "from_run": "2026-09-13-reference-digest-plain-h100",
                 "note": "the proof that run made, kept beside it; its digest is that "
                         "run's own, in full-digest.json"},
    "command": "boundary-grid --dir ser --tags $TAG --allow-gaps --verify "
               "--prompt prompt.json --verify-calibration calibration.json",
    "repetitions": len(reps),
    "harness": "none: this run reads no weight, no dump and no corpus",
    "note": "one segment's proof replayed on a few cores with no card, and a corrupted "
            "copy of it refused. The run makes no proof and commits nothing.",
}
(out / "config.json").write_text(json.dumps(config, indent=1, sort_keys=True) + "\n")
print("verify-consumer: median %.2f s of the verifier's own, %.2f s of process wall-clock "
      "time, peak %.2f GiB"
      % (measurement["secs_per_segment_median"], measurement["process_wall_secs_median"],
         measurement["peak_rss_bytes_median"] / 2 ** 30))
RECPY

# ---- the gate ----------------------------------------------------------------
python3 - \$OUT $REPS $CORES <<'GATEPY'
import json, pathlib, sys
out, reps, cores = pathlib.Path(sys.argv[1]), int(sys.argv[2]), int(sys.argv[3])
m = json.loads((out / "measurement.json").read_text())
c = json.loads((out / "negative-control.json").read_text())
bad = []
if len(m["reps"]) != reps:
    bad.append("%d replay(s) recorded and %d asked for" % (len(m["reps"]), reps))
if not all(x["accepts"] for x in m["reps"]):
    bad.append("a replay of the honest proof did not accept")
if any(x["threads"] != cores for x in m["reps"]):
    bad.append("a replay ran on a number of threads that is not the cores it was pinned to")
if not c["refused"]:
    bad.append("the corrupted proof was not refused")
if c.get("verdict", {}).get("accepts"):
    bad.append("the verifier accepted the corrupted proof")
if bad:
    sys.exit("verify-consumer: " + "; ".join(bad))
print("verify-consumer: %d replay(s) accepted, the corrupted copy refused with exit %d"
      % (len(m["reps"]), c["exit_code"]))
GATEPY
st "done"
JOBEOF

ssh -o BatchMode=yes "$HOST" "mkdir -p ~/runs/$NAME && cat > ~/runs/$NAME/job.sh" < "$JOB"
rm -f "$JOB"
# run.sh is not used and no lock is taken: its wrapper removes the host lock when
# the job exits, and on a machine that is running a locked job of its own that
# would free somebody else's.
ssh -o BatchMode=yes "$HOST" sh <<SHEOF
mkdir -p ~/runs && setsid nohup sh -c 'S=\$HOME/runs/$NAME.status; echo "running \$(date -u +%Y-%m-%dT%H:%M:%SZ) pid \$\$" > \$S; sh \$HOME/runs/$NAME/job.sh; rc=\$?; echo "done exit=\$rc \$(date -u +%Y-%m-%dT%H:%M:%SZ)" >> \$S' > ~/runs/$NAME.log 2>&1 < /dev/null &
SHEOF
echo "$NAME: started on $HOST, pinned to $CORES core(s), holding no lock"
echo "poll:   ssh $HOST cat '~/runs/$NAME.status'"
echo "tail:   ssh $HOST tail -20 '~/runs/$NAME.log'"
echo "when the status says done, run this command again with the same arguments"
