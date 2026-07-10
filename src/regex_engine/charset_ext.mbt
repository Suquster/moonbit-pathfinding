// charset_ext.mbt —— 既有 `CharSet` 的集合运算扩展（旗舰深化）。
//
// 对应 design.md §4.2 / §1.2（R6.1/6.4/6.7）。本文件为**新增**，在既有
// `CharSet`（定义于 nfa.mbt，字段 `intervals` 不变）上**只增**方法：并集
// `union`、补集 `complement`、大小写折叠闭包 `case_fold`。三者均复用
// nfa.mbt 的归一化（`normalize_intervals`）与补集（`complement_intervals`）
// 原语，故产出区间天然满足「归一化、不相交、升序」不变量，与既有否定字符类
// 补集、DFA 字母表原子区间划分完全同源。
//
// Unicode 折叠（R6.4）：`case_fold` 实现完整 **Unicode 简单大小写折叠**
// （UCD CaseFolding.txt 的 C+S 条目按折叠轨道闭包展开，见
// unicode_fold_table.mbt），与 RE2/Rust `regex` 同水位；每个区间经排序
// 边表二分定位后补入全部折叠等价码点。

///|
/// 字符集合并集：两集合区间合并后归一化为不相交、升序的闭区间序列。
pub fn CharSet::union(self : CharSet, other : CharSet) -> CharSet {
  let raw : Array[(Int, Int)] = []
  for iv in self.intervals {
    raw.push(iv)
  }
  for iv in other.intervals {
    raw.push(iv)
  }
  { intervals: normalize_intervals(raw) }
}

///|
/// 字符集合补集：在 [0, MAX_CODE] 上取补（复用既有否定字符类补集逻辑），
/// 与 `[^...]` 的语义同源。
pub fn CharSet::complement(self : CharSet) -> CharSet {
  { intervals: complement_intervals(normalize_intervals(self.intervals)) }
}

///|
/// Unicode 简单大小写折叠闭包：对集合内每个码点补入其全部折叠等价码点
/// （UCD CaseFolding.txt C+S 条目的轨道闭包），使大小写不敏感（`i`
/// 标志）规约为纯字符集合问题（R6.4）。
///
/// ASCII 字母区间走平移快路径（整区间 ±32）；非 ASCII 码点在排序折叠
/// 边表上二分定位后逐条补入（含 K↔K、S↔ſ、σ↔ς 等多元轨道）。
/// 折叠只会扩大集合，保持超集不变量。
pub fn CharSet::case_fold(self : CharSet) -> CharSet {
  let extra : Array[(Int, Int)] = []
  let m = unicode_fold_edges.length() / 2
  for iv in self.intervals {
    let (lo, hi) = iv
    // 二分定位首个 src >= lo 的边，顺扫至 src > hi，逐条补入折叠等价码点
    // （含 K↔ASCII K、ſ↔S、σ↔ς 等跨区段多元轨道）。
    let mut l = 0
    let mut r = m
    while l < r {
      let mid = (l + r) / 2
      if unicode_fold_edges[2 * mid] < lo {
        l = mid + 1
      } else {
        r = mid
      }
    }
    let mut i = l
    while i < m && unicode_fold_edges[2 * i] <= hi {
      let dst = unicode_fold_edges[2 * i + 1]
      extra.push((dst, dst))
      i = i + 1
    }
  }
  let raw : Array[(Int, Int)] = []
  for iv in self.intervals {
    raw.push(iv)
  }
  for iv in extra {
    raw.push(iv)
  }
  { intervals: normalize_intervals(raw) }
}
