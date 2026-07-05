# Rust `pathfinding` Comparison Report

- Generated at: `2026-07-05T13:11 UTC`
- Sides: MoonBit `bench_rust/moon_side` (本库，已接入 indexed 快路径：
  CSR + 扁平数组 + 4 叉编码堆 + 可复用 SearchCtx/BfsCtx + 小整数权
  Dial 桶队列 + 桶式 Dial A*) vs Rust `bench_rust/` (`pathfinding` crate 4.11.0)
- Seed: `1311768467463790320` (decimal, 64-bit)
- Workload: BFS/Dijkstra/A* × sizes {`1000,10000`} × avg out-degree
  {`4,16`} × `100` queries
- Sampling: warmup `5`, samples `30`, timeout `60s` per sample
- Machine: `Ubuntu 22.04.5 LTS`, `X64 x2`
- Toolchains: moon `0.1.20260608` release native; `rustc 1.83.0` release;
  Rust lib `pathfinding 4.11.0`

## Golden cross-check (R6.2)

✅ MATCH — 两侧黄金图样本逐元素一致（configs 规范化 JSON 相等）。

## Aggregate

- Median of per-case median speedups (MoonBit over Rust): **2.45×**
  (>1 means MoonBit faster；2026-06-21 采集为 0.2498×)
- Included cases: `12` / `12`（全部结果签名逐元素一致）

## Per-case comparison (median caliber, R6.6)

| Algorithm | Nodes | Deg | Rust median ms | MoonBit median ms | Speedup (Moon/Rust) | Included |
|---|---:|---:|---:|---:|---:|:--:|
| BFS | 1000 | 4 | 1.608 | 0.603 | **2.67×** | ✅ |
| Dijkstra | 1000 | 4 | 5.285 | 2.606 | **2.03×** | ✅ |
| A* | 1000 | 4 | 6.579 | 3.328 | **1.98×** | ✅ |
| BFS | 1000 | 16 | 1.502 | 0.502 | **2.99×** | ✅ |
| Dijkstra | 1000 | 16 | 10.749 | 5.205 | **2.07×** | ✅ |
| A* | 1000 | 16 | 12.618 | 5.613 | **2.25×** | ✅ |
| BFS | 10000 | 4 | 17.515 | 7.508 | **2.33×** | ✅ |
| Dijkstra | 10000 | 4 | 55.104 | 21.861 | **2.52×** | ✅ |
| A* | 10000 | 4 | 75.213 | 28.124 | **2.67×** | ✅ |
| BFS | 10000 | 16 | 10.414 | 4.390 | **2.37×** | ✅ |
| Dijkstra | 10000 | 16 | 136.924 | 51.963 | **2.61×** | ✅ |
| A* | 10000 | 16 | 159.338 | 57.935 | **2.75×** | ✅ |

## Methodology (R6.4)

- 输入生成：两侧共享逐位一致的 xorshift64 随机源与完全相同的确定性生成算法；边数 = 节点数 × 平均出度，按 (u,v,w) 顺序生成（自环改写为 (u+1)%n），查询按 (s,t) 顺序生成。
- 随机种子：1311768467463790320（十进制，64 位）；两侧用同一种子产出逐元素相同的图与查询集（黄金 JSON 交叉校验，R6.2）。
- 工作负载矩阵：BFS/Dijkstra/A* × 规模 {1000,10000} × 平均出度 {4,16} × 每组 100 查询。
- A* 启发式：一般图上使用零启发式（admissible），等价一致代价搜索；两侧一致。
- 预热/测量：每用例 ≥5 预热 + ≥30 计时采样；单次采样 = 运行该用例全部查询一遍；计时单位毫秒。
- 加速比口径：统一以中位计时计算（本库中位 ÷ Rust 中位 → 本库相对 Rust 的加速；>1 表示本库更快）（R6.6）。
- 排除规则：失败 / 超时（单次采样 >60s）/ 两库结果不一致（结果签名不同）的用例标注并排除出加速比（R6.7）。
- 测量环境：见报告头部 CPU/OS 与两套工具链版本；同机同轮采集。

历史与增量证据：`rust-comparison-indexed-20260705.md`（逐层优化过程），
2026-06-21 原始采集：`rust-comparison-20260621-130832.json`。
