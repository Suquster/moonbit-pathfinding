# bench_rust —— 与 Rust `pathfinding` crate 的对比基准（Requirement 6）

本目录实现 OSC 2026 冠军级升级方向 2「性能冠军」中的 **跨语言对比基础设施**：
将本库（MoonBit `moonbit-pathfinding`）与成熟的 Rust [`pathfinding`](https://crates.io/crates/pathfinding)
crate 在 **等价工作负载** 上做可复现对比，并产出对比报告（Markdown + JSON）。

## 目录结构

| 路径 | 说明 |
|---|---|
| `Cargo.toml` / `src/main.rs` | Rust 侧采集器（Cargo 工程，依赖 `pathfinding` crate） |
| `moon_side/` | 本库（MoonBit）侧采集器（主包，调用既有 `@unweighted`/`@directed`） |
| `../scripts/rust_comparison.ps1` | 编排器：构建、采集、黄金交叉校验、对比报告 |

## 等价输入与黄金交叉校验（R6.2）

两侧共享 **逐位一致的 xorshift64 随机源**（与 `src/infra_pbt` 的 `Rng` 完全一致）
与 **完全相同的确定性生成算法**：

- 边数 `m = n × 平均出度`，按 `(u, v, w)` 顺序生成；`u = next_below(n)`、
  `v = next_below(n)`（若 `v == u` 改写为 `(u+1) % n` 以规避自环）、`w = next_range(1, 100)`。
- 查询按 `(s, t)` 顺序生成，`s = next_below(n)`、`t = next_below(n)`。

`--mode golden` 让两侧各输出「黄金 JSON 图样本」，编排器逐元素比对（不一致即门禁失败），
从而证明两侧输入逐元素相同（R6.2）。

## 工作负载矩阵与采样（R6.1 / R6.3）

- 算法：BFS、Dijkstra、A\*（A\* 在一般图上使用 **零启发式**，admissible，等价一致代价搜索，两侧一致）。
- **同算法对齐**：主对比表两侧均为 **单向** BFS/Dijkstra/A\*（本库 CSR indexed 快路径 vs
  Rust `pathfinding` crate 公开 API + 预构建邻接表）；本库 **双向变体**（Rust crate 无对应
  API）单独列为 bonus 表并与本库单向签名逐元素交叉校验，**不进入同算法加速比**。
- 规模：`{1000, 10000, 100000}` 节点；平均出度 `{4, 16}`；每组 `≥100` 查询。
- 采样：每用例 `≥5` 预热 + `≥30` 计时样本；单次采样 = 运行该用例全部查询一遍。
- 结果签名：每条查询记录跳数（BFS）或路径代价（Dijkstra/A\*）；两侧签名逐元素比对做一致性校验。

## 加速比口径与排除规则（R6.6 / R6.7 / R6.8）

- 加速比统一以 **中位计时** 计算（本库中位 ÷ Rust 中位 → 本库相对 Rust 的加速；>1 表示本库更快）。
- 失败 / 超时（单次采样 >60s）/ 两库结果不一致（签名不同）的用例 **标注并排除** 出加速比。
- 跨机器 / 跨工具链对比 **显式标注且不据此声明加速比**。

## 运行

```bash
# 完整矩阵（在 release 模式下采集，含黄金交叉校验）
pwsh scripts/rust_comparison.ps1

# 快速烟雾验证（缩小矩阵；方法学不变，仅用于本地/CI 验证）
pwsh scripts/rust_comparison.ps1 -Quick -Sizes 1000 -Degrees 4,16 -Queries 100
```

产物写入 `benches/results/`：`latest-rust-comparison.md` 与 `latest-rust-comparison.json`
（含完整方法学声明、CPU/OS 与两套工具链版本、逐用例对比与排除标注）。

### 单独运行某一侧采集器

```bash
# Rust 侧
cargo run --release -- --mode bench --seed 1311768467463790320 \
  --sizes 1000,10000,100000 --degrees 4,16 --queries 100 --warmup 5 --samples 30 --out rust.json

# 本库（MoonBit）侧
moon run bench_rust/moon_side --target native --release -- \
  --mode bench --seed 1311768467463790320 --sizes 1000,10000,100000 --degrees 4,16 \
  --queries 100 --warmup 5 --samples 30
```

## 计时单位说明

- Rust 侧：`std::time::Instant`，毫秒。
- 本库侧：`@moonbitlang/core/bench` 单调时钟。经校准，**native 后端返回微秒**
  （300M 次循环原始读数 ≈ 2.70e6，对应 wall-clock ≈ 2.7s），故毫秒 = 原始读数 / 1000。

## 可复现性（R6.5）

- 依赖固定版本（`pathfinding = 4.11.0`，与 Rust 1.83 工具链兼容；`Cargo.lock` 已签入）。
- 相同种子与参数重跑，本库侧中位计时与报告值的相对差异应 ≤15%。
- 工具链缺失（cargo / moon）时编排器给出明确告警并优雅降级，不静默崩溃。
