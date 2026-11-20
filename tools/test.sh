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
#                 is written whole when every test has ended, or not at all.
# A bad option, a test named twice or a --times FILE that cannot be written
# stops the run before any test starts (exit status 2). Interrupted (INT,
# TERM, HUP), the run stops every test it started and writes no times.
set -e
cd "$(dirname "$0")/.."
FAST="core grow leaf letters plant settings reserve prepare_spec render_page inline headpiece lint"

# One test, by name.
run() {
  if [ "$1" = bake ]; then
    "${FLORA_PYTHON:-python3}" -I tests/test_bake.py
  elif [ "$1" = lint ]; then
    "${FLORA_PYTHON:-python3}" -I tests/test_lint.py
  else
    texlua "tests/test_$1.lua"
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
    grep -Ev '^(real|user|sys) ' "$2/$3.err" >&2
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
case "${1:-}" in
  fast) set -- $FAST bake ;;
  "") set -- $(ls tests/test_*.lua | sed 's|tests/test_||; s|\.lua$||') bake lint ;;
esac

# Each test once: two runs of one test would share its output files.
seen=" "
for t in "$@"; do
  case "$seen" in *" $t "*) usage "$t is named twice" ;; esac
  seen="$seen$t "
done

# One at a time and untimed: stop at the first failure, as always.
if [ "$jobs" = 1 ] && [ -z "$times" ]; then
  for t in "$@"; do run "$t"; done
  exit 0
fi

# The times file is written next to FILE and moved over it at the end:
# found unwritable now, not after the run.
if [ -n "$times" ]; then
  tmp_times="$times.partial.$$"
  { : > "$tmp_times"; } 2>/dev/null || usage "--times: cannot write $times"
fi
d=$(mktemp -d "${TMPDIR:-/tmp}/flora-test.XXXXXX")
trap 'rm -rf "$d"; [ -z "$times" ] || rm -f "$tmp_times"' EXIT
printf '%s\n' "$@" > "$d/names"
# The tests in a process group of their own (set -m), stopped as one when
# the run is interrupted.
set -m
xargs -P "$jobs" -n 1 tools/test.sh --keep "$d" < "$d/names" &
xpid=$!
set +m
stop() {
  echo "test.sh: interrupted; stopping the tests, no times written" >&2
  kill -TERM -- "-$xpid" 2>/dev/null || true
  wait "$xpid" 2>/dev/null || true
  exit "$1"
}
trap 'stop 130' INT
trap 'stop 143' TERM
trap 'stop 129' HUP
wait "$xpid" || true
trap - INT TERM HUP
failed=
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
  } > "$tmp_times"
  mv "$tmp_times" "$times"
fi
if [ -n "$failed" ]; then
  echo "test.sh: failed:$failed" >&2
  exit 1
fi
