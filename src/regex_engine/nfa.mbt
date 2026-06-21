// nfa.mbt —— Thompson 构造（`build_nfa`）与 NFA 匹配执行。
//
// 对应任务 6.2 的流水线一环（design.md §「方向二：Regex_Engine」）：
//   syntax → parser → **nfa（Thompson 构造）** → dfa（子集构造）→ matcher。
//
// 本文件负责：
//   * `CharSet` —— 以归一化、不相交、升序的码点闭区间表示"一个字符转移可
//     消费的字符集合"。字面字符是单点区间；字符类是区间并集；否定字符类
//     是其在 [0, MAX_CODE] 上的补集。区间化表示使得后续 DFA 子集构造可对
//     字母表做"原子区间划分"，从而正确处理范围与否定（见 dfa.mbt）。
//   * `Nfa` —— Thompson 构造产出的带 ε 转移的非确定自动机；锚点 `^` / `$`
//     建模为"位置受限的 ε 转移"（at_start / at_end），匹配时按当前绝对
//     位置决定是否可走，从而支持锚点出现在任意位置。
//   * `build_nfa` —— 由 `Regex` 语法树递归构造 NFA。
//   * `Nfa::find` —— 基于 NFA 的最左最长（leftmost-longest）匹配执行，返回
//     匹配区间（起止字符偏移，end 为开区间端点），与 DFA 路径结果一致
//     （为任务 6.4 差分一致性奠基）。
//
// 偏移约定：与 `@pc.Input` 一致，输入按 `String::iter()` 的 Unicode 标量
// 字符序列索引，`Match` 的 start/end 即该字符序列上的偏移。

///|
/// 受支持的最大 Unicode 码点（U+10FFFF）。否定字符类的补集在 [0, MAX_CODE]
/// 上闭合，字母表原子区间划分亦以此为上界。
const MAX_CODE : Int = 0x10FFFF

///|
/// 字符集合（character set）：一个字符转移所能消费的码点集合，以归一化、
/// 不相交、升序的闭区间序列表示。空区间序列表示"不匹配任何字符"。
pub(all) struct CharSet {
  intervals : Array[(Int, Int)]
} derive(Eq)

///|
/// 判定码点 `code` 是否落入字符集合。
///
/// `intervals` 满足「归一化、不相交、升序」不变量（由 `normalize_intervals`
/// 保证），故以二分查找定位可能覆盖 `code` 的区间：O(log k)（k 为区间数），
/// 替代原线性扫描 O(k)（旗舰深化：CharSet 二分查找性能，R5）。
pub fn CharSet::contains(self : CharSet, code : Int) -> Bool {
  let ivs = self.intervals
  let mut lo = 0
  let mut hi = ivs.length() - 1
  while lo <= hi {
    let mid = lo + (hi - lo) / 2
    let (l, h) = ivs[mid]
    if code < l {
      hi = mid - 1
    } else if code > h {
      lo = mid + 1
    } else {
      return true
    }
  }
  false
}

///|
/// Thompson 构造产出的非确定有限自动机（NFA）。
///
///   * `num_states` —— 状态总数；状态以 `0 ..< num_states` 的整数标识；
///   * `start` / `accept` —— 唯一起始状态与唯一接受状态；
///   * `eps`       —— 无条件 ε 转移邻接表；
///   * `at_start`  —— 仅当处于串首（绝对位置 0）时可走的 ε 转移（锚点 `^`）；
///   * `at_end`    —— 仅当处于串尾（位置 == 输入长度）时可走的 ε 转移（`$`）；
///   * `moves`     —— 字符消费转移：`(可消费字符集合, 目标状态)`。
pub struct Nfa {
  num_states : Int
  start : Int
  accept : Int
  eps : Array[Array[Int]]
  at_start : Array[Array[Int]]
  at_end : Array[Array[Int]]
  moves : Array[Array[(CharSet, Int)]]
}

///|
/// NFA 增量构造器：持有可变邻接表，按需分配新状态并登记转移。
priv struct NfaBuilder {
  eps : Array[Array[Int]]
  at_start : Array[Array[Int]]
  at_end : Array[Array[Int]]
  moves : Array[Array[(CharSet, Int)]]
}

///|
/// 片段（fragment）：子表达式编译产出的"单入口 `start`、单出口 `accept`"
/// 子自动机，便于按 Thompson 规则组合。
priv struct Frag {
  start : Int
  accept : Int
}

///|
/// 新建空构造器。
fn NfaBuilder::new() -> NfaBuilder {
  { eps: [], at_start: [], at_end: [], moves: [] }
}

///|
/// 分配一个新状态并返回其编号。
fn NfaBuilder::new_state(self : NfaBuilder) -> Int {
  let id = self.eps.length()
  self.eps.push([])
  self.at_start.push([])
  self.at_end.push([])
  self.moves.push([])
  id
}

///|
/// 登记无条件 ε 转移 `from -> to`。
fn NfaBuilder::add_eps(self : NfaBuilder, from : Int, to : Int) -> Unit {
  self.eps[from].push(to)
}

///|
/// 登记串首受限 ε 转移（锚点 `^`）。
fn NfaBuilder::add_start(self : NfaBuilder, from : Int, to : Int) -> Unit {
  self.at_start[from].push(to)
}

///|
/// 登记串尾受限 ε 转移（锚点 `$`）。
fn NfaBuilder::add_end(self : NfaBuilder, from : Int, to : Int) -> Unit {
  self.at_end[from].push(to)
}

///|
/// 登记字符消费转移 `from --cs--> to`。
fn NfaBuilder::add_move(
  self : NfaBuilder,
  from : Int,
  cs : CharSet,
  to : Int,
) -> Unit {
  self.moves[from].push((cs, to))
}

///|
/// 由 `Regex` 语法树构造等价 NFA（design.md `build_nfa`，R2.4）。
pub fn build_nfa(r : Regex) -> Nfa {
  let b = NfaBuilder::new()
  let frag = compile_frag(b, r)
  {
    num_states: b.eps.length(),
    start: frag.start,
    accept: frag.accept,
    eps: b.eps,
    at_start: b.at_start,
    at_end: b.at_end,
    moves: b.moves,
  }
}

///|
/// 递归地将子表达式编译为片段（Thompson 构造核心）。
fn compile_frag(b : NfaBuilder, r : Regex) -> Frag {
  match r {
    Char(c) => {
      let s = b.new_state()
      let a = b.new_state()
      b.add_move(s, char_set_of_char(c), a)
      { start: s, accept: a }
    }
    Class(cc) => {
      let s = b.new_state()
      let a = b.new_state()
      b.add_move(s, char_set_of_class(cc), a)
      { start: s, accept: a }
    }
    Anchor(Start) => {
      let s = b.new_state()
      let a = b.new_state()
      b.add_start(s, a)
      { start: s, accept: a }
    }
    Anchor(End) => {
      let s = b.new_state()
      let a = b.new_state()
      b.add_end(s, a)
      { start: s, accept: a }
    }
    Group(inner) => compile_frag(b, inner)
    Concat(parts) =>
      if parts.length() == 0 {
        let s = b.new_state()
        let a = b.new_state()
        b.add_eps(s, a)
        { start: s, accept: a }
      } else {
        let f0 = compile_frag(b, parts[0])
        let mut prev_accept = f0.accept
        for i in 1..<parts.length() {
          let fi = compile_frag(b, parts[i])
          b.add_eps(prev_accept, fi.start)
          prev_accept = fi.accept
        }
        { start: f0.start, accept: prev_accept }
      }
    Alt(branches) =>
      if branches.length() == 0 {
        let s = b.new_state()
        let a = b.new_state()
        b.add_eps(s, a)
        { start: s, accept: a }
      } else {
        let s = b.new_state()
        let a = b.new_state()
        for br in branches {
          let f = compile_frag(b, br)
          b.add_eps(s, f.start)
          b.add_eps(f.accept, a)
        }
        { start: s, accept: a }
      }
    Star(inner) => {
      let s = b.new_state()
      let a = b.new_state()
      let f = compile_frag(b, inner)
      b.add_eps(s, f.start)
      b.add_eps(s, a)
      b.add_eps(f.accept, f.start)
      b.add_eps(f.accept, a)
      { start: s, accept: a }
    }
    Plus(inner) => {
      let f = compile_frag(b, inner)
      let a = b.new_state()
      b.add_eps(f.accept, f.start)
      b.add_eps(f.accept, a)
      { start: f.start, accept: a }
    }
    Opt(inner) => {
      let s = b.new_state()
      let a = b.new_state()
      let f = compile_frag(b, inner)
      b.add_eps(s, f.start)
      b.add_eps(s, a)
      b.add_eps(f.accept, a)
      { start: s, accept: a }
    }
    Repeat(inner, m, hi) => compile_repeat(b, inner, m, hi)
  }
}

///|
/// 编译计数量词 `{m}` / `{m,}` / `{m,n}`：m 份强制副本，随后视上界附加
/// "无界星闭包"（`{m,}`）或 `(n-m)` 份可跳过的可选副本（`{m,n}`）。
fn compile_repeat(b : NfaBuilder, inner : Regex, m : Int, hi : Int?) -> Frag {
  let s = b.new_state()
  let mut tail = s
  for _i in 0..<m {
    let f = compile_frag(b, inner)
    b.add_eps(tail, f.start)
    tail = f.accept
  }
  match hi {
    None => {
      // {m,}：m 份强制副本之后接 inner 的星闭包。
      let f = compile_frag(b, inner)
      let endst = b.new_state()
      b.add_eps(tail, f.start)
      b.add_eps(tail, endst)
      b.add_eps(f.accept, f.start)
      b.add_eps(f.accept, endst)
      { start: s, accept: endst }
    }
    Some(n) => {
      // {m,n}：m 份强制副本之后接 (n-m) 份可选副本，每份均可跳到出口。
      let endst = b.new_state()
      let mut t = tail
      for _i in 0..<(n - m) {
        let f = compile_frag(b, inner)
        b.add_eps(t, f.start)
        b.add_eps(t, endst)
        t = f.accept
      }
      b.add_eps(t, endst)
      { start: s, accept: endst }
    }
  }
}

///|
/// 字面字符 → 单点区间字符集合。
fn char_set_of_char(c : Char) -> CharSet {
  let code = c.to_int()
  { intervals: [(code, code)] }
}

///|
/// 字符类 → 字符集合：正向类取成员区间并集；否定类取其在 [0, MAX_CODE]
/// 上的补集。
fn char_set_of_class(cc : CharClass) -> CharSet {
  let raw : Array[(Int, Int)] = []
  for item in cc.items {
    match item {
      Single(c) => {
        let v = c.to_int()
        raw.push((v, v))
      }
      Range(lo, hi) => {
        let a = lo.to_int()
        let b = hi.to_int()
        if a <= b {
          raw.push((a, b))
        } else {
          raw.push((b, a))
        }
      }
    }
  }
  let merged = normalize_intervals(raw)
  if cc.negated {
    { intervals: complement_intervals(merged) }
  } else {
    { intervals: merged }
  }
}

///|
/// 按下界升序对区间数组就地排序（插入排序，区间数通常很小）。
fn sort_intervals(arr : Array[(Int, Int)]) -> Unit {
  let n = arr.length()
  for i in 1..<n {
    let key = arr[i]
    let (klo, _khi) = key
    let mut j = i - 1
    while j >= 0 {
      let (jlo, _jhi) = arr[j]
      if jlo > klo {
        arr[j + 1] = arr[j]
        j = j - 1
      } else {
        break
      }
    }
    arr[j + 1] = key
  }
}

///|
/// 归一化区间：排序后合并重叠或相邻（`lo <= chi + 1`）的区间，得到不相交、
/// 升序的闭区间序列。
fn normalize_intervals(raw : Array[(Int, Int)]) -> Array[(Int, Int)] {
  if raw.length() == 0 {
    return []
  }
  sort_intervals(raw)
  let (flo, fhi) = raw[0]
  let mut clo = flo
  let mut chi = fhi
  let out : Array[(Int, Int)] = []
  for i in 1..<raw.length() {
    let (lo, hi) = raw[i]
    if lo <= chi + 1 {
      if hi > chi {
        chi = hi
      }
    } else {
      out.push((clo, chi))
      clo = lo
      chi = hi
    }
  }
  out.push((clo, chi))
  out
}

///|
/// 求归一化区间序列在 [0, MAX_CODE] 上的补集（用于否定字符类）。
fn complement_intervals(ivs : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let mut cur = 0
  for iv in ivs {
    let (lo, hi) = iv
    if lo > cur {
      out.push((cur, lo - 1))
    }
    if hi + 1 > cur {
      cur = hi + 1
    }
  }
  if cur <= MAX_CODE {
    out.push((cur, MAX_CODE))
  }
  out
}

///|
/// ε / 锚点闭包：从 `seeds` 出发，沿无条件 ε 转移恒走，并在 `at_start` /
/// `at_end` 标志成立时沿对应受限 ε 转移走，直至不动点。返回去重后的可达
/// 状态列表（次序为广度优先发现序）。
fn Nfa::closure(
  self : Nfa,
  seeds : Array[Int],
  at_start : Bool,
  at_end : Bool,
) -> Array[Int] {
  let visited = Array::make(self.num_states, false)
  let order : Array[Int] = []
  for s in seeds {
    if !visited[s] {
      visited[s] = true
      order.push(s)
    }
  }
  let mut i = 0
  while i < order.length() {
    let s = order[i]
    i = i + 1
    for t in self.eps[s] {
      if !visited[t] {
        visited[t] = true
        order.push(t)
      }
    }
    if at_start {
      for t in self.at_start[s] {
        if !visited[t] {
          visited[t] = true
          order.push(t)
        }
      }
    }
    if at_end {
      for t in self.at_end[s] {
        if !visited[t] {
          visited[t] = true
          order.push(t)
        }
      }
    }
  }
  order
}

///|
/// 从状态集合出发，对码点 `code` 求字符转移后的目标状态集合（可能含重复，
/// 由后续闭包去重）。
fn Nfa::move_on(self : Nfa, states : Array[Int], code : Int) -> Array[Int] {
  let out : Array[Int] = []
  for s in states {
    for pair in self.moves[s] {
      let (cs, t) = pair
      if cs.contains(code) {
        out.push(t)
      }
    }
  }
  out
}

///|
/// 基于 NFA 的最左最长匹配（R2.5）：自最小起始偏移起逐一尝试，返回首个
/// 能匹配的起点及其最长匹配区间；无匹配时返回 `None`。
pub fn Nfa::find(self : Nfa, input : String) -> Match? {
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
/// 自固定起点 `start` 模拟 NFA，返回最长接受位置（开区间端点）；若无任何
/// 接受位置可达则返回 `None`。
fn Nfa::match_at(self : Nfa, chars : Array[Char], n : Int, start : Int) -> Int? {
  let mut frontier = [self.start]
  let mut pos = start
  let mut best : Int? = None
  while true {
    let active = self.closure(frontier, pos == 0, pos == n)
    if list_contains(active, self.accept) {
      best = Some(pos)
    }
    if pos >= n {
      break
    }
    let moved = self.move_on(active, chars[pos].to_int())
    if moved.length() == 0 {
      break
    }
    frontier = moved
    pos = pos + 1
  }
  best
}

///|
/// 整型列表线性成员判定（状态集合通常很小）。
fn list_contains(xs : Array[Int], v : Int) -> Bool {
  for x in xs {
    if x == v {
      return true
    }
  }
  false
}
