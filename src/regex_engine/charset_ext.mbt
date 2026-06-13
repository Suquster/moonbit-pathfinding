// charset_ext.mbt —— 既有 `CharSet` 的集合运算扩展（旗舰深化）。
//
// 对应 design.md §4.2 / §1.2（R6.1/6.4/6.7）。本文件为**新增**，在既有
// `CharSet`（定义于 nfa.mbt，字段 `intervals` 不变）上**只增**方法：并集
// `union`、补集 `complement`、ASCII 大小写闭包 `case_fold`。三者均复用
// nfa.mbt 的归一化（`normalize_intervals`）与补集（`complement_intervals`）
// 原语，故产出区间天然满足「归一化、不相交、升序」不变量，与既有否定字符类
// 补集、DFA 字母表原子区间划分完全同源。
//
// Unicode 折叠边界声明（R6.4）：`case_fold` 仅实现 **ASCII 简单大小写折叠**
// （`A-Z` ↔ `a-z`），与 RE2/Rust `regex` 的完整 Unicode 折叠相比是显式取舍，
// 已在 README 与 design.md「设计权衡」声明。

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
/// ASCII 大小写折叠闭包：对集合内落在 `A-Z` / `a-z` 的码点，补入其对应的
/// 小写 / 大写形态，使大小写不敏感（`i` 标志）规约为纯字符集合问题（R6.4）。
///
/// 仅处理 ASCII 字母；非字母码点与非 ASCII 码点原样保留（Unicode 简单折叠
/// 边界已声明）。
pub fn CharSet::case_fold(self : CharSet) -> CharSet {
  let extra : Array[(Int, Int)] = []
  for iv in self.intervals {
    let (lo, hi) = iv
    // 与大写区间 [65,90] 求交，平移 +32 得到对应小写区间。
    let ulo = if lo > 65 { lo } else { 65 }
    let uhi = if hi < 90 { hi } else { 90 }
    if ulo <= uhi {
      extra.push((ulo + 32, uhi + 32))
    }
    // 与小写区间 [97,122] 求交，平移 -32 得到对应大写区间。
    let llo = if lo > 97 { lo } else { 97 }
    let lhi = if hi < 122 { hi } else { 122 }
    if llo <= lhi {
      extra.push((llo - 32, lhi - 32))
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
