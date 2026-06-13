// liveness.mbt —— 活跃变量数据流分析（liveness analysis），旗舰深化旁路新增。
//
// paper-to-code：经典后向数据流不动点（backward dataflow fixpoint）；
// Appel《Modern Compiler Implementation》活跃性分析章节。
//
// 设计落点（design.md §4.1，R4）：骨架的 `InterferenceGraph` 与 `LiveInterval`
// 此前需人工构造；本模块让它们来自真实活跃性。指令的 use/def 由块内记号串解析：
//   * `name = rhs...`     —— 定义 `name`，右值中的变量为 use；
//   * `ret x`             —— 仅含 use `x`；
//   * `br L`              —— 无 use（`L` 为块标签）；
//   * `cbr c L1 L2`       —— 仅条件 `c` 为 use（`L1`/`L2` 为块标签）。
//
// 变量以名字标识，本模块按「全程序出现的变量名升序」分配确定性的 `Var.id`，
// 使活跃性集合、干涉图与活跃区间在 `wasm-gc`/`js`/`native` 三后端逐位一致
// （R16.1，集合一律以 `Var.id` 升序数组规范化，不依赖 `Map` 遍历顺序）。

// ---------------------------------------------------------------------------
// 活跃性结果
// ---------------------------------------------------------------------------

///|
/// 活跃性分析结果：每个基本块的 live-in / live-out 变量集（按 `Var.id` 升序）。
pub(all) struct LivenessResult {
  live_in : Map[String, Array[Var]]
  live_out : Map[String, Array[Var]]
} derive(Show)

// ---------------------------------------------------------------------------
// 变量名 ↔ Var.id 的确定性映射
// ---------------------------------------------------------------------------

///|
/// 一个记号是否为「变量名」：既非整型字面量，也非二元运算符记号。
fn is_var_token(tok : String) -> Bool {
  if tok == "" {
    return false
  }
  match parse_int(tok) {
    Some(_) => false
    None =>
      not(tok == "+" || tok == "-" || tok == "*" || tok == "/" || tok == "=")
  }
}

///|
/// 解析单条指令的 use（变量名，去重保序）与 def（变量名，若有）。
fn instr_use_def(instr : String) -> (Array[String], String?) {
  let toks = tokenize(instr)
  if toks.length() >= 2 && toks[1] == "=" {
    let uses : Array[String] = []
    let mut j = 2
    while j < toks.length() {
      let t = toks[j]
      if is_var_token(t) && not(array_contains_str(uses, t)) {
        uses.push(t)
      }
      j = j + 1
    }
    return (uses, Some(toks[0]))
  }
  if toks.length() == 0 {
    return ([], None)
  }
  let kw = toks[0]
  let uses : Array[String] = []
  if kw == "br" {
    // 无变量 use（操作数为块标签）。
    ()
  } else if kw == "cbr" {
    // 仅条件记号（toks[1]）为 use；其余为块标签。
    if toks.length() >= 2 && is_var_token(toks[1]) {
      uses.push(toks[1])
    }
  } else {
    // `ret x` 及其它非定义指令：其后所有变量记号均为 use。
    let mut j = 1
    while j < toks.length() {
      let t = toks[j]
      if is_var_token(t) && not(array_contains_str(uses, t)) {
        uses.push(t)
      }
      j = j + 1
    }
  }
  (uses, None)
}

///|
/// 数组是否包含某字符串。
fn array_contains_str(arr : Array[String], x : String) -> Bool {
  for v in arr {
    if v == x {
      return true
    }
  }
  false
}

///|
/// 收集全程序出现的变量名（use ∪ def），升序去重。
fn collect_var_names(blocks : Array[BasicBlock]) -> Array[String] {
  let seen : Map[String, Bool] = Map([])
  let names : Array[String] = []
  for b in blocks {
    for instr in b.instrs {
      let (uses, def) = instr_use_def(instr)
      for u in uses {
        if not(seen.contains(u)) {
          seen[u] = true
          names.push(u)
        }
      }
      match def {
        Some(d) =>
          if not(seen.contains(d)) {
            seen[d] = true
            names.push(d)
          }
        None => ()
      }
    }
  }
  names.sort()
  names
}

///|
/// 构造变量名 → `Var.id` 的确定性映射（id = 升序名次）。
fn name_to_id_map(names : Array[String]) -> Map[String, Int] {
  let m : Map[String, Int] = Map([])
  for i, nm in names {
    m[nm] = i
  }
  m
}

// ---------------------------------------------------------------------------
// 整数集合工具（以升序 Int 数组规范化表示）
// ---------------------------------------------------------------------------

///|
/// 将 id 集合（Map 充当集合）规范化为升序数组。
fn id_set_to_sorted(s : Map[Int, Bool]) -> Array[Int] {
  let out : Array[Int] = []
  for kv in s {
    let (k, _) = kv
    out.push(k)
  }
  out.sort()
  out
}

///|
/// 升序 Int 数组转为 `Var` 数组。
fn ids_to_vars(ids : Array[Int]) -> Array[Var] {
  let out : Array[Var] = []
  for i in ids {
    out.push({ id: i })
  }
  out
}

// ---------------------------------------------------------------------------
// 块级 use / def（upward-exposed use；按 id 集合）
// ---------------------------------------------------------------------------

///|
/// 计算块的 upward-exposed use 集与 def 集（按 `Var.id`）。
///
/// 在块内顺序扫描指令，每条指令先记入「在本块内尚未被定义」的 use（向上暴露），
/// 再登记其 def——故 `x = x + 1` 中对 `x` 的使用读取的是入块前的值，被视为向上
/// 暴露 use。这是活跃性传递方程 `live_in(b)=use(b)∪(live_out(b)\def(b))` 中
/// `use(b)`/`def(b)` 的标准定义。
fn block_use_def(
  block : BasicBlock,
  name2id : Map[String, Int],
) -> (Map[Int, Bool], Map[Int, Bool]) {
  let defined : Map[String, Bool] = Map([])
  let use_set : Map[Int, Bool] = Map([])
  let def_set : Map[Int, Bool] = Map([])
  for instr in block.instrs {
    let (uses, def) = instr_use_def(instr)
    for u in uses {
      if not(defined.contains(u)) {
        match name2id.get(u) {
          Some(id) => use_set[id] = true
          None => ()
        }
      }
    }
    match def {
      Some(d) => {
        match name2id.get(d) {
          Some(id) => def_set[id] = true
          None => ()
        }
        defined[d] = true
      }
      None => ()
    }
  }
  (use_set, def_set)
}

// ---------------------------------------------------------------------------
// 活跃性不动点
// ---------------------------------------------------------------------------

///|
/// 对当前活跃性集合施加一轮后向传递方程，返回新的活跃性结果。
///
///   `live_out(b) = ⋃_{s∈succ(b)} live_in(s)`
///   `live_in(b)  = use(b) ∪ (live_out(b) \ def(b))`
///
/// 该函数是「不动点」性质（Property 6）的传递算子：`analyze_liveness` 的结果
/// 应是其不动点（再施加一次不改变任何块集合）。
pub fn liveness_step(
  blocks : Array[BasicBlock],
  live : LivenessResult,
) -> LivenessResult {
  let names = collect_var_names(blocks)
  let name2id = name_to_id_map(names)
  // 当前 live_in（id 集），缺省空集。
  let cur_in : Map[String, Map[Int, Bool]] = Map([])
  for b in blocks {
    let s : Map[Int, Bool] = Map([])
    match live.live_in.get(b.label) {
      Some(vs) =>
        for v in vs {
          s[v.id] = true
        }
      None => ()
    }
    cur_in[b.label] = s
  }
  let new_in : Map[String, Array[Var]] = Map([])
  let new_out : Map[String, Array[Var]] = Map([])
  for b in blocks {
    // live_out = ⋃ succ live_in
    let out_set : Map[Int, Bool] = Map([])
    for s in b.succs {
      match cur_in.get(s) {
        Some(sin) =>
          for kv in sin {
            let (id, _) = kv
            out_set[id] = true
          }
        None => ()
      }
    }
    let (use_set, def_set) = block_use_def(b, name2id)
    // live_in = use ∪ (live_out \ def)
    let in_set : Map[Int, Bool] = Map([])
    for kv in use_set {
      let (id, _) = kv
      in_set[id] = true
    }
    for kv in out_set {
      let (id, _) = kv
      if not(def_set.contains(id)) {
        in_set[id] = true
      }
    }
    new_out[b.label] = ids_to_vars(id_set_to_sorted(out_set))
    new_in[b.label] = ids_to_vars(id_set_to_sorted(in_set))
  }
  { live_in: new_in, live_out: new_out }
}

///|
/// 比较两个活跃性结果是否在所有块的 live-in / live-out 上完全一致。
fn liveness_equal(
  blocks : Array[BasicBlock],
  a : LivenessResult,
  b : LivenessResult,
) -> Bool {
  for blk in blocks {
    if not(
        var_arrays_equal(
          a.live_in.get(blk.label).unwrap_or([]),
          b.live_in.get(blk.label).unwrap_or([]),
        ),
      ) {
      return false
    }
    if not(
        var_arrays_equal(
          a.live_out.get(blk.label).unwrap_or([]),
          b.live_out.get(blk.label).unwrap_or([]),
        ),
      ) {
      return false
    }
  }
  true
}

///|
/// 两个（已按 id 升序规范化的）`Var` 数组是否相等。
fn var_arrays_equal(a : Array[Var], b : Array[Var]) -> Bool {
  if a.length() != b.length() {
    return false
  }
  for i in 0..<a.length() {
    if a[i].id != b[i].id {
      return false
    }
  }
  true
}

///|
/// 活跃变量分析：后向数据流不动点迭代。
///
/// 初始 live_in = live_out = ∅，反复施加 `liveness_step` 直到一轮内所有块集合
/// 不再变化（或达安全上界），返回最小不动点。集合按 `Var.id` 升序规范化以保证
/// 三后端确定性。
pub fn analyze_liveness(blocks : Array[BasicBlock]) -> LivenessResult {
  let empty_in : Map[String, Array[Var]] = Map([])
  let empty_out : Map[String, Array[Var]] = Map([])
  for b in blocks {
    empty_in[b.label] = []
    empty_out[b.label] = []
  }
  let mut cur : LivenessResult = { live_in: empty_in, live_out: empty_out }
  // 安全上界：后向活跃性最多 (块数 * 变量数 + 1) 轮收敛，留足冗余。
  let limit = blocks.length() * (collect_var_names(blocks).length() + 1) + 2
  let mut iter = 0
  while iter <= limit {
    let next = liveness_step(blocks, cur)
    if liveness_equal(blocks, next, cur) {
      return next
    }
    cur = next
    iter = iter + 1
  }
  cur
}

// ---------------------------------------------------------------------------
// 由活跃性构造干涉图与活跃区间
// ---------------------------------------------------------------------------

///|
/// 由活跃性结果构造干涉图：在同一程序点同时活跃的每一对变量之间建无向边。
///
/// 对每个块自 live-out 起后向逐指令推进活跃集，在每个程序点登记当前活跃集中
/// 的全部变量对（较小 id 在前）。边按字典序去重排序，保证三后端确定性。
pub fn build_interference_from_liveness(
  blocks : Array[BasicBlock],
  live : LivenessResult,
) -> InterferenceGraph {
  let names = collect_var_names(blocks)
  let name2id = name_to_id_map(names)
  let nodes : Array[Var] = []
  for i in 0..<names.length() {
    nodes.push({ id: i })
  }
  let edge_set : Map[(Int, Int), Bool] = Map([])
  fn add_pairs(cur : Map[Int, Bool]) -> Unit {
    let live_ids = id_set_to_sorted(cur)
    for i in 0..<live_ids.length() {
      for j in (i + 1)..<live_ids.length() {
        edge_set[(live_ids[i], live_ids[j])] = true
      }
    }
  }

  for b in blocks {
    let cur : Map[Int, Bool] = Map([])
    match live.live_out.get(b.label) {
      Some(vs) =>
        for v in vs {
          cur[v.id] = true
        }
      None => ()
    }
    add_pairs(cur)
    // 后向逐指令推进活跃集。
    let mut idx = b.instrs.length() - 1
    while idx >= 0 {
      let (uses, def) = instr_use_def(b.instrs[idx])
      match def {
        Some(d) =>
          match name2id.get(d) {
            Some(id) => cur.remove(id)
            None => ()
          }
        None => ()
      }
      for u in uses {
        match name2id.get(u) {
          Some(id) => cur[id] = true
          None => ()
        }
      }
      add_pairs(cur)
      idx = idx - 1
    }
  }
  let edges : Array[(Var, Var)] = []
  for kv in edge_set {
    let ((a, b), _) = kv
    edges.push(({ id: a }, { id: b }))
  }
  edges.sort_by(fn(e1, e2) {
    let (a1, b1) = e1
    let (a2, b2) = e2
    if a1.id != a2.id {
      a1.id - a2.id
    } else {
      b1.id - b2.id
    }
  })
  { nodes, edges }
}

///|
/// 由活跃性结果构造活跃区间：每个变量的区间覆盖其首次出现到最后一次出现的
/// 线性化指令序号；并依据 live-in / live-out 将区间延展至其活跃的块边界。
pub fn build_intervals_from_liveness(
  blocks : Array[BasicBlock],
  live : LivenessResult,
) -> Array[LiveInterval] {
  let names = collect_var_names(blocks)
  let name2id = name_to_id_map(names)
  // 为每条指令分配全局线性序号；空块占一个序号槽。
  let block_start : Map[String, Int] = Map([])
  let block_end : Map[String, Int] = Map([])
  let start_of : Map[Int, Int] = Map([]) // var id → 区间起点
  let end_of : Map[Int, Int] = Map([]) // var id → 区间终点
  fn touch(id : Int, idx : Int) -> Unit {
    match start_of.get(id) {
      Some(s) => if idx < s { start_of[id] = idx }
      None => start_of[id] = idx
    }
    match end_of.get(id) {
      Some(e) => if idx > e { end_of[id] = idx }
      None => end_of[id] = idx
    }
  }

  let mut idx = 0
  for b in blocks {
    block_start[b.label] = idx
    if b.instrs.length() == 0 {
      idx = idx + 1
    } else {
      for instr in b.instrs {
        let (uses, def) = instr_use_def(instr)
        for u in uses {
          match name2id.get(u) {
            Some(id) => touch(id, idx)
            None => ()
          }
        }
        match def {
          Some(d) =>
            match name2id.get(d) {
              Some(id) => touch(id, idx)
              None => ()
            }
          None => ()
        }
        idx = idx + 1
      }
    }
    block_end[b.label] = idx - 1
  }
  // 依据 live-in / live-out 延展区间至活跃的块边界。
  for b in blocks {
    let bs = block_start.get(b.label).unwrap_or(0)
    let be = block_end.get(b.label).unwrap_or(bs)
    match live.live_in.get(b.label) {
      Some(vs) =>
        for v in vs {
          touch(v.id, bs)
        }
      None => ()
    }
    match live.live_out.get(b.label) {
      Some(vs) =>
        for v in vs {
          touch(v.id, be)
        }
      None => ()
    }
  }
  let intervals : Array[LiveInterval] = []
  for id in 0..<names.length() {
    match (start_of.get(id), end_of.get(id)) {
      (Some(s), Some(e)) =>
        intervals.push({ variable: { id, }, start: s, end: e })
      _ => ()
    }
  }
  intervals.sort_by(fn(a, b) { a.variable.id - b.variable.id })
  intervals
}
