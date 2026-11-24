# The Ubuntu of CI's runner (.github/workflows/test.yml: ubuntu-latest, now
# 24.04) with what CI installs for the engine's tests (texlive-binaries,
# time) and what the runner image brings that the tests use (python3,
# procps for pgrep). tools/test-linux.sh builds and runs it.
FROM ubuntu:24.04
RUN apt-get update -qq \
 && DEBIAN_FRONTEND=noninteractive apt-get install -y -qq --no-install-recommends texlive-binaries time python3 procps >/dev/null \
 && rm -rf /var/lib/apt/lists/*
WORKDIR /work
