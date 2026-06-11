// matcher.mbt —— 匹配结果类型 `Match` 与高层匹配入口 `find`。
//
// 对应任务 6.2 流水线终点（design.md §「方向二：Regex_Engine」）：
//   syntax → parser → nfa → dfa → **matcher（执行）**。
//
// `find(r, input)` 串联完整流水线：`build_nfa`（Thompson 构造）→ `to_dfa`
// （子集构造确定化）→ `Dfa::find`（执行），返回是否匹配及匹配区间（R2.5）。
// NFA 与 DFA 两条匹配路径均对外可用（`Nfa::find` / `Dfa::find`），结果一致，
// 为任务 6.4「NFA/DFA 差分一致性」做准备。

///|
/// 匹配结果（match）：匹配区间的起止字符偏移。
///
///   * `start` —— 匹配起点偏移（0 起始，含）；
///   * `end`   —— 匹配终点偏移（开区间端点，不含）。
///
/// 偏移基于输入按 `String::iter()` 得到的 Unicode 标量字符序列，与
/// `@pc.Input` 的偏移约定一致。空匹配满足 `start == end`。
pub(all) struct Match {
  start : Int
  end : Int
} derive(Eq)

///|
/// 高层匹配入口（design.md `find`，R2.5）：对正则语法树 `r` 在输入 `input`
/// 上执行最左最长匹配，返回匹配区间；无匹配时返回 `None`。
///
/// 内部串联 `build_nfa` → `to_dfa` → `Dfa::find` 完整流水线。
pub fn find(r : Regex, input : String) -> Match? {
  let nfa = build_nfa(r)
  let dfa = to_dfa(nfa)
  dfa.find(input)
}

///|
/// 便捷判定：输入中是否存在 `r` 的匹配（不关心区间）。
pub fn is_match(r : Regex, input : String) -> Bool {
  match find(r, input) {
    Some(_) => true
    None => false
  }
}
