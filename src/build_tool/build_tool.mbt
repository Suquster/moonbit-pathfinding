// build_tool.mbt —— Build_Tool 的核心实现（任务 9.2）。
//
// 在任务 9.1 接口桩之上落地方向六（design.md §「方向六：Build_Tool」）的核心
// 流水线，复用既有图资产，不重写已被证明谓词覆盖的图算法：
//   * `parse_rules` —— 最小可用的规则文本文法解析（目标 + 依赖边），足以支撑
//                      `schedule` / `is_dirty` 测试；完整规则文法（命令、变量、
//                      带位置诊断的 @parser_combinator 风格）留作后续迭代。
//   * `detect_cycle`—— 复用 `@directed.tarjan_scc`（`condensation` 的底层）识别
//                      强连通分量，报告构成环的目标序列（含自环）。
//   * `topo_order`  —— 复用 `@directed.topological_sort`（Kahn 拓扑序）；存在环
//                      时经 `detect_cycle` 报告具体环节点序列。
//   * `schedule`    —— 按拓扑分层产出「无相互依赖目标」的并行批次，并以并行度
//                      `jobs` 约束批内宽度。
//   * `is_dirty`    —— 基于 mtime 与内容哈希比对当前指纹与基线指纹，支撑
//                      「输入未变 → 零重建」的增量空操作。

///|
/// 由构建图的依赖边推导某目标的后继（out-neighbors）。
///
/// 依赖边 `(u, v)` 表示「`u` 必须在 `v` 之前」，因此 `u` 的后继包含 `v`。
/// 该函数把 `BuildGraph` 适配为 `@directed` 算法所需的 `(N) -> Array[N]`
/// successors 形式。骨架阶段采用直接线性扫描，规模优化留待后续迭代。
fn successors_in(g : BuildGraph, node : Target) -> Array[Target] {
  let out : Array[Target] = []
  for edge in g.edges {
    let (u, v) = edge
    if u == node {
      out.push(v)
    }
  }
  out
}

// ───────────────────────── 规则解析（graph 子模块） ─────────────────────────

///|
/// 判定字符是否为「行内空白」（空格 / 制表符 / 回车）。
fn is_ws(c : Char) -> Bool {
  c == ' ' || c == '\t' || c == '\r'
}

///|
/// 将字符序列拼接为字符串（骨架阶段以 `+` 拼接，规模优化留待后续）。
fn chars_to_string(cs : Array[Char]) -> String {
  let mut s = ""
  for c in cs {
    s = s + c.to_string()
  }
  s
}

///|
/// 去除字符序列两端的行内空白，返回新序列。
fn trim_chars(cs : Array[Char]) -> Array[Char] {
  let mut a = 0
  let mut b = cs.length()
  while a < b && is_ws(cs[a]) {
    a += 1
  }
  while b > a && is_ws(cs[b - 1]) {
    b -= 1
  }
  let out : Array[Char] = []
  let mut k = a
  while k < b {
    out.push(cs[k])
    k += 1
  }
  out
}

///|
/// 取字符序列的子区间 `[a, b)`，返回新序列。
fn slice_chars(cs : Array[Char], a : Int, b : Int) -> Array[Char] {
  let out : Array[Char] = []
  let mut k = a
  while k < b {
    out.push(cs[k])
    k += 1
  }
  out
}

///|
/// 按空白切分字符序列为词法单元（token）序列，丢弃空串。
fn tokenize_ws(cs : Array[Char]) -> Array[String] {
  let toks : Array[String] = []
  let mut cur : Array[Char] = []
  for c in cs {
    if is_ws(c) {
      if cur.length() > 0 {
        toks.push(chars_to_string(cur))
        cur = []
      }
    } else {
      cur.push(c)
    }
  }
  if cur.length() > 0 {
    toks.push(chars_to_string(cur))
  }
  toks
}

///|
/// 将源文本按 `\n` 切分为若干行（每行为一个字符序列），保留空行。
fn split_lines(chars : Array[Char]) -> Array[Array[Char]] {
  let lines : Array[Array[Char]] = []
  let mut cur : Array[Char] = []
  for c in chars {
    if c == '\n' {
      lines.push(cur)
      cur = []
    } else {
      cur.push(c)
    }
  }
  lines.push(cur)
  lines
}

///|
/// 解析构建规则源文本为构建图。
///
/// 最小可用规则文法（每行一条规则，足以支撑调度与脏检查测试）：
///
/// ```text
/// # 以 '#' 起始的行为注释，空行忽略
/// target : dep1 dep2 dep3
/// ```
///
/// 语义：`target` 依赖空格分隔的 `dep*`；对每个依赖生成一条边 `(dep, target)`
/// （表示「dep 必须在 target 之前」），目标与依赖均登记为图节点（按首次出现
/// 去重）。冒号后依赖可为空（叶子目标）。
///
/// 错误：行内缺少 `:` 分隔符，或冒号左侧目标名为空，返回带 1 起始行号的
/// `ParseError`。
///
/// 说明：完整规则文法（构建命令、变量展开、include、复用 @parser_combinator
/// 的带列号诊断）属本方向后续迭代；本实现仅覆盖「目标 + 依赖边」这一支撑
/// 拓扑调度与增量脏检查所需的最小子集。
pub fn parse_rules(src : String) -> Result[BuildGraph, ParseError] {
  let nodes : Array[Target] = []
  let seen : Map[String, Bool] = Map([])
  let edges : Array[(Target, Target)] = []
  // 按首次出现登记节点，保持稳定顺序并去重。
  fn ensure(name : String) -> Unit {
    if !seen.contains(name) {
      seen[name] = true
      nodes.push(Target::new(name))
    }
  }

  let lines = split_lines(src.iter().to_array())
  let mut line_no = 0
  for line in lines {
    line_no += 1
    let trimmed = trim_chars(line)
    // 空行与注释行跳过。
    if trimmed.length() == 0 || trimmed[0] == '#' {
      continue
    }
    // 定位首个 ':' 作为「目标 : 依赖」分隔符。
    let mut colon = -1
    for k in 0..<line.length() {
      if line[k] == ':' {
        colon = k
        break
      }
    }
    if colon < 0 {
      return Err(ParseError::new("规则缺少 ':' 依赖分隔符", line_no))
    }
    let target_name = chars_to_string(trim_chars(slice_chars(line, 0, colon)))
    if target_name == "" {
      return Err(ParseError::new("规则目标名为空", line_no))
    }
    ensure(target_name)
    let target = Target::new(target_name)
    for dep in tokenize_ws(slice_chars(line, colon + 1, line.length())) {
      ensure(dep)
      // 边 (dep, target)：依赖必须在目标之前构建。
      edges.push((Target::new(dep), target))
    }
  }
  Ok(BuildGraph::new(nodes, edges))
}

// ───────────────────────── 脏检查（dirty 子模块） ─────────────────────────

///|
/// 判定构建目标相对缓存是否「脏」（需重建）。
///
/// 基于 mtime 与内容哈希比对目标的「当前观测指纹」与「基线指纹」
/// （见 `BuildCache`）：
///   * 当前指纹缺失（无从判断）→ 保守视为脏；
///   * 基线指纹缺失（从未成功构建）→ 脏；
///   * 当前 mtime 或内容哈希与基线不一致 → 脏；
///   * 两者完全一致 → 干净（`false`）。
///
/// 「干净」分支正是增量空操作（Requirement 6.6）的基础：一次成功构建后输入
/// 未变，则所有目标均判为干净，再次构建零重建。
pub fn is_dirty(t : Target, cache : BuildCache) -> Bool {
  let name = t.name
  match (cache.current_mtimes.get(name), cache.current_hashes.get(name)) {
    (Some(cur_mtime), Some(cur_hash)) =>
      match (cache.recorded_mtimes.get(name), cache.recorded_hashes.get(name)) {
        // 基线齐备：mtime 或哈希任一变化即为脏。
        (Some(rec_mtime), Some(rec_hash)) =>
          cur_mtime != rec_mtime || cur_hash != rec_hash
        // 无基线：从未成功构建过 → 脏。
        _ => true
      }
    // 无当前观测指纹：无从判断 → 保守重建。
    _ => true
  }
}

// ─────────────────────── 调度（schedule 子模块） ───────────────────────

///|
/// 生成构建目标的并行执行批次。
///
/// 按拓扑「分层」（Kahn 逐层剥离入度为 0 的目标）产出批次：同一批次内的目标
/// 相互无依赖，可并行执行；批次间严格满足「任一目标在其所有依赖之后」的
/// 拓扑不变量（Requirement 6.7）。`jobs > 0` 时按并行度上限把宽层切分为多个
/// 批宽不超过 `jobs` 的批次；`jobs <= 0` 视为不限并行度（整层一批）。
///
/// 构建图存在依赖环时无法完成调度（剩余目标入度恒大于 0），此处停止并返回
/// 已能调度的批次前缀；环的报告由 `detect_cycle` 负责（Requirement 6.2）。
pub fn schedule(g : BuildGraph, jobs : Int) -> Array[Array[Target]] {
  // 计算入度：依赖边 (u, v) 表示 v 依赖 u，故 v 的入度 +1。
  let in_degree : Map[Target, Int] = Map([])
  for n in g.nodes {
    in_degree[n] = 0
  }
  for edge in g.edges {
    let (_, v) = edge
    match in_degree.get(v) {
      Some(d) => in_degree[v] = d + 1
      None => () // 指向未登记节点的边忽略
    }
  }
  let removed : Map[Target, Bool] = Map([])
  let batches : Array[Array[Target]] = []
  let mut remaining = g.nodes.length()
  while remaining > 0 {
    // 收集当前无依赖（入度 0 且未移除）目标，保持 nodes 原序以稳定输出。
    let ready : Array[Target] = []
    for n in g.nodes {
      if !removed.get(n).unwrap_or(false) && in_degree.get(n).unwrap_or(0) == 0 {
        ready.push(n)
      }
    }
    if ready.length() == 0 {
      // 剩余目标构成依赖环，无法继续调度；停止。
      break
    }
    // 剥离本层目标并更新其后继入度。
    for n in ready {
      removed[n] = true
      remaining -= 1
      for edge in g.edges {
        let (u, v) = edge
        if u == n {
          match in_degree.get(v) {
            Some(d) => in_degree[v] = d - 1
            None => ()
          }
        }
      }
    }
    // 并行度约束：jobs > 0 时按批宽 jobs 切分本层；否则整层一批。
    if jobs > 0 && ready.length() > jobs {
      let mut i = 0
      while i < ready.length() {
        let chunk : Array[Target] = []
        let mut k = 0
        while k < jobs && i < ready.length() {
          chunk.push(ready[i])
          i += 1
          k += 1
        }
        batches.push(chunk)
      }
    } else {
      batches.push(ready)
    }
  }
  batches
}

// ─────────────────── 环检测与拓扑序（复用既有图资产） ───────────────────

///|
/// 检测构建图中的依赖环，返回参与环的目标序列；无环返回 `None`。
///
/// 复用 `@directed.tarjan_scc`（`@directed.condensation` 的底层强连通分量
/// 算法）：任一规模大于 1 的强连通分量即为依赖环，直接报告其目标序列；规模
/// 为 1 的分量再检查自环边 `(u, u)`（目标依赖自身）。该实现支撑 Requirement
/// 6.2「报告构成环的节点序列并拒绝执行构建」。
pub fn detect_cycle(g : BuildGraph) -> Array[Target]? {
  let sccs = @directed.tarjan_scc(g.nodes, fn(node) { successors_in(g, node) })
  // 多节点强连通分量即为依赖环。
  for scc in sccs {
    if scc.length() > 1 {
      return Some(scc)
    }
  }
  // 单节点分量：检查自环（目标直接依赖自身）。
  for edge in g.edges {
    let (u, v) = edge
    if u == v {
      return Some([u])
    }
  }
  None
}

///|
/// 计算构建图的拓扑序；存在依赖环时返回 `Cycle`（含具体环节点序列）。
///
/// 直接复用既有图资产 `@directed.topological_sort`（Kahn 算法，O(V+E)）：
/// 依赖边 `(u, v)` 经 `successors_in` 适配为后继函数，拓扑序保证每个目标排在
/// 其全部依赖之后。当 `@directed` 报告存在环时，进一步复用 `detect_cycle`
/// （基于 `tarjan_scc`）给出构成环的目标序列，承载 Requirement 6.3。
pub fn topo_order(g : BuildGraph) -> Result[Array[Target], Cycle] {
  match
    @directed.topological_sort(g.nodes, fn(node) { successors_in(g, node) }) {
    Ok(order) => Ok(order)
    Err(_) =>
      match detect_cycle(g) {
        Some(nodes) => Err(Cycle::new(nodes))
        None => Err(Cycle::new([]))
      }
  }
}
