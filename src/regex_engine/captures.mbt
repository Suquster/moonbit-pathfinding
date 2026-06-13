// captures.mbt —— 捕获与子匹配结果模型 `Captures`（旗舰深化）。
//
// 对应 design.md §4.5（R1/R8.4）。本文件为**新增**，仅依赖既有 `Match` 类型。
//
// 捕获寄存器布局：`slots[2g]` / `slots[2g+1]` 为第 `g` 组的起 / 止偏移，`-1`
// 表示「未设置」。第 0 组为整体匹配区间 `[slots[0], slots[1])`。命名组经
// `names`（名称 → 编号）解析后委托 `group` 检索。

///|
/// 捕获结果（capture result）：一次匹配的整体区间与各捕获组区间集合。
///
///   * `slots` —— 长度 `2*(num_groups+1)` 的寄存器数组；`slots[2g]` /
///     `slots[2g+1]` 为第 `g` 组起 / 止偏移，`-1` 表示未设置；
///   * `names` —— 命名捕获组「名称 → 编号」映射。
pub struct Captures {
  slots : Array[Int]
  names : Map[String, Int]
}

///|
/// 检索第 `i` 组的匹配区间：`i=0` 为整体匹配；越界或未设置（任一端为 `-1`）
/// 返回 `None`（R1.4/1.5）。
pub fn Captures::group(self : Captures, i : Int) -> Match? {
  let lo_idx = 2 * i
  let hi_idx = 2 * i + 1
  if i < 0 || hi_idx >= self.slots.length() {
    return None
  }
  let s = self.slots[lo_idx]
  let e = self.slots[hi_idx]
  if s < 0 || e < 0 {
    None
  } else {
    Some({ start: s, end: e })
  }
}

///|
/// 按名称检索命名捕获组区间：经 `names` 解析编号后委托 `group`；未知名称
/// 返回 `None`（R1.6）。
pub fn Captures::name(self : Captures, n : String) -> Match? {
  match self.names.get(n) {
    Some(i) => self.group(i)
    None => None
  }
}

///|
/// 捕获组总数（含第 0 组整体匹配）。
pub fn Captures::group_count(self : Captures) -> Int {
  self.slots.length() / 2
}
