// match_kind.mbt —— 匹配策略 `MatchKind`（旗舰深化）。
//
// 对应 design.md §4.6（R4）。本文件为**新增**。匹配策略只改变 Pike VM 在
// 「同起点多候选」时的取舍，不改变可匹配性：
//
//   * `LeftmostFirst`   —— PCRE/Perl：最左 + 按书写顺序与量词优先级首个成功；
//   * `LeftmostLongest` —— POSIX：最左 + 最长（默认，兼容既有 `find`/`is_match`）。
//
// paper-to-code：`LeftmostLongest` 追溯 POSIX 正则规范；`LeftmostFirst` 追溯
// Perl/PCRE 的择一与量词优先级语义（Russ Cox 的 Pike VM 线程优先级实现）。

///|
/// 匹配策略：决定 Pike VM 在「同一起点、多候选」时如何取舍，不改变可匹配性。
pub(all) enum MatchKind {
  /// PCRE/Perl 最左优先：取首个按优先级成功的匹配。
  LeftmostFirst
  /// POSIX 最左最长（默认）：在最左起点的所有匹配中取最长者。
  LeftmostLongest
} derive(Eq)
