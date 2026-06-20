// dfa.mbt —— 子集构造确定化（`to_dfa`）与 DFA 匹配执行。
//
// 对应任务 6.2 流水线一环（design.md §「方向二：Regex_Engine」）：
//   syntax → parser → nfa → **dfa（子集构造确定化）** → matcher。
//
// 设计要点：
//   * **字母表原子区间划分**：NFA 的字符转移以码点闭区间表示。收集所有区间
//     的边界点（连同 0 与 MAX_CODE+1）排序去重，得到一组覆盖 [0, MAX_CODE]
//     的不相交"原子区间"。同一原子区间内的所有码点对每条转移的判定一致，
//     故可作为 DFA 的等价字符类（symbol class）。这正确处理了范围 `[a-z]`
//     与否定 `[^...]`（其补集亦为区间并集）。
//   * **锚点作为转移输入的一部分**：锚点 `^` / `$` 依赖绝对位置而非所消费
//     字符，无法折叠进纯字符转移表。故 DFA 转移以 `(状态, 锚点标志, 字符类)`
//     为键：锚点标志取自当前位置（串首 / 串尾），在每一步据其对 NFA 状态集
//     做"锚点闭包"后再判定接受与字符转移。这是确定化自动机处理零宽断言的
//     标准做法，且与 NFA 路径共享同一闭包/转移核心，保证两条路径结果一致
//     （为任务 6.4 差分一致性奠基）。
//
// DFA 状态 = NFA 状态集合（无条件 ε 闭包后的"核"，以排序去重的整型列表
// 表示）。子集构造以广度优先枚举所有可达核。

///|
/// 子集构造确定化产出的确定有限自动机（DFA）。
///
///   * `num_states` —— DFA 状态总数；
///   * `start`      —— DFA 起始状态编号；
///   * `bounds`     —— 字符类原子区间边界（升序去重，首元为 0、末元为
///     MAX_CODE+1）；字符类数 = `bounds.length() - 1`，类 k 覆盖
///     `[bounds[k], bounds[k+1] - 1]`；
///   * `accept`     —— `accept[state][flags]`：在给定锚点标志下，该状态对应
///     的 NFA 状态集（经锚点闭包）是否含接受状态；`flags` ∈ 0..3；
///   * `trans`      —— `trans[state][flags][class]`：转移目标状态编号，
///     `-1` 表示无转移（死路）。
pub struct Dfa {
  num_states : Int
  start : Int
  bounds : Array[Int]
  accept : Array[Array[Bool]]
  trans : Array[Array[Array[Int]]]
}

///|
/// 由锚点标志（是否串首 / 是否串尾）计算其编码下标（0..3）。
fn flag_index(at_start : Bool, at_end : Bool) -> Int {
  if at_start && at_end {
    3
  } else if at_start {
    1
  } else if at_end {
    2
  } else {
    0
  }
}

///|
/// 收集 NFA 全部字符转移的区间边界，连同 0 与 MAX_CODE+1，排序去重，得到
/// 覆盖 [0, MAX_CODE] 的原子区间边界数组。
fn build_bounds(nfa : Nfa) -> Array[Int] {
  let pts : Array[Int] = [0, MAX_CODE + 1]
  for s in 0..<nfa.num_states {
    for pair in nfa.moves[s] {
      let (cs, _t) = pair
      for iv in cs.intervals {
        let (lo, hi) = iv
        pts.push(lo)
        pts.push(hi + 1)
      }
    }
  }
  pts.sort()
  let out : Array[Int] = []
  for i, x in pts {
    if i == 0 || x != out[out.length() - 1] {
      out.push(x)
    }
  }
  out
}

///|
/// 将排序去重的核（NFA 状态集合）编码为可作哈希键的字符串。
fn encode_core(core : Array[Int]) -> String {
  // 以 TextBuilder 物化逗号分隔键，消除循环内字符串 `+`（Requirement 1.5）。
  let acc = @infra_text.TextBuilder::new()
  for i, x in core {
    if i > 0 {
      acc.push_char(',')
    }
    acc.push_str(x.to_string())
  }
  acc.build()
}

///|
/// 子集构造确定化（design.md `to_dfa`，R2.4）。
pub fn to_dfa(nfa : Nfa) -> Dfa {
  let bounds = build_bounds(nfa)
  let num_classes = bounds.length() - 1
  let core_list : Array[Array[Int]] = []
  let id_of : Map[String, Int] = Map([])
  fn intern(core : Array[Int]) -> Int {
    let key = encode_core(core)
    match id_of.get(key) {
      Some(id) => id
      None => {
        let id = core_list.length()
        id_of[key] = id
        core_list.push(core)
        id
      }
    }
  }

  let start_core = nfa.closure([nfa.start], false, false)
  start_core.sort()
  let start_id = intern(start_core)
  let trans : Array[Array[Array[Int]]] = []
  let accept : Array[Array[Bool]] = []
  let mut idx = 0
  while idx < core_list.length() {
    let core = core_list[idx]
    let state_trans : Array[Array[Int]] = []
    let state_accept : Array[Bool] = []
    for f in 0..<4 {
      let at_start = f == 1 || f == 3
      let at_end = f == 2 || f == 3
      let active = nfa.closure(core, at_start, at_end)
      state_accept.push(list_contains(active, nfa.accept))
      let row : Array[Int] = []
      for k in 0..<num_classes {
        let rep = bounds[k]
        let moved = nfa.move_on(active, rep)
        if moved.length() == 0 {
          row.push(-1)
        } else {
          let next_core = nfa.closure(moved, false, false)
          next_core.sort()
          row.push(intern(next_core))
        }
      }
      state_trans.push(row)
    }
    trans.push(state_trans)
    accept.push(state_accept)
    idx = idx + 1
  }
  { num_states: core_list.length(), start: start_id, bounds, accept, trans }
}

///|
/// 将码点映射到其所属字符类下标（原子区间通常很少，线性查找即可）。
fn Dfa::class_of(self : Dfa, code : Int) -> Int {
  let nc = self.bounds.length() - 1
  let mut k = 0
  while k < nc - 1 && self.bounds[k + 1] <= code {
    k = k + 1
  }
  k
}

///|
/// 基于 DFA 的最左最长匹配（R2.5）：语义与 `Nfa::find` 一致，自最小起始
/// 偏移起逐一尝试，返回首个能匹配的起点及其最长匹配区间。
pub fn Dfa::find(self : Dfa, input : String) -> Match? {
  let chars = input.iter().to_array()
  let n = chars.length()
  for i in 0..<=n {
    match self.match_at(chars, n, i) {
      Some(endp) => return Some({ start: i, end: endp })
      None => ()
    }
  }
  None
}

///|
/// 自固定起点 `start` 模拟 DFA，返回最长接受位置（开区间端点）；无接受位置
/// 可达时返回 `None`。
fn Dfa::match_at(self : Dfa, chars : Array[Char], n : Int, start : Int) -> Int? {
  let mut state = self.start
  let mut pos = start
  let mut best : Int? = None
  while true {
    let flags = flag_index(pos == 0, pos == n)
    if self.accept[state][flags] {
      best = Some(pos)
    }
    if pos >= n {
      break
    }
    let cls = self.class_of(chars[pos].to_int())
    let nxt = self.trans[state][flags][cls]
    if nxt < 0 {
      break
    }
    state = nxt
    pos = pos + 1
  }
  best
}
