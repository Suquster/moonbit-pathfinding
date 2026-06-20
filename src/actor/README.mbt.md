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
---

# 旗舰能力（ActorSystem）可执行示例

> 以下各段示例覆盖**旗舰驱动器 `ActorSystem[S, M]`** 接线的全部高级能力：监督
> （supervision）、请求-响应（ask）、行为切换（become / unbecome）、消息暂存
> （stash）、路由器（router）、死亡监视（death watch）、有界邮箱与背压（bounded
> mailbox）、以及受监督工作池端到端（worker pool）。每段都是独立、自洽、可编译运行
> 的 ` ```mbt check ` 块，断言确定可重放的结果（对应 **R11.6 / R15.3**）。
>
> `ActorSystem` 与既有冻结的 `Scheduler` **平行共存**：前者承载新能力，后者语义零改动。
> 沿用本文档约定——枚举一律以**限定形式**（如 `ActorOutcome::Updated` /
> `SupervisionStrategy::OneForOne` / `Directive::Restart`）构造，生命周期 / 结果用
> `match` 解构。

---

## 示例 5 · 监督（supervision）—— OneForOne 仅重启失败子

`ActorSystem::supervise` 把一组子置于某 `SupervisorSpec`（策略 + 重启强度 + 默认指令）
之下。下例 coordinator 以 `OneForOne` 监督两个 worker：`worker_a` 处理到哨兵消息
`-1` 时返回 `Errored` 触发失败，`OneForOne` 策略**仅重启该 worker**（状态重置为初始
`0`、触发失败的消息被丢弃不重放），`worker_b` 完全不受影响（错误隔离，**R1.2 / R2.2 /
R3.4 / R3.5**）。

```mbt check
///|
test "README · OneForOne 监督仅重启失败的子 actor" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  // coordinator 仅作监督者，不参与累加
  let coordinator = sys.spawn(
    0,
    Behavior::new(fn(_ctx, s, _m) { ActorOutcome::Updated(s) }),
  )
  // worker_a：累加；收到哨兵 -1 触发未捕获错误
  let worker_a = sys.spawn(
    0,
    Behavior::new(fn(_ctx, s, m) {
      if m == -1 {
        ActorOutcome::Errored("boom")
      } else {
        ActorOutcome::Updated(s + m)
      }
    }),
  )
  // worker_b：纯累加，应不受 worker_a 失败影响
  let worker_b = sys.spawn(
    0,
    Behavior::new(fn(_ctx, s, m) { ActorOutcome::Updated(s + m) }),
  )
  // OneForOne + 宽松强度 + Restart 指令
  sys.supervise(
    coordinator,
    SupervisorSpec::new(
      SupervisionStrategy::OneForOne,
      RestartIntensity::new(100, 1000),
      Directive::Restart,
    ),
    [worker_a, worker_b],
  )
  // worker_a 邮箱：5 → 累加到 5；-1 → 失败重启（状态重置为 0、该消息丢弃）；3 → 累加到 3
  worker_a.send(5)
  worker_a.send(-1)
  worker_a.send(3)
  worker_b.send(10)
  sys.run_until_idle()
  // worker_a 被重启一次，重启后只处理了 3
  assert_eq(sys.restart_count(worker_a), 1)
  assert_eq(sys.state_of(worker_a), Some(3))
  assert_true(sys.is_running(worker_a))
  // 错误隔离：worker_b 零重启、状态完好、仍在运行
  assert_eq(sys.restart_count(worker_b), 0)
  assert_eq(sys.state_of(worker_b), Some(10))
  assert_true(sys.is_running(worker_b))
}
```

下例以纯 helper 直接见证三种监督策略的**处置范围**（`affected_children`）与**重启强度
窗口上界**（`within_intensity`）：`OneForOne` 仅失败者；`OneForAll` 全体；`RestForOne`
失败者及其后启动的兄弟（**R1.2 / R1.3 / R1.4 / R2.5**）。

```mbt check
///|
test "README · 三种监督策略的处置范围与重启强度上界" {
  // 5 个子，失败者下标为 2
  // OneForOne：仅失败者 {2}
  assert_eq(affected_children(SupervisionStrategy::OneForOne, 5, 2), [2])
  // OneForAll：全体 {0,1,2,3,4}
  assert_eq(affected_children(SupervisionStrategy::OneForAll, 5, 2), [
    0, 1, 2, 3, 4,
  ])
  // RestForOne：失败者及其后 {2,3,4}
  assert_eq(affected_children(SupervisionStrategy::RestForOne, 5, 2), [2, 3, 4])
  // 重启强度：window=1000 内 max_restarts=3。
  // 已在时刻 [0,1,2] 重启 3 次，当前时钟 5 → 窗口内已达上限，不可再重启
  assert_false(within_intensity([0, 1, 2], 5, 1000, 3))
  // 仅 2 次重启 → 仍可重启
  assert_true(within_intensity([0, 1], 5, 1000, 3))
}
```

---

## 示例 6 · 请求-响应（ask）—— Replied 与确定性 Timeout

`ask(system, broker, target, make_req, budget)` 经 `AskBroker` 分配唯一关联 id、把
请求 `send` 给 target、驱动系统至多 `budget` 步、再 `poll` 取回结果（**R4.1 / R4.3 /
R4.4**）。被请求 actor 处理请求时调用 `broker.fulfill(id, resp)` 回填响应。下例一个
server 回填 `请求值 × 10`，另一个 server 从不回填以演示确定性 `Timeout`。

```mbt check
///|
test "README · ask 取回 Replied，沉默 actor 得确定性 Timeout" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let broker : AskBroker[Int] = AskBroker::new()
  // responder：消息即关联 id 值，处理时回填 resp = id * 10
  let responder = sys.spawn(
    0,
    Behavior::new(fn(_ctx, s, m) {
      broker.fulfill({ value: m }, m * 10)
      ActorOutcome::Updated(s + 1)
    }),
  )
  // 第一次 ask：关联 id 为 1 → resp = 10
  let r1 = ask(sys, broker, responder, fn(id) { id.value }, 8)
  match r1 {
    Replied(v) => assert_eq(v, 10)
    Timeout => fail("期望 Replied")
  }
  // 沉默 actor：从不回填 → 预算内确定性 Timeout
  let silent = sys.spawn(
    0,
    Behavior::new(fn(_ctx, s, _m) { ActorOutcome::Updated(s) }),
  )
  let r2 = ask(sys, broker, silent, fn(id) { id.value }, 8)
  match r2 {
    Timeout => ()
    Replied(_) => fail("期望 Timeout")
  }
}
```

---

## 示例 7 · 行为切换（become / unbecome）—— 运行时切换处理逻辑

`ActorContext::become_(b)` 把新行为压入行为栈，`unbecome()` 弹出恢复先前行为
（栈仅含初始行为时 `unbecome` 为空操作，**R5.4 / R5.7**）。下例初始行为「累加」，
收到哨兵 `7` 时 `become_` 切换为「翻倍」行为，收到哨兵 `8` 时 `unbecome` 恢复累加。

```mbt check
///|
test "README · become 切换处理行为，unbecome 恢复且弹空为空操作" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  // 翻倍行为：哨兵 8 → unbecome 恢复累加；否则把状态翻倍（忽略消息值）
  let doubling : Behavior[Int, Int] = Behavior::new(fn(ctx, s, m) {
    if m == 8 {
      ctx.unbecome()
      ActorOutcome::Updated(s)
    } else {
      ActorOutcome::Updated(s * 2)
    }
  })
  // 初始（累加）行为：哨兵 7 → become(翻倍)；哨兵 8 → unbecome；否则累加
  let adding : Behavior[Int, Int] = Behavior::new(fn(ctx, s, m) {
    if m == 7 {
      ctx.become_(doubling)
      ActorOutcome::Updated(s)
    } else if m == 8 {
      ctx.unbecome()
      ActorOutcome::Updated(s)
    } else {
      ActorOutcome::Updated(s + m)
    }
  })
  let a = sys.spawn(0, adding)
  a.send(8) // 栈仅含初始行为：unbecome 为空操作，状态保持 0
  a.send(3) // 累加 → 3
  a.send(7) // become(翻倍)
  a.send(5) // 翻倍行为：3 * 2 = 6（忽略 5）
  a.send(8) // unbecome → 恢复累加行为
  a.send(4) // 累加 → 6 + 4 = 10
  sys.run_until_idle()
  assert_eq(sys.state_of(a), Some(10))
  assert_true(sys.is_running(a))
}
```

---

## 示例 8 · 消息暂存（stash）—— 延迟处理直至就绪

`ActorContext::stash()` 把当前消息暂存（不处理），`unstash_all()` 把暂存消息按原
相对顺序回流到邮箱待处理消息之前（**R6.1 / R6.2**）。下例 actor 在「未就绪」时
暂存数据消息，收到就绪信号 `0` 时 `unstash_all` 并切换为直接累加，暂存消息随即按
原序被处理。

```mbt check
///|
test "README · stash 暂存消息，unstash_all 按原序回流处理" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  // ready 行为：直接累加
  let ready : Behavior[Int, Int] = Behavior::new(fn(_ctx, s, m) {
    ActorOutcome::Updated(s + m)
  })
  // waiting 行为：收到就绪信号 0 → unstash_all + become(ready)；否则 stash
  let waiting : Behavior[Int, Int] = Behavior::new(fn(ctx, s, m) {
    if m == 0 {
      ctx.unstash_all()
      ctx.become_(ready)
      ActorOutcome::Updated(s)
    } else {
      ctx.stash()
      ActorOutcome::Updated(s)
    }
  })
  let a = sys.spawn(0, waiting)
  a.send(1) // 暂存
  a.send(2) // 暂存
  a.send(3) // 暂存
  a.send(0) // 就绪：回流 [1,2,3] 到队首之前并切换为 ready
  sys.run_until_idle()
  // 暂存的 1 + 2 + 3 按原序被累加 = 6
  assert_eq(sys.state_of(a), Some(6))
  assert_true(sys.is_running(a))
}
```

---

## 示例 9 · 路由器（router）—— RoundRobin / Broadcast / ConsistentHash

`Router[M]` 以一组 worker 与 `RoutingStrategy` 构造，`route` / `route_keyed` 把消息
分发给 worker（经其 `ActorRef::send` 入队，随后由系统处理）。下例分别演示三种策略：
`RoundRobin` 按固定循环均衡分发、`Broadcast` 复制到全部 worker、`ConsistentHash`
对相同键稳定命中同一 worker（**R8.2 / R8.3 / R8.4 / R8.5**）。

```mbt check
///|
test "README · 三种路由策略：RoundRobin / Broadcast / ConsistentHash" {
  // RoundRobin：3 worker、6 条消息 → 各 2 条（整数倍均衡）
  let rr_sys : ActorSystem[Int, Int] = ActorSystem::new()
  let rr_workers : Array[ActorRef[Int]] = [
    rr_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
    rr_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
    rr_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
  ]
  let rr = Router::new(RoutingStrategy::RoundRobin, rr_workers)
  for i in 0..<6 {
    rr.route(i)
  }
  assert_eq(rr_sys.pending(rr_workers[0]), 2)
  assert_eq(rr_sys.pending(rr_workers[1]), 2)
  assert_eq(rr_sys.pending(rr_workers[2]), 2)

  // Broadcast：每个 worker 收到全部 3 条
  let bc_sys : ActorSystem[Int, Int] = ActorSystem::new()
  let bc_workers : Array[ActorRef[Int]] = [
    bc_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
    bc_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
  ]
  let bc = Router::new(RoutingStrategy::Broadcast, bc_workers)
  bc.route(1)
  bc.route(2)
  bc.route(3)
  assert_eq(bc_sys.pending(bc_workers[0]), 3)
  assert_eq(bc_sys.pending(bc_workers[1]), 3)

  // ConsistentHash：相同键稳定命中同一 worker
  let ch_sys : ActorSystem[Int, Int] = ActorSystem::new()
  let ch_workers : Array[ActorRef[Int]] = [
    ch_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
    ch_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
    ch_sys.spawn(
      0,
      Behavior::new(fn(_c, s, m) { ActorOutcome::Updated(s + m) }),
    ),
  ]
  let ch = Router::new(RoutingStrategy::ConsistentHash, ch_workers)
  // 同键两次命中同一 worker（稳定）
  let key_a = ch.worker_for_key("alpha")
  assert_eq(ch.worker_for_key("alpha"), key_a)
  ch.route_keyed("alpha", 1)
  ch.route_keyed("alpha", 2)
  // 命中 worker 恰收到 2 条，其余之和为 0
  let mut total = 0
  for w in ch_workers {
    total = total + ch_sys.pending(w)
  }
  assert_eq(total, 2)
}
```

---

## 示例 10 · 死亡监视（death watch）—— Terminated 通知

`ActorContext::watch(target, on_terminated)` 登记对 target 终止的监视，并附 Akka
`watchWith` 风格适配器把终止事件映射为本 actor 的消息类型（**R7.1**）。target 终止
（停止或失败）时，仍在监视的监视者**恰收到一条** Terminated 通知（**R7.2 / R7.5 /
R7.6**）。下例 watcher 监视 target，target 停止后 watcher 收到一条哨兵消息并计数。

```mbt check
///|
test "README · watch 监视目标，目标终止后收到一条 Terminated 通知" {
  let sys : ActorSystem[Int, Int] = ActorSystem::new()
  let target = sys.spawn(
    0,
    Behavior::new(fn(_c, s, _m) { ActorOutcome::Updated(s) }),
  )
  // watcher：消息 1 → watch(target)，把终止事件映射为哨兵 9999；收到 9999 → 计数 +1
  let watcher = sys.spawn(
    0,
    Behavior::new(fn(ctx, s, m) {
      if m == 1 {
        ctx.watch(target.id, fn(_id, _reason) { 9999 })
        ActorOutcome::Updated(s)
      } else if m == 9999 {
        ActorOutcome::Updated(s + 1)
      } else {
        ActorOutcome::Updated(s)
      }
    }),
  )
  watcher.send(1) // 建立监视
  sys.run_until_idle()
  target.stop() // 终止 target → 投递一条 Terminated
  sys.run_until_idle()
  // watcher 恰收到一条 Terminated（计数为 1），且 target 已停止
  assert_eq(sys.state_of(watcher), Some(1))
  match sys.status_of(target) {
    Some(Stopped) => ()
    other => fail("期望 Stopped，实际 \{other}")
  }
}
```

---

## 示例 11 · 有界邮箱与背压（bounded mailbox）

`BoundedMailbox[M]` 以容量与 `BackpressurePolicy` 构造：未满时 FIFO 入队，满时按策略
处置——`DropNewest` 丢弃新消息、`DropOldest` 移除最旧消息、`Reject` 拒绝新消息；每次
投递返回 `OfferResult`（`Enqueued` / `Dropped` / `Rejected`）并计数（**R9.2 ~ R9.5**）。
任意时刻 `length ≤ capacity`。

```mbt check
///|
test "README · 有界邮箱在满时按背压策略处置并计数" {
  // DropNewest：容量 2，投递 [1,2,3] → 队列保持 [1,2]，新消息 3 被丢弃
  let dn : BoundedMailbox[Int] = BoundedMailbox::new(
    2,
    BackpressurePolicy::DropNewest,
  )
  assert_eq(dn.offer(1), Enqueued)
  assert_eq(dn.offer(2), Enqueued)
  assert_eq(dn.offer(3), Dropped)
  assert_eq(dn.length(), 2)
  assert_eq(dn.dequeue(), Some(1))
  assert_eq(dn.dequeue(), Some(2))
  // counts = (enqueued, dropped, rejected)
  assert_eq(dn.counts(), (2, 1, 0))

  // DropOldest：满时移除最旧 → 队列 [2,3]
  let dolds : BoundedMailbox[Int] = BoundedMailbox::new(
    2,
    BackpressurePolicy::DropOldest,
  )
  let _ = dolds.offer(1)
  let _ = dolds.offer(2)
  assert_eq(dolds.offer(3), Dropped)
  assert_eq(dolds.dequeue(), Some(2))
  assert_eq(dolds.dequeue(), Some(3))

  // Reject：满时拒绝新消息 → 队列保持 [1,2]
  let rj : BoundedMailbox[Int] = BoundedMailbox::new(
    2,
    BackpressurePolicy::Reject,
  )
  let _ = rj.offer(1)
  let _ = rj.offer(2)
  assert_eq(rj.offer(3), Rejected)
  assert_eq(rj.length(), 2)
  assert_eq(rj.counts(), (2, 0, 1))
  // 容量上界：始终不超过 capacity
  assert_true(rj.length() <= rj.capacity())
}
```

---

## 示例 12 · 受监督工作池端到端（worker pool）

`worker_pool_demo(worker_count, tasks, fault_at, seed)` 把路由分发、监督重启、死亡
监视与 ask 四项能力串成一个**端到端场景**：coordinator 以 `RoundRobin` 监督并派生
worker、分发任务、`watch` 各 worker；`fault_at` 注入的失败任务在 `OneForOne` 下仅
重启该 worker、其余 worker 结果不丢失；client 以 `ask` 取回各 worker 完成计数
（**R11.1 ~ R11.5**）。同一 `seed` 的运行确定可重放。

```mbt check
///|
test "README · 受监督工作池端到端（无失败与单点失败两种场景）" {
  let tasks : Array[Task] = [
    { id: 0, payload: 10 },
    { id: 1, payload: 20 },
    { id: 2, payload: 30 },
    { id: 3, payload: 40 },
    { id: 4, payload: 50 },
    { id: 5, payload: 60 },
  ]
  // ① 无失败：6 任务经 RoundRobin 分发给 3 worker（各 2），全部完成、零重启
  let clean = worker_pool_demo(3, tasks, None, 42)
  assert_eq(clean.completed, 6)
  assert_eq(clean.restarts, 0)
  // coordinator 监视全部 3 个 worker，停止阶段恰各收到一条 Terminated
  assert_eq(clean.terminated_seen.length(), 3)
  // ask 取回各 worker 完成计数：每个完成 2 个
  assert_eq(clean.ask_results, [Replied(2), Replied(2), Replied(2)])

  // ② 单点失败：fault_at = Some(1) → OneForOne 仅重启 worker#1，未失败结果不丢失
  let faulted = worker_pool_demo(3, tasks, Some(1), 7)
  assert_eq(faulted.restarts, 1)
  // 可完成任务数 = 总数 6 − 注入失败 1 = 5
  assert_eq(faulted.completed, 5)
  assert_eq(faulted.terminated_seen.length(), 3)
  // 被重启的 worker#1 重启后仅完成 1 个，其余各 2 个
  assert_eq(faulted.ask_results, [Replied(2), Replied(1), Replied(2)])

  // 确定性可重放：同输入同种子两次运行结果逐字段一致
  assert_eq(worker_pool_demo(3, tasks, Some(1), 7), faulted)
}
```
