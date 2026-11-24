#!/bin/sh
# Runs tools/test.sh in Ubuntu, as CI does: /bin/sh is dash there and the
# userland GNU (time, xargs, awk is mawk). docs/testing.md.
#
#   tools/test-linux.sh [TEST.SH ARGS...]     default: fast
#   tools/test-linux.sh --list                the files it sends, one a line
#
# Needs docker (not for --list). The image (tools/test-linux.Dockerfile) is
# built once per architecture and kept as tikz-flora-test:ubuntu-24.04-ARCH;
# FLORA_LINUX_REBUILD=1 builds it again.
#
# The container gets the tree CI checks out, as it stands in the working
# tree: the files git tracks and those it would track (untracked and not
# ignored), so uncommitted work is tried too, and nothing git ignores
# (build/, node_modules, local settings). A tracked file deleted in the
# working tree is not sent, as a commit of the tree would not hold it; a
# symlink is sent as the link, as git keeps it. Nothing the tests write
# comes back.
set -eu
cd "$(dirname "$0")/.."

# The working tree's files as git sees them. core.quotePath=false keeps
# names as they are; a name git must still quote (a newline or the like in
# it) cannot go through a line-per-file list, and stops the run.
files() {
  command -v git > /dev/null || { echo "test-linux: needs git, to list the tree's files" >&2; exit 2; }
  git rev-parse --is-inside-work-tree > /dev/null || { echo "test-linux: not in a git working tree" >&2; exit 2; }
  git -c core.quotePath=false ls-files --cached --others --exclude-standard | sort -u | while IFS= read -r f; do
    case "$f" in \"*) echo "test-linux: cannot send $f" >&2; exit 2 ;; esac
    if [ -e "$f" ] || [ -L "$f" ]; then printf '%s\n' "$f"; fi
  done
}

if [ "${1:-}" = --list ]; then
  files
  exit 0
fi

# The container has a name of this run's own and is stopped when the run is
# interrupted: a signal to this shell would otherwise leave the container,
# and the tests in it, running. The build and the container run in the
# background, waited for, so that the signal is acted on at once; one that
# comes before there is a child to stop ends the run here. A trap's action
# must not end with a command whose failure set -e acts on (docker kill
# finds no container before one is started).
name=tikz-flora-test-$$
list=
tarfile=
child=
got=
launching=
# shellcheck disable=SC2329
on_signal() {
  got=$1
  docker kill "$name" > /dev/null 2>&1 || true
  [ -z "$child" ] || kill "$child" 2> /dev/null || true
  # Between starting a background job and saving its pid there is no pid to
  # stop: the signal is acted on right after, by stop_launched.
  [ -n "$child" ] || [ -n "$launching" ] || exit "$got"
}
# After "launching=1; job & child=$!; launching=": a signal that came in
# between is sent on now.
stop_launched() {
  [ -z "$got" ] || { docker kill "$name" > /dev/null 2>&1 || true; kill "$child" 2> /dev/null || true; }
}
# Waits for the background job in child; a signal ends the wait before the
# job, which is waited for, and the run then leaves with the signal's status.
wait_child() {
  rc=0
  wait "$child" || rc=$?
  while kill -0 "$child" 2> /dev/null; do wait "$child" 2> /dev/null || true; done
  child=
  [ -z "$got" ] || exit "$got"
}
trap 'rm -f "$list" "$tarfile" || true' EXIT
trap 'on_signal 130' INT
trap 'on_signal 143' TERM
trap 'on_signal 129' HUP

# CI's runner is amd64. FLORA_LINUX_PLATFORM=linux/amd64 runs that
# architecture here too, emulated on another machine and many times
# slower; by default the container runs the machine's own architecture,
# the same Ubuntu, shell and userland.
command -v docker > /dev/null || { echo "test-linux: needs docker" >&2; exit 2; }
docker info > /dev/null 2>&1 || { echo "test-linux: docker is not running (docker info fails)" >&2; exit 2; }
platform=${FLORA_LINUX_PLATFORM:-}
if [ -z "$platform" ]; then
  case "$(docker info --format '{{.Architecture}}')" in
    aarch64|arm64) platform=linux/arm64 ;;
    *) platform=linux/amd64 ;;
  esac
fi
image=tikz-flora-test:ubuntu-24.04-${platform#linux/}
if [ "${FLORA_LINUX_REBUILD:-}" = 1 ] || ! docker image inspect "$image" > /dev/null 2>&1; then
  launching=1
  docker build -q --platform "$platform" -t "$image" -f tools/test-linux.Dockerfile tools > /dev/null &
  child=$!
  launching=
  stop_launched
  wait_child
  [ "$rc" -eq 0 ] || exit "$rc"
fi
[ $# -gt 0 ] || set -- fast
list=$(mktemp "${TMPDIR:-/tmp}/test-linux.XXXXXX")
tarfile=$(mktemp "${TMPDIR:-/tmp}/test-linux.XXXXXX")
files > "$list"
# --no-recursion: the list names every file, and a directory in it (none
# is, git lists files) would otherwise bring what git leaves out.
# COPYFILE_DISABLE: macOS's tar would add a ._ file for each file that has
# attributes, and the container would then hold files the tree does not.
COPYFILE_DISABLE=1 tar -c --no-xattrs --no-recursion -T "$list" > "$tarfile"
launching=1
docker run --rm -i --name "$name" --platform "$platform" -e FLORA_IN_LINUX_CONTAINER=1 "$image" sh -c 'tar -x && exec tools/test.sh "$@"' sh "$@" < "$tarfile" &
child=$!
launching=
stop_launched
wait_child
exit "$rc"
