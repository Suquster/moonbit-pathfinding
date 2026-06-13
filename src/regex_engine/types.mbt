// types.mbt —— Regex_Engine 的正则语法树（syntax tree）与解析错误类型。
//
// 设计依据（design.md §「方向二：Regex_Engine」核心类型）：
//
//   pub enum Regex { Char(Char); Class(CharClass); Star(Regex); Plus(Regex)
//                    Opt(Regex); Repeat(Regex, Int, Int?); Concat(Array[Regex])
//                    Alt(Array[Regex]); Anchor(AnchorKind); Group(Regex) }
//
// 本文件锁定语法树形态与"含位置的解析错误"模型（R2.1 / R2.3）。NFA/DFA 等
// 自动机类型属于任务 6.2，本文件不涉及。

///|
/// 锚点类型（anchor kind）。
///
/// 对应正则中的位置锚点：`^`（行/串首）与 `$`（行/串尾）。锚点不消费字符，
/// 仅约束匹配位置；在语法树中作为独立节点 `Anchor(AnchorKind)` 存在。
pub(all) enum AnchorKind {
  /// 串首锚点 `^`。
  Start
  /// 串尾锚点 `$`。
  End
} derive(Eq)

///|
/// 字符类成员项（character-class item）。
///
/// 字符类（如 `[a-z0-9_]`）由若干成员项组成，每项要么是单个字符，要么是一段
/// 闭区间范围 `a-b`（含两端）。
pub(all) enum ClassItem {
  /// 单个字符成员，如 `[_]` 中的 `_`。
  Single(Char)
  /// 字符范围成员 `lo-hi`（含两端），如 `[a-z]`。
  Range(Char, Char)
} derive(Eq)

///|
/// 字符类（character class），对应正则 `[...]` 与 `[^...]`。
///
///   * `negated` —— 是否为否定字符类（以 `^` 开头，匹配不在集合内的字符）；
///   * `items`   —— 字符类成员项序列（单字符或范围）。
pub(all) struct CharClass {
  negated : Bool
  items : Array[ClassItem]
} derive(Eq)

///|
/// 正则语法树（regular-expression syntax tree）。
///
/// 严格对应 design.md 的枚举形态，覆盖 R2.1 声明的受支持子集：字符、字符类、
/// 量词（`*` `+` `?` `{m,n}`）、分组、择一（`|`）与锚点。
pub(all) enum Regex {
  /// 单个字面字符，如 `a`。
  Char(Char)
  /// 字符类，如 `[a-z]` / `[^0-9]`。
  Class(CharClass)
  /// Kleene 星号 `*`：重复零次或多次。
  Star(Regex)
  /// Kleene 加号 `+`：重复一次或多次。
  Plus(Regex)
  /// 可选 `?`：出现零次或一次。
  Opt(Regex)
  /// 计数量词 `{m}` / `{m,}` / `{m,n}`：第二参数为 `None` 表示无上界 `{m,}`。
  Repeat(Regex, Int, Int?)
  /// 串接（concatenation）：按序匹配子表达式序列；空序列表示空正则。
  Concat(Array[Regex])
  /// 择一（alternation）`a|b|c`：匹配任一分支。
  Alt(Array[Regex])
  /// 位置锚点 `^` / `$`。
  Anchor(AnchorKind)
  /// 分组 `( ... )`：显式分组以约束量词/择一的作用范围。
  Group(Regex)
} derive(Eq)

///|
/// 正则解析错误（parse error），均携带**字符偏移位置**以满足 R2.3
/// 「返回包含错误位置的解析错误，且不构造自动机」。
///
/// 沿用 design.md §「跨方向共享：结果与错误模型」约定——错误是枚举而非
/// 字符串，便于测试断言与后续证明谓词引用，且每个变体均含定位信息。
pub(all) enum ParseError {
  /// 在 `pos` 处遇到非法/意外输入；`expected` 给出此处期望的符号集合。
  Unexpected(pos~ : Int, expected~ : Array[String])
  /// 未闭合的分组或字符类；`what` 标注起始定界符（`"("` 或 `"["`）。
  Unbalanced(pos~ : Int, what~ : String)
  /// 量词（`*` `+` `?` `{...}`）出现在没有可作用对象的位置。
  DanglingQuantifier(pos~ : Int)
  /// 计数量词 `{m,n}` 语法非法（缺少数字、缺少 `}` 等）。
  InvalidRepeat(pos~ : Int)
  /// 顶层解析完成后仍有未消费输入（如多余的 `)`）。
  TrailingInput(pos~ : Int)
} derive(Eq)

///|
/// 提取解析错误所在的字符偏移位置（0 起始）。
pub fn ParseError::pos(self : ParseError) -> Int {
  match self {
    Unexpected(pos~, ..) => pos
    Unbalanced(pos~, ..) => pos
    DanglingQuantifier(pos~) => pos
    InvalidRepeat(pos~) => pos
    TrailingInput(pos~) => pos
  }
}
