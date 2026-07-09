#!/usr/bin/env python3
"""compat_gate.py —— 发布流水线自动兼容性 diff 门禁（G-A2 自动化收口）。

与 src/release_aggregate/compat_diff.mbt 的语义内核一致（cargo-semver-checks /
Go apidiff 思路），作用对象为全仓 `pkg.generated.mbti` API 表面：

  1. 基线定位：最近一次 `moon.mod` 中 `version = ...` 行发生变化的提交 C
     （当前版本引入点），其父提交 P 即上一发布的 API 表面基线；
  2. 表面 diff：P 与工作树的全部 .mbti 逐行集合比较——
     删除/修改既有声明行 → 破坏性（要求 MAJOR）；仅新增 → MINOR；无变化 → PATCH；
  3. 实际档位：P 的版本号 → 当前版本号的升级档位；
  4. 判定：实际档位必须覆盖要求档位，否则非零退出并输出违规见证。

0.x 约定（与 cargo-semver-checks 一致）：major==0 时 minor 位承担破坏性升级
档位（0.y.z → 0.(y+1).0 视为 MAJOR 级），major==0 且 minor==0 时每个 patch
均可含破坏性变更（任何单调升级均覆盖）。
"""

import re
import subprocess
import sys

ROOT = subprocess.run(
    ["git", "rev-parse", "--show-toplevel"], capture_output=True, text=True
).stdout.strip()


def run(args):
    return subprocess.run(args, capture_output=True, text=True, cwd=ROOT)


def read_version(blob):
    m = re.search(r'^version\s*=\s*"([^"]+)"', blob, re.M)
    return m.group(1) if m else None


def parse_semver(v):
    m = re.match(r"^(\d+)\.(\d+)\.(\d+)", v or "")
    return tuple(int(g) for g in m.groups()) if m else None


def surfaces_at(ref):
    """ref 为 None 时读工作树；否则读指定提交。返回 {path: set(lines)}。"""
    if ref is None:
        ls = run(["git", "ls-files", "*.mbti"]).stdout.splitlines()
    else:
        ls = [
            p
            for p in run(["git", "ls-tree", "-r", "--name-only", ref]).stdout.splitlines()
            if p.endswith(".mbti")
        ]
    out = {}
    for path in ls:
        if not path.endswith("pkg.generated.mbti"):
            continue
        if ref is None:
            with open(f"{ROOT}/{path}", encoding="utf-8") as f:
                text = f.read()
        else:
            text = run(["git", "show", f"{ref}:{path}"]).stdout
        lines = {ln.strip() for ln in text.splitlines() if ln.strip() and not ln.startswith("//")}
        out[path] = lines
    return out


LEVELS = {"PATCH": 0, "MINOR": 1, "MAJOR": 2}


def actual_bump(old, new):
    """semver 档位（0.x 按 rank-shift 约定）。非单调返回 None。"""
    o, n = parse_semver(old), parse_semver(new)
    if o is None or n is None or n <= o:
        return None
    if o[0] == 0 and n[0] == 0:
        if o[1] == 0 and n[1] == 0:
            return "MAJOR"  # 0.0.x：每个 patch 均可含破坏性变更
        if n[1] > o[1]:
            return "MAJOR"  # 0.y → 0.(y+1)：minor 位承担 MAJOR 档
        return "MINOR"  # 0.y.z → 0.y.(z+1)
    if n[0] > o[0]:
        return "MAJOR"
    if n[1] > o[1]:
        return "MINOR"
    return "PATCH"


def main():
    with open(f"{ROOT}/moon.mod", encoding="utf-8") as f:
        cur_ver = read_version(f.read())
    if cur_ver is None:
        print("compat_gate: cannot read version from moon.mod")
        return 1

    bump_commit = run(
        ["git", "log", "-1", "--format=%H", "-G", "^version = ", "--", "moon.mod"]
    ).stdout.strip()
    if not bump_commit:
        print("compat_gate: no version-bump commit found; trivially pass (initial release).")
        return 0
    baseline = f"{bump_commit}^"
    prev_mod = run(["git", "show", f"{baseline}:moon.mod"]).stdout
    if not prev_mod:
        prev_mod = run(["git", "show", f"{baseline}:moon.mod.json"]).stdout
        prev_ver = None
        m = re.search(r'"version"\s*:\s*"([^"]+)"', prev_mod)
        if m:
            prev_ver = m.group(1)
    else:
        prev_ver = read_version(prev_mod)
    if prev_ver is None:
        print(f"compat_gate: cannot read baseline version at {baseline[:12]}; pass.")
        return 0

    old_s, new_s = surfaces_at(baseline), surfaces_at(None)
    removed, changed, added = [], [], []
    for path, old_lines in old_s.items():
        new_lines = new_s.get(path)
        if new_lines is None:
            removed.append(f"{path} (package removed)")
            continue
        gone = old_lines - new_lines
        fresh = new_lines - old_lines
        if gone:
            changed.append(f"{path}: -{len(gone)} decl line(s), e.g. `{sorted(gone)[0][:100]}`")
        elif fresh:
            added.append(f"{path}: +{len(fresh)} decl line(s)")
    for path in new_s:
        if path not in old_s:
            added.append(f"{path} (new package)")

    if removed or changed:
        required = "MAJOR"
    elif added:
        required = "MINOR"
    else:
        required = "PATCH"
    actual = actual_bump(prev_ver, cur_ver)

    print(f"compat_gate: baseline {baseline[:12]} ({prev_ver}) -> HEAD ({cur_ver})")
    print(f"compat_gate: surface diff: {len(removed)} removed, {len(changed)} changed, {len(added)} added package surface(s)")
    print(f"compat_gate: required bump = {required}, actual bump = {actual}")
    for msg in (removed + changed)[:10]:
        print(f"  breaking: {msg}")
    for msg in added[:10]:
        print(f"  added:    {msg}")

    if actual is None:
        print(f"compat_gate FAIL: invalid or non-increasing version {prev_ver} -> {cur_ver}")
        return 1
    if LEVELS[actual] < LEVELS[required]:
        print(f"compat_gate FAIL: {required} bump required but version bump only covers {actual}")
        return 1
    print("compat_gate: PASS — actual bump covers required bump.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
