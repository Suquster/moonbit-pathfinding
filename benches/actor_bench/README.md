# benches/actor_bench — Actor_Framework 性能基准与回归 guard

方向十（Actor_Framework）的可复现性能基准包，覆盖**五类代表性负载**，输出含
机器标识 / 后端目标 / 负载规模 / 计时统计的 JSON 工件，并内置**回归 guard**：将一次
运行的中位数（median）与记入的基线中位数比较，超声明容差时产出可审计的失败报告。

- 实现：`benches/actor_bench/actor_bench.mbt`
- 后端标识：`actor_bench_backend_{wasm,js,native}.mbt`（经 `moon.pkg` 的
  `options(targets:)` 按当前编译后端注入「后端目标」字段）
- _Requirements: 12.1, 12.2, 12.3, 12.4, 12.5_

---

## 一、五类工作负载与负载参数

负载参数全部以**命名常量**记录于 `actor_bench.mbt`，禁止 magic number。下表参数与
常量一一对应（单位：计时统计为微秒 µs）。

| # | 负载 | bench 行名 | 负载参数（命名常量 = 值） |
|---|------|-----------|---------------------------|
| ① | 高频 `send` | `actor_send_<N>` | `send_workload_msgs = 5000`（单 actor 入队并串行消费的消息条数） |
| ② | 海量 actor 调度 | `actor_scheduling_<A>x<M>` | `massive_actor_count = 200`、`massive_msgs_per_actor = 50`（总调度量 = 200 × 50 = 10000） |
| ③ | ask 往返 | `actor_ask_roundtrip_<N>` | `ask_roundtrip_count = 500`、`ask_step_budget = 8`（单次 ask 的驱动步数预算） |
| ④ | 路由分发 | `actor_router_{round_robin,broadcast,consistent_hash}_<N>` | `router_worker_count = 8`、`router_dispatch_msgs = 2000`（三种 `RoutingStrategy` 各一行） |
| ⑤ | 监督重启 | `actor_supervision_restart_<W>x<T>` | `supervision_worker_count = 8`、`supervision_task_count = 400`、`supervision_fault_at = 17`、`supervision_seed = 0x9E3779B97F4A7C15` |

工件采样次数由 `artifact_sample_count = 3` 控制（保持工件生成轻量）。

---

## 二、运行命令

### 1. 原生 `moon bench`（逐负载计时）

> **native 后端运行前必须先执行**（缺失会导致链接失败）：
>
> ```bash
> export LIBRARY_PATH=/usr/lib64:/usr/lib   # R12.4 / R15.4
> ```

```bash
# native（须先 export LIBRARY_PATH，见上）
export LIBRARY_PATH=/usr/lib64:/usr/lib
moon bench benches/actor_bench --target native

# 其它后端
moon bench benches/actor_bench --target wasm-gc
moon bench benches/actor_bench --target js
```

### 2. JSON 工件（含机器标识 / 后端目标 / 负载规模 / 计时统计，R12.2）

工件由 `render_actor_bench_artifact` 产出，并在
`test "artifact: actor_bench emits machine/backend/scale/timing json"` 中 `println`
留痕，任一后端的 `moon test` 即可采集：

```bash
moon test benches/actor_bench --target wasm-gc   # 控制台打印 JSON 工件
moon test benches/actor_bench --target js
export LIBRARY_PATH=/usr/lib64:/usr/lib
moon test benches/actor_bench --target native
```

### 3. 三后端 smoke / guard 测试（每次提交均应通过）

```bash
moon test benches/actor_bench --target wasm-gc
moon test benches/actor_bench --target js
export LIBRARY_PATH=/usr/lib64:/usr/lib       # native 前置
moon test benches/actor_bench --target native
```

---

## 三、回归 guard（R12.3）

guard 将一次运行的**中位数**与记入的**基线中位数**比较，超出**声明容差**即判回归并
产出可审计的失败报告。

- **基线表**（命名常量，`actor_bench.mbt`，单位 µs）：

  | 负载 | 基线常量 = 值（µs） |
  |------|---------------------|
  | ① 高频 send | `baseline_send_us = 1500.0` |
  | ② 海量调度 | `baseline_scheduling_us = 4000.0` |
  | ③ ask 往返 | `baseline_ask_us = 900.0` |
  | ④ 路由分发 | `baseline_router_us = 1800.0` |
  | ⑤ 监督重启 | `baseline_supervision_us = 1200.0` |

- **声明容差**：`bench_guard_tolerance_ratio = 0.50`（+50%）。判定式：实测中位数
  `> baseline × (1 + tolerance)` 即判回归。

  > 注意：基线值依赖运行机器，此处为**示意 / 可更新基线**（不同机器请按实测重新声明）。
  > guard 的**判定逻辑本身与基线数值无关、确定性可测**。

- **可审计失败报告**（结构化文本，列出负载名、基线、实测、容差、允许上限、相对增幅、
  是否回归），示例：

  ```text
  ACTOR-BENCH REGRESSION GUARD (timing unit: microseconds)
  schema=moonbit-pathfinding.actor-bench.v1 machine_id=... backend=wasm-gc
  columns: workload | baseline_us | measured_us | tolerance_pct | allowed_us | delta_pct | verdict
  high_frequency_send | 1500 | 470 | 50% | 2250 | -69% | OK
  massive_actor_scheduling | 4000 | 9597 | 50% | 6000 | 140% | REGRESSED
  ...
  status: FAIL
  ```

- **测试见证**：
  - `test "guard: regression verdict and audit report are deterministic on synthetic medians"`
    —— 以**确定性合成数值**断言比较判定与报告内容，三后端稳定通过（不依赖真实墙钟计时）。
  - `test "guard: emits auditable report comparing live run to recorded baselines"`
    —— 采集一次真实运行的中位数、与基线比较并 `println` 报告留痕；仅断言报告结构
    （标题 / 状态行 / 五类负载齐备），**不**对 PASS/FAIL 结论断言（结论随机器而异，
    避免真实计时引入 flaky）。

---

## 四、复现性说明

- 所有负载规模、基线与容差均为命名常量，改动需同步本文件表格。
- 计时单位统一为**微秒（microseconds）**，与 JSON 工件 `timing_unit` 字段一致。
- 工件含 `machine_id`（运行环境标识）与 `backend_target`（编译后端），便于跨环境审计。
- 本基准为**本机算法级回归证据**，不构成跨语言加速比声明。
