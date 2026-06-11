# actor · 可执行文档

> **方向十（R10）基于消息传递的 Actor 并发框架（Actor_Framework）** — spawn 派生 · send 投递（FIFO）· 串行处理 · stop 停止 · 错误隔离与监督 · 三后端一致 · 文档即测试。
>
> 本文件既是 `actor` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/actor/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）** 与 **R10.1~10.7（消息传递语义）**，
tasks.md **任务 16.5**。

本文件作为 `actor` 包的黑盒测试运行，可直接调用本包公开 API
（`Scheduler::new` / `Scheduler::spawn` / `ActorRef::send` / `ActorRef::stop` /
`Scheduler::run_until_idle` / `Scheduler::step` / `Scheduler::state_of` /
`Scheduler::status_of` / `Scheduler::is_running` / `Scheduler::pending` 等）
而无需限定包名。下面 4 段示例覆盖 **spawn 派生 → send 投递（FIFO）→ run_until_idle
串行处理 → step 单步 → stop 停止 → 错误隔离与 supervisor 通知** 的端到端用法。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。
>
> **关于类型构造**：黑盒 `.mbt.md` 对「表达式位置直接构造枚举」有限制，因此本文档
> 统一以限定形式 `ActorOutcome::Updated` / `ActorOutcome::Errored` 构造处理结果，
> 并以 `match` 解构生命周期状态 `ActorStatus`（`Running` / `Stopped` / `Failed`）。

---

## 核心概念（concepts）

`Scheduler[S, M]` 是一台**确定性串行调度器**：以状态类型 `S` 与消息类型 `M` 参数化。
`spawn(init, handle, supervisor?)` 在调度器中派生一个 actor，返回可投递消息的引用句柄
`ActorRef[M]`（**R10.1**）。`handle : (S, M) -> ActorOutcome[S]` 是消息处理函数，返回
`Updated(s)`（更新状态）或 `Errored(reason)`（未捕获错误信号）。

向句柄 `send` 一条消息即把它追加到该 actor 的**邮箱队尾**（FIFO，**R10.2**）。`step`
至多处理「某一就绪 actor」的「一条」消息（串行不变量，**R10.3**）；同一 actor 的消息
按投递顺序处理（**R10.4**）；空邮箱 actor 被跳过、不占处理步（**R10.5**）。
`run_until_idle` 反复 `step` 直到所有邮箱清空或所有 actor 停止 / 失败。

`stop` 在处理完当前消息后停止该 actor（**R10.7**）；处理期间返回 `Errored` 会终止该
actor、通知其 `supervisor` 且**不影响其他 actor**（错误隔离，**R10.6**）。

---

## 示例 1 · spawn + send + run_until_idle —— 基本消息传递

`Scheduler::spawn` 派生一个计数器 actor（初始状态 `0`，处理函数把消息累加到状态上），
返回引用句柄。`send` 把消息投递进邮箱，`run_until_idle` 串行处理全部消息后，
状态汇总为各消息之和（**R10.1 / R10.2**）。

```mbt check
///|
test "README · spawn 派生 actor 并经 send 投递消息" {
  let sched : Scheduler[Int, Int] = Scheduler::new()
  // 派生一个累加 actor：初始状态 0，处理函数将消息累加到状态
  let counter = sched.spawn(0, fn(s, m) { ActorOutcome::Updated(s + m) })
  // send 把消息追加到邮箱（尚未处理）
  counter.send(1)
  counter.send(2)
  counter.send(3)
  assert_eq(sched.pending(counter), 3)
  // run_until_idle 串行处理全部消息：1 + 2 + 3 = 6
  sched.run_until_idle()
  assert_eq(sched.state_of(counter), Some(6))
  assert_eq(sched.pending(counter), 0)
  // 处理完毕后 actor 仍在运行，可继续接收消息
  assert_true(sched.is_running(counter))
}
```

---

## 示例 2 · send 的 FIFO 顺序 + step 单步串行处理

同一发送者投递的消息按**先进先出**顺序被处理（**R10.4**）。下例以字符串拼接
（顺序敏感）验证 FIFO：依次投递 `"a"`、`"b"`、`"c"`，处理后得到 `"abc"`。并用 `step`
演示**单 actor 一次仅处理一条消息**的串行不变量（**R10.3**）。

```mbt check
///|
test "README · send 保持 FIFO 顺序且 step 单步串行处理" {
  let sched : Scheduler[String, String] = Scheduler::new()
  let log = sched.spawn("", fn(s, m) { ActorOutcome::Updated(s + m) })
  log.send("a")
  log.send("b")
  log.send("c")
  // step 每次只处理一条消息（串行，R10.3）：先处理队首 "a"
  assert_true(sched.step())
  assert_eq(sched.state_of(log), Some("a"))
  assert_eq(sched.pending(log), 2)
  // 第二步处理 "b"
  assert_true(sched.step())
  assert_eq(sched.state_of(log), Some("ab"))
  // 第三步处理 "c"；FIFO 顺序使结果为 "abc"（R10.4）
  assert_true(sched.step())
  assert_eq(sched.state_of(log), Some("abc"))
  // 邮箱已空：step 不再有进展（空邮箱挂起，R10.5）
  assert_eq(sched.step(), false)
}
```

---

## 示例 3 · stop —— 处理完当前消息后停止

`ActorRef::stop` 请求停止某个 actor：先前已入队的消息处理完后停止消息循环，
此后 `send` 的新消息被丢弃、不再处理（**R10.7**）。下例累加 `1 + 2 = 3` 后调用
`stop`，再投递的 `99` 被丢弃，状态保持 `3`，生命周期状态转为 `Stopped`。

```mbt check
///|
test "README · stop 在处理完当前消息后停止 actor" {
  let sched : Scheduler[Int, Int] = Scheduler::new()
  let acc = sched.spawn(0, fn(s, m) { ActorOutcome::Updated(s + m) })
  acc.send(1)
  acc.send(2)
  sched.run_until_idle()
  assert_eq(sched.state_of(acc), Some(3))
  assert_true(sched.is_running(acc))
  // 请求停止：邮箱关闭，此后 send 的消息被丢弃（R10.7）
  acc.stop()
  acc.send(99)
  sched.run_until_idle()
  // 状态保持不变，生命周期转为 Stopped
  assert_eq(sched.state_of(acc), Some(3))
  match sched.status_of(acc) {
    Some(Stopped) => ()
    other => fail("期望 Stopped，实际 \{other}")
  }
  assert_false(sched.is_running(acc))
}
```

---

## 示例 4 · 错误隔离与 supervisor 通知 —— 单个 actor 失败不影响其他 actor

处理函数返回 `ActorOutcome::Errored(reason)` 表示一次未捕获错误：调度器终止该 actor
（生命周期转为 `Failed`）、丢弃其残留消息并通知其 `supervisor`，而**其他 actor 不受影响**
继续运行（**R10.6**）。下例 `worker` 在收到 `0` 时报错失败，supervisor 收到通知；
同一调度器中的 `healthy` actor 不受波及，照常完成累加。

```mbt check
///|
test "README · 未捕获错误终止 actor 并通知 supervisor（错误隔离）" {
  let sched : Scheduler[Int, Int] = Scheduler::new()
  // 用一个数组记录 supervisor 收到的通知，便于观测
  let notes : Array[String] = []
  // worker：收到 0 时报错；否则累加 100 / m
  let worker = sched.spawn(
    0,
    fn(s, m) {
      if m == 0 {
        ActorOutcome::Errored("除零错误")
      } else {
        ActorOutcome::Updated(s + 100 / m)
      }
    },
    supervisor=fn(id, reason) { notes.push("actor #\{id.value}: \{reason}") },
  )
  // healthy：独立的累加 actor，不应受 worker 失败影响
  let healthy = sched.spawn(0, fn(s, m) { ActorOutcome::Updated(s + m) })
  worker.send(10) // 100 / 10 = 10，正常处理
  worker.send(0) // 触发错误：终止 worker、通知 supervisor
  worker.send(5) // worker 失败后该消息被丢弃，不再处理
  healthy.send(7)
  healthy.send(8)
  sched.run_until_idle()
  // worker 因未捕获错误被终止
  match sched.status_of(worker) {
    Some(Failed(reason)) => assert_eq(reason, "除零错误")
    other => fail("期望 Failed，实际 \{other}")
  }
  assert_false(sched.is_running(worker))
  // supervisor 恰好收到一次通知（R10.6）
  assert_eq(notes.length(), 1)
  assert_eq(notes[0], "actor #1: 除零错误")
  // 错误隔离：healthy 不受影响，照常完成 7 + 8 = 15 且仍在运行
  assert_eq(sched.state_of(healthy), Some(15))
  assert_true(sched.is_running(healthy))
}
```

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/actor/README.mbt.md

# 三后端一致性（R11.1 / R10）：同一文档套件在三后端均须通过
moon test src/actor/README.mbt.md --target wasm-gc
moon test src/actor/README.mbt.md --target js
moon test src/actor/README.mbt.md --target native
```

预期看到：

```
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改 actor 调度实现使其输出与本文档的
`assert_*` 断言或 `match` 解构不符，`moon test` 会立即报错并以最小化差异提示同步
更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
