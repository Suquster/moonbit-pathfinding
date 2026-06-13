// flags.mbt —— 编译标志集 `Flags` 与预定义字符类 → `CharSet` 构造（旗舰深化）。
//
// 对应 design.md §4.2「标志 `Flags` 与字符类增强」（R6）。本文件为**新增**，
// 不改动既有 `CharSet`（定义于 nfa.mbt）的字段，仅在其上构造区间集合，从而
// 把「预定义类 / 点号 / 大小写」等语义统一规约为 `CharSet` 区间运算（R6.7），
// 与既有否定字符类补集、DFA 字母表原子区间划分完全同源。
//
// paper-to-code：预定义类 `\d\w\s` 的码点集合遵循 POSIX / PCRE 的 ASCII 约定；
// `\D\W\S` 为对应正向类在 [0, MAX_CODE] 上的精确补集（复用 nfa.mbt 的
// `complement_intervals`），与 Rust `regex` 的 ASCII 类语义一致。

///|
/// 编译标志集（flag set）：影响匹配语义的标志组合（R6）。
///
///   * `ignore_case` —— `i`：字面字符与字符类按 ASCII 大小写折叠匹配；
///   * `multiline`   —— `m`：锚点 `^`/`$` 匹配每行行首 / 行尾；
///   * `dotall`      —— `s`：点号 `.` 匹配包含换行在内的任意字符。
///
/// 默认全 `false`，保持与既有 `find`/`is_match` 行为兼容（R6.6）。
pub(all) struct Flags {
  ignore_case : Bool
  multiline : Bool
  dotall : Bool
} derive(Eq)

///|
/// 默认标志集：全部关闭（保持既有语义，R6.6）。
pub fn Flags::default() -> Flags {
  { ignore_case: false, multiline: false, dotall: false }
}

///|
/// 由标志字符串（`"ims"` 子集）构造标志集；未识别字符忽略。
pub fn Flags::parse(spec : String) -> Flags {
  let mut i = false
  let mut m = false
  let mut s = false
  for c in spec {
    match c {
      'i' => i = true
      'm' => m = true
      's' => s = true
      _ => ()
    }
  }
  { ignore_case: i, multiline: m, dotall: s }
}

///|
/// 预定义字符类 `\d` → 数字集合 `[0-9]`。
pub fn predef_digit() -> CharSet {
  { intervals: normalize_intervals([('0'.to_int(), '9'.to_int())]) }
}

///|
/// 预定义字符类 `\w` → 词字符集合 `[0-9A-Za-z_]`。
pub fn predef_word() -> CharSet {
  let raw : Array[(Int, Int)] = [
    ('0'.to_int(), '9'.to_int()),
    ('A'.to_int(), 'Z'.to_int()),
    ('_'.to_int(), '_'.to_int()),
    ('a'.to_int(), 'z'.to_int()),
  ]
  { intervals: normalize_intervals(raw) }
}

///|
/// 预定义字符类 `\s` → 空白集合 `[ \t\n\r\f\v]`（码点 9..13 与 32）。
pub fn predef_space() -> CharSet {
  let raw : Array[(Int, Int)] = [(9, 13), (32, 32)]
  { intervals: normalize_intervals(raw) }
}

///|
/// `\d` 的否定 `\D`：数字集合在 [0, MAX_CODE] 上的补集。
pub fn predef_non_digit() -> CharSet {
  predef_digit().complement()
}

///|
/// `\w` 的否定 `\W`：词字符集合的补集。
pub fn predef_non_word() -> CharSet {
  predef_word().complement()
}

///|
/// `\s` 的否定 `\S`：空白集合的补集。
pub fn predef_non_space() -> CharSet {
  predef_space().complement()
}

///|
/// 点号 `.` 对应的字符集合：启用 dotall（`s`）时为全集 [0, MAX_CODE]，否则
/// 为全集去换行符 `\n`（码点 10），即 `(0,9) ∪ (11, MAX_CODE)`（R6.2/6.3）。
pub fn Flags::dot_set(self : Flags) -> CharSet {
  if self.dotall {
    { intervals: [(0, MAX_CODE)] }
  } else {
    { intervals: [(0, 9), (11, MAX_CODE)] }
  }
}
