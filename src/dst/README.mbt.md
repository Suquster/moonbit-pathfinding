# dst · 可执行文档

> **方向八（R8）确定性仿真测试框架（DST_Framework）** — 种子驱动 · 同种子同执行 · 故障注入 · 可重放 · 三后端一致 · 文档即测试。
>
> 本文件既是 `dst` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/dst/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）** 与 **R8.2（确定性可重放不变量）**，
tasks.md **任务 13.4**。

本文件作为 `dst` 包的黑盒测试运行，可直接调用本包公开 API
（`run` / `replay` / `Scenario::new` / `Task::new` / `FaultPolicy::new` / `rng_new` 等）
而无需限定包名。下面 4 段示例覆盖 **确定性可重放 → 随机源序列 → 故障注入 → 失败重放**
的端到端用法。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。
>
> **关于类型构造**：黑盒 `.mbt.md` 对「表达式位置直接构造结构体」有限制，因此本文档
> 统一通过公开构造函数（`Task::new` / `Scenario::new` / `FaultPolicy::new` / `rng_new`）
> 创建输入数据，并以 `match` 解构终态 `SimStatus`。

---

## 核心概念（concepts）

一次仿真由若干 **任务 `Task`** 组成；`run(seed, scenario)` 以 **种子 `seed`** 驱动一个
确定性随机源，按确定性顺序调度任务并产出 **事件轨迹 `trace`**，最终给出 **终态 `SimStatus`**
（`Completed` 正常完成 / `Failed` 失败）。**故障策略 `FaultPolicy`** 在指示注入点对目标任务
触发故障（崩溃 `Crash` / 延迟 `Delay` / 丢弃 `Drop`）。「`seed` + `trace`」构成可重放凭据：
`replay(seed, trace)` 复现完全相同的结果。

核心价值：**同种子 → 同执行**——相同种子的两次运行产生逐事件一致的调度序列与终态。

---

## 示例 1 · 同种子两次运行产生一致调度序列（R8.2）

`run(seed, scenario)` 对同一种子保证**逐事件一致的调度序列与相同终态**（满足 **R8.2**）。
`SimResult` 派生 `Eq`，故两次运行结果可整体逐项比对。下例以同一种子运行同一场景两次，
验证事件轨迹与终态完全一致——这正是确定性可重放的基石。

```mbt check
///|
test "README · 同种子两次运行结果逐事件一致" {
  let tasks = [
    Task::new(0, "build"),
    Task::new(1, "test"),
    Task::new(2, "lint"),
    Task::new(3, "package"),
  ]
  let scenario = Scenario::new(tasks, [], 16)
  // 同种子两次运行。
  let first = run(0xDEAD_BEEF, scenario)
  let second = run(0xDEAD_BEEF, scenario)
  // 调度序列（事件轨迹）逐事件一致。
  assert_true(first.trace == second.trace)
  // SimResult 整体（种子 + 轨迹 + 终态）逐项一致。
  assert_eq(first, second)
  // 无故障场景：终态为 Completed，四个任务全部完成。
  match first.status {
    Completed => ()
    Failed(reason~) => fail("预期 Completed，实际 Failed：\{reason}")
  }
}
```

调度序列**不依赖输入任务的排列**：`run` 以任务 id 升序规范化待调度集合，因此正序与逆序
的同一任务集在同种子下产生一致结果。

```mbt check
///|
test "README · 调度序列与输入任务排列无关" {
  let forward = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  let reversed = [Task::new(2, "c"), Task::new(1, "b"), Task::new(0, "a")]
  let r1 = run(42, Scenario::new(forward, [], 8))
  let r2 = run(42, Scenario::new(reversed, [], 8))
  assert_eq(r1, r2)
}
```

---

## 示例 2 · 种子驱动的确定性随机源 `rng_new`

确定性来自种子驱动的伪随机源：`rng_new(seed)` 构造随机源，`next` / `next_below` 推进并产出
随机字。同种子产生**逐位一致**的序列（采用 xorshift64：仅移位 + 异或，三后端逐位一致），
这是「同种子 → 同执行」的底层保证。

```mbt check
///|
test "README · rng_new 同种子产生逐位一致序列" {
  let a = rng_new(0xC0FFEE)
  let b = rng_new(0xC0FFEE)
  // 两个同种子随机源逐字一致。
  for _ in 0..<5 {
    assert_eq(a.next(), b.next())
  }
  // next_below 将随机字约束到 [0, n)，供调度器从待运行任务集选择下一任务。
  let r = rng_new(7)
  for _ in 0..<10 {
    let k = r.next_below(4)
    assert_true(k >= 0 && k < 4)
  }
}
```

---

## 示例 3 · 故障注入 —— 崩溃令终态为 Failed（R8.4）

`FaultPolicy::new(at_step, task_id, kind)` 描述「在第 `at_step` 步对任务 `task_id` 注入 `kind`
故障」。崩溃故障 `Crash` 在命中注入点触发后，目标任务被移出调度集合且整体终态判定为
`Failed`，其余任务仍正常完成（崩溃隔离）。下例在第 0 步令任务 1 崩溃。

```mbt check
///|
test "README · 崩溃故障使运行失败且隔离其余任务" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  // 第 0 步对任务 1 注入崩溃故障。
  let faults = [FaultPolicy::new(0, 1, FaultKind::Crash)]
  let result = run(123, Scenario::new(tasks, faults, 16))
  // 终态为 Failed，原因引用崩溃任务与步序号。
  match result.status {
    Failed(reason~) => assert_true(reason.length() > 0)
    Completed => fail("预期因注入崩溃而 Failed")
  }
  // 丢弃故障为非致命：被丢弃的任务永不调度，终态仍为 Completed。
  let dropped = run(
    55,
    Scenario::new(
      [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")],
      [FaultPolicy::new(0, 2, FaultKind::Drop)],
      16,
    ),
  )
  match dropped.status {
    Completed => ()
    Failed(reason~) =>
      fail("丢弃为非致命故障，预期 Completed：\{reason}")
  }
}
```

---

## 示例 4 · 失败重放 —— 种子 + 轨迹复现完全相同的失败（R8.6）

一次运行失败时，`SimResult` 携带可重放凭据「`seed` + `trace`」。`replay(seed, trace)` 依此
复现**完全相同**的结果（满足 **R8.6**）。下例先得到一次崩溃失败的运行，再以其种子与轨迹
重放，验证两者逐项一致。

```mbt check
///|
test "README · replay 以种子与轨迹复现相同失败" {
  let tasks = [Task::new(0, "a"), Task::new(1, "b"), Task::new(2, "c")]
  // 第 1 步对任务 0 注入崩溃故障，触发失败运行。
  let faults = [FaultPolicy::new(1, 0, FaultKind::Crash)]
  let original = run(0x1234, Scenario::new(tasks, faults, 16))
  // 以失败运行输出的种子 + 事件轨迹重放。
  let replayed = replay(original.seed, original.trace)
  // 种子、逐事件轨迹与终态完全一致。
  assert_eq(replayed, original)
  // 正常完成的运行同样可被精确重放。
  let ok_run = run(
    2024,
    Scenario::new([Task::new(0, "x"), Task::new(1, "y")], [], 8),
  )
  assert_eq(replay(ok_run.seed, ok_run.trace), ok_run)
}
```

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/dst/README.mbt.md

# 三后端一致性（R11.1 / R8.7）：同一文档套件在三后端均须通过
moon test src/dst/README.mbt.md --target wasm-gc
moon test src/dst/README.mbt.md --target js
moon test src/dst/README.mbt.md --target native
```

预期看到：

```
Total tests: 5, passed: 5, failed: 0.
```

（示例 1~4 的 5 段可执行测试全部通过。）一旦修改实现使其输出与本文档的
`assert_*` 断言不符，`moon test` 会立即报错并以最小化差异提示同步更新文档——这正是
MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
