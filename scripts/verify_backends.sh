#!/usr/bin/env bash
# verify_backends.sh —— T1.1/T1.2 端到端差分验证：
#   moon run src/backend_cli 产出语料的「解释器期望值 / 类型形状 / JS / wat」，
#   本脚本对每例：node 执行 JS 产物、wat2wasm 汇编后 node WebAssembly 执行
#   wasm 产物，两者输出与解释器期望值逐字符对拍。
# 依赖：moon、node、wat2wasm（wabt）。
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

moon run src/backend_cli > "$work/dump.txt"

# 按分隔符切分语料转储。
python3 - "$work" <<'EOF'
import sys, os, re
work = sys.argv[1]
text = open(f"{work}/dump.txt").read()
cases = re.split(r"^=====CASE (\d+)$", text, flags=re.M)[1:]
n = 0
for i in range(0, len(cases), 2):
    idx = cases[i]
    body = cases[i + 1].split("=====END")[0]
    def sect(name, nxt):
        m = re.search(rf"^-----{name}$\n(.*?)(?=^-----{nxt}$|\Z)", body, re.S | re.M)
        return m.group(1) if m else None
    src = sect("SRC", "EXPECTED")
    exp = sect("EXPECTED", "SHAPE")
    shape = sect("SHAPE", "JS")
    js = sect("JS", "WAT")
    wat = body.split("-----WAT\n", 1)[1]
    d = f"{work}/case{idx}"
    os.makedirs(d)
    open(f"{d}/src.txt", "w").write(src)
    open(f"{d}/expected.txt", "w").write(exp.strip() + "\n")
    open(f"{d}/shape.json", "w").write(shape.strip() + "\n")
    open(f"{d}/prog.js", "w").write(js)
    open(f"{d}/prog.wat", "w").write(wat)
    n += 1
print(f"split {n} cases")
EOF

# wasm 宿主：实例化模块、调用 main、按静态类型形状渲染结果。
cat > "$work/run_wasm.mjs" <<'EOF'
import { readFileSync } from "node:fs";
const [wasmPath, shapePath] = process.argv.slice(2);
const shape = JSON.parse(readFileSync(shapePath, "utf8"));
const { instance } = await WebAssembly.instantiate(readFileSync(wasmPath), {});
const mem = () => new Int32Array(instance.exports.memory.buffer);
const render = (v, s) => {
  if (s === "int") return String(v | 0);
  if (s === "bool") return v ? "true" : "false";
  if (s === "fun") return "<closure>";
  // ["tuple", ...]: v 为堆指针，[len, elems...]。
  const m = mem();
  const base = v >> 2;
  const parts = [];
  for (let i = 0; i < s.length - 1; i++) parts.push(render(m[base + 1 + i], s[i + 1]));
  return "(" + parts.join(", ") + ")";
};
console.log(render(instance.exports.main() | 0, shape));
EOF

pass=0; fail=0
for d in "$work"/case*; do
  idx=$(basename "$d")
  exp=$(cat "$d/expected.txt")
  jsout=$(node "$d/prog.js")
  wat2wasm "$d/prog.wat" -o "$d/prog.wasm"
  wasmout=$(node "$work/run_wasm.mjs" "$d/prog.wasm" "$d/shape.json")
  if [[ "$jsout" == "$exp" && "$wasmout" == "$exp" ]]; then
    pass=$((pass+1))
    printf 'PASS %s  src=%s  expected=%s\n' "$idx" "$(cat "$d/src.txt" | head -1)" "$exp"
  else
    fail=$((fail+1))
    printf 'FAIL %s  src=%s\n  expected=%s\n  js=%s\n  wasm=%s\n' \
      "$idx" "$(cat "$d/src.txt" | head -1)" "$exp" "$jsout" "$wasmout"
  fi
done
echo "----"
echo "verify_backends: $pass passed, $fail failed"
[[ $fail -eq 0 ]]
