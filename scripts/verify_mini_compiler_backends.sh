#!/usr/bin/env bash
# 验证 compile(TypedAst, Backend) 的 wasm 二进制与 JS 产物可真实执行。
set -euo pipefail
cd "$(dirname "$0")/.."
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

moon run src/mini_compiler_backend_cli > "$work/dump.txt"
python3 - "$work" <<'EOF'
from pathlib import Path
import re
import sys

work = Path(sys.argv[1])
text = (work / "dump.txt").read_text()
pattern = re.compile(
    r"=====CASE ([^\n]+)\n"
    r"-----EXPECTED\n(.*?)\n"
    r"-----WASM_HEX\n(.*?)\n"
    r"-----JS\n(.*?)"
    r"=====ENDCASE",
    re.S,
)
cases = pattern.findall(text)
if not cases:
    raise SystemExit("no mini compiler backend cases found")
for name, expected, wasm_hex, js in cases:
    case = work / name
    case.mkdir()
    (case / "expected.txt").write_text(expected + "\n")
    (case / "program.wasm").write_bytes(bytes.fromhex(wasm_hex.strip()))
    (case / "program.js").write_text(js)
EOF

pass=0
for case in "$work"/*/; do
  js_out=$(node "$case/program.js")
  wasm_out=$(node -e '
const fs = require("fs");
WebAssembly.instantiate(fs.readFileSync(process.argv[1]), {}).then(({instance}) => {
  console.log(instance.exports.main() | 0);
});
' "$case/program.wasm")
  expected=$(cat "$case/expected.txt")
  [[ "$js_out" == "$expected" ]]
  [[ "$wasm_out" == "$expected" ]]
  pass=$((pass+1))
  echo "PASS $(basename "$case") js=$js_out wasm=$wasm_out"
done
echo "verify_mini_compiler_backends: $pass passed"
