// histogram.mbt —— patience / histogram diff（git 同款算法家族）。
//
// paper-to-code：
// - Cohen *Patience Diff*（bzr 起源，git `--diff-algorithm=patience`）：
//   两侧各出现恰一次的行作锚点，对锚点序列取最长递增子序列（LIS，
//   耐心排序牌堆法，O(n log n)），锚点间递归；无锚点区间回退 Myers；
// - git `--histogram`（JGit HistogramDiff）：patience 的推广——放宽
//   "唯一行"为"最低出现次数行"，构建旧侧行频直方图，选出现次数
//   最少（且 ≤ 上限 64）的公共行作分割锚，两侧递归；
// - 两者输出与 Myers 同构（Keep/Delete/Insert 编辑脚本），
//   patch 语义完全兼容 `patch_apply`/`hunks_of`/`format_unified`。

///|
/// 最长递增子序列（耐心排序牌堆 + 二分，O(n log n)）：
/// 输入 `pairs` 为 (old 下标, new 下标) 锚点、按 old 下标升序，
/// 返回按 new 下标严格递增的最长子序列。
fn patience_lis(pairs : Array[(Int, Int)]) -> Array[(Int, Int)] {
  let n = pairs.length()
  if n == 0 {
    return []
  }
  // tails[i] = 长度 i+1 的递增子序列的最小结尾在 pairs 中的下标。
  let tails : Array[Int] = []
  let prev : Array[Int] = Array::make(n, -1)
  for i in 0..<n {
    let key = pairs[i].1
    // 二分找第一个结尾 ≥ key 的堆。
    let mut lo = 0
    let mut hi = tails.length()
    while lo < hi {
      let mid = (lo + hi) / 2
      if pairs[tails[mid]].1 < key {
        lo = mid + 1
      } else {
        hi = mid
      }
    }
    if lo > 0 {
      prev[i] = tails[lo - 1]
    }
    if lo == tails.length() {
      tails.push(i)
    } else {
      tails[lo] = i
    }
  }
  // 回溯。
  let out : Array[(Int, Int)] = []
  let mut cur = tails[tails.length() - 1]
  while cur >= 0 {
    out.push(pairs[cur])
    cur = prev[cur]
  }
  out.rev_in_place()
  out
}

///|
/// 收集两侧均恰出现一次的公共行锚点（patience 核心筛选）。
fn unique_common_anchors(
  old : Array[String],
  new : Array[String],
  ol : Int,
  oh : Int,
  nl : Int,
  nh : Int,
) -> Array[(Int, Int)] {
  // 行 → (旧侧计数, 旧侧下标, 新侧计数, 新侧下标)。
  let counts : Map[String, (Int, Int, Int, Int)] = Map([])
  for i in ol..<oh {
    let line = old[i]
    match counts.get(line) {
      Some((oc, _, nc, nj)) => counts[line] = (oc + 1, i, nc, nj)
      None => counts[line] = (1, i, 0, -1)
    }
  }
  for j in nl..<nh {
    let line = new[j]
    match counts.get(line) {
      Some((oc, oi, nc, _)) => counts[line] = (oc, oi, nc + 1, j)
      None => counts[line] = (0, -1, 1, j)
    }
  }
  let pairs : Array[(Int, Int)] = []
  for i in ol..<oh {
    match counts.get(old[i]) {
      Some((1, oi, 1, nj)) => pairs.push((oi, nj))
      _ => ()
    }
  }
  pairs
}

///|
/// 区间辅助：把 [ol,oh) × [nl,nh) 的两侧内容取出并做 Myers diff 追加。
fn diff_fallback(
  old : Array[String],
  new : Array[String],
  ol : Int,
  oh : Int,
  nl : Int,
  nh : Int,
  out : Array[DiffOp],
) -> Unit {
  let sub_old : Array[String] = []
  for i in ol..<oh {
    sub_old.push(old[i])
  }
  let sub_new : Array[String] = []
  for j in nl..<nh {
    sub_new.push(new[j])
  }
  for op in diff_lines(sub_old, sub_new) {
    out.push(op)
  }
}

///|
/// patience 递归主体。
fn patience_rec(
  old : Array[String],
  new : Array[String],
  ol : Int,
  oh : Int,
  nl : Int,
  nh : Int,
  out : Array[DiffOp],
) -> Unit {
  // 首尾公共前后缀剥离（所有 diff 实现的标准预处理）。
  let mut lo_o = ol
  let mut lo_n = nl
  let mut hi_o = oh
  let mut hi_n = nh
  while lo_o < hi_o && lo_n < hi_n && old[lo_o] == new[lo_n] {
    out.push(Keep(old[lo_o]))
    lo_o = lo_o + 1
    lo_n = lo_n + 1
  }
  // 尾部先记数，最后补写。
  let mut tail = 0
  while hi_o > lo_o && hi_n > lo_n && old[hi_o - 1] == new[hi_n - 1] {
    tail = tail + 1
    hi_o = hi_o - 1
    hi_n = hi_n - 1
  }
  if lo_o >= hi_o {
    for j in lo_n..<hi_n {
      out.push(Insert(new[j]))
    }
  } else if lo_n >= hi_n {
    for i in lo_o..<hi_o {
      out.push(Delete(old[i]))
    }
  } else {
    let anchors = patience_lis(
      unique_common_anchors(old, new, lo_o, hi_o, lo_n, hi_n),
    )
    if anchors.length() == 0 {
      diff_fallback(old, new, lo_o, hi_o, lo_n, hi_n, out)
    } else {
      let mut po = lo_o
      let mut pn = lo_n
      for a in anchors {
        patience_rec(old, new, po, a.0, pn, a.1, out)
        out.push(Keep(old[a.0]))
        po = a.0 + 1
        pn = a.1 + 1
      }
      patience_rec(old, new, po, hi_o, pn, hi_n, out)
    }
  }
  for k in 0..<tail {
    out.push(Keep(old[hi_o + k]))
  }
}

///|
/// patience diff（Cohen；git `--diff-algorithm=patience`）：
/// 唯一公共行锚点 + LIS 递归分治，锚点间回退 Myers。
/// 输出与 `diff_lines` 同构、可直接喂给 `patch_apply`/`format_unified`。
pub fn diff_patience(old : Array[String], new : Array[String]) -> Array[DiffOp] {
  let out : Array[DiffOp] = []
  patience_rec(old, new, 0, old.length(), 0, new.length(), out)
  out
}

///|
/// histogram 递归主体：选旧侧出现次数最少（≤64）的公共行作分割锚。
/// 行已在入口处 intern 为整数 id（`old_ids`/`new_ids`），直方图用
/// 数组计数代替字符串哈希；频次并列时取最靠近新侧区间中点的锚，
/// 使递归两侧规模均衡（避免退化成 O(n²) 的链式切分）。
fn histogram_rec(
  old : Array[String],
  new : Array[String],
  old_ids : Array[Int],
  new_ids : Array[Int],
  counts : Array[Int],
  first_idx : Array[Int],
  ol : Int,
  oh : Int,
  nl : Int,
  nh : Int,
  out : Array[DiffOp],
) -> Unit {
  let mut lo_o = ol
  let mut lo_n = nl
  let mut hi_o = oh
  let mut hi_n = nh
  while lo_o < hi_o && lo_n < hi_n && old[lo_o] == new[lo_n] {
    out.push(Keep(old[lo_o]))
    lo_o = lo_o + 1
    lo_n = lo_n + 1
  }
  let mut tail = 0
  while hi_o > lo_o && hi_n > lo_n && old[hi_o - 1] == new[hi_n - 1] {
    tail = tail + 1
    hi_o = hi_o - 1
    hi_n = hi_n - 1
  }
  if lo_o >= hi_o {
    for j in lo_n..<hi_n {
      out.push(Insert(new[j]))
    }
  } else if lo_n >= hi_n {
    for i in lo_o..<hi_o {
      out.push(Delete(old[i]))
    }
  } else {
    // 旧侧行频直方图（数组计数，同时记录首次出现下标）。
    for i in lo_o..<hi_o {
      let id = old_ids[i]
      if counts[id] == 0 {
        first_idx[id] = i
      }
      counts[id] = counts[id] + 1
    }
    // 新侧扫描：选旧侧频次最低（且 ≤64，JGit MAX_CHAIN_LENGTH）的公共行；
    // 频次并列时取最靠近区间中点的锚，使两侧递归规模均衡。
    let mid = (lo_n + hi_n) / 2
    let mut best_count = 65
    let mut best_old = -1
    let mut best_new = -1
    let mut best_gap = 0
    for j in lo_n..<hi_n {
      let c = counts[new_ids[j]]
      if c > 0 && c < 65 {
        let gap = if j > mid { j - mid } else { mid - j }
        if c < best_count || (c == best_count && gap < best_gap) {
          best_count = c
          best_old = first_idx[new_ids[j]]
          best_new = j
          best_gap = gap
        }
      }
    }
    // 回收本层计数（只清触碰过的 id，保持每层 O(区间长度)）。
    for i in lo_o..<hi_o {
      counts[old_ids[i]] = 0
    }
    if best_old < 0 {
      diff_fallback(old, new, lo_o, hi_o, lo_n, hi_n, out)
    } else {
      histogram_rec(
        old, new, old_ids, new_ids, counts, first_idx, lo_o, best_old, lo_n, best_new,
        out,
      )
      out.push(Keep(old[best_old]))
      histogram_rec(
        old,
        new,
        old_ids,
        new_ids,
        counts,
        first_idx,
        best_old + 1,
        hi_o,
        best_new + 1,
        hi_n,
        out,
      )
    }
  }
  for k in 0..<tail {
    out.push(Keep(old[hi_o + k]))
  }
}

///|
/// histogram diff（JGit HistogramDiff；git `--diff-algorithm=histogram`，
/// 亦为 `merge.diffAlgorithm` 推荐值）：patience 的推广——
/// 放宽唯一行为最低频公共行，实践中比 Myers 更快且 diff 更符合直觉。
pub fn diff_histogram(
  old : Array[String],
  new : Array[String],
) -> Array[DiffOp] {
  // 行 intern：字符串只哈希一次，递归内层全部走整数 id 数组。
  let table : Map[String, Int] = Map([])
  let old_ids : Array[Int] = Array::make(old.length(), 0)
  for i in 0..<old.length() {
    match table.get(old[i]) {
      Some(id) => old_ids[i] = id
      None => {
        let id = table.length()
        table[old[i]] = id
        old_ids[i] = id
      }
    }
  }
  let new_ids : Array[Int] = Array::make(new.length(), 0)
  for j in 0..<new.length() {
    match table.get(new[j]) {
      Some(id) => new_ids[j] = id
      None => {
        let id = table.length()
        table[new[j]] = id
        new_ids[j] = id
      }
    }
  }
  let counts : Array[Int] = Array::make(table.length(), 0)
  let first_idx : Array[Int] = Array::make(table.length(), -1)
  let out : Array[DiffOp] = []
  histogram_rec(
    old,
    new,
    old_ids,
    new_ids,
    counts,
    first_idx,
    0,
    old.length(),
    0,
    new.length(),
    out,
  )
  out
}
