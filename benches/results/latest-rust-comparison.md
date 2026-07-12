# Rust `pathfinding` Comparison Report

- Generated at: `2026-07-12T16:15:47.7690303+00:00`
- Script: `scripts/rust_comparison.ps1`
- Sides: MoonBit `bench_rust/moon_side` (本库) vs Rust `bench_rust/` (`pathfinding` crate)
- Seed: `1311768467463790320` (decimal, 64-bit)
- Workload: BFS/Dijkstra/A* × sizes {`1000,10000,100000`} × avg out-degree {`4,16`} × `100` queries
- Sampling: warmup `5`, samples `30`, timeout `60s` per sample
- Machine: `Ubuntu 22.04.5 LTS`, `X64 x2`
- Toolchains: moon `moon 0.1.20260703 (6fbf8c3 2026-07-03)  Feature flags enabled: rr_moon_mod,rr_moon_pkg`; `rustc 1.83.0 (90b35a623 2024-11-26)`; `cargo 1.83.0 (5ffbef321 2024-10-29)`; Rust lib `pathfinding 4.11.0`

## Golden cross-check (R6.2)

✅ MATCH — 两侧黄金图样本逐元素一致（configs 规范化 JSON 相等）。

## Aggregate

- Median of per-case median speedups (MoonBit over Rust): **2.6733×** (>1 means MoonBit faster)
- Included cases: `18` / `18`

## Per-case comparison (median caliber, R6.6)

| Algorithm | Nodes | Deg | Edges | Rust median ms | MoonBit median ms | Speedup (Moon/Rust) | Included | Note |
|---|---:|---:|---:|---:|---:|---:|:--:|---|
| BFS | 1000 | 4 | 4000 | 1.616 | 0.6015 | 2.6867× | ✅ |  |
| Dijkstra | 1000 | 4 | 4000 | 5.3042 | 2.0229 | 2.622× | ✅ |  |
| A* | 1000 | 4 | 4000 | 6.5257 | 2.6989 | 2.4179× | ✅ |  |
| BFS | 1000 | 16 | 16000 | 1.5498 | 0.4995 | 3.1028× | ✅ |  |
| Dijkstra | 1000 | 16 | 16000 | 10.6675 | 4.181 | 2.5514× | ✅ |  |
| A* | 1000 | 16 | 16000 | 12.7914 | 4.8666 | 2.6284× | ✅ |  |
| BFS | 10000 | 4 | 40000 | 17.543 | 8.1939 | 2.141× | ✅ |  |
| Dijkstra | 10000 | 4 | 40000 | 55.0823 | 22.0044 | 2.5032× | ✅ |  |
| A* | 10000 | 4 | 40000 | 74.4612 | 27.5357 | 2.7042× | ✅ |  |
| BFS | 10000 | 16 | 160000 | 10.4297 | 3.9694 | 2.6275× | ✅ |  |
| Dijkstra | 10000 | 16 | 160000 | 133.7348 | 49.4862 | 2.7025× | ✅ |  |
| A* | 10000 | 16 | 160000 | 160.5688 | 54.4968 | 2.9464× | ✅ |  |
| BFS | 100000 | 4 | 400000 | 289.3024 | 112.3413 | 2.5752× | ✅ |  |
| Dijkstra | 100000 | 4 | 400000 | 1190.0679 | 347.9156 | 3.4206× | ✅ |  |
| A* | 100000 | 4 | 400000 | 1522.7894 | 424.7667 | 3.585× | ✅ |  |
| BFS | 100000 | 16 | 1600000 | 198.0335 | 74.4533 | 2.6598× | ✅ |  |
| Dijkstra | 100000 | 16 | 1600000 | 2613.1304 | 821.6417 | 3.1804× | ✅ |  |
| A* | 100000 | 16 | 1600000 | 3023.835 | 935.251 | 3.2332× | ✅ |  |

## MoonBit bidirectional bonus (no Rust counterpart; excluded from speedup)

Rust `pathfinding` crate 不提供双向 BFS/Dijkstra/A* API；以下为本库双向变体在同一工作负载上的计时，仅展示库能力，不计入同算法加速比。签名与本库单向结果逐元素交叉校验。

| Algorithm | Nodes | Deg | Edges | Moon uni median ms | Moon bidir median ms | Bidir vs uni | Signatures match |
|---|---:|---:|---:|---:|---:|---:|:--:|
| BFS-bidir | 1000 | 4 | 4000 | 0.6015 | 0.0366 | 16.4331× | ✅ |
| Dijkstra-bidir | 1000 | 4 | 4000 | 2.0229 | 0.3954 | 5.1159× | ✅ |
| A*-bidir | 1000 | 4 | 4000 | 2.6989 | 0.8293 | 3.2545× | ✅ |
| BFS-bidir | 1000 | 16 | 16000 | 0.4995 | 0.0609 | 8.1968× | ✅ |
| Dijkstra-bidir | 1000 | 16 | 16000 | 4.181 | 1.1163 | 3.7455× | ✅ |
| A*-bidir | 1000 | 16 | 16000 | 4.8666 | 1.3657 | 3.5633× | ✅ |
| BFS-bidir | 10000 | 4 | 40000 | 8.1939 | 0.2296 | 35.6812× | ✅ |
| Dijkstra-bidir | 10000 | 4 | 40000 | 22.0044 | 1.2659 | 17.3819× | ✅ |
| A*-bidir | 10000 | 4 | 40000 | 27.5357 | 2.3382 | 11.7765× | ✅ |
| BFS-bidir | 10000 | 16 | 160000 | 3.9694 | 0.2324 | 17.0797× | ✅ |
| Dijkstra-bidir | 10000 | 16 | 160000 | 49.4862 | 4.0892 | 12.1016× | ✅ |
| A*-bidir | 10000 | 16 | 160000 | 54.4968 | 5.4709 | 9.9613× | ✅ |
| BFS-bidir | 100000 | 4 | 400000 | 112.3413 | 1.6478 | 68.1746× | ✅ |
| Dijkstra-bidir | 100000 | 4 | 400000 | 347.9156 | 10.9143 | 31.877× | ✅ |
| A*-bidir | 100000 | 4 | 400000 | 424.7667 | 15.9507 | 26.6299× | ✅ |
| BFS-bidir | 100000 | 16 | 1600000 | 74.4533 | 2.8285 | 26.3225× | ✅ |
| Dijkstra-bidir | 100000 | 16 | 1600000 | 821.6417 | 17.7264 | 46.3512× | ✅ |
| A*-bidir | 100000 | 16 | 1600000 | 935.251 | 22.743 | 41.1226× | ✅ |

## Methodology (R6.4)

- 输入生成：两侧共享逐位一致的 xorshift64 随机源与完全相同的确定性生成算法；边数 = 节点数 × 平均出度，按 (u,v,w) 顺序生成（自环改写为 (u+1)%n），查询按 (s,t) 顺序生成。
- 随机种子：1311768467463790320（十进制，64 位）；两侧用同一种子产出逐元素相同的图与查询集（黄金 JSON 交叉校验，R6.2）。
- 工作负载矩阵：BFS/Dijkstra/A* × 规模 {1000,10000,100000} × 平均出度 {4,16} × 每组 100 查询。
- A* 启发式：一般图上使用零启发式（admissible），等价一致代价搜索；两侧一致。
- 同算法对齐：主对比表中两侧均为单向 BFS/Dijkstra/A*（本库使用 CSR indexed 快路径，Rust 侧使用 pathfinding crate 公开 API + 预构建邻接表）；本库双向变体（Rust crate 无对应 API）单独列为 bonus 表，不进入同算法加速比。
- 预热/测量：每用例 ≥5 预热 + ≥30 计时采样；单次采样 = 运行该用例全部查询一遍；计时单位毫秒。
- 加速比口径：统一以中位计时计算（本库中位 ÷ Rust 中位 → 本库相对 Rust 的加速；>1 表示本库更快）（R6.6）。
- 排除规则：失败 / 超时（单次采样 >60s）/ 两库结果不一致（结果签名不同）的用例标注并排除出加速比（R6.7）。
- 测量环境：见报告头部 CPU/OS 与两套工具链版本；跨机器/跨工具链对比显式标注且不据此声明加速比（R6.8）。

Raw artifacts: `rust-comparison-20260712-161547.json`, `latest-rust-comparison.json`.
