// piece_table.mbt —— E6 文本基础设施：piece-table 变体。
//
// paper-to-code：对标 VS Code 文本缓冲（piece tree 的线性 piece 变体）与
// 经典 piece-table（Crowley, "Data Structures for Text Sequences" 1998）：
// 文档 = 只读 original 缓冲 + append-only add 缓冲上的 piece 序列
// （(which, start, len) 三元组）。编辑不移动任何已有文本字节：
// - insert：新文本追加进 add 缓冲，在命中 piece 处最多一分为三；
// - delete：命中区间的 piece 收缩/剔除；
// 单次编辑代价 O(#pieces)（定位 + 常数个 piece 重排），与文档字节数
// 无关；朴素 String 拼接每次编辑 O(文档长度) 重建。
//
// 与 rope（rope.mbt）互补：rope O(log n) 编辑 + 平衡树；piece-table
// 结构更简单、原始文本零拷贝、天然保留 undo 所需的不可变缓冲，
// 编辑序列较短（piece 数有限）时常数更小。
//
// 对外 API：PieceTable::{from_string, len, insert, delete, to_string,
// code_unit_at, piece_count}。

///|
/// piece：which（false=original / true=add）、缓冲内起点、长度。
struct Piece {
  in_add : Bool
  start : Int
  len : Int
}

///|
/// piece-table 文本缓冲。
pub struct PieceTable {
  original : String
  add : StringBuilder
  mut add_len : Int
  pieces : Array[Piece]
  mut total : Int
  mut add_cache : String // add 缓冲的物化缓存（懒失效）
  mut add_cache_len : Int
}

///|
/// 由初始文本构造。
pub fn PieceTable::from_string(s : String) -> PieceTable {
  let pieces : Array[Piece] = []
  if s.length() > 0 {
    pieces.push({ in_add: false, start: 0, len: s.length() })
  }
  {
    original: s,
    add: StringBuilder::new(),
    add_len: 0,
    pieces,
    total: s.length(),
    add_cache: "",
    add_cache_len: 0,
  }
}

///|
/// 文档长度（UTF-16 码元）。O(1)。
pub fn PieceTable::len(self : PieceTable) -> Int {
  self.total
}

///|
/// 当前 piece 数（诊断）。
pub fn PieceTable::piece_count(self : PieceTable) -> Int {
  self.pieces.length()
}

///|
/// add 缓冲的物化视图（懒缓存：仅在有新追加后重建一次）。
fn PieceTable::add_view(self : PieceTable) -> String {
  if self.add_cache_len != self.add_len {
    self.add_cache = self.add.to_string()
    self.add_cache_len = self.add_len
  }
  self.add_cache
}

///|
/// 在 off 处插入文本。off 夹取到 [0, len]。O(#pieces)。
pub fn PieceTable::insert(self : PieceTable, off : Int, text : String) -> Unit {
  if text.length() == 0 {
    return
  }
  let pos = if off < 0 {
    0
  } else if off > self.total {
    self.total
  } else {
    off
  }
  let np : Piece = { in_add: true, start: self.add_len, len: text.length() }
  self.add.write_string(text)
  self.add_len = self.add_len + text.length()
  self.total = self.total + text.length()
  // 定位命中 piece。
  let mut acc = 0
  for i in 0..<self.pieces.length() {
    let p = self.pieces[i]
    if pos <= acc + p.len {
      let k = pos - acc
      if k == 0 {
        self.pieces.insert(i, np)
      } else if k == p.len {
        self.pieces.insert(i + 1, np)
      } else {
        // 一分为三。
        self.pieces[i] = { in_add: p.in_add, start: p.start, len: k }
        self.pieces.insert(i + 1, np)
        self.pieces.insert(i + 2, {
          in_add: p.in_add,
          start: p.start + k,
          len: p.len - k,
        })
      }
      return
    }
    acc = acc + p.len
  }
  self.pieces.push(np) // 空文档或 pos == len 且无 piece
}

///|
/// 删除 [off, off+count)。区间夹取到文档内。O(#pieces)。
pub fn PieceTable::delete(self : PieceTable, off : Int, count : Int) -> Unit {
  let lo = if off < 0 { 0 } else if off > self.total { self.total } else { off }
  let hi0 = lo + (if count < 0 { 0 } else { count })
  let hi = if hi0 > self.total { self.total } else { hi0 }
  if hi <= lo {
    return
  }
  let out : Array[Piece] = []
  let mut acc = 0
  for p in self.pieces {
    let pstart = acc
    let pend = acc + p.len
    acc = pend
    if pend <= lo || pstart >= hi {
      out.push(p)
      continue
    }
    // 左保留段。
    if pstart < lo {
      out.push({ in_add: p.in_add, start: p.start, len: lo - pstart })
    }
    // 右保留段。
    if pend > hi {
      out.push({
        in_add: p.in_add,
        start: p.start + (hi - pstart),
        len: pend - hi,
      })
    }
  }
  self.pieces.clear()
  for p in out {
    self.pieces.push(p)
  }
  self.total = self.total - (hi - lo)
}

///|
/// 取 off 处 UTF-16 码元（越界 None）。O(#pieces)。
pub fn PieceTable::code_unit_at(self : PieceTable, off : Int) -> Int? {
  if off < 0 || off >= self.total {
    return None
  }
  let mut acc = 0
  for p in self.pieces {
    if off < acc + p.len {
      let src = if p.in_add { self.add_view() } else { self.original }
      return Some(src.at(p.start + (off - acc)).to_int())
    }
    acc = acc + p.len
  }
  None
}

///|
/// 物化整个文档。O(文档长度)。
pub fn PieceTable::to_string(self : PieceTable) -> String {
  let sb = StringBuilder::new()
  let addv = self.add_view()
  for p in self.pieces {
    let src = if p.in_add { addv } else { self.original }
    sb.write_view(src[p.start:p.start + p.len])
  }
  sb.to_string()
}
