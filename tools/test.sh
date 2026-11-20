#!/bin/sh
# Runs the engine's tests under texlua. One list for the justfile, the
# pre-push hook and CI (docs/testing.md).
#   tools/test.sh fast        tests that finish in seconds (pre-push)
#   tools/test.sh <name>...   the named tests, e.g. mix layout
#   tools/test.sh             every test
# Options, before the names:
#   -j N          run N tests at a time (default 1). Each test's output is
#                 printed whole when it ends; every test runs and the
#                 failures are named at the end. -j auto is half the
#                 processors the system has online (getconf
#                 _NPROCESSORS_ONLN, on macOS and Linux alike; logical
#                 processors, so hyperthreads count), at least one.
#   --times FILE  write each test's exit status and seconds (wall, user,
#                 sys) to FILE, tab-separated, most CPU first, with the
#                 machine's load; tools/test_times.py shows and compares
#                 such files. A test killed by a signal has status 128 + its
#                 number; one with no times recorded has NA for them. FILE
#                 is written whole when every test has ended, or not at
#                 all; when it cannot be, the run says where the whole
#                 times are instead and exits 1.
# A bad option, a name that is no test, a test named twice, fast with another
# name or a --times FILE that cannot be written (or is a directory) stops
# the run before any test starts (exit status 2). Interrupted (INT, TERM,
# HUP), the run stops every test it started and writes no times.
set -e
cd "$(dirname "$0")/.."
FAST="core grow leaf letters plant settings reserve prepare_spec render_page inline headpiece row_phase lint tools"

# One test, by name; "run NAME exec" replaces the shell that runs it with
# the test, so that a signal sent to that process is the test's own.
run() {
  x=
  [ "${2:-}" != exec ] || x="exec"
  if [ "$1" = bake ]; then
    $x "${FLORA_PYTHON:-python3}" -I tests/test_bake.py
  elif [ "$1" = lint ]; then
    $x "${FLORA_PYTHON:-python3}" -I tests/test_lint.py
  elif [ "$1" = tools ]; then
    $x "${FLORA_PYTHON:-python3}" -I tests/test_tools.py
  elif [ "$1" = tools_matrix ]; then
    $x "${FLORA_PYTHON:-python3}" -I tests/test_tools_matrix.py
  else
    $x texlua "tests/test_$1.lua"
  fi
}

# Internal, for -j and --times: "--run NAME" runs one test;
# "--keep DIR NAME" runs it timed, its output and status kept in DIR.
case "${1:-}" in
  --run) run "$2"; exit $? ;;
  --keep)
    set +e
    /usr/bin/time -p tools/test.sh --run "$3" > "$2/$3.out" 2> "$2/$3.err"
    echo $? > "$2/$3.status"
    # The run may have been stopped and its directory removed meanwhile.
    [ -d "$2" ] || exit 0
    cat "$2/$3.out"
    # The timer's own lines: -p's three, and GNU time's note on a test that
    # failed or was killed (BSD time writes none).
    grep -Ev '^(real|user|sys) |^Command (exited with non-zero status|terminated by signal) ' "$2/$3.err" >&2
    exit 0 ;;
esac

usage() { echo "test.sh: $1" >&2; exit 2; }

jobs=1
times=
while [ $# -gt 0 ]; do
  case "$1" in
    -j) [ $# -ge 2 ] || usage "-j takes a number or auto"; jobs="$2"; shift 2 ;;
    -j*) jobs="${1#-j}"; shift ;;
    --times) [ $# -ge 2 ] && [ -n "$2" ] || usage "--times takes a file"; times="$2"; shift 2 ;;
    *) break ;;
  esac
done
if [ "$jobs" = auto ]; then
  n=$(getconf _NPROCESSORS_ONLN 2>/dev/null || sysctl -n hw.ncpu 2>/dev/null || echo 2)
  jobs=$((n / 2))
  [ "$jobs" -ge 1 ] || jobs=1
fi
case "$jobs" in ''|*[!0-9]*|0) usage "-j takes a positive whole number or auto, not '$jobs'" ;; esac

# The test names are plain words; the lists are split on purpose.
# shellcheck disable=SC2086,SC2046,SC2012
if [ $# -eq 0 ]; then
  set -- $(ls tests/test_*.lua | sed 's|tests/test_||; s|\.lua$||') bake lint tools tools_matrix
elif [ "$1" = fast ]; then
  [ $# -eq 1 ] || usage "fast takes no other test names"
  set -- $FAST bake
fi

# Each test once: two runs of one test would share its output files. And
# each a test there is: a name that is not one stops the run before it
# starts, as an empty name or an option in the wrong place would otherwise.
seen=" "
for t in "$@"; do
  case "$t" in
    "") usage "an empty test name" ;;
    -*) usage "$t is not an option here (options come before the test names)" ;;
    bake|lint|tools|tools_matrix) ;;
    *) [ -f "tests/test_$t.lua" ] || usage "no test named $t (tests/test_$t.lua)" ;;
  esac
  case "$seen" in *" $t "*) usage "$t is named twice" ;; esac
  seen="$seen$t "
done

# One at a time and untimed: stop at the first failure, as always.
# A test runs in the background, waited for, so that a signal to this shell
# is forwarded to it (a shell waiting on a foreground command acts on the
# signal only when the command ends).
if [ "$jobs" = 1 ] && [ -z "$times" ]; then
  child=
  got=
  # The action of a trap must not end with a command whose failure set -e
  # acts on: the test may be gone already, or not started yet.
  # shellcheck disable=SC2329
  on_signal() {
    got=$1
    [ -z "$child" ] || kill -TERM "$child" 2> /dev/null || true
  }
  trap 'on_signal 130' INT
  trap 'on_signal 143' TERM
  trap 'on_signal 129' HUP
  for t in "$@"; do
    [ -z "$got" ] || exit "$got"
    (run "$t" exec) &
    child=$!
    # A signal that came before child was set is sent on now.
    [ -z "$got" ] || kill -TERM "$child" 2> /dev/null || true
    rc=0
    wait "$child" || rc=$?
    # A signal ends the wait before the test: wait for the test, then
    # leave with the signal's status.
    while kill -0 "$child" 2> /dev/null; do wait "$child" 2> /dev/null || true; done
    child=
    [ -z "$got" ] || exit "$got"
    [ "$rc" -eq 0 ] || exit "$rc"
  done
  exit 0
fi

[ -x /usr/bin/time ] || usage "-j and --times need /usr/bin/time (the time package)"
PY=${FLORA_PYTHON:-python3}
command -v "$PY" > /dev/null || usage "-j and --times need $PY (FLORA_PYTHON) to stop the tests when interrupted"
# FILE is found unwritable now, not after the run. The times are made whole
# in the run's own directory, then copied to FILE; that directory stays, and
# is named, when the copy fails.
tmp_times="$times.partial.$$"
if [ -n "$times" ]; then
  [ ! -d "$times" ] || usage "--times: $times is a directory"
  # Not ":", whose failed redirection ends a POSIX shell (dash) silently.
  { true > "$tmp_times"; } 2>/dev/null || usage "--times: cannot write $times"
  rm -f "$tmp_times"
fi
d=$(mktemp -d "${TMPDIR:-/tmp}/flora-test.XXXXXX")
keep=
trap '[ -n "$keep" ] || rm -rf "$d" || true' EXIT
printf '%s\n' "$@" > "$d/names"
# The tests in a process group of their own, stopped as one when the run
# is interrupted. The shell cannot make one without a terminal (set -m is
# job control, which dash turns off without a tty) nor signal one alike
# (dash's kill takes no "--" before a negative pid), so Python does both:
# setpgid before exec'ing xargs, and killpg. Before the setpgid there is no
# group yet, only that one process, and it is signalled alone.
"$PY" -c 'import os, sys; os.setpgid(0, 0); os.execvp(sys.argv[1], sys.argv[1:])' \
  xargs -P "$jobs" -n 1 tools/test.sh --keep "$d" < "$d/names" &
xpid=$!
stop() {
  echo "test.sh: interrupted; stopping the tests, no times written" >&2 || true
  # tools/toolproc.py: TERM to the group, a wait for it to be gone, KILL
  # for what is left, as for every other tool that starts processes.
  "$PY" -I tools/toolproc.py stop-group "$xpid" TERM || echo "test.sh: could not stop the tests (process group $xpid)" >&2
  wait "$xpid" || true
  exit "$1"
}
trap 'stop 130' INT
trap 'stop 143' TERM
trap 'stop 129' HUP
wait "$xpid" || true
trap - INT TERM HUP
failed=
saved=
for t in "$@"; do
  [ "$(cat "$d/$t.status" 2>/dev/null)" = 0 ] || failed="$failed $t"
done
if [ -n "$times" ]; then
  tab=$(printf '\t')
  for t in "$@"; do
    # /usr/bin/time -p writes a decimal comma under some locales.
    # A test with no times recorded (its timer killed too) gets NA.
    LC_ALL=C awk -v t="$t" -v s="$(cat "$d/$t.status" 2>/dev/null || echo NA)" '
      /^real / { r = $2 } /^user / { u = $2 } /^sys / { y = $2 }
      END { if (r == "" || u == "" || y == "") { printf "%s\t%s\tNA\tNA\tNA\tNA\n", t, s; exit }
            gsub(",", ".", r); gsub(",", ".", u); gsub(",", ".", y)
            printf "%s\t%s\t%s\t%s\t%s\t%.2f\n", t, s, r, u, y, u + y }' "$d/$t.err"
  done | LC_ALL=C sort -t "$tab" -k6,6gr > "$d/times"
  {
    printf 'test\tstatus\twall\tuser\tsys\tcpu\n'
    cat "$d/times"
    echo "# jobs=$jobs $(date -u +%Y-%m-%dT%H:%M:%SZ) $(uptime | sed 's/.*load/load/')"
  } > "$d/times.tsv"
  if [ -d "$times" ] || ! cp "$d/times.tsv" "$tmp_times" 2> /dev/null || ! mv "$tmp_times" "$times" 2> /dev/null; then
    rm -f "$tmp_times"
    keep=1
    echo "test.sh: could not write $times; the times are in $d/times.tsv" >&2
    saved=no
  fi
fi
if [ -n "$failed" ]; then
  echo "test.sh: failed:$failed" >&2
  exit 1
fi
[ -z "$saved" ] || exit 1
