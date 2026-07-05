// prop_cp_schedule_test.mbt —— T6.2 关键路径优先列表调度的三项不变量。
//
// 复用 gen_dag（prop_support_test.mbt）随机 DAG：
//   * 拓扑不变量：任一目标出现的批次严格晚于其全部依赖；
//   * 完整性：批次并集 = 全体节点（无重复、无遗漏）；
//   * makespan 有界：critical_path_length ≤ len(cp 调度) ≤ len(schedule)
//     （单位时长任务下 CP 优先调度不劣于 FIFO 分层切块调度）。

///|
/// 目标 → 批次序号的索引表。
fn batch_index_of(batches : Array[Array[Target]]) -> Map[String, Int] {
  let idx : Map[String, Int] = Map([])
  for i, batch in batches {
    for t in batch {
      idx[t.name] = i
    }
  }
  idx
}

///|
/// Feature: build-tool, T6.2: 关键路径优先调度不变量（拓扑/完整性/makespan 有界）
///
/// **Validates: Requirements 6.7, 7.3, 7.4（T6.2）**
test "T6.2 property: critical-path schedule invariants (100 iters)" {
  let jobs_choices = [1, 2, 3]
  let ok = @infra_pbt.holds_for_all(gen_dag(), fn(g) {
    let mut all_ok = true
    for jobs in jobs_choices {
      let cp = schedule_critical_path(g, jobs)
      let fifo = schedule(g, jobs)
      let idx = batch_index_of(cp)
      // 完整性：批次并集 = 全体节点。
      let mut count = 0
      for batch in cp {
        count = count + batch.length()
      }
      if count != g.nodes.length() || idx.length() != g.nodes.length() {
        all_ok = false
      }
      // 拓扑不变量：依赖边 (u, v) ⇒ u 的批次严格早于 v。
      for edge in g.edges {
        let (u, v) = edge
        match (idx.get(u.name), idx.get(v.name)) {
          (Some(iu), Some(iv)) => if iu >= iv { all_ok = false }
          _ => all_ok = false
        }
      }
      // makespan 有界：关键路径 ≤ CP 调度 ≤ FIFO 调度。
      if cp.length() < critical_path_length(g) || cp.length() > fifo.length() {
        all_ok = false
      }
      // 并行度约束：每波宽度 ≤ jobs。
      for batch in cp {
        if batch.length() > jobs {
          all_ok = false
        }
      }
    }
    // jobs <= 0 退化为整层一批（与 schedule 一致）。
    if schedule_critical_path(g, 0) != schedule(g, 0) {
      all_ok = false
    }
    all_ok
  })
  assert_true(ok)
}

///|
/// T6.2 定向用例：CP 优先在受限并行度下严格缩短 makespan。
///
/// 图：长链 a→b→c→d 与四个独立目标 x0..x3，jobs=2。
/// FIFO 分层切块把首层 [a,x0,x1,x2,x3] 切成 3 波再走链尾 3 波（共 6 波）；
/// CP 优先每波都让链上目标先行、独立目标填充剩余槽位，4 波完成。
test "T6.2: critical-path schedule strictly beats FIFO on chain+fanout" {
  let names = ["a", "b", "c", "d", "x0", "x1", "x2", "x3"]
  let nodes : Array[Target] = []
  for n in names {
    nodes.push(Target::new(n))
  }
  let g = BuildGraph::new(nodes, [
    (Target::new("a"), Target::new("b")),
    (Target::new("b"), Target::new("c")),
    (Target::new("c"), Target::new("d")),
  ])
  let cp = schedule_critical_path(g, 2)
  let fifo = schedule(g, 2)
  assert_eq(cp.length(), 4)
  assert_true(fifo.length() > cp.length())
  // 每波首位都是链上目标（rank 最高）。
  assert_eq(cp[0][0].name, "a")
  assert_eq(cp[1][0].name, "b")
  assert_eq(cp[2][0].name, "c")
  assert_eq(cp[3][0].name, "d")
}
