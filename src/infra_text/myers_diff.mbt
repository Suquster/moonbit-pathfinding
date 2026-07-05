// myers_diff.mbt —— E6 文本基础设施：Myers 最短编辑脚本 diff。
//
// paper-to-code：Myers. *An O(ND) Difference Algorithm and Its Variations.*
// Algorithmica 1986，§4a 贪心正向算法。在编辑图上按编辑距离 d 逐层扩展
// 对角线 furthest-reaching 端点 V[k]，并对每层保存 V 快照用于回溯还原
// 最短编辑脚本。时间 O((N+M)·D)、空间 O((N+M)·D)——对相似文本
// （D ≪ N+M）远优于全量 DP LCS 的 O(N·M)。
//
// 索引单位与 rope 一致：UTF-16 码元。
//
// 对外 API：DiffOp / myers_diff / diff_apply / diff_edit_cost / lcs_dp_cost
// （后者为 O(N·M) DP 参照，供差分验证最小性）。

///|
/// 编辑脚本操作（对 a → b）：Equal 保留、Delete 从 a 删除、Insert 插入 b 的片段。
pub(all) enum DiffOp {
  Equal(String)
  Delete(String)
  Insert(String)
} derive(Eq, Debug)

///|
/// Myers 最短编辑脚本：把 a 变成 b 的操作序列（Equal/Delete/Insert）。
pub fn myers_diff(a : String, b : String) -> Array[DiffOp] {
  let n = a.length()
  let m = b.length()
  if n == 0 && m == 0 {
    return []
  }
  if n == 0 {
    return [Insert(b)]
  }
  if m == 0 {
    return [Delete(a)]
  }
  let max_d = n + m
  let offset = max_d
  // V[k + offset] = 对角线 k 上 furthest-reaching 的 x。
  let v : Array[Int] = Array::make(2 * max_d + 1, 0)
  // 每层 d 的 V 快照（回溯用）。
  let trace : Array[Array[Int]] = []
  let mut found_d = -1
  for d in 0..<=max_d {
    let mut k = -d
    while k <= d {
      let idx = k + offset
      let mut x = if k == -d || (k != d && v[idx - 1] < v[idx + 1]) {
        v[idx + 1] // 向下（插入 b 的一个码元）
      } else {
        v[idx - 1] + 1 // 向右（删除 a 的一个码元）
      }
      let mut y = x - k
      // 贪心沿蛇形（公共段）滑行。
      while x < n && y < m && a.at(x) == b.at(y) {
        x = x + 1
        y = y + 1
      }
      v[idx] = x
      if x >= n && y >= m {
        found_d = d
        break
      }
      k = k + 2
    }
    trace.push(v.copy())
    if found_d >= 0 {
      break
    }
  }
  // 回溯：从 (n, m) 沿快照逐层还原路径，先收集反向操作序列。
  // rev_ops 项：(op, len)，op ∈ {0=Equal, 1=Delete(a), 2=Insert(b)}，
  // 附带片段在源串中的终点，最后统一物化子串。
  let ops : Array[DiffOp] = []
  let mut x = n
  let mut y = m
  let rev : Array[(Int, Int, Int)] = [] // (op, x_end, len)
  let mut d = found_d
  while d > 0 {
    let vd = trace[d - 1]
    let k = x - y
    let (prev_k, down) = if k == -d ||
      (k != d && vd[k - 1 + offset] < vd[k + 1 + offset]) {
      (k + 1, true) // 来自向下一步（Insert）
    } else {
      (k - 1, false) // 来自向右一步（Delete）
    }
    let prev_x = vd[prev_k + offset]
    let prev_y = prev_x - prev_k
    // 蛇形公共段。
    let mid_x = if down { prev_x } else { prev_x + 1 }
    let mid_y = if down { prev_y + 1 } else { prev_y }
    if x > mid_x {
      rev.push((0, x, x - mid_x)) // Equal，a 的 [mid_x, x)
    }
    if down {
      rev.push((2, mid_y, 1)) // Insert，b 的 [prev_y, mid_y)
    } else {
      rev.push((1, mid_x, 1)) // Delete，a 的 [prev_x, mid_x)
    }
    x = prev_x
    y = prev_y
    d = d - 1
  }
  if x > 0 {
    rev.push((0, x, x)) // d=0 的初始蛇形：a[0, x) == b[0, y)
  }
  // 反转并合并同类相邻段。
  let mut i = rev.length() - 1
  while i >= 0 {
    let (op, endp, len0) = rev[i]
    let mut startp = endp - len0
    let mut endq = endp
    // 合并相邻同类。
    while i - 1 >= 0 {
      let (op2, endp2, len2) = rev[i - 1]
      if op2 == op && endp2 - len2 == endq {
        endq = endp2
        i = i - 1
      } else {
        break
      }
    }
    if startp < 0 {
      startp = 0
    }
    match op {
      0 => ops.push(Equal(a[startp:endq].to_owned()))
      1 => ops.push(Delete(a[startp:endq].to_owned()))
      _ => ops.push(Insert(b[startp:endq].to_owned()))
    }
    i = i - 1
  }
  ops
}

///|
/// 应用编辑脚本：Equal + Insert 依序拼接即得目标串 b。
pub fn diff_apply(ops : Array[DiffOp]) -> String {
  let sb = StringBuilder::new()
  for op in ops {
    match op {
      Equal(s) => sb.write_string(s)
      Insert(s) => sb.write_string(s)
      Delete(_) => ()
    }
  }
  sb.to_string()
}

///|
/// 还原源串：Equal + Delete 依序拼接即得源串 a。
pub fn diff_source(ops : Array[DiffOp]) -> String {
  let sb = StringBuilder::new()
  for op in ops {
    match op {
      Equal(s) => sb.write_string(s)
      Delete(s) => sb.write_string(s)
      Insert(_) => ()
    }
  }
  sb.to_string()
}

///|
/// 编辑代价：Delete + Insert 的码元总数（Myers 的 D 值）。
pub fn diff_edit_cost(ops : Array[DiffOp]) -> Int {
  let mut c = 0
  for op in ops {
    match op {
      Equal(_) => ()
      Delete(s) => c = c + s.length()
      Insert(s) => c = c + s.length()
    }
  }
  c
}

///|
/// O(N·M) 全量 DP 参照：最小编辑距离（仅插入/删除，即 N+M−2·LCS），
/// 供小规模差分验证 myers_diff 的最小性。
pub fn lcs_dp_cost(a : String, b : String) -> Int {
  let n = a.length()
  let m = b.length()
  // 滚动一维 DP 求 LCS 长度。
  let prev : Array[Int] = Array::make(m + 1, 0)
  let cur : Array[Int] = Array::make(m + 1, 0)
  for i in 1..<=n {
    cur[0] = 0
    for j in 1..<=m {
      if a.at(i - 1) == b.at(j - 1) {
        cur[j] = prev[j - 1] + 1
      } else {
        cur[j] = if prev[j] > cur[j - 1] { prev[j] } else { cur[j - 1] }
      }
    }
    for j in 0..<=m {
      prev[j] = cur[j]
    }
  }
  n + m - 2 * prev[m]
}
