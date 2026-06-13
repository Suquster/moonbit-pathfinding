# 实现计划（Implementation Plan）：Actor_Framework（方向十 · 旗舰深化）

## 概览（Overview）

本计划把 `design.md` 拆解为**增量、可验证**的 MoonBit 编码任务，落地 `requirements.md` 的 15 条需求与设计中的 31 条正确性属性（Property 1~31）。核心纪律：

- **严格向后兼容**：既有 `pub(all)` 类型 `ActorId`/`Mailbox[M]`/`ActorRef[M]`/`ActorOutcome[S]`/`ActorStatus` 与 `pub struct Scheduler[S, M]` 的形状/语义**冻结**；既有 `types.mbt`/`actor.mbt`/`scheduler.mbt` 主体不改动。全部新能力以**旁路新增的平行类型 + 新增 `.mbt` 文件**承载，新增驱动器 `ActorSystem[S, M]` 与既有 `Scheduler[S, M]` 平行共存。
- **任务顺序遵循依赖**：behavior/lifecycle → supervision → ask/stash/deathwatch/router/bounded_mailbox → system/deterministic → demo/基准/文档/发布，各阶段间设检查点。
- **属性测试**：每条 Property 各自独立为一个 `*` 可选测试子任务，复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`，每条 ≥100 次迭代，三后端（`wasm-gc`/`js`/`native`）逐位一致、可重放；测试命名遵循 `Feature: actor, Property N: <标题>` 约定，文件以 `prop_p<NN>_*_test.mbt` 命名、本地辅助用独立前缀避免同包冲突。
- **`*` 标记规则**：仅子任务可带 `*`（可选，含属性测试/单元测试/集成测试/文档与基准校验）；顶层任务与检查点不带 `*`，且必须实现。
- **native 前置**：凡涉及 native 后端的测试 / 基准 / 可执行文档校验，**先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R12.4 / R15.4）。

> 实现语言：MoonBit（设计已给出 MoonBit 级签名，无需选择语言）。包目录：`src/actor/`（横切叶子子包，不新增子目录）；基准包：`benches/actor_bench/`。

---

## 任务（Tasks）

- [ ] 1. 行为与处理上下文（behavior.mbt，R5）
  - [ ] 1.1 实现 `behavior.mbt`
    - 定义 `Behavior[S, M]`（`receive : (ActorContext, S, M) -> ActorOutcome[S]`）与 `Behavior::new`；返回值复用冻结枚举 `ActorOutcome[S]`，不新增结果类型
    - 定义 `ActorContext[S, M]`（`self_id` + `effects` 记录器）与私有 `ContextEffect`（`PushBehavior`/`PopBehavior`/`StashCurrent`/`UnstashAll`/`Watch`/`Unwatch`）
    - 实现 `become_`/`unbecome`/`stash`/`unstash_all`/`watch`/`unwatch` 仅记录效果（不立即改全局）
    - 实现纯行为栈 helper（`Array[Behavior]` 的 push/peek/pop，深度==1 时 pop 为空操作，不弹空初始行为）
    - _Requirements: 5.1, 5.2, 5.3, 5.4_
  - [ ]* 1.2 为行为栈编写属性测试
    - **Property 14: become 当前行为生效**（对栈顶选择建模的纯 reducer：折叠 become/unbecome 效果后，每条消息由其被处理时刻栈顶行为处理）
    - **Validates: Requirements 5.1, 5.2, 5.3, 5.6**
  - [ ]* 1.3 为行为栈往返编写属性测试
    - **Property 15: 行为栈往返与不弹空**（`become(b)` 紧随 `unbecome()` 恢复操作前状态；仅含初始行为时 `unbecome()` 保持不变）
    - **Validates: Requirements 5.4, 5.7**
  - [ ]* 1.4 编写 behavior 单元测试
    - 覆盖弹空空操作见证、效果记录顺序见证
    - _Requirements: 5.1, 5.4_

- [ ] 2. 生命周期钩子与重启语义（lifecycle.mbt，R3）
  - [ ] 2.1 实现 `lifecycle.mbt`
    - 定义 `LifecycleHooks[S]`（`pre_start`/`post_stop`/`pre_restart`/`post_restart`）与全默认 `LifecycleHooks::identity()`
    - 定义 `TerminationReason`（`StoppedNormally`/`FailedWith(String)`）`derive(Eq, Show)`
    - 实现纯重启 reducer：`restart_state(init, hooks, reason)` 严格按 `pre_restart → 以初始状态重置 → post_restart` 顺序产出重启后状态
    - _Requirements: 3.1, 3.2, 3.3, 3.5_
  - [ ]* 2.2 为重启语义编写属性测试
    - **Property 7: 重启状态重置且按序调用钩子**（重启后状态等于「以初始状态为起点、不重放失败前消息」，且钩子按序）
    - **Validates: Requirements 3.3, 3.5, 3.6**
  - [ ]* 2.3 编写 lifecycle 单元测试
    - 覆盖钩子调用顺序见证、`identity()` 默认行为见证
    - _Requirements: 3.1, 3.3_

- [ ] 3. 监督策略、重启指令与最大重启强度（supervision.mbt，R1 R2）
  - [ ] 3.1 实现 `supervision.mbt`
    - 定义 `SupervisionStrategy`（`OneForOne`/`OneForAll`/`RestForOne`）、`Directive`（`Restart`/`Stop`/`Escalate`）`derive(Eq, Show)`
    - 定义 `RestartIntensity{max_restarts, window}` + `RestartIntensity::new`、`SupervisorSpec{strategy, intensity, default_directive}`
    - 实现纯 helper `affected_children(strategy, child_count, failed_index) -> Array[Int]`（OneForOne=仅失败者；OneForAll=全部；RestForOne=失败者及其后）
    - 实现纯 helper `within_intensity(restart_times, clock, window, max_restarts) -> Bool`（判定窗口内是否仍可重启）
    - _Requirements: 1.1, 2.1, 2.5_
  - [ ]* 3.2 为 OneForOne 隔离编写属性测试
    - **Property 1: OneForOne 兄弟隔离**（`affected_children(OneForOne, n, i)` 恒为 `{i}`，未失败兄弟不受影响）
    - **Validates: Requirements 1.2, 1.6**
  - [ ]* 3.3 为 OneForAll 编写属性测试
    - **Property 2: OneForAll 全体处置**（范围恒为全部子）
    - **Validates: Requirements 1.3**
  - [ ]* 3.4 为 RestForOne 编写属性测试
    - **Property 3: RestForOne 影响范围**（仅失败者及其后启动者，其前不受影响）
    - **Validates: Requirements 1.4, 1.7**
  - [ ]* 3.5 为重启强度上界编写属性测试
    - **Property 6: 重启强度上界**（任意 `window` 窗口内单 actor 重启次数 ≤ `max_restarts`，超限升级/停止）
    - **Validates: Requirements 2.5, 2.6, 2.7**
  - [ ]* 3.6 编写 supervision 单元测试
    - 覆盖三策略范围见证、强度窗口边界见证
    - _Requirements: 1.1, 2.5_

- [ ] 4. 检查点 — 能力基座（behavior/lifecycle/supervision）
  - 三后端运行全部已有测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）。Ensure all tests pass, ask the user if questions arise.

- [ ] 5. 请求-响应 ask 注册表（ask.mbt，R4）
  - [ ] 5.1 实现 `ask.mbt` 的关联 id 与注册表
    - 定义 `CorrelationId{value : Int}`、`AskResult[R]`（`Replied(R)`/`Timeout`）`derive(Eq, Show)`
    - 定义 `AskBroker[R]`（`next`/`pending : Map[Int, R]`/`consumed : Map[Int, Bool]`）
    - 实现 `AskBroker::new`/`allocate`（单调递增、运行内唯一）/`fulfill`（回填）/`poll`（按 id 精确定位、消费一次、命中 `Replied` 否则 `Timeout`）
    - _Requirements: 4.1, 4.2_
  - [ ]* 5.2 为关联 id 唯一性编写属性测试
    - **Property 11: ask 关联 id 唯一性**（同一运行内 `allocate` 的 id 两两不同）
    - **Validates: Requirements 4.2, 4.7**
  - [ ]* 5.3 为响应匹配编写属性测试
    - **Property 12: ask 响应-请求匹配唯一性**（响应恰匹配其关联 id，至多消费一次，不串号）
    - **Validates: Requirements 4.3, 4.5, 4.6**
  - [ ]* 5.4 编写 ask 注册表单元测试
    - 覆盖未回填即 `poll` 得 `Timeout`、重复 `poll` 不二次消费见证
    - _Requirements: 4.4_

- [ ] 6. 消息暂存（stash.mbt，R6）
  - [ ] 6.1 实现 `stash.mbt`
    - 定义 `StashBuffer[M]{items : Array[M]}`
    - 实现 `new`/`push`（追加，不立即处理）/`length`/`is_empty`/`clear`（重启或停止清空）/`drain_to_front`（按原相对顺序置于邮箱待处理消息之前）
    - _Requirements: 6.1, 6.2, 6.4_
  - [ ]* 6.2 为暂存保序编写属性测试
    - **Property 17: stash 保序与就绪判定**（`unstash_all` 后被暂存消息相对顺序一致；仅含暂存消息的 actor 不被错误唤醒）
    - **Validates: Requirements 6.2, 6.3, 6.5**
  - [ ]* 6.3 编写暂存单元测试
    - 覆盖 `drain_to_front` 与原邮箱消息拼接顺序见证
    - _Requirements: 6.2_

- [ ] 7. 死亡监视注册表（deathwatch.mbt，R7）
  - [ ] 7.1 实现 `deathwatch.mbt`
    - 定义 `WatchRegistry[M]{entries : Array[WatchEntry[M]]}` 与私有 `WatchEntry[M]{target, watcher, on_terminated : (ActorId, TerminationReason) -> M, active}`（数组承载保证遍历有序，三后端一致）
    - 实现 `WatchRegistry::new`/`watch`（登记）/`unwatch`（置非 active）
    - 采用 Akka `watchWith` 风格适配器，不向冻结的消息类型 `M` 或 `ActorOutcome` 注入系统消息变体
    - _Requirements: 7.1, 7.3_
  - [ ]* 7.2 编写监视注册表单元测试
    - 覆盖登记/撤销、重复登记幂等见证（投递语义属性见任务 11）
    - _Requirements: 7.1, 7.3_

- [ ] 8. 路由器（router.mbt，R8）
  - [ ] 8.1 实现 `router.mbt`
    - 定义 `RoutingStrategy`（`RoundRobin`/`Broadcast`/`ConsistentHash`）`derive(Eq, Show)`、`Router[M]{strategy, workers, cursor}`
    - 实现 `Router::new`/`route`（RoundRobin 按游标循环、Broadcast 复制到全部 worker）/`route_keyed`（ConsistentHash 用整数 FNV-1a + 排序哈希环，不使用浮点）/`worker_for_key`（可观测键→worker）
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5_
  - [ ]* 8.2 为 Broadcast 编写属性测试
    - **Property 22: Broadcast 全达**（每个 worker 收到条数等于输入条数）
    - **Validates: Requirements 8.3, 8.6**
  - [ ]* 8.3 为 RoundRobin 编写属性测试
    - **Property 23: RoundRobin 均衡**（长度为 worker 数整数倍时各 worker 条数相等，按固定循环命中）
    - **Validates: Requirements 8.2, 8.7**
  - [ ]* 8.4 为 ConsistentHash 编写属性测试
    - **Property 24: ConsistentHash 分发稳定**（worker 集合不变时相同键稳定命中同一 worker）
    - **Validates: Requirements 8.4, 8.5, 8.8**
  - [ ]* 8.5 编写路由器单元测试
    - 覆盖三策略分发见证、`worker_for_key` 稳定性见证
    - _Requirements: 8.1_

- [ ] 9. 有界邮箱与背压（bounded_mailbox.mbt，R9）
  - [ ] 9.1 实现 `bounded_mailbox.mbt`
    - 定义 `BackpressurePolicy`（`DropNewest`/`DropOldest`/`Reject`）、`OfferResult`（`Enqueued`/`Dropped`/`Rejected`）`derive(Eq, Show)`
    - 定义 `BoundedMailbox[M]{capacity, policy, items, enqueued, dropped, rejected}`
    - 实现 `new`/`offer`（未满 FIFO 入队；满时按策略处置并计数）/`dequeue`（FIFO 出队）/`length`/`counts`
    - _Requirements: 9.1, 9.2, 9.3, 9.4, 9.5, 9.6_
  - [ ]* 9.2 为容量上界编写属性测试
    - **Property 25: 有界邮箱容量上界与未满 FIFO**（任意时刻 `length ≤ capacity`；未满时与无界 FIFO 一致）
    - **Validates: Requirements 9.2, 9.7**
  - [ ]* 9.3 为背压计数守恒编写属性测试
    - **Property 26: 背压计数守恒**（入队+丢弃+拒绝 == 投递总数，每次投递恰使三者之一加一）
    - **Validates: Requirements 9.3, 9.4, 9.5, 9.8**
  - [ ]* 9.4 编写有界邮箱单元测试
    - 覆盖满时 DropNewest/DropOldest/Reject 三策略见证
    - _Requirements: 9.3, 9.4, 9.5_

- [ ] 10. 检查点 — 中层能力（ask/stash/deathwatch/router/bounded_mailbox）
  - 三后端运行全部已有测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）。Ensure all tests pass, ask the user if questions arise.

- [ ] 11. 旗舰驱动器与确定性调度（system.mbt + deterministic.mbt，整合 R1~R10）
  - [ ] 11.1 实现 `deterministic.mbt` 的 trace 事件类型
    - 定义 `TraceEvent{actor : ActorId, seq : Int}` `derive(Eq, Show)`（供 `system.mbt` 引用）
    - _Requirements: 10.3_
  - [ ] 11.2 实现 `system.mbt` 的结构、构造与派生/观测
    - 定义私有 `SupervisedCell[S, M]`（mailbox 复用既有 FIFO、可选 `bounded`、`state`/`init_state`、`behaviors` 行为栈、`stash`、`hooks`、`directive`、`status`、`started`、`restart_times`）
    - 定义 `ActorSystem[S, M]`（cells/supervisors/parents/watches/trace/clock/rng?/next_id）
    - 实现 `ActorSystem::new`（登记顺序）/`with_seed`（种子 Rng）、`spawn`（`init` + `behavior` + `hooks?`/`supervisor?`/`directive?`/`bounded?`）、`supervise`（建立监督树节点）、`state_of`/`status_of`/`is_running`/`restart_count`
    - _Requirements: 14.1, 14.4, 1.1, 3.1_
  - [ ] 11.3 实现 `system.mbt` 的 step 流水线
    - 就绪选取（种子 Rng 在「Running 且邮箱非空」中确定性选取；无种子退化为登记顺序）→ FIFO 取一条 → 栈顶 `Behavior` 处理 → step 末尾统一应用 `ctx` 效果（become/unbecome/stash/unstash/watch/unwatch）→ 记录一条 `TraceEvent`
    - 实现 `run_until_idle`（反复 step 至返回 false）
    - _Requirements: 10.1, 10.4, 5.6, 6.1_
  - [ ]* 11.4 为 ActorSystem 路径串行/FIFO 编写属性测试
    - **Property 28: 串行处理与 FIFO 顺序**（ActorSystem 路径复测既有不变量，一次仅处理一条、严格按投递顺序）
    - **Validates: Requirements 10.3, 10.4**
  - [ ]* 11.5 为调度终止性编写属性测试
    - **Property 29: 调度终止性**（`run_until_idle` 有限步内停机，得有限长度 trace）
    - **Validates: Requirements 10.5**
  - [ ] 11.6 实现 `system.mbt` 的监督决策与重启接线
    - 检测 `Errored` → `on_child_failed`：用 `within_intensity` 判定是否超限（超限按 `Escalate` 沿 `parents` 链上抛、根退化为停止根，或停止该 actor）→ 否则按 `directive` 处置（Restart 调 `restart_state` 重置状态、行为栈重置为初始、清空 stash、按钩子；Stop 终止；Escalate 上抛）→ 按 `affected_children` 扩展处置范围，范围外子隔离不变
    - _Requirements: 1.2, 1.3, 1.4, 1.5, 2.2, 2.3, 2.4, 2.6, 2.7, 3.3, 3.4, 5.5, 6.4_
  - [ ]* 11.7 为监督树升级编写属性测试
    - **Property 4: 监督树升级传递**（下层 `Escalate` 上抛至上层并按上层策略处置）
    - **Validates: Requirements 1.5, 2.4**
  - [ ]* 11.8 为重启指令语义编写属性测试
    - **Property 5: 重启指令语义**（`Restart` 重置为初始并恢复 Running；`Stop` 终止为 Stopped 且不再处理后续消息）
    - **Validates: Requirements 2.1, 2.2, 2.3**
  - [ ]* 11.9 为重启丢弃当前消息编写属性测试
    - **Property 8: 重启丢弃当前消息**（触发失败的消息不被重放，从下一条继续）
    - **Validates: Requirements 3.4**
  - [ ]* 11.10 为 pre_start 钩子编写属性测试
    - **Property 9: pre_start 至多一次且先于处理**
    - **Validates: Requirements 3.1, 3.7**
  - [ ]* 11.11 为 post_stop 钩子编写属性测试
    - **Property 10: post_stop 调用一次**（因 stop/Stop 终止后恰调用一次）
    - **Validates: Requirements 3.2**
  - [ ]* 11.12 为重启重置行为栈编写属性测试
    - **Property 16: 重启重置行为栈**（重启后行为栈恢复为仅含初始行为）
    - **Validates: Requirements 5.5**
  - [ ]* 11.13 为重启/停止清空暂存编写属性测试
    - **Property 18: 重启或停止清空暂存**（重启或停止后暂存缓冲为空）
    - **Validates: Requirements 6.4**
  - [ ] 11.14 实现 `system.mbt` 的死亡监视投递与就绪接线
    - 终止（Stopped/Failed）时遍历 `WatchRegistry`，对每个 active 监视者经 `on_terminated` 适配构造一条用户消息投递（含「watch 已终止 target 立即投递」、同一监视者×同一终止至多一条）
    - 接线有界邮箱 `offer`、暂存消息不计入「邮箱空即挂起」的就绪判定
    - _Requirements: 7.2, 7.4, 7.5, 7.6, 6.3, 9.2_
  - [ ]* 11.15 为终止通知编写属性测试
    - **Property 19: 终止通知必达且不重复**（仍在监视的监视者恰收到一条携带 id 与原因的 Terminated）
    - **Validates: Requirements 7.1, 7.2, 7.5, 7.6**
  - [ ]* 11.16 为 unwatch 编写属性测试
    - **Property 20: unwatch 撤销监视**（unwatch 后的终止不再通知）
    - **Validates: Requirements 7.3**
  - [ ]* 11.17 为 watch 已终止目标编写属性测试
    - **Property 21: watch 已终止目标立即通知**
    - **Validates: Requirements 7.4**
  - [ ] 11.18 实现 `deterministic.mbt` 的重放校验与 trace 暴露
    - 实现 `replay_consistent(seed, build)`（同种子两次运行比对 trace 逐事件一致）与 `ActorSystem::trace_of`
    - _Requirements: 10.2, 10.3, 10.6_
  - [ ]* 11.19 为重放确定性编写属性测试
    - **Property 27: 重放确定性**（同种子两次运行产生逐事件一致处理序列）
    - **Validates: Requirements 10.1, 10.2, 10.6**
  - [ ]* 11.20 编写 ActorSystem 集成单元测试
    - 覆盖两层监督升级、`unbecome` 弹空空操作、向已停止 actor `send` 丢弃见证
    - _Requirements: 1.5, 5.4, 14.3_

- [ ] 12. ask 系统驱动与端到端（在 ask.mbt 追加 `ask()`，R4）
  - [ ] 12.1 在 `ask.mbt` 追加系统级 `ask()` 函数
    - `ask(system, broker, target, make_req, budget)`：`broker.allocate()` → `target.send(make_req(id))` → 驱动 `system` 至多 `budget` 步 → `broker.poll(id)` 返回 `Replied`/`Timeout`；保留既有 `send`（tell）语义不变
    - _Requirements: 4.1, 4.3, 4.4_
  - [ ]* 12.2 为 ask 超时编写属性测试
    - **Property 13: ask 超时确定性**（预算内未收到匹配响应确定性判定为 `Timeout`，重复执行结果一致）
    - **Validates: Requirements 4.4**
  - [ ]* 12.3 编写 ask 端到端单元测试
    - 覆盖 `Replied` 命中与 `Timeout` 见证
    - _Requirements: 4.3, 4.4_

- [ ] 13. 检查点 — 驱动层（ActorSystem/确定性/ask）
  - 三后端运行全部已有测试（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）。Ensure all tests pass, ask the user if questions arise.

- [ ] 14. 受监督工作池端到端示例（demo.mbt，R11）
  - [ ] 14.1 实现 `demo.mbt`
    - 定义 `Task` 与 `WorkerPoolReport{completed, restarts, terminated_seen, ask_results}` `derive(Eq, Show)`
    - 实现 `worker_pool_demo(worker_count, tasks, fault_at, seed)`：coordinator 以路由策略派生并监督 workers、router 分发任务、注入失败触发 `OneForOne` 仅重启该 worker、coordinator `watch` worker 收 `Terminated`、client 以 `ask` 取回结果
    - _Requirements: 11.1, 11.2, 11.3, 11.4, 11.5_
  - [ ]* 14.2 为工作池韧性编写属性测试
    - **Property 30: 工作池韧性**（单点注入失败并 OneForOne 重启后最终完成所有可完成任务，未失败 worker 结果不丢失）
    - **Validates: Requirements 11.7**
  - [ ]* 14.3 编写工作池单元测试
    - 覆盖无失败/单点失败两个代表性场景见证
    - _Requirements: 11.3, 11.4, 11.5_

- [ ] 15. 向后兼容回归保障（R14）
  - [ ] 15.1 重新生成并核对 `pkg.generated.mbti` 快照
    - 运行 `moon info` 重新生成 `.mbti`，核对既有条目零回归（不删除/不改签名），新增条目只增不改
    - _Requirements: 14.1, 14.2, 14.4, 14.5_
  - [ ]* 15.2 为向后兼容编写属性测试
    - **Property 31: 向后兼容**（仅用既有 `spawn`/`send`/`stop` 与 `Scheduler` API 的消息序列，处理结果与 `0.1.0` 骨架逐字段一致）
    - **Validates: Requirements 14.3, 14.6**

- [ ] 16. 可执行文档扩充（README.mbt.md，R11.6 R15.3）
  - [ ] 16.1 在 `README.mbt.md` 追加可执行示例块
    - 追加覆盖监督、ask、become/unbecome、stash、router、death watch、有界邮箱与受监督工作池端到端的 ` ```mbt check ` 块
    - _Requirements: 11.6, 15.3_
  - [ ]* 16.2 校验可执行文档
    - 运行 `moon test src/actor/README.mbt.md`（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
    - _Requirements: 11.6, 15.3_

- [ ] 17. 性能基准与回归 guard（benches/actor_bench/，R12）
  - [ ] 17.1 新增 `benches/actor_bench/` 基准包
    - 新增 `moon.pkg`（import `Suquster/moonbit-pathfinding/src/actor` 与 `moonbitlang/core/bench`）与 `actor_bench.mbt`，覆盖五类负载：高频 `send`、海量 actor 调度、ask 往返、路由分发、监督重启；输出含机器标识/后端目标/负载规模/计时统计的 JSON 或 Markdown 工件
    - _Requirements: 12.1, 12.2_
  - [ ] 17.2 实现回归 guard 与基准文档
    - 与记入基线中位数比较、超声明容差时产出可审计失败报告；在基准文档记录运行命令与负载参数，并注明 native 前须 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 12.3, 12.4, 12.5_
  - [ ]* 17.3 编写基准 smoke 单元测试
    - 小规模负载可运行见证（native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
    - _Requirements: 12.1_

- [ ] 18. 发布推进与质量门禁（release.mbt + CHANGELOG.md，R15）
  - [ ] 18.1 推进 `release.mbt` 的 SemVer
    - 将 `actor_version` 自 `0.1.0` 推进至次/主版本，确认 `release_info_with_gates` 经三门禁（测试/证明谓词/可执行文档）聚合 `release_ready`，未通过则阻止发布就绪
    - _Requirements: 15.5, 15.6_
  - [ ] 18.2 更新 `CHANGELOG.md`
    - 在 `src/actor/CHANGELOG.md` 记录本次旗舰深化条目（新增能力、版本推进、实现边界）
    - _Requirements: 15.5_
  - [ ]* 18.3 编写 release 单元测试
    - 覆盖版本推进与门禁聚合见证
    - _Requirements: 15.6_

- [ ] 19. 最终检查点 — 三后端全绿与发布就绪
  - 三后端（`wasm-gc`/`js`/`native`，native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）运行全部测试与可执行文档校验，确认 31 条属性各 ≥100 迭代通过、`release_info_with_gates` 标记就绪。Ensure all tests pass, ask the user if questions arise.

---

## 备注（Notes）

- 标记 `*` 的子任务为可选（属性测试/单元测试/集成测试/文档与基准校验），可为快速 MVP 跳过；顶层任务与检查点必须实现。
- 每条属性子任务恰对应设计文档 Property 1~31 中的一条，并标注其验证的需求条款，便于可追溯。
- 全部新增以平行类型 + 新增 `.mbt` 承载；既有 `types.mbt`/`actor.mbt`/`scheduler.mbt` 主体与 `pub(all)` 类型冻结，`ActorSystem` 与既有 `Scheduler` 平行共存。
- 属性测试一律复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`），每条 ≥100 迭代，三后端逐位一致、可重放。
- 凡涉及 native 后端的测试/基准/文档校验，先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

## 任务依赖图（Task Dependency Graph）

下图按**执行波次（wave）**组织：同一波次内的子任务相互独立、可并行，且**不写入同一文件**（避免写冲突）；跨波次为顺序依赖。每个叶子子任务在图中恰出现一次。`writes` 标注该子任务写入的文件（`—` 表示仅运行校验、不写文件），`deps` 标注其前置子任务。

```json
{
  "feature": "actor",
  "legend": {
    "wave": "执行波次，越小越先；同波次可并行",
    "writes": "该子任务写入的文件（— 表示仅校验不写文件）",
    "deps": "前置子任务（必须先完成）"
  },
  "waves": [
    { "wave": 1,  "tasks": ["1.1", "2.1"] },
    { "wave": 2,  "tasks": ["1.2", "1.3", "1.4", "2.2", "2.3", "3.1"] },
    { "wave": 3,  "tasks": ["3.2", "3.3", "3.4", "3.5", "3.6"] },
    { "wave": 4,  "tasks": ["4"] },
    { "wave": 5,  "tasks": ["5.1", "6.1", "7.1", "8.1", "9.1"] },
    { "wave": 6,  "tasks": ["5.2", "5.3", "5.4", "6.2", "6.3", "7.2", "8.2", "8.3", "8.4", "8.5", "9.2", "9.3", "9.4"] },
    { "wave": 7,  "tasks": ["10"] },
    { "wave": 8,  "tasks": ["11.1"] },
    { "wave": 9,  "tasks": ["11.2"] },
    { "wave": 10, "tasks": ["11.3"] },
    { "wave": 11, "tasks": ["11.4", "11.5", "11.6"] },
    { "wave": 12, "tasks": ["11.7", "11.8", "11.9", "11.10", "11.11", "11.12", "11.13", "11.14"] },
    { "wave": 13, "tasks": ["11.15", "11.16", "11.17", "11.18", "11.20"] },
    { "wave": 14, "tasks": ["11.19", "12.1"] },
    { "wave": 15, "tasks": ["12.2", "12.3"] },
    { "wave": 16, "tasks": ["13"] },
    { "wave": 17, "tasks": ["14.1"] },
    { "wave": 18, "tasks": ["14.2", "14.3", "15.1", "16.1"] },
    { "wave": 19, "tasks": ["15.2", "16.2", "17.1"] },
    { "wave": 20, "tasks": ["17.2"] },
    { "wave": 21, "tasks": ["17.3", "18.1", "18.2"] },
    { "wave": 22, "tasks": ["18.3"] },
    { "wave": 23, "tasks": ["19"] }
  ],
  "nodes": {
    "1.1":   { "wave": 1,  "writes": "src/actor/behavior.mbt",                 "deps": [] },
    "1.2":   { "wave": 2,  "writes": "src/actor/prop_p14_become_active_test.mbt", "deps": ["1.1"] },
    "1.3":   { "wave": 2,  "writes": "src/actor/prop_p15_behavior_stack_test.mbt", "deps": ["1.1"] },
    "1.4":   { "wave": 2,  "writes": "src/actor/behavior_test.mbt",            "deps": ["1.1"] },
    "2.1":   { "wave": 1,  "writes": "src/actor/lifecycle.mbt",                "deps": [] },
    "2.2":   { "wave": 2,  "writes": "src/actor/prop_p07_restart_reset_test.mbt", "deps": ["2.1"] },
    "2.3":   { "wave": 2,  "writes": "src/actor/lifecycle_test.mbt",           "deps": ["2.1"] },
    "3.1":   { "wave": 2,  "writes": "src/actor/supervision.mbt",              "deps": ["1.1", "2.1"] },
    "3.2":   { "wave": 3,  "writes": "src/actor/prop_p01_one_for_one_test.mbt", "deps": ["3.1"] },
    "3.3":   { "wave": 3,  "writes": "src/actor/prop_p02_one_for_all_test.mbt", "deps": ["3.1"] },
    "3.4":   { "wave": 3,  "writes": "src/actor/prop_p03_rest_for_one_test.mbt", "deps": ["3.1"] },
    "3.5":   { "wave": 3,  "writes": "src/actor/prop_p06_intensity_test.mbt",  "deps": ["3.1"] },
    "3.6":   { "wave": 3,  "writes": "src/actor/supervision_test.mbt",         "deps": ["3.1"] },
    "4":     { "wave": 4,  "writes": "—",                                      "deps": ["1.2", "1.3", "1.4", "2.2", "2.3", "3.2", "3.3", "3.4", "3.5", "3.6"] },
    "5.1":   { "wave": 5,  "writes": "src/actor/ask.mbt",                      "deps": ["4"] },
    "6.1":   { "wave": 5,  "writes": "src/actor/stash.mbt",                    "deps": ["4"] },
    "7.1":   { "wave": 5,  "writes": "src/actor/deathwatch.mbt",               "deps": ["4", "2.1"] },
    "8.1":   { "wave": 5,  "writes": "src/actor/router.mbt",                   "deps": ["4"] },
    "9.1":   { "wave": 5,  "writes": "src/actor/bounded_mailbox.mbt",          "deps": ["4"] },
    "5.2":   { "wave": 6,  "writes": "src/actor/prop_p11_corr_id_test.mbt",    "deps": ["5.1"] },
    "5.3":   { "wave": 6,  "writes": "src/actor/prop_p12_ask_match_test.mbt",  "deps": ["5.1"] },
    "5.4":   { "wave": 6,  "writes": "src/actor/ask_test.mbt",                 "deps": ["5.1"] },
    "6.2":   { "wave": 6,  "writes": "src/actor/prop_p17_stash_order_test.mbt", "deps": ["6.1"] },
    "6.3":   { "wave": 6,  "writes": "src/actor/stash_test.mbt",               "deps": ["6.1"] },
    "7.2":   { "wave": 6,  "writes": "src/actor/deathwatch_test.mbt",          "deps": ["7.1"] },
    "8.2":   { "wave": 6,  "writes": "src/actor/prop_p22_broadcast_test.mbt",  "deps": ["8.1"] },
    "8.3":   { "wave": 6,  "writes": "src/actor/prop_p23_round_robin_test.mbt", "deps": ["8.1"] },
    "8.4":   { "wave": 6,  "writes": "src/actor/prop_p24_consistent_hash_test.mbt", "deps": ["8.1"] },
    "8.5":   { "wave": 6,  "writes": "src/actor/router_test.mbt",              "deps": ["8.1"] },
    "9.2":   { "wave": 6,  "writes": "src/actor/prop_p25_capacity_test.mbt",   "deps": ["9.1"] },
    "9.3":   { "wave": 6,  "writes": "src/actor/prop_p26_backpressure_test.mbt", "deps": ["9.1"] },
    "9.4":   { "wave": 6,  "writes": "src/actor/bounded_mailbox_test.mbt",     "deps": ["9.1"] },
    "10":    { "wave": 7,  "writes": "—",                                      "deps": ["5.2", "5.3", "5.4", "6.2", "6.3", "7.2", "8.2", "8.3", "8.4", "8.5", "9.2", "9.3", "9.4"] },
    "11.1":  { "wave": 8,  "writes": "src/actor/deterministic.mbt",            "deps": ["10"] },
    "11.2":  { "wave": 9,  "writes": "src/actor/system.mbt",                   "deps": ["10", "1.1", "2.1", "3.1", "5.1", "6.1", "7.1", "8.1", "9.1", "11.1"] },
    "11.3":  { "wave": 10, "writes": "src/actor/system.mbt",                   "deps": ["11.2"] },
    "11.4":  { "wave": 11, "writes": "src/actor/prop_p28_serial_fifo_test.mbt", "deps": ["11.3"] },
    "11.5":  { "wave": 11, "writes": "src/actor/prop_p29_termination_test.mbt", "deps": ["11.3"] },
    "11.6":  { "wave": 11, "writes": "src/actor/system.mbt",                   "deps": ["11.3", "3.1", "2.1"] },
    "11.7":  { "wave": 12, "writes": "src/actor/prop_p04_escalate_tree_test.mbt", "deps": ["11.6"] },
    "11.8":  { "wave": 12, "writes": "src/actor/prop_p05_directive_test.mbt",  "deps": ["11.6"] },
    "11.9":  { "wave": 12, "writes": "src/actor/prop_p08_discard_msg_test.mbt", "deps": ["11.6"] },
    "11.10": { "wave": 12, "writes": "src/actor/prop_p09_pre_start_test.mbt",  "deps": ["11.6"] },
    "11.11": { "wave": 12, "writes": "src/actor/prop_p10_post_stop_test.mbt",  "deps": ["11.6"] },
    "11.12": { "wave": 12, "writes": "src/actor/prop_p16_restart_behavior_test.mbt", "deps": ["11.6"] },
    "11.13": { "wave": 12, "writes": "src/actor/prop_p18_restart_stash_test.mbt", "deps": ["11.6"] },
    "11.14": { "wave": 12, "writes": "src/actor/system.mbt",                   "deps": ["11.6", "7.1", "9.1", "6.1"] },
    "11.15": { "wave": 13, "writes": "src/actor/prop_p19_terminated_test.mbt", "deps": ["11.14"] },
    "11.16": { "wave": 13, "writes": "src/actor/prop_p20_unwatch_test.mbt",    "deps": ["11.14"] },
    "11.17": { "wave": 13, "writes": "src/actor/prop_p21_watch_dead_test.mbt", "deps": ["11.14"] },
    "11.18": { "wave": 13, "writes": "src/actor/deterministic.mbt",            "deps": ["11.3", "11.1"] },
    "11.20": { "wave": 13, "writes": "src/actor/system_test.mbt",              "deps": ["11.14"] },
    "11.19": { "wave": 14, "writes": "src/actor/prop_p27_replay_test.mbt",     "deps": ["11.18"] },
    "12.1":  { "wave": 14, "writes": "src/actor/ask.mbt",                      "deps": ["11.3", "5.1"] },
    "12.2":  { "wave": 15, "writes": "src/actor/prop_p13_ask_timeout_test.mbt", "deps": ["12.1"] },
    "12.3":  { "wave": 15, "writes": "src/actor/ask_e2e_test.mbt",             "deps": ["12.1"] },
    "13":    { "wave": 16, "writes": "—",                                      "deps": ["11.4", "11.5", "11.7", "11.8", "11.9", "11.10", "11.11", "11.12", "11.13", "11.15", "11.16", "11.17", "11.19", "11.20", "12.2", "12.3"] },
    "14.1":  { "wave": 17, "writes": "src/actor/demo.mbt",                     "deps": ["13"] },
    "14.2":  { "wave": 18, "writes": "src/actor/prop_p30_worker_pool_test.mbt", "deps": ["14.1"] },
    "14.3":  { "wave": 18, "writes": "src/actor/demo_test.mbt",                "deps": ["14.1"] },
    "15.1":  { "wave": 18, "writes": "src/actor/pkg.generated.mbti",           "deps": ["13", "14.1"] },
    "16.1":  { "wave": 18, "writes": "src/actor/README.mbt.md",                "deps": ["14.1"] },
    "15.2":  { "wave": 19, "writes": "src/actor/prop_p31_backward_compat_test.mbt", "deps": ["15.1"] },
    "16.2":  { "wave": 19, "writes": "—",                                      "deps": ["16.1"] },
    "17.1":  { "wave": 19, "writes": "benches/actor_bench/actor_bench.mbt",    "deps": ["14.1"] },
    "17.2":  { "wave": 20, "writes": "benches/actor_bench/actor_bench.mbt",    "deps": ["17.1"] },
    "17.3":  { "wave": 21, "writes": "benches/actor_bench/actor_bench_test.mbt", "deps": ["17.2"] },
    "18.1":  { "wave": 21, "writes": "src/actor/release.mbt",                  "deps": ["13"] },
    "18.2":  { "wave": 21, "writes": "src/actor/CHANGELOG.md",                 "deps": ["13"] },
    "18.3":  { "wave": 22, "writes": "src/actor/release_test.mbt",             "deps": ["18.1"] },
    "19":    { "wave": 23, "writes": "—",                                      "deps": ["14.2", "14.3", "15.2", "16.2", "17.3", "18.3"] }
  }
}
```

> 写冲突校验：写入 `src/actor/system.mbt` 的子任务（11.2/11.3/11.6/11.14）分处波次 9/10/11/12，互不同波；写入 `src/actor/deterministic.mbt` 的（11.1/11.18）分处波次 8/13；写入 `src/actor/ask.mbt` 的（5.1/12.1）分处波次 5/14；写入 `benches/actor_bench/actor_bench.mbt` 的（17.1/17.2）分处波次 19/20。其余文件均唯一写入，同波次无并行写同一文件。
