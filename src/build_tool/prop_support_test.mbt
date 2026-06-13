// prop_support_test.mbt —— 旗舰深化属性测试共享生成器与辅助谓词（测试期）。
//
// 集中放置 P1–P15 复用的 `@infra_pbt` 生成器（随机 DAG / 含脏子集 / 随机
// BuildCache / 随机 RuleSet / 最小文法文本 / 缓存键与溯源输入 / 含环标记图 /
// 动态依赖三元组）与调度 / 可达性辅助，避免在各属性文件间重复。命名与既有
// `prop_schedule_test.mbt` / `prop_cycle_idem_test.mbt` 中的生成器（
// `gen_acyclic_build_graph` / `gen_cyclic_graph` 等）刻意区分，杜绝重名。
//
// 所有生成器以序号化节点名（`n0..`）保证唯一，DAG 仅生成「低编号 → 高编号」
// 边保证无环（依赖边 `(u, v)` 语义为「u 必须在 v 之前」，方向与编号单调一致）。

// ───────────────────────────── 通用生成器 ─────────────────────────────

///|
/// 随机无环构建图（1..8 节点，低→高随机边）。
fn gen_dag() -> @infra_pbt.Gen[BuildGraph] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let nodes : Array[Target] = []
    for i in 0..<n {
      nodes.push(Target::new("n" + i.to_string()))
    }
    let edges : Array[(Target, Target)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push((nodes[i], nodes[j]))
        }
      }
    }
    BuildGraph::new(nodes, edges)
  })
}

///|
/// 随机无环构建图 + 随机脏输入子集。
fn gen_dag_with_dirty() -> @infra_pbt.Gen[(BuildGraph, Array[Target])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 8)
    let nodes : Array[Target] = []
    for i in 0..<n {
      nodes.push(Target::new("n" + i.to_string()))
    }
    let edges : Array[(Target, Target)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push((nodes[i], nodes[j]))
        }
      }
    }
    let dirty : Array[Target] = []
    for i in 0..<n {
      if rng.next_bool() {
        dirty.push(nodes[i])
      }
    }
    (BuildGraph::new(nodes, edges), dirty)
  })
}

///|
/// 随机 `BuildCache`：所有目标观测当前指纹，部分固化基线（mark_built）。
/// 名字 / 哈希无空白，mtime 为正，保序列化往返安全。
fn gen_build_cache() -> @infra_pbt.Gen[BuildCache] {
  @infra_pbt.Gen::new(fn(rng) {
    let cache = BuildCache::new()
    let n = rng.next_range(0, 6)
    for i in 0..<n {
      let name = "t" + i.to_string()
      cache.observe(
        name,
        rng.next_range(1, 1000000).to_int64(),
        "h" + rng.next_range(0, 9999).to_string(),
      )
      if rng.next_bool() {
        cache.mark_built(name)
      }
    }
    cache
  })
}

///|
/// 随机 recipe 行（0..2 行，含空格的简单命令，无 `$(` / 换行）。
fn gen_recipe_lines(rng : @infra_pbt.Rng) -> Array[String] {
  let n = rng.next_range(0, 2)
  let out : Array[String] = []
  for _i in 0..<n {
    out.push("echo build" + rng.next_range(0, 99).to_string())
  }
  out
}

///|
/// 随机合法 `RuleSet`（含变量 / phony / 模式规则 / 具体规则），刻意构造为可经
/// `print_rules` → `parse_rules_full` 无损往返的规范形态（P1）。
fn gen_ruleset() -> @infra_pbt.Gen[RuleSet] {
  @infra_pbt.Gen::new(fn(rng) {
    let variables : Map[String, String] = Map([])
    let nv = rng.next_range(0, 3)
    for i in 0..<nv {
      variables["V" + i.to_string()] = "val" + rng.next_range(0, 99).to_string()
    }
    let phony : Array[String] = []
    let np = rng.next_range(0, 3)
    for i in 0..<np {
      phony.push("p" + i.to_string())
    }
    let pattern_rules : Array[PatternRule] = []
    let npr = rng.next_range(0, 2)
    for i in 0..<npr {
      pattern_rules.push({
        target_pattern: "%.o" + i.to_string(),
        dep_patterns: ["%.c" + i.to_string()],
        recipe: { lines: gen_recipe_lines(rng) },
      })
    }
    let rules : Array[Rule] = []
    let nr = rng.next_range(1, 5)
    for i in 0..<nr {
      let nd = rng.next_range(0, 4)
      let deps : Array[String] = []
      for _j in 0..<nd {
        deps.push("d" + rng.next_range(0, 9).to_string())
      }
      rules.push({
        target: "r" + i.to_string(),
        deps,
        recipe: { lines: gen_recipe_lines(rng) },
      })
    }
    { rules, pattern_rules, variables, phony }
  })
}

///|
/// 随机最小文法文本（仅 `target: dep*`、`#` 注释、空行），用于向后兼容差分（P2）。
fn gen_minimal_text() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    let mut out = ""
    let lines = rng.next_range(1, 7)
    for i in 0..<lines {
      let r = rng.next_below(10)
      if r < 2 {
        out = out + "# comment " + i.to_string() + "\n"
      } else if r < 3 {
        out = out + "\n"
      } else {
        out = out + "n" + rng.next_range(0, 6).to_string() + ":"
        let nd = rng.next_range(0, 4)
        for _j in 0..<nd {
          out = out + " n" + rng.next_range(0, 6).to_string()
        }
        out = out + "\n"
      }
    }
    out
  })
}

///|
/// 随机缓存键输入（目标, 输入哈希序列, 动作指纹）。
fn gen_key_inputs() -> @infra_pbt.Gen[(String, Array[String], String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let target = "t" + rng.next_range(0, 99).to_string()
    let k = rng.next_range(0, 5)
    let hs : Array[String] = []
    for _i in 0..<k {
      hs.push("h" + rng.next_range(0, 999).to_string())
    }
    (target, hs, "a" + rng.next_range(0, 999).to_string())
  })
}

///|
/// 随机溯源输入（目标, 输入哈希集合, recipe）。
fn gen_prov_inputs() -> @infra_pbt.Gen[(String, Array[String], Recipe)] {
  @infra_pbt.Gen::new(fn(rng) {
    let target = "t" + rng.next_range(0, 99).to_string()
    let k = rng.next_range(0, 5)
    let hs : Array[String] = []
    for _i in 0..<k {
      hs.push("h" + rng.next_range(0, 999).to_string())
    }
    (target, hs, { lines: gen_recipe_lines(rng) })
  })
}

///|
/// 随机构建图 + 「是否含环」真值标记。无环分支仅低→高边；含环分支额外注入
/// 2-环（`(i,j)` 与 `(j,i)`）或自环，保证标记与事实一致。
fn gen_graph_with_cycle_flag() -> @infra_pbt.Gen[(BuildGraph, Bool)] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 7)
    let nodes : Array[Target] = []
    for i in 0..<n {
      nodes.push(Target::new("n" + i.to_string()))
    }
    let edges : Array[(Target, Target)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push((nodes[i], nodes[j]))
        }
      }
    }
    if rng.next_bool() {
      if rng.next_bool() {
        let i = rng.next_below(n - 1)
        let j = i + 1 + rng.next_below(n - i - 1)
        edges.push((nodes[i], nodes[j]))
        edges.push((nodes[j], nodes[i]))
      } else {
        let idx = rng.next_below(n)
        edges.push((nodes[idx], nodes[idx]))
      }
      (BuildGraph::new(nodes, edges), true)
    } else {
      (BuildGraph::new(nodes, edges), false)
    }
  })
}

///|
/// 随机 DAG + 目标 + 不引入环的动态依赖（索引严格小于目标，保持低→高单调）。
fn gen_dag_dynamic() -> @infra_pbt.Gen[(BuildGraph, Target, Array[Target])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(2, 8)
    let nodes : Array[Target] = []
    for i in 0..<n {
      nodes.push(Target::new("n" + i.to_string()))
    }
    let edges : Array[(Target, Target)] = []
    for i in 0..<n {
      for j in (i + 1)..<n {
        if rng.next_bool() {
          edges.push((nodes[i], nodes[j]))
        }
      }
    }
    let t = 1 + rng.next_below(n - 1)
    let dyn : Array[Target] = []
    for i in 0..<t {
      if rng.next_bool() {
        dyn.push(nodes[i])
      }
    }
    (BuildGraph::new(nodes, edges), nodes[t], dyn)
  })
}

// ───────────────────────────── 调度 / 可达性辅助 ─────────────────────────────

///|
/// 批次序列展平为执行顺序。
fn flatten_order(batches : Array[Array[Target]]) -> Array[Target] {
  let out : Array[Target] = []
  for b in batches {
    for t in b {
      out.push(t)
    }
  }
  out
}

///|
/// 目标 → 全局执行序号映射。
fn position_map(batches : Array[Array[Target]]) -> Map[Target, Int] {
  let m : Map[Target, Int] = Map([])
  let mut i = 0
  for b in batches {
    for t in b {
      m[t] = i
      i = i + 1
    }
  }
  m
}

///|
/// 目标 → 所在批次序号映射。
fn batch_index_map(batches : Array[Array[Target]]) -> Map[Target, Int] {
  let m : Map[Target, Int] = Map([])
  let mut bi = 0
  for b in batches {
    for t in b {
      m[t] = bi
    }
    bi = bi + 1
  }
  m
}

///|
/// 数组是否含某目标（测试侧辅助，黑盒测试不可见源内私有同名函数）。
fn list_contains_target(arr : Array[Target], x : Target) -> Bool {
  for t in arr {
    if t == x {
      return true
    }
  }
  false
}

///|
/// 两个目标序列逐元素相等。
fn targets_eq(a : Array[Target], b : Array[Target]) -> Bool {
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

///|
/// 两个依赖边序列逐元素相等。
fn edges_eq(
  a : Array[(Target, Target)],
  b : Array[(Target, Target)],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    let (u1, v1) = a[i]
    let (u2, v2) = b[i]
    if u1 != u2 || v1 != v2 {
      return false
    }
  }
  true
}

///|
/// 独立的前向可达闭包（边松弛不动点），作为最小重建集充分 / 最小性的对照 oracle。
fn reachable_from_any(
  g : BuildGraph,
  sources : Array[Target],
) -> Map[Target, Bool] {
  let r : Map[Target, Bool] = Map([])
  for s in sources {
    r[s] = true
  }
  let mut changed = true
  while changed {
    changed = false
    for edge in g.edges {
      let (u, v) = edge
      if r.contains(u) && !r.contains(v) {
        r[v] = true
        changed = true
      }
    }
  }
  r
}
