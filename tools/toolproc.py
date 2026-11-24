"""The one way the tools and their tests start a process.

tests/test_tools.py and tests/test_tools_matrix.py run the runner, the
profiler and the rest, some of them in parallel and some of them
supervisors that start processes of their own; tools/lint.py and
tools/test_times.py run programs too. However such a test ends
(finished, failed, an exception in it, INT, TERM or HUP) no process it
started may be left running, those the tools started in turn included.

Every child is started here, in a session of its own, and is tracked
until it has been waited for. On INT, TERM or HUP (install) the signal is
sent on to every tracked group, which lets a supervisor like tools/test.sh
stop what it started; the children are waited for up to GRACE seconds, what
did not obey is killed, and the test ends with status 128 plus the signal's
number. atexit does the same for an exception that ends the test. When a
child has been waited for, what it left in its group is killed.

A script run with python3 -I outside tools/ imports it with sys.path.insert
of tools/. tests/test_tools.py fails when one of the two tool tests calls
subprocess or starts a group of its own anywhere else.
"""

import atexit
import os
import signal
import subprocess
import sys
import threading
import time

GRACE = 15.0
_lock = threading.Lock()
_live = {}
_handling = False


def _killpg(pid, sig):
    try:
        os.killpg(pid, sig)
    except (ProcessLookupError, PermissionError):
        pass


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


def run(argv, timeout=None, input=None, check=False, capture_output=False, **kw):
    """subprocess.run, tracked; a child that outlives the timeout is killed
    with its group."""
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
            _killpg(child.pid, signal.SIGKILL)
            child.communicate()
            raise
        done = subprocess.CompletedProcess(argv, child.returncode, out, err)
    if check and done.returncode:
        raise subprocess.CalledProcessError(done.returncode, argv, out, err)
    return done


def stop_all(sig=signal.SIGTERM, grace=GRACE):
    """Send sig to every tracked group, wait for the children, kill the
    rest."""
    with _lock:
        children = list(_live.values())
    for child in children:
        _killpg(child.pid, sig)
    deadline = time.monotonic() + grace
    for child in children:
        try:
            child.wait(timeout=max(0.0, deadline - time.monotonic()))
        except subprocess.TimeoutExpired:
            pass
    for child in children:
        _killpg(child.pid, signal.SIGKILL)
        try:
            child.wait(timeout=5)
        except subprocess.TimeoutExpired:
            pass
        with _lock:
            _live.pop(child.pid, None)


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
    atexit.register(stop_all)
