// executor_prop_test.mbt —— Executor 框架属性测试（任务 4.2，覆盖 Property 3）。
//
// 对应 design.md「正确性属性」Property 3（R3 调度完备性，Validates:
// Requirements 3.4 / 3.6 / 3.7）：
//   1. 任一波次内两两 Action 在依赖图上互不可达（无依赖路径，含无直接边，AC4）；
//   2. 全波次展开后的 Action id 多重集合恰等于输入 Action 集合（不重不漏，AC7）；
//   3. 指纹相同则 `is_up_to_date` 为真、指纹不同则为假（增量比对，AC6）。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all`（每条属性
// `iters >= 100`）。所有辅助以 `p3_` 前缀命名，杜绝与既有
// `mk_action`（executor_smoke_test.mbt）/ `gen_dag` / `reachable_from_any`
// （prop_support_test.mbt）等同包符号重名。
//
// 反模式禁令：所有 id / 命令 / 输入输出名均为「单次拼接」（前缀 + Int::to_string），
// 不在循环内累积字符串（无 `out = out + s` 模式）。

// ───────────────────────────── 随机 DAG 生成 ─────────────────────────────

///|
/// 动作 id：前缀 "a" 与序号的单次拼接（避免循环内字符串累积）。
fn p3_action_id(i : Int) -> String {
  "a" + i.to_string()
}

///|
/// 随机「Action 集合 + 无环依赖边」生成器（1..7 个动作）。
///
/// 无环保证：动作按序号 0..n 排列，依赖边只允许「小序号 → 大序号」(i<j)，
/// 即 `(id_i, id_j)` 表示 id_i 必须先于 id_j 执行。方向与序号单调一致，
/// 天然不可能成环，故 `build_parallel_schedule` 必得合法分层。
fn p3_gen_action_dag() -> @infra_pbt.Gen[
  (Array[Action], Array[(String, String)]),
] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let actions : Array[Action] = []
    let ids : Array[String] = []
    for i in 0..<n {
      let id = p3_action_id(i)
      ids.push(id)
      // 字段对 Property 1/2 不敏感，仅给出确定性占位（均为单次拼接）。
      actions.push({
        id,
        inputs: [],
        outputs: [id + ".o"],
        command: "build " + id,
      })
    }
    let edges : Array[(String, String)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push((ids[i], ids[j]))
        }
      }
    }
    (actions, edges)
  })
}

// ───────────────────────────── 可达性 oracle ─────────────────────────────

///|
/// 从 `src` 出发的前向可达闭包（边松弛不动点）。返回所有可经 ≥1 条边到达的
/// 节点集合（不含 src 自身，除非存在环——本生成器无环）。
fn p3_reachable_set(
  edges : Array[(String, String)],
  src : String,
) -> Map[String, Bool] {
  let r : Map[String, Bool] = Map([])
  // 直接后继。
  for e in edges {
    let (u, v) = e
    if u == src {
      r[v] = true
    }
  }
  // 传递闭包：反复松弛直至不动点。
  let mut changed = true
  while changed {
    changed = false
    for e in edges {
      let (u, v) = e
      if r.contains(u) && !r.contains(v) {
        r[v] = true
        changed = true
      }
    }
  }
  r
}

///|
/// 预计算每个动作 id 的前向可达集合，避免逐对重复计算。
fn p3_reach_all(
  actions : Array[Action],
  edges : Array[(String, String)],
) -> Map[String, Map[String, Bool]] {
  let result : Map[String, Map[String, Bool]] = Map([])
  for a in actions {
    result[a.id] = p3_reachable_set(edges, a.id)
  }
  result
}

///|
/// `u` 是否在依赖图上可达 `v`（基于预计算闭包）。
fn p3_reaches(
  reach : Map[String, Map[String, Bool]],
  u : String,
  v : String,
) -> Bool {
  match reach.get(u) {
    Some(m) => m.contains(v)
    None => false
  }
}

///|
/// 两个字符串序列逐元素相等（用于多重集合排序后比较）。
fn p3_strings_eq(a : Array[String], b : Array[String]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i] != b[i] {
      return false
    }
  }
  true
}

// ───────────────────────────── 指纹生成 ─────────────────────────────

///|
/// 构造一个随机动作（指定 id）：随机 0..3 个输入、0..3 个输出与随机命令。
/// 各名字均为单次拼接（前缀 + 随机序号）。
fn p3_rand_action(rng : @infra_pbt.Rng, id : String) -> Action {
  let ni = rng.next_range(0, 4)
  let inputs : Array[String] = []
  for _k in 0..<ni {
    inputs.push("in" + rng.next_range(0, 99).to_string())
  }
  let no = rng.next_range(0, 4)
  let outputs : Array[String] = []
  for _k in 0..<no {
    outputs.push("out" + rng.next_range(0, 99).to_string())
  }
  let command = "cc " + rng.next_range(0, 999).to_string()
  { id, inputs, outputs, command }
}

///|
/// 随机「(原动作, 变体动作)」对：二者共享 id，但 inputs / outputs / command
/// 独立随机生成（变体可能恰好与原动作字段一致，也可能不同）。用于检验 AC6：
/// `is_up_to_date` 当且仅当当前指纹与记录指纹一致。
fn p3_gen_action_pair() -> @infra_pbt.Gen[(Action, Action)] {
  @infra_pbt.Gen::new(fn(rng) {
    let id = "a" + rng.next_range(0, 99).to_string()
    let orig = p3_rand_action(rng, id)
    let variant = p3_rand_action(rng, id)
    (orig, variant)
  })
}

// ───────────────────────────── 属性 ─────────────────────────────

///|
/// **Validates: Requirements 3.4**
test "Feature: production-hardening, Property 3: intra-wave actions have no dependency path" {
  let ok = @infra_pbt.holds_for_all(
    p3_gen_action_dag(),
    fn(pair) {
      let (actions, edges) = pair
      let sched = build_parallel_schedule(actions, edges)
      let reach = p3_reach_all(actions, edges)
      // 同一波次内任意两动作：依赖图上互不可达（无路径 ⇒ 无直接边）。
      for wave in sched.waves {
        for a in 0..<wave.length() {
          for b in (a + 1)..<wave.length() {
            let ua = wave[a].id
            let ub = wave[b].id
            if p3_reaches(reach, ua, ub) || p3_reaches(reach, ub, ua) {
              return false
            }
          }
        }
      }
      true
    },
    iters=120,
  )
  assert_true(ok)
}

///|
/// **Validates: Requirements 3.7**
test "Feature: production-hardening, Property 3: waves flatten to each action exactly once" {
  let ok = @infra_pbt.holds_for_all(
    p3_gen_action_dag(),
    fn(pair) {
      let (actions, edges) = pair
      let sched = build_parallel_schedule(actions, edges)
      // 展开全部波次的动作 id。
      let seen : Array[String] = []
      for wave in sched.waves {
        for act in wave {
          seen.push(act.id)
        }
      }
      // 输入动作 id 集合。
      let expected : Array[String] = []
      for act in actions {
        expected.push(act.id)
      }
      // 多重集合相等：id 唯一，故排序后逐元素相等即「不重不漏，各一次」。
      seen.sort()
      expected.sort()
      p3_strings_eq(seen, expected)
    },
    iters=120,
  )
  assert_true(ok)
}

///|
/// **Validates: Requirements 3.6**
test "Feature: production-hardening, Property 3: same fingerprint marks up-to-date, differing does not" {
  let ok = @infra_pbt.holds_for_all(
    p3_gen_action_pair(),
    fn(pair) {
      let (orig, variant) = pair
      let log = BuildLog::new()
      log.record(orig, Executed(output_hash="h"))
      // 同字段副本（不同对象，相同字段 ⇒ 相同指纹）：必判为 up-to-date。
      let copy : Action = {
        id: orig.id,
        inputs: orig.inputs,
        outputs: orig.outputs,
        command: orig.command,
      }
      let same_ok = log.is_up_to_date(copy)
      // 变体（同 id）：is_up_to_date 当且仅当其指纹与记录指纹一致（AC6）。
      // 当 inputs / outputs / command 任一改变导致指纹不同时，判定为 false。
      let fp_equal = variant.fingerprint() == orig.fingerprint()
      let variant_ok = log.is_up_to_date(variant) == fp_equal
      same_ok && variant_ok
    },
    iters=120,
  )
  assert_true(ok)
}
