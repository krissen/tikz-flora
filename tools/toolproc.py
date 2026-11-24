"""The one way the tools and their tests start a process.

tests/test_tools.py and tests/test_tools_matrix.py run the runner, the
profiler and the rest, some of them in parallel and some of them
supervisors that start processes of their own; tools/lint.py and
tools/test_times.py run programs too. However such a test ends
(finished, failed, an exception in it, INT, TERM or HUP) no process it
started may be left running, those the tools started in turn included.

Every child is started here, in a session of its own, and is tracked
until it has been waited for. On INT, TERM or HUP (install) the signal is
sent on to every tracked group and to every other child of the process (one
started a moment before it was tracked, or not through here; found with
/bin/ps, and where that cannot be run only the tracked groups are stopped,
which needs nothing), which lets a
supervisor like tools/test.sh stop what it started; the groups are waited
for up to GRACE seconds (TOOLPROC_GRACE, in seconds, sets it), what did not
obey is killed, and the test ends with status 128 plus the signal's number.
atexit does the same for an exception that ends the test. A command that
outlives its timeout is stopped the same way, TERM first. When a child has
been waited for, what it left in its group is killed.

Run as a program, stop-group PID SIGNAL stops the group of PID (or the
process alone, where it has none yet) in the same way: tools/test.sh uses it
for the tests it runs in parallel.

A script run with python3 -I outside tools/ imports it with sys.path.insert
of tools/. tests/test_tools.py fails when one of the python programs of the
tools calls subprocess or starts a group of its own anywhere else.
"""

import atexit
import os
import signal
import subprocess
import sys
import threading
import time

GRACE = float(os.environ.get("TOOLPROC_GRACE") or 15)
# Reentrant: the handler for a signal runs in the thread that may hold it.
_lock = threading.RLock()
_live = {}
_handling = False


def _killpg(pgid, sig):
    try:
        os.killpg(pgid, sig)
    except (ProcessLookupError, PermissionError):
        pass


def _kill(pid, sig):
    try:
        os.kill(pid, sig)
    except (ProcessLookupError, PermissionError):
        pass


PS = "/bin/ps"  # by path: a PATH without ps (a test's) must not stop the stop


def _processes():
    """(pid, ppid, pgid, live) of every process, live false for a zombie
    (dead, waiting to be waited for); None when they cannot be listed."""
    try:
        done = subprocess.run([PS, "-A", "-o", "pid=,ppid=,pgid=,stat="], capture_output=True, text=True, check=False)
    except OSError:
        return None
    rows = []
    for line in done.stdout.splitlines():
        parts = line.split()
        if len(parts) >= 4 and all(p.isdigit() for p in parts[:3]):
            rows.append((int(parts[0]), int(parts[1]), int(parts[2]), not parts[3].startswith("Z")))
    return rows if done.returncode == 0 and rows else None


def _stop(targets, sig, grace, reap=()):
    """Send sig to each target, a (pid, group) pair where the group is None
    for a process alone (or in this process's own group); wait up to grace
    for them to be gone; kill what is left. Where the processes cannot be
    listed, the wait asks each group with signal 0 and reaps the children
    in reap, which is slower to see a group gone and never fails."""
    own = os.getpgrp()
    groups = {g for _, g in targets if g is not None and g != own}
    alone = {p for p, g in targets if g is None or g == own}

    def send(s):
        for g in groups:
            _killpg(g, s)
        for p in alone:
            _kill(p, s)

    def gone():
        rows = _processes()
        if rows is not None:
            return not any(live and (pgid in groups or pid in alone) for pid, _, pgid, live in rows)
        for child in reap:
            child.poll()
        try:
            for g in groups:
                os.killpg(g, 0)
            for p in alone:
                os.kill(p, 0)
        except ProcessLookupError:
            return True
        except PermissionError:
            return False
        return False

    send(sig)
    deadline = time.monotonic() + grace
    while time.monotonic() < deadline and not gone():
        time.sleep(0.1)
    send(signal.SIGKILL)


def stop_group(pid, sig=signal.SIGTERM, grace=None):
    """Stop the group led by pid (the process alone if it leads none)."""
    grace = GRACE if grace is None else grace
    rows = _processes()
    leads = rows is None or any(p == pid and g == pid and live for p, _, g, live in rows)
    _stop([(pid, pid if leads else None)] + ([(pid, None)] if rows is None else []), sig, grace)


def forget(child):
    """Kill what a finished child left in its group, and stop tracking it."""
    with _lock:
        _live.pop(child.pid, None)
    _killpg(child.pid, signal.SIGKILL)


class Child(subprocess.Popen):
    """A Popen in a session of its own; leaving its with block, which waits
    for it, forgets it."""

    def __exit__(self, *exc):
        try:
            super().__exit__(*exc)
        finally:
            forget(self)


def popen(argv, **kw):
    """subprocess.Popen, tracked and in a session of its own. Use it in a
    with block, or call forget(child) once it has been waited for."""
    child = Child(argv, start_new_session=True, **kw)
    with _lock:
        _live[child.pid] = child
    return child


def _close(child):
    for stream in (child.stdin, child.stdout, child.stderr):
        if stream:
            try:
                stream.close()
            except OSError:
                pass


def run(argv, timeout=None, input=None, check=False, capture_output=False, **kw):
    """subprocess.run, tracked. A child that outlives the timeout (or is
    interrupted) is stopped as a signal stops it, TERM first, so that a
    supervisor can stop what it started; its pipes are closed when what it
    left in another group keeps them open."""
    if capture_output:
        kw["stdout"] = kw["stderr"] = subprocess.PIPE
    with popen(argv, stdin=subprocess.PIPE if input is not None else None, **kw) as child:
        # In slices: a blocking wait holds the child's wait lock, and the
        # handler for a signal, which runs in this thread, could then not
        # wait for the child to stop.
        end = None if timeout is None else time.monotonic() + timeout
        try:
            while True:
                try:
                    out, err = child.communicate(input, timeout=0.5)
                    break
                except subprocess.TimeoutExpired:
                    if end is not None and time.monotonic() >= end:
                        raise
        except BaseException:
            stop_group(child.pid)
            try:
                child.communicate(timeout=5)
            except subprocess.TimeoutExpired:
                _close(child)
                child.wait()
            raise
        done = subprocess.CompletedProcess(argv, child.returncode, out, err)
    if check and done.returncode:
        raise subprocess.CalledProcessError(done.returncode, argv, out, err)
    return done


def stop_all(sig=signal.SIGTERM, grace=None, scan=True):
    """Send sig to every tracked group and, with scan, every other child of
    this process, wait up to grace for them, kill the rest."""
    grace = GRACE if grace is None else grace
    with _lock:
        tracked = list(_live.values())
    targets = {child.pid: child.pid for child in tracked}
    for pid, ppid, pgid, live in (_processes() or []) if scan else []:
        if ppid == os.getpid() and live:
            targets.setdefault(pid, pgid)
    _stop(list(targets.items()), sig, grace, tracked)
    for child in tracked:
        child.poll()
        with _lock:
            _live.pop(child.pid, None)


def _at_exit():
    """A program that has ended cleanly has nothing tracked, and then
    nothing to look for."""
    with _lock:
        tracked = bool(_live)
    if tracked:
        stop_all()


def _on_signal(num, _frame):
    global _handling
    if not _handling:
        _handling = True
        stop_all(num)
    sys.exit(128 + num)


def install():
    """Handlers for INT, TERM and HUP, and atexit. Call it from the main
    thread, first. It also makes the children start with the default for
    INT, which a test run in the background would otherwise pass on as
    ignored."""
    for sig in (signal.SIGINT, signal.SIGTERM, signal.SIGHUP):
        signal.signal(sig, _on_signal)
    atexit.register(_at_exit)


if __name__ == "__main__":
    if len(sys.argv) == 4 and sys.argv[1] == "stop-group" and sys.argv[2].isdigit() and sys.argv[3] in ("INT", "TERM", "HUP"):
        stop_group(int(sys.argv[2]), getattr(signal, "SIG" + sys.argv[3]))
    else:
        print("usage: toolproc.py stop-group PID INT|TERM|HUP", file=sys.stderr)
        sys.exit(2)
