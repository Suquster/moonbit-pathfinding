// rope.mbt —— E6 文本基础设施：rope 编辑器内核（对标 xi-editor rope /
// SGI cord）。
//
// paper-to-code：Boehm, Atkinson & Plass. *Ropes: An Alternative to Strings.*
// Software—Practice & Experience 1995。文本表示为叶子（不可变 String 片段）
// 与 Concat 内部节点构成的二叉树；插入/删除通过「按位置 split → 三段
// concat」实现，单次编辑代价 O(log n + 片段量)，避免朴素字符串重建的
// 整篇 O(n) 拷贝。
//
// 平衡策略（对应原文 §「Rebalancing」的简化确定性变体）：concat 时若树深
// 超过 `2·⌈log₂ n⌉ + ROPE_DEPTH_SLACK` 则收集全部叶子重建为完全平衡树
// （O(n)，但触发频率随深度上界呈几何衰减，摊销 O(log n)）。叶子长度上界
// `ROPE_LEAF_MAX` 控制局部拷贝量；相邻小叶子在 concat 时就地合并，避免
// 碎片化退化为链表。
//
// 索引单位：UTF-16 码元（与 MoonBit `String::length`/`at` 一致，亦与
// lsp_server 位置编码模型的 UTF-16 缺省对齐）。
//
// 编辑器级索引（批次 2，对标 xi-editor rope 的 metric 体系）：每个节点
// 缓存 (UTF-16 码元数, UTF-8 字节数, 换行数)，支持 O(log n + 叶内扫描) 的
// UTF-8↔UTF-16 偏移双向转换与行列定位（LSP PositionEncoding 全套所需）。
// 孤立代理项按 WTF-8 语义计 3 字节（Simonsen. *The WTF-8 encoding.*）。
//
// 对外 API：new / from_string / len / utf8_len / line_count /
// charcode_at / slice / insert / delete / to_string /
// utf16_to_utf8 / utf8_to_utf16 / line_col_at / offset_of_line /
// is_leaf_balanced（诊断）/ depth（诊断）/ leaf_count（诊断）。

///|
/// 叶子长度上界：更长的插入文本会被切成多个叶子。
const ROPE_LEAF_MAX : Int = 512

///|
/// concat 时相邻两叶合并的长度阈值（合并后 ≤ ROPE_LEAF_MAX 才合并）。
const ROPE_JOIN_MAX : Int = 256

///|
/// 深度上界松弛量：depth > 2·⌈log₂ n⌉ + slack 时触发全量重建。
const ROPE_DEPTH_SLACK : Int = 4

///|
/// 子树度量：UTF-16 码元数 / UTF-8 字节数（WTF-8 语义）/ 换行（'\n'）数。
priv struct Meta {
  u16 : Int
  u8 : Int
  nl : Int
}

///|
enum RopeNode {
  /// 不可变文本片段 + 度量。
  Leaf(String, Meta)
  /// Concat(left, right, meta, depth)。
  Concat(RopeNode, RopeNode, Meta, Int)
}

///|
/// rope 编辑器内核：UTF-16 码元索引的可编辑文本。
pub struct Rope {
  mut root : RopeNode
}

///|
fn RopeNode::meta(self : RopeNode) -> Meta {
  match self {
    Leaf(_, m) => m
    Concat(_, _, m, _) => m
  }
}

///|
fn RopeNode::len(self : RopeNode) -> Int {
  self.meta().u16
}

///|
fn RopeNode::depth(self : RopeNode) -> Int {
  match self {
    Leaf(_, _) => 0
    Concat(_, _, _, d) => d
  }
}

///|
/// 计算字符串度量：UTF-8 字节按 WTF-8 语义（配对代理项 4 字节/对，
/// 孤立代理项 3 字节）。O(|s|)。
fn measure(s : String) -> Meta {
  let n = s.length()
  let mut u8 = 0
  let mut nl = 0
  let mut i = 0
  while i < n {
    let c = s.at(i).to_int()
    if c < 0x80 {
      if c == 10 {
        nl = nl + 1
      }
      u8 = u8 + 1
      i = i + 1
    } else if c < 0x800 {
      u8 = u8 + 2
      i = i + 1
    } else if c >= 0xD800 && c < 0xDC00 && i + 1 < n {
      let d = s.at(i + 1).to_int()
      if d >= 0xDC00 && d < 0xE000 {
        u8 = u8 + 4
        i = i + 2
      } else {
        u8 = u8 + 3
        i = i + 1
      }
    } else {
      u8 = u8 + 3
      i = i + 1
    }
  }
  { u16: n, u8, nl }
}

///|
fn Meta::add(self : Meta, other : Meta) -> Meta {
  { u16: self.u16 + other.u16, u8: self.u8 + other.u8, nl: self.nl + other.nl }
}

///|
fn mk_leaf(s : String) -> RopeNode {
  Leaf(s, measure(s))
}

///|
/// 空 rope。
pub fn Rope::new() -> Rope {
  { root: mk_leaf("") }
}

///|
/// 从字符串构造：切成 ≤ ROPE_LEAF_MAX 的叶子后完全平衡建树。
pub fn Rope::from_string(s : String) -> Rope {
  { root: build_balanced(chunk_leaves(s)) }
}

///|
/// 文本总长（UTF-16 码元数）。
pub fn Rope::len(self : Rope) -> Int {
  self.root.len()
}

///|
/// 文本 UTF-8 字节总数（WTF-8 语义）。O(1)。
pub fn Rope::utf8_len(self : Rope) -> Int {
  self.root.meta().u8
}

///|
/// 行数（换行数 + 1）。O(1)。
pub fn Rope::line_count(self : Rope) -> Int {
  self.root.meta().nl + 1
}

///|
/// 诊断：当前树深。
pub fn Rope::depth(self : Rope) -> Int {
  self.root.depth()
}

///|
/// 诊断：叶子数。
pub fn Rope::leaf_count(self : Rope) -> Int {
  fn go(n : RopeNode) -> Int {
    match n {
      Leaf(_, _) => 1
      Concat(l, r, _, _) => go(l) + go(r)
    }
  }

  go(self.root)
}

///|
/// 将字符串切成 ≤ ROPE_LEAF_MAX 的叶子序列（空串产生单个空叶）。
/// 叶界避开代理对中缝，保证叶内度量与全文 WTF-8 语义一致。
fn chunk_leaves(s : String) -> Array[RopeNode] {
  let n = s.length()
  if n == 0 {
    return [mk_leaf("")]
  }
  let out : Array[RopeNode] = []
  let mut i = 0
  while i < n {
    let mut j = if i + ROPE_LEAF_MAX < n { i + ROPE_LEAF_MAX } else { n }
    // 避免把代理对切成两半。
    if j < n {
      let c = s.at(j - 1).to_int()
      if c >= 0xD800 && c < 0xDC00 {
        j = j - 1
      }
    }
    out.push(mk_leaf(s[i:j].to_owned()))
    i = j
  }
  out
}

///|
/// 由叶子序列构建完全平衡树（自底向上两两配对）。
fn build_balanced(leaves : Array[RopeNode]) -> RopeNode {
  if leaves.length() == 0 {
    return mk_leaf("")
  }
  let mut layer = leaves
  while layer.length() > 1 {
    let next : Array[RopeNode] = []
    let mut i = 0
    while i + 1 < layer.length() {
      next.push(mk_concat(layer[i], layer[i + 1]))
      i = i + 2
    }
    if i < layer.length() {
      next.push(layer[i])
    }
    layer = next
  }
  layer[0]
}

///|
/// 构造 Concat 节点（缓存度量与深度）。
fn mk_concat(l : RopeNode, r : RopeNode) -> RopeNode {
  let d = if l.depth() > r.depth() { l.depth() } else { r.depth() }
  Concat(l, r, l.meta().add(r.meta()), d + 1)
}

///|
/// ⌈log₂ n⌉（n ≥ 1）。
fn ceil_log2(n : Int) -> Int {
  let mut k = 0
  let mut v = 1
  while v < n {
    v = v * 2
    k = k + 1
  }
  k
}

///|
/// 拼接两棵子树：空树短路、相邻小叶合并、深度超界触发全量重建。
fn concat_nodes(a : RopeNode, b : RopeNode) -> RopeNode {
  if a.len() == 0 {
    return b
  }
  if b.len() == 0 {
    return a
  }
  // 相邻小叶合并，抑制碎片化。
  let joined = match (a, b) {
    (Leaf(x, _), Leaf(y, _)) =>
      if x.length() + y.length() <= ROPE_JOIN_MAX {
        mk_leaf(x + y)
      } else {
        mk_concat(a, b)
      }
    (Concat(al, ar, _, _), Leaf(y, _)) =>
      match ar {
        Leaf(x, _) =>
          if x.length() + y.length() <= ROPE_JOIN_MAX {
            mk_concat(al, mk_leaf(x + y))
          } else {
            mk_concat(a, b)
          }
        _ => mk_concat(a, b)
      }
    (Leaf(x, _), Concat(bl, br, _, _)) =>
      match bl {
        Leaf(y, _) =>
          if x.length() + y.length() <= ROPE_JOIN_MAX {
            mk_concat(mk_leaf(x + y), br)
          } else {
            mk_concat(a, b)
          }
        _ => mk_concat(a, b)
      }
    _ => mk_concat(a, b)
  }
  let n = joined.len()
  if n > 0 && joined.depth() > 2 * ceil_log2(n) + ROPE_DEPTH_SLACK {
    rebuild(joined)
  } else {
    joined
  }
}

///|
/// 收集叶子并重建为完全平衡树。
fn rebuild(node : RopeNode) -> RopeNode {
  let leaves : Array[RopeNode] = []
  fn collect(n : RopeNode) -> Unit {
    match n {
      Leaf(s, _) => if s.length() > 0 { leaves.push(n) }
      Concat(l, r, _, _) => {
        collect(l)
        collect(r)
      }
    }
  }

  collect(node)
  build_balanced(leaves)
}

///|
/// 诊断：深度是否满足平衡不变量（≤ 2·⌈log₂ n⌉ + slack）。
pub fn Rope::is_leaf_balanced(self : Rope) -> Bool {
  let n = self.root.len()
  if n <= 1 {
    return true
  }
  self.root.depth() <= 2 * ceil_log2(n) + ROPE_DEPTH_SLACK
}

///|
/// 在位置 i 处切分为 (前缀, 后缀)。要求 0 ≤ i ≤ len。
fn split_at(node : RopeNode, i : Int) -> (RopeNode, RopeNode) {
  match node {
    Leaf(s, _) =>
      if i <= 0 {
        (mk_leaf(""), node)
      } else if i >= s.length() {
        (node, mk_leaf(""))
      } else {
        (mk_leaf(s[:i].to_owned()), mk_leaf(s[i:].to_owned()))
      }
    Concat(l, r, _, _) => {
      let ll = l.len()
      if i < ll {
        let (a, b) = split_at(l, i)
        (a, concat_nodes(b, r))
      } else if i > ll {
        let (a, b) = split_at(r, i - ll)
        (concat_nodes(l, a), b)
      } else {
        (l, r)
      }
    }
  }
}

///|
/// 读取位置 pos 的 UTF-16 码元（越界返回 None）。O(depth)。
pub fn Rope::charcode_at(self : Rope, pos : Int) -> Int? {
  if pos < 0 || pos >= self.root.len() {
    return None
  }
  let mut node = self.root
  let mut i = pos
  while true {
    match node {
      Leaf(s, _) => return Some(s.at(i).to_int())
      Concat(l, r, _, _) => {
        let ll = l.len()
        if i < ll {
          node = l
        } else {
          node = r
          i = i - ll
        }
      }
    }
  }
  None
}

///|
/// 在位置 pos 插入文本 s（pos 夹取到 [0, len]）。摊销 O(log n + |s|)。
pub fn Rope::insert(self : Rope, pos : Int, s : String) -> Unit {
  if s.length() == 0 {
    return
  }
  let n = self.root.len()
  let p = if pos < 0 { 0 } else if pos > n { n } else { pos }
  let (l, r) = split_at(self.root, p)
  let mid = build_balanced(chunk_leaves(s))
  self.root = concat_nodes(concat_nodes(l, mid), r)
}

///|
/// 删除半开区间 [lo, hi)（区间夹取到有效范围）。摊销 O(log n)。
pub fn Rope::delete(self : Rope, lo : Int, hi : Int) -> Unit {
  let n = self.root.len()
  let a = if lo < 0 { 0 } else if lo > n { n } else { lo }
  let b = if hi < a { a } else if hi > n { n } else { hi }
  if a == b {
    return
  }
  let (left, rest) = split_at(self.root, a)
  let (_, right) = split_at(rest, b - a)
  self.root = concat_nodes(left, right)
}

///|
/// 提取半开区间 [lo, hi) 的文本（区间夹取）。O(log n + 命中量)。
pub fn Rope::slice(self : Rope, lo : Int, hi : Int) -> String {
  let n = self.root.len()
  let a = if lo < 0 { 0 } else if lo > n { n } else { lo }
  let b = if hi < a { a } else if hi > n { n } else { hi }
  if a == b {
    return ""
  }
  let sb = StringBuilder::new()
  fn go(node : RopeNode, s : Int, e : Int) -> Unit {
    if s >= e {
      return
    }
    match node {
      Leaf(str, _) => sb.write_stringview(str[s:e])
      Concat(l, r, _, _) => {
        let ll = l.len()
        if e <= ll {
          go(l, s, e)
        } else if s >= ll {
          go(r, s - ll, e - ll)
        } else {
          go(l, s, ll)
          go(r, 0, e - ll)
        }
      }
    }
  }

  go(self.root, a, b)
  sb.to_string()
}

///|
/// 物化全文。O(n)。
pub fn Rope::to_string(self : Rope) -> String {
  let sb = StringBuilder::new()
  fn go(node : RopeNode) -> Unit {
    match node {
      Leaf(s, _) => sb.write_string(s)
      Concat(l, r, _, _) => {
        go(l)
        go(r)
      }
    }
  }

  go(self.root)
  sb.to_string()
}

///|
/// 叶内前缀 [0, upto16) 的 UTF-8 字节数（WTF-8 语义）。
fn prefix_u8(s : String, upto16 : Int) -> Int {
  let mut u8 = 0
  let mut i = 0
  while i < upto16 {
    let c = s.at(i).to_int()
    if c < 0x80 {
      u8 = u8 + 1
      i = i + 1
    } else if c < 0x800 {
      u8 = u8 + 2
      i = i + 1
    } else if c >= 0xD800 && c < 0xDC00 && i + 1 < upto16 {
      let d = s.at(i + 1).to_int()
      if d >= 0xDC00 && d < 0xE000 {
        u8 = u8 + 4
        i = i + 2
      } else {
        u8 = u8 + 3
        i = i + 1
      }
    } else {
      u8 = u8 + 3
      i = i + 1
    }
  }
  u8
}

///|
/// UTF-16 码元偏移 → UTF-8 字节偏移（偏移夹取到 [0, len]；偏移应落在
/// 字符边界，落入代理对中缝时按孤立代理项 WTF-8 计）。O(log n + 叶内扫描)。
pub fn Rope::utf16_to_utf8(self : Rope, off : Int) -> Int {
  let n = self.root.len()
  let mut i = if off < 0 { 0 } else if off > n { n } else { off }
  let mut acc = 0
  let mut node = self.root
  while true {
    match node {
      Leaf(s, _) => return acc + prefix_u8(s, i)
      Concat(l, r, _, _) => {
        let lm = l.meta()
        if i <= lm.u16 {
          node = l
        } else {
          acc = acc + lm.u8
          i = i - lm.u16
          node = r
        }
      }
    }
  }
  acc
}

///|
/// UTF-8 字节偏移 → UTF-16 码元偏移（偏移夹取到 [0, utf8_len]；落在
/// 字符中间时向下取整到字符起点）。O(log n + 叶内扫描)。
pub fn Rope::utf8_to_utf16(self : Rope, off : Int) -> Int {
  let total = self.root.meta().u8
  let mut i = if off < 0 { 0 } else if off > total { total } else { off }
  let mut acc = 0
  let mut node = self.root
  while true {
    match node {
      Leaf(s, _) => {
        // 叶内扫描：累计字节直到覆盖 i。
        let n16 = s.length()
        let mut u8 = 0
        let mut j = 0
        while j < n16 {
          let c = s.at(j).to_int()
          let (step8, step16) = if c < 0x80 {
            (1, 1)
          } else if c < 0x800 {
            (2, 1)
          } else if c >= 0xD800 && c < 0xDC00 && j + 1 < n16 {
            let d = s.at(j + 1).to_int()
            if d >= 0xDC00 && d < 0xE000 {
              (4, 2)
            } else {
              (3, 1)
            }
          } else {
            (3, 1)
          }
          if u8 + step8 > i {
            break
          }
          u8 = u8 + step8
          j = j + step16
        }
        return acc + j
      }
      Concat(l, r, _, _) => {
        let lm = l.meta()
        if i <= lm.u8 {
          node = l
        } else {
          acc = acc + lm.u16
          i = i - lm.u8
          node = r
        }
      }
    }
  }
  acc
}

///|
/// 第 line 行（0 基）行首的 UTF-16 偏移；line 夹取到 [0, line_count-1]。
/// O(log n + 叶内扫描)。
pub fn Rope::offset_of_line(self : Rope, line : Int) -> Int {
  let total_nl = self.root.meta().nl
  let mut k = if line < 0 {
    0
  } else if line > total_nl {
    total_nl
  } else {
    line
  }
  if k == 0 {
    return 0
  }
  // 目标：第 k 个 '\n' 之后的位置。
  let mut acc = 0
  let mut node = self.root
  while true {
    match node {
      Leaf(s, _) => {
        let n = s.length()
        let mut seen = 0
        for j in 0..<n {
          if s.at(j).to_int() == 10 {
            seen = seen + 1
            if seen == k {
              return acc + j + 1
            }
          }
        }
        return acc + n
      }
      Concat(l, r, _, _) => {
        let lm = l.meta()
        if k <= lm.nl {
          node = l
        } else {
          acc = acc + lm.u16
          k = k - lm.nl
          node = r
        }
      }
    }
  }
  acc
}

///|
/// UTF-16 偏移 → (行, 列)（均 0 基，列为行内 UTF-16 码元数；偏移夹取）。
/// O(log n + 叶内扫描)。
pub fn Rope::line_col_at(self : Rope, off : Int) -> (Int, Int) {
  let n = self.root.len()
  let p = if off < 0 { 0 } else if off > n { n } else { off }
  // 行号 = [0, p) 内换行数。
  let mut i = p
  let mut line = 0
  let mut node = self.root
  while true {
    match node {
      Leaf(s, _) => {
        for j in 0..<i {
          if s.at(j).to_int() == 10 {
            line = line + 1
          }
        }
        break
      }
      Concat(l, r, _, _) => {
        let lm = l.meta()
        if i <= lm.u16 {
          node = l
        } else {
          line = line + lm.nl
          i = i - lm.u16
          node = r
        }
      }
    }
  }
  (line, p - self.offset_of_line(line))
}
