# Rust `pathfinding` Comparison Report

- Generated at: `2026-06-21T13:08:32.4011034+00:00`
- Script: `scripts/rust_comparison.ps1`
- Sides: MoonBit `bench_rust/moon_side` (本库) vs Rust `bench_rust/` (`pathfinding` crate)
- Seed: `1311768467463790320` (decimal, 64-bit)
- Workload: BFS/Dijkstra/A* × sizes {`1000`} × avg out-degree {`4,16`} × `100` queries
- Sampling: warmup `5`, samples `30`, timeout `60s` per sample
- Machine: `Ubuntu 22.04.5 LTS`, `X64 x2`
- Toolchains: moon `moon 0.1.20260608 (60bc8c3 2026-06-08)  Feature flags enabled: rr_moon_mod,rr_moon_pkg`; `rustc 1.83.0 (90b35a623 2024-11-26)`; `cargo 1.83.0 (5ffbef321 2024-10-29)`; Rust lib `pathfinding 4.11.0`
- **Quick mode**: reduced matrix (smoke validation, not formal comparison evidence)

## Golden cross-check (R6.2)

✅ MATCH — 两侧黄金图样本逐元素一致（configs 规范化 JSON 相等）。

## Aggregate

- Median of per-case median speedups (MoonBit over Rust): **0.2498×** (>1 means MoonBit faster)
- Included cases: `6` / `6`

## Per-case comparison (median caliber, R6.6)

| Algorithm | Nodes | Deg | Edges | Rust median ms | MoonBit median ms | Speedup (Moon/Rust) | Included | Note |
|---|---:|---:|---:|---:|---:|---:|:--:|---|
| BFS | 1000 | 4 | 4000 | 1.9455 | 9.7402 | 0.1997× | ✅ |  |
| Dijkstra | 1000 | 4 | 4000 | 6.2033 | 30.0844 | 0.2062× | ✅ |  |
| A* | 1000 | 4 | 4000 | 7.7207 | 26.3169 | 0.2934× | ✅ |  |
| BFS | 1000 | 16 | 16000 | 1.8239 | 9.6784 | 0.1885× | ✅ |  |
| Dijkstra | 1000 | 16 | 16000 | 14.2975 | 47.1101 | 0.3035× | ✅ |  |
| A* | 1000 | 16 | 16000 | 15.8166 | 50.1069 | 0.3157× | ✅ |  |

## Methodology (R6.4)

- 输入生成：两侧共享逐位一致的 xorshift64 随机源与完全相同的确定性生成算法；边数 = 节点数 × 平均出度，按 (u,v,w) 顺序生成（自环改写为 (u+1)%n），查询按 (s,t) 顺序生成。
- 随机种子：1311768467463790320（十进制，64 位）；两侧用同一种子产出逐元素相同的图与查询集（黄金 JSON 交叉校验，R6.2）。
- 工作负载矩阵：BFS/Dijkstra/A* × 规模 {1000} × 平均出度 {4,16} × 每组 100 查询。
- A* 启发式：一般图上使用零启发式（admissible），等价一致代价搜索；两侧一致。
- 预热/测量：每用例 ≥5 预热 + ≥30 计时采样；单次采样 = 运行该用例全部查询一遍；计时单位毫秒。
- 加速比口径：统一以中位计时计算（本库中位 ÷ Rust 中位 → 本库相对 Rust 的加速；>1 表示本库更快）（R6.6）。
- 排除规则：失败 / 超时（单次采样 >60s）/ 两库结果不一致（结果签名不同）的用例标注并排除出加速比（R6.7）。
- 测量环境：见报告头部 CPU/OS 与两套工具链版本；跨机器/跨工具链对比显式标注且不据此声明加速比（R6.8）。

Raw artifacts: `rust-comparison-20260621-130832.json`, `latest-rust-comparison.json`.
