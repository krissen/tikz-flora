# Running, timing and profiling the tests

## Running

`tools/test.sh` is the one list of the engine's tests: `just test` runs it, the pre-push hook runs `tools/test.sh fast` (`.pre-commit-config.yaml`), and CI runs named groups of it (`.github/workflows/test.yml`).

- `tools/test.sh` runs every `tests/test_*.lua` under texlua, then `tests/test_bake.py`, `tests/test_lint.py`, `tests/test_tools.py` and `tests/test_tools_matrix.py`. One at a time it stops at the first failure.
- `tools/test.sh fast` runs the tests meant to finish in seconds; `tools/test.sh mix layout` runs the ones named (a name is the file's, without `test_` and `.lua`).
- `-j` and `--times` need `/usr/bin/time` and Python (`FLORA_PYTHON`, else `python3`): the tests run in a process group of their own, which Python makes and stops, since a shell without a terminal cannot (dash, `/bin/sh` on Ubuntu, turns job control off).
- When something goes wrong the runner says so rather than measuring wrongly: a bad option, a test named twice or a `--times` file that cannot be written stop it before any test starts (exit status 2); interrupted (Ctrl-C, TERM, HUP) it stops every test it started and writes no times (exit status 130, 143, 129).
- `-j N` runs N tests at a time. Each test's output is printed whole when it ends, every test runs, and the failures are named at the end. `-j auto` is half the processors the system has online, as `getconf _NPROCESSORS_ONLN` counts them on macOS and Linux alike: logical processors, so on a Linux machine with hyperthreading each core counts twice, and on Apple silicon (no hyperthreading) logical and physical are the same. At least one. A test file runs in one process however many jobs there are, so the wall time is never less than the slowest file's.
- `just test` is `tools/test.sh -j auto`; `just test 6` runs six at a time, and `just test 1` one at a time, stopping at the first failure. The pre-push hook and CI call `tools/test.sh` without `-j`, one test at a time.

## What runs where

- `just test`: every `tests/test_*.lua`, then `test_bake.py`, `test_lint.py`, `test_tools.py` and `test_tools_matrix.py` (the measuring tools' own tests; the second runs every call the tools document, and is not in `fast`).
- Pre-push (`tools/test.sh fast`): core, grow, leaf, letters, plant, settings, reserve, prepare_spec, render_page, inline, headpiece, lint, tools and bake, each a second or two at most. header_mark and support take minutes and run in CI instead.
- CI (`.github/workflows/test.yml`): four groups that name 30 of the 44 test files, header_mark in the first and support in the last.
- Not in CI yet, a known gap: floret_passes, frame_matrix, pattern, pattern_colourways, pattern_ground, pattern_matrix, pattern_perimeter, pattern_protect, pattern_reach, pattern_values, pdf_form_cache, preview, progression_frame_resources and stem_taper. They run under `just test` only, so a green CI says nothing about the pattern engine.

## In Linux

CI runs Ubuntu, where `/bin/sh` is dash and the userland is GNU's (`time`, `xargs`; `awk` is mawk); a Mac runs bash as `sh` and BSD tools. `tools/test-linux.sh [ARGS]` (`just test-linux [ARGS]`) runs `tools/test.sh ARGS` (default: `fast`) in a container of CI's Ubuntu (24.04) with the packages CI installs (texlive-binaries, time) and those the runner brings that the tests use (python3, procps), from `tools/test-linux.Dockerfile`. The container runs the machine's own architecture; `FLORA_LINUX_PLATFORM=linux/amd64` runs CI's, emulated on another machine and many times slower (the fast set about 150 s against about 12 s natively on an Apple silicon Mac).

The container gets the tree CI checks out, as it stands in the working tree: the files git tracks and those it would track (untracked and not ignored), so uncommitted work is tried too, and nothing git ignores. A tracked file deleted in the working tree is not sent, and a symlink goes as the link. `tools/test-linux.sh --list` prints the files it sends, and `tests/test_tools.py` checks that every file the tests name is among them. Nothing written inside comes back.

It needs docker. The first run for an architecture builds its image (under a minute natively, several minutes emulated); `FLORA_LINUX_REBUILD=1` builds it again. Docker's virtual machine stops while the Mac sleeps, so a run's wall time across a sleep says nothing; time a run inside, with `--times`.

## Every documented call

The tools take their arguments in many forms, and each was once found wrong only in the call someone happened to make (`just test-times auto` lost its run; `tools/test.sh ""` ran every test; `--times` a directory moved the file into it). A call must either work or refuse in words, with a status other than 0, before it starts any test: none gives a traceback, fails silently, loses a measurement or ends with status 0 when it went wrong.

`tests/test_tools_matrix.py` holds the calls as a table (the rows of `CELLS`) and runs each one against stand-in tests in a temporary tree: `tools/test.sh` with every form of `-j` (omitted, 1, a number, `auto`, 0, a word, empty), of `--times` (omitted, a file, an unwritable path, empty, a directory) and of the test names (none, one, two, `fast`, unknown, twice, empty, failing, mixed), `tools/test_times.py` `show` and `compare` with every form of the file and of `--jobs`, `tools/profile.lua` with every option in its good and bad forms, and the justfile's recipes that call these (`just test`, `test-times`, `profile`, `test-linux`), and `tools/test-linux.sh` in docker. A recipe in the justfile that calls a tool and has no row fails the test, and so does one this page does not mention, so the table and the documentation stay together. Rows needing docker or just are skipped, with a line saying so, where it is missing. `TOOLS_MATRIX_TABLE=1 python3 -I tests/test_tools_matrix.py` prints the table with each call's expected and actual outcome and status. It takes about 25 s (50 s of CPU) with the container's rows, so it is not in `fast`; CI runs it as its own job (`.github/workflows/test.yml`). Add a row when a tool gains an option; a branch that adds a tool puts its rows in `tests/tools_matrix_extra.py`.

## Two runs at once

Several people, or several agents, run tests on one machine, so nothing the tools use may be shared between two runs. `tools/test.sh` keeps each run's files in a directory of its own (`mktemp -d`) and stops only the process group it made; `--times FILE` is written next to FILE under a name with the run's process id and moved over it at the end; `tools/test-linux.sh` sends a list from `mktemp` and starts an unnamed container. The one shared name is the image, built from the same recipe by whichever run finds it missing, and `build/test-times.tsv`, where the last finished run stays. A test of the tools finds the processes it started by the pid they record, never by their command line, and `tests/test_tools.py` runs two copies of the runner's tests at once beside an unrelated process that has the command line of its sleepers, and requires that both pass and that the process is left alone.

## Timing

`tools/test.sh --times FILE` writes one tab-separated line per test: its name, exit status, and wall, user, sys and CPU (user + sys) seconds, most CPU first; the last line records the jobs, the time (UTC) and the machine's load average when the run ended. `just test-times [JOBS] [NAMES]` (JOBS a number or `auto`) runs it (default 4 jobs, every test), shows its own file and keeps it as `build/test-times.tsv` (when two runs overlap the one that ends last stays; its own output goes to a file of its own, named when the run fails):

```
python3 -I tools/test_times.py show build/test-times.tsv
python3 -I tools/test_times.py compare old.tsv new.tsv
```

A test that failed has its exit status in the file (one killed by a signal 128 plus the signal's number) and one without recorded times has NA. `tools/test_times.py` refuses a file that is empty, lacks its header or its closing line, or has a line that is not a test's times, naming the line; it marks failed and untimed tests and leaves them out of the totals and the schedule.

`show` prints the table with each test's share of the CPU and the least wall time some numbers of jobs could take on those CPU times (longest test first on the first free job; never less than the longest test). `compare` prints each test's CPU seconds in two runs and the change, and totals only the tests both runs timed and passed, naming the ones it left out (only in one run, failed, untimed).

Compare CPU time, not wall time. Wall time depends on what else the machine runs (the load average in the file says how much), and tests run side by side share the machine too. Even CPU time moves by some per cent with load (shared caches, clock speed), so a change of a few per cent needs repeated runs to be believed; a count that does not depend on the machine (pages painted, calls made, below) settles it better.

## Profiling

`tools/profile.lua` runs a Lua script, or a chunk given with `-e`, and reports where it spent its time. `just profile ARGS` is `texlua tools/profile.lua ARGS`.

```
texlua tools/profile.lua tests/test_pattern_perimeter.lua
texlua tools/profile.lua --period 50000 --top 40 --out build/prof.txt tests/test_pattern.lua
texlua tools/profile.lua --time flora.pattern.clearance,flora.compose.page tests/test_pattern_matrix.lua
texlua tools/profile.lua --no-sample --time flora.compose.page -e 'dofile("my_bench.lua")'
```

Sampling (the default) notes the running function and its stack every `--period` virtual-machine instructions (10000 by default; larger is lighter on the run and coarser). The report has three tables: by function alone ("self"), by function with everything it calls ("inclusive"), and by line. The shares are of instructions run, not of seconds: time spent in C (building strings, allocating tables, the garbage collector, `string.format`) counts to the Lua line that asked for it, so a line that allocates in a loop shows up as that line. Under sampling a run takes some per cent longer.

`--time MODULE.FN,...` wraps the functions named and counts, exactly, each one's calls and its CPU seconds (callees included; a call nested in another of the same function is counted but not timed twice). It is the check on what the sampling points at, and it gives the counts (calls per page, pages per test) that do not depend on the machine's load. A function must be reached through its module's table (`Pattern.clearance`, not a local copy) to be counted.

The report is written when the script ends, by `os.exit` or an error too, so a failing test still reports, and its first line says which: completed, ended by os.exit(N) or stopped by an error. A timed function that raises an error is timed to the error and the report says how many of its calls raised; the error goes on as the same value (a pcall round it catches what it would have caught), but a traceback taken outside starts at the profiler's wrapper. Recursive calls are timed once, at the outermost; calls nest by coroutine, and a call's time includes any time it lies suspended in a coroutine. Coroutines the script creates are sampled too. A bad option, a `--time` name that does not resolve to a function, or an `--out` file that cannot be written stop the run before it starts (exit status 2).
