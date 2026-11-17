# Writing tuned values into tune.lua (tools/bake_tune.py), on a copy of the
# real file. Run from the repository root: python3 -I tests/test_bake.py
import copy
import os
import shutil
import sys
import tempfile

sys.path.insert(0, os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "tools"))
import bake_tune as B

failures = 0


def check(cond, msg):
    global failures
    if not cond:
        failures += 1
        sys.stderr.write("FAIL: " + msg + "\n")


tmp = tempfile.mkdtemp()
try:
    path = os.path.join(tmp, "tune.lua")
    shutil.copy(B.TUNE, path)
    with open(path) as f:
        original = f.read()
    old = B.read_tune(path)
    new = copy.deepcopy(old)
    # A number, a range, a choice, a curve; a range inside a one-line look
    # and one inside a two-line bloom style; and hero.petals, whose key
    # also appears in every bloom style, which must not move.
    new["gesture"]["edge"] = 0.31
    new["gesture"]["bow_amp"] = [0.25, 0.375]
    new["hero"]["style"] = "round"
    new["hero"]["petals"] = 6
    new["color"]["looks"]["fan"]["tip_l"] = [0.3, 0.45]
    new["blooms"]["fan"]["rays"] = [20, 40]
    new["sizes"]["leaf"] = {"range": [0.4, 1.2], "points": [[0, 0.2], [0.4, 1], [1, 0.1]]}
    want = {"gesture.edge", "gesture.bow_amp", "hero.style", "hero.petals", "color.looks.fan.tip_l",
            "blooms.fan.rays", "sizes.leaf"}

    changed = B.bake(new, path)
    check(set(changed) == want, f"changed {sorted(changed)}")
    back = B.read_tune(path)
    for p in want:
        check(B._same(B._get(back, p), B._get(new, p)), f"{p} reads back as {B._get(back, p)}")
    for style in back["blooms"]:
        check(back["blooms"][style]["petals"] == old["blooms"][style]["petals"], f"blooms.{style}.petals moved")
    with open(path) as f:
        text = f.read()
    a, b = original.splitlines(), text.splitlines()
    check(len(a) == len(b), "line count changed")
    differ = sum(1 for x, y in zip(a, b) if x != y)
    check(differ <= len(want), f"{differ} lines differ for {len(want)} settings")
    for line in a:
        if "--" in line:
            comment = line[line.index("--"):]
            check(comment in text, f"comment lost: {comment}")
    check(B.bake(new, path) == [], "a second write changes nothing")
    check(B.literal([0.25, 0.375]) == "{ 0.25, 0.375 }", B.literal([0.25, 0.375]))
    check(B.literal(1.0) == "1", B.literal(1.0))
    # Keys are matched at their own table's depth: a nested `x` that comes
    # first is not the top-level `x`.
    small = os.path.join(tmp, "small.lua")
    with open(small, "w") as f:
        f.write("-- test\nlocal T = {\n  a = { x = 1 }, -- nested x\n  x = 2,\n}\nreturn T\n")
    check(B.bake({"a": {"x": 1}, "x": 3}, small) == ["x"], "small table: wrong paths")
    back = B.read_tune(small)
    check(back == {"a": {"x": 1}, "x": 3}, f"small table reads back as {back}")
finally:
    shutil.rmtree(tmp)

if failures:
    sys.stderr.write(f"bake: {failures} failure(s)\n")
    sys.exit(1)
print("bake: ok")
