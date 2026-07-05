// rope_sync.mbt —— T5.1 增量同步性能：rope 化文档表示
// （对数级单次增量变更，对标 rope science / xi-editor、VS Code piece tree 思路）。
//
// 既有 `apply_changes` / `apply_incremental`（sync.mbt / incremental_sync.mbt）
// 每条变更都要 O(N) 物化整篇码位序列；长文档高频编辑呈次平方级。本文件引入
// 高度平衡 rope（join-based balanced tree，参照 Blelloch/Ferizovic/Sun 2016
// "Just Join for Parallel Ordered Sets" 的 join 算法，键改为码位权重）：
//
//   * 节点缓存「码位数 cp_len / 换行数 nl / 高度 h」三元元数据；
//   * `split` / `join` 均 O(log N)，单条增量变更 = 两次 split + 两次 join +
//     新文本叶构造 = **O(log N + L + M)**（L 为受影响行长、M 为替换文本长），
//     不再随文档总长线性增长；
//   * `Position`（line/character，列号单位由 `PositionEncoding` 决定）→ 全局
//     码位索引的换算：先按换行计数下降定位行首（O(log N)），再仅在该行内
//     按码元扫描列（O(L)）——语义与 `position_to_cp_index` 完全一致（越界 /
//     落在多码元字符中间返回 `None`），由等价性 PBT 锁定。
//
// 不可变（persistent）结构：所有操作返回新 rope，旧版本继续有效，与既有
// `Input` / `VersionedDocument` 的不可变约定一致。

///|
/// rope 叶子的最大码位数（分块大小）。
const ROPE_MAX_LEAF : Int = 512

///|
/// 高度平衡 rope：叶子持有码位块，分支缓存两侧合计的码位数 / 换行数 / 高度。
priv enum Rope {
  RLeaf(Array[Int])
  RBranch(Rope, Rope, Int, Int, Int) // (left, right, cp_len, nl, height)
}

///|
/// 码位总数。
fn Rope::cp_len(self : Rope) -> Int {
  match self {
    RLeaf(cps) => cps.length()
    RBranch(_, _, len, _, _) => len
  }
}

///|
/// 换行符 `'\n'` 总数。
fn Rope::nl(self : Rope) -> Int {
  match self {
    RLeaf(cps) => {
      let mut k = 0
      for cp in cps {
        if cp == 0x0A {
          k = k + 1
        }
      }
      k
    }
    RBranch(_, _, _, nl, _) => nl
  }
}

///|
/// 树高（叶子为 1）。
fn Rope::height(self : Rope) -> Int {
  match self {
    RLeaf(_) => 1
    RBranch(_, _, _, _, h) => h
  }
}

///|
/// 由左右子树构造分支节点（缓存元数据）。
fn rope_mk(l : Rope, r : Rope) -> Rope {
  let h = if l.height() > r.height() { l.height() } else { r.height() }
  RBranch(l, r, l.cp_len() + r.cp_len(), l.nl() + r.nl(), h + 1)
}

///|
/// 左旋：`(a, (b, c)) → ((a, b), c)`。
fn rope_rotate_left(l : Rope, r : Rope) -> Rope {
  match r {
    RBranch(b, c, _, _, _) => rope_mk(rope_mk(l, b), c)
    RLeaf(_) => rope_mk(l, r)
  }
}

///|
/// 右旋：`((a, b), c) → (a, (b, c))`。
fn rope_rotate_right(l : Rope, r : Rope) -> Rope {
  match l {
    RBranch(a, b, _, _, _) => rope_mk(a, rope_mk(b, r))
    RLeaf(_) => rope_mk(l, r)
  }
}

///|
/// join 的右下降分支（左树更高）：沿左树右脊下降到高度可直接拼接处，回溯时
/// 逐层修复平衡（join-based balanced tree 的 joinRight，键改为权重）。
fn rope_join_right(l : Rope, r : Rope) -> Rope {
  match l {
    RLeaf(_) => rope_mk(l, r)
    RBranch(ll, lr, _, _, _) =>
      if lr.height() <= r.height() + 1 {
        let t = rope_mk(lr, r)
        if t.height() <= ll.height() + 1 {
          rope_mk(ll, t)
        } else {
          // t 过高：先右旋 t 再整体左旋。
          let t2 = match t {
            RBranch(tl, tr, _, _, _) => rope_rotate_right(tl, tr)
            RLeaf(_) => t
          }
          match rope_mk(ll, t2) {
            RBranch(x, y, _, _, _) => rope_rotate_left(x, y)
            other => other
          }
        }
      } else {
        let t = rope_join_right(lr, r)
        let l2 = rope_mk(ll, t)
        if t.height() <= ll.height() + 1 {
          l2
        } else {
          match l2 {
            RBranch(x, y, _, _, _) => rope_rotate_left(x, y)
            other => other
          }
        }
      }
  }
}

///|
/// join 的左下降分支（右树更高，与 `rope_join_right` 镜像对称）。
fn rope_join_left(l : Rope, r : Rope) -> Rope {
  match r {
    RLeaf(_) => rope_mk(l, r)
    RBranch(rl, rr, _, _, _) =>
      if rl.height() <= l.height() + 1 {
        let t = rope_mk(l, rl)
        if t.height() <= rr.height() + 1 {
          rope_mk(t, rr)
        } else {
          let t2 = match t {
            RBranch(tl, tr, _, _, _) => rope_rotate_left(tl, tr)
            RLeaf(_) => t
          }
          match rope_mk(t2, rr) {
            RBranch(x, y, _, _, _) => rope_rotate_right(x, y)
            other => other
          }
        }
      } else {
        let t = rope_join_left(l, rl)
        let r2 = rope_mk(t, rr)
        if t.height() <= rr.height() + 1 {
          r2
        } else {
          match r2 {
            RBranch(x, y, _, _, _) => rope_rotate_right(x, y)
            other => other
          }
        }
      }
  }
}

///|
/// 拼接两个 rope（O(|Δh|) ≤ O(log N)），空侧直接返回另一侧。
fn rope_join(l : Rope, r : Rope) -> Rope {
  if l.cp_len() == 0 {
    return r
  }
  if r.cp_len() == 0 {
    return l
  }
  let dh = l.height() - r.height()
  if dh > 1 {
    rope_join_right(l, r)
  } else if dh < -1 {
    rope_join_left(l, r)
  } else {
    rope_mk(l, r)
  }
}

///|
/// 在码位索引 `at`（0 ≤ at ≤ cp_len）处切分为左右两半（O(log² N)）。
fn Rope::split_at(self : Rope, at : Int) -> (Rope, Rope) {
  match self {
    RLeaf(cps) => {
      let a : Array[Int] = []
      let b : Array[Int] = []
      for i, cp in cps {
        if i < at {
          a.push(cp)
        } else {
          b.push(cp)
        }
      }
      (RLeaf(a), RLeaf(b))
    }
    RBranch(l, r, _, _, _) =>
      if at <= l.cp_len() {
        let (a, b) = l.split_at(at)
        (a, rope_join(b, r))
      } else {
        let (a, b) = r.split_at(at - l.cp_len())
        (rope_join(l, a), b)
      }
  }
}

///|
/// 第 `k`（0 起始）个换行符的全局码位索引；`k ≥ nl` 时返回 `cp_len`。
fn Rope::nth_newline(self : Rope, k : Int) -> Int {
  match self {
    RLeaf(cps) => {
      let mut seen = 0
      for i, cp in cps {
        if cp == 0x0A {
          if seen == k {
            return i
          }
          seen = seen + 1
        }
      }
      cps.length()
    }
    RBranch(l, r, _, _, _) =>
      if k < l.nl() {
        l.nth_newline(k)
      } else {
        l.cp_len() + r.nth_newline(k - l.nl())
      }
  }
}

///|
/// 把子区间 `[from, to)` 的码位追加到 `out`（O(log N + (to-from))）。
fn Rope::collect_range(
  self : Rope,
  from : Int,
  to : Int,
  out : Array[Int],
) -> Unit {
  if from >= to {
    return
  }
  match self {
    RLeaf(cps) => {
      let hi = if to < cps.length() { to } else { cps.length() }
      let mut i = if from > 0 { from } else { 0 }
      while i < hi {
        out.push(cps[i])
        i = i + 1
      }
    }
    RBranch(l, r, _, _, _) => {
      let ln = l.cp_len()
      if from < ln {
        l.collect_range(from, if to < ln { to } else { ln }, out)
      }
      if to > ln {
        r.collect_range(if from > ln { from - ln } else { 0 }, to - ln, out)
      }
    }
  }
}

///|
/// 由码位数组的子区间 `[from, to)` 构建平衡 rope（自底向上二分，O(n)）。
fn rope_build(cps : Array[Int], from : Int, to : Int) -> Rope {
  let n = to - from
  if n <= ROPE_MAX_LEAF {
    let chunk : Array[Int] = []
    let mut i = from
    while i < to {
      chunk.push(cps[i])
      i = i + 1
    }
    RLeaf(chunk)
  } else {
    let mid = from + n / 2
    rope_mk(rope_build(cps, from, mid), rope_build(cps, mid, to))
  }
}

// ───────────────────────────── 文档级封装 ─────────────────────────────────

///|
/// rope 化文档（T5.1）：与 `VersionedDocument` 同语义的不可变文档表示，
/// 单条增量变更 O(log N + L + M) 而非 O(N)。导出但字段私有（`pub`）。
pub struct RopeDocument {
  priv rope : Rope
}

///|
/// 从全文构造 rope 文档（O(N)，一次性）。
pub fn RopeDocument::from_string(text : String) -> RopeDocument {
  let cps : Array[Int] = []
  for c in text {
    cps.push(c.to_int())
  }
  { rope: rope_build(cps, 0, cps.length()) }
}

///|
/// 物化为全文字符串（O(N)）。
pub fn RopeDocument::to_string(self : RopeDocument) -> String {
  let out : Array[Int] = []
  self.rope.collect_range(0, self.rope.cp_len(), out)
  let sb = StringBuilder::new()
  for cp in out {
    sb.write_char(cp.unsafe_to_char())
  }
  sb.to_string()
}

///|
/// 文档码位总数（O(1)，取自缓存元数据）。
pub fn RopeDocument::length(self : RopeDocument) -> Int {
  self.rope.cp_len()
}

///|
/// 文档行数（换行符数 + 1，O(1)）。
pub fn RopeDocument::line_count(self : RopeDocument) -> Int {
  self.rope.nl() + 1
}

///|
/// 把 `Position` 解析为全局码位索引（语义与 `position_to_cp_index` 逐一致）：
/// 先按换行计数定位行首（O(log N)），再仅在该行内按 `enc` 码元扫描列（O(L)）。
/// 越界 / 落在多码元字符中间返回 `None`。
fn RopeDocument::position_to_index(
  self : RopeDocument,
  pos : Position,
  enc : PositionEncoding,
) -> Int? {
  if pos.line < 0 || pos.character < 0 {
    return None
  }
  let total = self.rope.cp_len()
  if pos.line > self.rope.nl() {
    return None
  }
  // 行首：第 line-1 个换行符之后；行末界：第 line 个换行符（或文末）。
  let start = if pos.line == 0 {
    0
  } else {
    self.rope.nth_newline(pos.line - 1) + 1
  }
  let end = if pos.line < self.rope.nl() {
    self.rope.nth_newline(pos.line)
  } else {
    total
  }
  // 仅物化该行内容（O(L)），按 enc 码元累计列号。
  let line_cps : Array[Int] = []
  self.rope.collect_range(start, end, line_cps)
  let mut col = 0
  for i, cp in line_cps {
    if col == pos.character {
      return Some(start + i)
    }
    if col > pos.character {
      return None
    }
    col = col + code_units(cp, enc)
  }
  // 行尾（换行符处或文末）。
  if col == pos.character {
    Some(end)
  } else {
    None
  }
}

///|
/// 应用单条内容变更（LSP `TextDocumentContentChangeEvent`）：
///   * `range = None`（Full）→ 以 `text` 整体替换（重建，O(M)）；
///   * `range = Some(r)`（Incremental）→ split/join 区间替换，
///     **O(log N + L + M)**。
/// 错误语义与 `apply_changes` 一致：越界 / 非码位边界 / start > end 返回
/// `Err(invalid_params_code, ..)`，不产生部分应用结果。
pub fn RopeDocument::apply_change(
  self : RopeDocument,
  change : ContentChange,
  encoding : PositionEncoding,
) -> Result[RopeDocument, @lsp_binding.RpcError] {
  match change.range {
    None => Ok(RopeDocument::from_string(change.text))
    Some(r) => {
      let si = match self.position_to_index(r.start, encoding) {
        Some(s) => s
        None =>
          return Err(
            @lsp_binding.RpcError::new(
              @lsp_binding.invalid_params_code,
              "content change range.start out of bounds at line \{r.start.line}, character \{r.start.character}",
            ),
          )
      }
      let ei = match self.position_to_index(r.end, encoding) {
        Some(e) => e
        None =>
          return Err(
            @lsp_binding.RpcError::new(
              @lsp_binding.invalid_params_code,
              "content change range.end out of bounds at line \{r.end.line}, character \{r.end.character}",
            ),
          )
      }
      if si > ei {
        return Err(
          @lsp_binding.RpcError::new(
            @lsp_binding.invalid_params_code,
            "content change range.start (line \{r.start.line}, character \{r.start.character}) is after range.end (line \{r.end.line}, character \{r.end.character})",
          ),
        )
      }
      let (prefix, rest) = self.rope.split_at(si)
      let (_, suffix) = rest.split_at(ei - si)
      let mid_cps : Array[Int] = []
      for c in change.text {
        mid_cps.push(c.to_int())
      }
      let mid = rope_build(mid_cps, 0, mid_cps.length())
      Ok({ rope: rope_join(rope_join(prefix, mid), suffix) })
    }
  }
}

///|
/// 按序应用多条内容变更（每条作用于上一条结果），任一失败立即返回 `Err`
/// 且不产生部分应用结果——与 `apply_changes`（sync.mbt）语义一致。
pub fn RopeDocument::apply_changes(
  self : RopeDocument,
  changes : Array[ContentChange],
  encoding : PositionEncoding,
) -> Result[RopeDocument, @lsp_binding.RpcError] {
  let mut cur = self
  for change in changes {
    match cur.apply_change(change, encoding) {
      Ok(next) => cur = next
      Err(e) => return Err(e)
    }
  }
  Ok(cur)
}
