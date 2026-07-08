#!/usr/bin/env python3
# gen_vectors.py —— Luhn 黄金向量再生脚本（参考实现：ISO/IEC 7812-1 附录 B）。
# 输出 vectors/luhn.psv：`号码|valid/invalid` 或 `主体|check:<校验位>`。
import os


def luhn_sum(s: str) -> int:
    ds = [int(c) for c in s]
    total = 0
    n = len(ds)
    for i, pos in enumerate(range(n - 1, -1, -1)):
        d = ds[pos]
        if i % 2 == 1:
            d *= 2
            if d > 9:
                d -= 9
        total += d
    return total


VALIDITY = [
    "79927398713", "49927398716", "49927398717",
    "1234567812345670", "4111111111111111", "378282246310005",
]
CHECK = ["7992739871", "411111111111111", "123456781234567"]

out = []
for s in VALIDITY:
    out.append(f"{s}|{'valid' if luhn_sum(s) % 10 == 0 else 'invalid'}")
for p in CHECK:
    out.append(f"{p}|check:{(10 - luhn_sum(p + '0') % 10) % 10}")

path = os.path.join(os.path.dirname(__file__), "..", "vectors", "luhn.psv")
with open(path, "w") as f:
    f.write("\n".join(out) + "\n")
print(f"wrote {len(out)} vectors to {path}")
