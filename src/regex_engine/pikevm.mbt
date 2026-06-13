// pikevm.mbt —— Pike VM 执行引擎 `Program::exec` / `Program::is_match`
// （旗舰深化）。
//
// 对应 design.md §4.4 / §4.7（R2/R3/R4/R5）。本文件为**新增**。
//
// paper-to-code：Russ Cox《Regular Expression Matching: the Virtual Machine
// Approach》的 Pike VM。以「线程（thread = (pc, 捕获寄存器快照)）列表」沿输入
// 逐字符推进，每步对线程集做 ε 闭包式展开（处理 `ISplit/IJmp/ISave/IAssert/
// ILook`），并以**每个 pc 至多一条线程**去重（`seen`），把运行步数压到
// `O(程序规模 × 输入长度)`，避免回溯指数爆炸（R2.2）。
//
//   * 优先级与策略（R4）：线程入列顺序即优先级。`LeftmostFirst` 首达 `IMatch`
//     的线程即结果并剪除其后低优先级线程；`LeftmostLongest` 不剪除，按「最左
//     起点优先、同起点取最长」收敛，与 `Nfa::find` 语义一致（R2.6/4.3）。
//   * 捕获寄存器（R2.4）：`ISave(slot)` 写当前位置到线程寄存器副本（写时复制）。
//   * 断言求值（R5）：`IAssert` 按位置判定（`\b` 参考谓词、`^`/`$` 多行 / 非多行）；
//     `ILook` 在当前位置锚定执行子程序（独立、不消费、仅判 bool），捕获不跨界。
//   * 无匹配返回 `None`，不抛异常（R2.5）。
//   * 通过「在每个位置追加一条最低优先级的起点线程」实现单遍最左扫描（leftmost）。

///|
/// Pike VM 线程列表：稠密线程数组 + 按 pc 去重的 `seen` 位图。
priv struct ThreadList {
  mut pcs : Array[Int]
  mut saveds : Array[Array[Int]]
  seen : Array[Bool]
}

///|
/// 新建容量为 `ninst` 的线程列表。
fn ThreadList::new(ninst : Int) -> ThreadList {
  { pcs: [], saveds: [], seen: Array::make(ninst, false) }
}

///|
/// 清空线程列表（保留 `seen` 容量，逐位复位）。
fn ThreadList::reset(self : ThreadList) -> Unit {
  self.pcs = []
  self.saveds = []
  for i in 0..<self.seen.length() {
    self.seen[i] = false
  }
}

///|
/// 复制整型寄存器数组（写时复制语义所需）。
fn copy_ints(a : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  for x in a {
    out.push(x)
  }
  out
}

///|
/// 是否为词字符（`\w`：数字 / 字母 / 下划线）。
fn is_word_code(c : Int) -> Bool {
  (c >= '0'.to_int() && c <= '9'.to_int()) ||
  (c >= 'A'.to_int() && c <= 'Z'.to_int()) ||
  (c >= 'a'.to_int() && c <= 'z'.to_int()) ||
  c == '_'.to_int()
}

///|
/// 词边界判定：pos 左 / 右词字符性相异（串首前 / 串尾后视为非词字符）。
fn word_boundary(chars : Array[Char], n : Int, pos : Int) -> Bool {
  let left = pos > 0 && is_word_code(chars[pos - 1].to_int())
  let right = pos < n && is_word_code(chars[pos].to_int())
  left != right
}

///|
/// 零宽断言在位置 `pos` 是否成立（R5.2/5.3、R6.5/6.6）。
fn assert_holds(
  kind : AssertKind,
  chars : Array[Char],
  n : Int,
  pos : Int,
) -> Bool {
  match kind {
    TextStart => pos == 0
    TextEnd => pos == n
    LineStart => pos == 0 || (pos > 0 && chars[pos - 1] == '\n')
    LineEnd => pos == n || (pos < n && chars[pos] == '\n')
    WordBoundary => word_boundary(chars, n, pos)
    NotWordBoundary => not(word_boundary(chars, n, pos))
  }
}

///|
/// 把线程加入列表，并就地展开 ε 转移（Split/Jmp/Save/Assert/Look），按 pc 去重。
/// `pos` 为该线程所处的输入位置（断言 / 前瞻据此求值）。
fn Program::add_thread(
  self : Program,
  list : ThreadList,
  pc : Int,
  saved : Array[Int],
  chars : Array[Char],
  n : Int,
  pos : Int,
) -> Unit {
  if list.seen[pc] {
    return
  }
  list.seen[pc] = true
  match self.insts[pc] {
    IJmp(x) => self.add_thread(list, x, saved, chars, n, pos)
    ISplit(a, b) => {
      // a 高优先级先入列，b 次之。
      self.add_thread(list, a, saved, chars, n, pos)
      self.add_thread(list, b, saved, chars, n, pos)
    }
    ISave(slot) => {
      let s2 = copy_ints(saved)
      if slot >= 0 && slot < s2.length() {
        s2[slot] = pos
      }
      self.add_thread(list, pc + 1, s2, chars, n, pos)
    }
    IAssert(kind) =>
      if assert_holds(kind, chars, n, pos) {
        self.add_thread(list, pc + 1, saved, chars, n, pos)
      }
    ILook(positive~, prog~) => {
      // 前瞻：锚定执行子程序（不消费、仅判 bool）；捕获不跨前瞻边界导出。
      let ok = prog.run_bool(chars, n, pos)
      if ok == positive {
        self.add_thread(list, pc + 1, saved, chars, n, pos)
      }
    }
    // IChar / ISet / IMatch：在当前位置终结，加入稠密列表待逐字符处理。
    _ => {
      list.pcs.push(pc)
      list.saveds.push(saved)
    }
  }
}

///|
/// 布尔模式运行（供前瞻）：自 `start` 锚定执行，是否存在到达 `IMatch` 的线程。
fn Program::run_bool(
  self : Program,
  chars : Array[Char],
  n : Int,
  start : Int,
) -> Bool {
  let ninst = self.insts.length()
  let mut clist = ThreadList::new(ninst)
  let mut nlist = ThreadList::new(ninst)
  let init = Array::make(2 * (self.num_groups + 1), -1)
  self.add_thread(clist, 0, init, chars, n, start)
  let mut pos = start
  while true {
    let mut i = 0
    while i < clist.pcs.length() {
      let pc = clist.pcs[i]
      let saved = clist.saveds[i]
      match self.insts[pc] {
        IChar(ch) =>
          if pos < n && chars[pos] == ch {
            self.add_thread(nlist, pc + 1, saved, chars, n, pos + 1)
          }
        ISet(cs) =>
          if pos < n && cs.contains(chars[pos].to_int()) {
            self.add_thread(nlist, pc + 1, saved, chars, n, pos + 1)
          }
        IMatch => return true
        _ => ()
      }
      i = i + 1
    }
    if pos >= n {
      break
    }
    pos = pos + 1
    let tmp = clist
    clist = nlist
    nlist = tmp
    nlist.reset()
    if clist.pcs.length() == 0 {
      break
    }
  }
  false
}

///|
/// 在 leftmost-longest 候选间取舍：最左起点优先，同起点取最长。
fn pick_longest(cur : Array[Int]?, cand : Array[Int]) -> Array[Int]? {
  match cur {
    None => Some(cand)
    Some(c) => {
      let cs = c[0]
      let ce = c[1]
      let ds = cand[0]
      let de = cand[1]
      if ds < cs {
        Some(cand)
      } else if ds == cs && de > ce {
        Some(cand)
      } else {
        Some(c)
      }
    }
  }
}

///|
/// Pike VM 执行入口（R2.1）：在 `input` 上自 `start` 起做最左匹配，按 `kind`
/// 策略产出含捕获结果的匹配；无匹配返回 `None`（R2.5）。
pub fn Program::exec(
  self : Program,
  input : String,
  start~ : Int = 0,
  kind~ : MatchKind = LeftmostLongest,
) -> Captures? {
  let chars = input.iter().to_array()
  let n = chars.length()
  let ninst = self.insts.length()
  let slots_len = 2 * (self.num_groups + 1)
  let mut clist = ThreadList::new(ninst)
  let mut nlist = ThreadList::new(ninst)
  let mut matched : Array[Int]? = None
  let mut pos = start
  while true {
    // 在每个位置追加最低优先级起点线程，实现单遍最左扫描；命中后停止播种。
    match matched {
      None => {
        let init = Array::make(slots_len, -1)
        self.add_thread(clist, 0, init, chars, n, pos)
      }
      Some(_) => ()
    }
    let mut i = 0
    while i < clist.pcs.length() {
      let pc = clist.pcs[i]
      let saved = clist.saveds[i]
      match self.insts[pc] {
        IChar(ch) =>
          if pos < n && chars[pos] == ch {
            self.add_thread(nlist, pc + 1, saved, chars, n, pos + 1)
          }
        ISet(cs) =>
          if pos < n && cs.contains(chars[pos].to_int()) {
            self.add_thread(nlist, pc + 1, saved, chars, n, pos + 1)
          }
        IMatch =>
          match kind {
            // 最左优先：首达即结果，剪除其后（更低优先级）线程。
            LeftmostFirst => {
              matched = Some(saved)
              break
            }
            // 最左最长：不剪除，按最左 / 最长收敛。
            LeftmostLongest => matched = pick_longest(matched, saved)
          }
        _ => ()
      }
      i = i + 1
    }
    let tmp = clist
    clist = nlist
    nlist = tmp
    nlist.reset()
    if pos >= n {
      break
    }
    match matched {
      Some(_) => if clist.pcs.length() == 0 { break }
      None => ()
    }
    pos = pos + 1
  }
  match matched {
    Some(s) => Some({ slots: s, names: self.names })
    None => None
  }
}

///|
/// 便捷判定：输入中是否存在匹配（不关心区间 / 捕获）。
pub fn Program::is_match(self : Program, input : String) -> Bool {
  match self.exec(input) {
    Some(_) => true
    None => false
  }
}


///|
/// 基准 / 复杂度 guard 用：返回 Pike VM 在 `input` 上自位置 0 起执行的**线程
/// 步数**（每处理 `clist` 中一个待消费线程计 1 步）。
///
/// 该计数完全确定、跨三后端逐位一致，是 Pike VM「运行步数与正则规模 × 输入
/// 长度成线性、绝不指数回溯」保证（R2.2）的可观测见证，供 `benches/regex_bench`
/// 的回归 guard 以声明容差守护（R9.4）。本函数为**新增旁路**，不改任何既有
/// 执行入口的签名或行为。
pub fn Program::exec_steps(self : Program, input : String) -> Int {
  let chars = input.iter().to_array()
  let n = chars.length()
  let ninst = self.insts.length()
  let slots_len = 2 * (self.num_groups + 1)
  let mut clist = ThreadList::new(ninst)
  let mut nlist = ThreadList::new(ninst)
  let mut steps = 0
  let mut pos = 0
  let mut matched = false
  while true {
    if not(matched) {
      let init = Array::make(slots_len, -1)
      self.add_thread(clist, 0, init, chars, n, pos)
    }
    let mut i = 0
    while i < clist.pcs.length() {
      steps = steps + 1
      let pc = clist.pcs[i]
      let saved = clist.saveds[i]
      match self.insts[pc] {
        IChar(ch) =>
          if pos < n && chars[pos] == ch {
            self.add_thread(nlist, pc + 1, saved, chars, n, pos + 1)
          }
        ISet(cs) =>
          if pos < n && cs.contains(chars[pos].to_int()) {
            self.add_thread(nlist, pc + 1, saved, chars, n, pos + 1)
          }
        IMatch => matched = true
        _ => ()
      }
      i = i + 1
    }
    let tmp = clist
    clist = nlist
    nlist = tmp
    nlist.reset()
    if pos >= n {
      break
    }
    pos = pos + 1
  }
  steps
}
