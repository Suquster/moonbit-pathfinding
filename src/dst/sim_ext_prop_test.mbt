// sim_ext_prop_test.mbt —— DST_Framework 旗舰深化：可执行任务体 + 时序断言的
// 属性测试（任务 9.3，覆盖 Property 8）。
//
// 本文件以共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`（每条属性
// ≥100 次迭代）随机化输入，验证 9.1（`run_executable`）与 9.2（`eventually` /
// `check_invariant_over`）落地的三条核心性质：
//   1. **相同种子逐事件可复现**（AC3，Requirement 8.3）：相同 seed + 相同任务集
//      （含「以同一规格重新构造的等价任务集」）→ 逐事件相同的 `Array[SimEvent]`。
//   2. **eventually 未成立报告 / 迟早成立**（AC6，Requirement 8.6）：对恒假谓词
//      返回 `ENeverHeld`；对迟早成立谓词返回 `EHolds(step=...)`。
//   3. **invariant 违例报告**（AC5，Requirement 8.5）：对某步必然违反的不变量
//      返回 `Some(<报告>)` 且报告含名称；对恒真不变量返回 `None`。
//
// 解耦说明：@infra_pbt 的 `Rng` 仅作属性测试的输入采样驱动；被测的确定性随机源
// 是 dst 运行时自有的 `Rng`（由 `run_executable` 内部使用），二者互不耦合。
//
// 任务体确定性约束（保证 AC3 可复现）：生成器只产出「规格」（确定性捕获值
// `(id, k, to, after, tag)`），任务体内仅以这些捕获的固定值调用 `append` /
// `send` 并返回固定的 `TaskResult`，绝不引入任何非确定行为（无墙钟、无外部随机
// 源），因此「同规格 → 同任务体逻辑 → 同轨迹」。

///|
/// 单条任务规格：以确定性捕获值描述一个可执行任务的全部行为。
///   * `id`    —— 任务标识（同时作为发送方节点 id）；
///   * `k`     —— 任务体追加到本地日志并作为发送负载的固定值；
///   * `to`    —— 发送目标节点 id；
///   * `after` —— 相对当前逻辑时钟的投递延迟；
///   * `tag`   —— 任务体返回的 `TaskResult` 选择子（0/1→TDone，2→TFailed，3→TYield）。
type TaskSpec = (Int, Int, Int, UInt64, Int)

///|
/// 由规格 `tag` 选择确定性的任务结果（命名常量化分支，避免散落魔法数字语义）。
fn result_of_tag(tag : Int) -> TaskResult {
  match tag {
    0 => TDone
    1 => TDone
    2 => TFailed(reason="确定性失败")
    _ => TYield
  }
}

///|
/// 由一组规格构造等价的可执行任务集。任务体为闭包，但仅捕获规格中的确定性值，
/// 故「同一组规格构造两次」得到逻辑等价的任务集，执行轨迹必然逐事件相同。
fn build_tasks(specs : Array[TaskSpec]) -> Array[ExecutableTask] {
  let tasks : Array[ExecutableTask] = []
  for spec in specs {
    let (id, k, to, after, tag) = spec
    // 任务体：固定追加 k、固定发送 (to, k, after)、返回固定结果。无非确定行为。
    let body = fn(ctx : SimContext) -> TaskResult {
      ctx.append(value=k)
      ctx.send(to~, payload=k, after~)
      result_of_tag(tag)
    }
    // 单次插值构造名称（非循环内字符串累积，符合高效文本构建约束）。
    tasks.push(ExecutableTask::new(id, "t\{id}", body))
  }
  tasks
}

///|
/// 生成器：「随机种子 + 随机任务规格集 + 随机 max_steps」三元组。
///
/// 采样空间（智能约束到有意义的输入域）：
///   * `seed`      —— 取随机源下一个 64 位字，覆盖整个种子空间；
///   * 任务数      —— `[1, 6]`，保证至少一个任务（轨迹非空），避免退化为空调度；
///   * `id`        —— 取 `0 ..< n`，保证规范化排序稳定且无重复；
///   * `k`         —— `[0, 1000)` 随机负载；
///   * `to`        —— `[0, n)` 指向集合内某节点；
///   * `after`     —— `[0, 3]` 投递延迟（含 0，即同刻投递）；
///   * `tag`       —— `[0, 3]` 覆盖 TDone / TFailed / TYield 全部结果；
///   * `max_steps` —— `[n, n + 8]`，足以在无让出时让全部任务完成，亦不至于让
///                    持续 TYield 的任务把轨迹撑得过长（仍由上限收敛终止）。
fn gen_seed_specs_steps() -> @infra_pbt.Gen[(UInt64, Array[TaskSpec], Int)] {
  @infra_pbt.Gen::new(fn(rng) {
    let seed = rng.next()
    let n = rng.next_range(1, 6)
    let specs : Array[TaskSpec] = []
    for i in 0..<n {
      let k = rng.next_below(1000)
      let to = rng.next_below(n)
      let after = rng.next_below(4).to_uint64()
      let tag = rng.next_below(4)
      specs.push((i, k, to, after, tag))
    }
    let max_steps = rng.next_range(n, n + 8)
    (seed, specs, max_steps)
  })
}

///|
/// Feature: production-hardening, Property 8: 相同种子逐事件可复现（确定性）
///
/// *对任意* 随机种子、任务规格集与步数上限：
///   (1) 同一任务集对象两次执行逐事件相同（`SimEvent` 派生 `Eq`，逐项比对）；
///   (2) 以同一规格**重新构造**的等价任务集，相同种子下结果仍逐事件相同——
///       排除「任务体闭包对象身份」对结果的任何影响，刻画纯种子 + 逻辑可复现。
///
/// **Validates: Requirements 8.3**
test "Feature: production-hardening, Property 8: 相同种子逐事件可复现" {
  let ok = @infra_pbt.holds_for_all(
    gen_seed_specs_steps(),
    fn(t) {
      let (seed, specs, max_steps) = t
      // (1) 同一任务集对象两次执行：逐事件相等。
      let tasks = build_tasks(specs)
      let r1 = run_executable(seed, tasks, max_steps~)
      let r2 = run_executable(seed, tasks, max_steps~)
      if r1 != r2 {
        return false
      }
      // (2) 以同一规格重新构造的等价任务集：相同种子下结果仍逐事件相等。
      let rebuilt = build_tasks(specs)
      let r3 = run_executable(seed, rebuilt, max_steps~)
      r1 == r3
    },
    iters=128,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 8: eventually 未成立与迟早成立报告
///
/// *对任意* 随机生成的执行轨迹（任务数 ≥ 1 且 max_steps ≥ 1，故轨迹非空）：
///   (1) 对恒假谓词，遍历完整轨迹仍未成立 → `ENeverHeld`（AC6 失败语义）；
///   (2) 对迟早成立谓词「前缀长度达到整条轨迹长度」，在最后一步（前缀展开为
///       整条轨迹）首次成立 → `EHolds(step = len - 1)`。
///
/// **Validates: Requirements 8.6**
test "Feature: production-hardening, Property 8: eventually 未成立与迟早成立报告" {
  let ok = @infra_pbt.holds_for_all(
    gen_seed_specs_steps(),
    fn(t) {
      let (seed, specs, max_steps) = t
      let trace = run_executable(seed, build_tasks(specs), max_steps~)
      // 生成器保证任务数 ≥ 1 且 max_steps ≥ 1，至少产出一条 EvScheduled。
      if trace.length() == 0 {
        return false
      }
      let len = trace.length()
      // (1) 恒假谓词 → 始终未成立 → ENeverHeld。
      let never = eventually(trace, fn(_p) { false }) == ENeverHeld
      // (2) 迟早成立谓词 → 末步首次成立 → EHolds(step = len - 1)。
      let holds = eventually(trace, fn(p) { p.length() >= len }) ==
        EHolds(step=len - 1)
      never && holds
    },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 8: invariant 违例报告与恒真无报告
///
/// *对任意* 随机生成的执行轨迹（非空）：
///   (1) 恒真不变量在任一前缀均成立 → `None`（无违例）；
///   (2) 必然违反的不变量「前缀长度严格小于整条轨迹长度」在末步（前缀展开为
///       整条轨迹）被违反 → `Some(<报告>)`，且报告文本包含不变量名称（AC5）。
///
/// **Validates: Requirements 8.5**
test "Feature: production-hardening, Property 8: invariant 违例报告" {
  let ok = @infra_pbt.holds_for_all(
    gen_seed_specs_steps(),
    fn(t) {
      let (seed, specs, max_steps) = t
      let trace = run_executable(seed, build_tasks(specs), max_steps~)
      if trace.length() == 0 {
        return false
      }
      let len = trace.length()
      // (1) 恒真不变量 → 全程成立 → None。
      let always_ok = check_invariant_over(trace, name="恒真", fn(_p) { true })
        is None
      // (2) 末步必然违反的不变量 → Some(<报告>)，报告含名称。
      let inv_name = "长度上限违例"
      let report = check_invariant_over(trace, name=inv_name, fn(p) {
        p.length() < len
      })
      let violated = match report {
        Some(msg) => msg.contains(inv_name)
        None => false
      }
      always_ok && violated
    },
    iters=100,
  )
  assert_true(ok)
}
