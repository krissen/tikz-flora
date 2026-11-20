#!/bin/sh
# Runs tools/test.sh in Ubuntu, as CI does: /bin/sh is dash there, the
# userland GNU (time, xargs, awk is mawk), and the architecture CI's
# (amd64, emulated on another machine). docs/testing.md.
#
#   tools/test-linux.sh [TEST.SH ARGS...]     default: fast
#
# Needs docker. The image (tools/test-linux.Dockerfile) is built once and
# kept as tikz-flora-test:ubuntu-24.04; FLORA_LINUX_REBUILD=1 builds it
# again. The working tree, uncommitted changes included, is copied into
# the container (build/, site/ and tuner/ left out), so nothing the tests
# write reaches it.
set -eu
cd "$(dirname "$0")/.."
image=tikz-flora-test:ubuntu-24.04
platform=linux/amd64
command -v docker > /dev/null || { echo "test-linux: needs docker" >&2; exit 2; }
if [ "${FLORA_LINUX_REBUILD:-}" = 1 ] || ! docker image inspect "$image" > /dev/null 2>&1; then
  docker build -q --platform "$platform" -t "$image" -f tools/test-linux.Dockerfile tools > /dev/null
fi
[ $# -gt 0 ] || set -- fast
tar -c --no-xattrs --exclude ./build --exclude ./site --exclude ./tuner --exclude ./.git . |
  docker run --rm -i --platform "$platform" "$image" sh -c 'tar -x && exec tools/test.sh "$@"' sh "$@"
