// demo.mbt —— 实战 demo 正则集（旗舰深化）。
//
// 对应 design.md §4.11（R11）。本文件为**新增**，提供贯穿可执行文档与基准的
// 实战模式（email / IPv4 / ISO 日期 / 数字字面量），覆盖编号与命名捕获组、
// 预定义字符类、量词与转义。所有模式均可经 `Pattern::compile` 验证（依赖
// search.mbt），并在 README.mbt.md 与 benches/regex_bench 复用。
//
// paper-to-code：模式遵循 RE2 / Rust `regex` 的 ASCII 字符类约定；捕获组用于
// 从真实文本抽取结构化字段（R11.2/11.3）。

///|
/// Email 模式：命名捕获 `user`（含编号 1）与 `domain`（编号 2）。
///
/// `[a-z0-9_.]+@[a-z0-9.]+` 的命名捕获形态，匹配 ASCII 小写 email 局部部分与
/// 域名（类内 `.` 为字面）。
pub fn demo_email() -> String {
  "(?<user>[a-z0-9_.]+)@(?<domain>[a-z0-9.]+)"
}

///|
/// IPv4 模式：四个八位组各为一个编号捕获组（1..4）。
///
/// `(\d{1,3})\.(\d{1,3})\.(\d{1,3})\.(\d{1,3})`，`\.` 为转义字面点。
pub fn demo_ipv4() -> String {
  "(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})\\.(\\d{1,3})"
}

///|
/// ISO 日期模式：命名捕获 `year` / `month` / `day`（编号 1..3）。
///
/// `(?<year>\d{4})-(?<month>\d{2})-(?<day>\d{2})`。
pub fn demo_iso_date() -> String {
  "(?<year>\\d{4})-(?<month>\\d{2})-(?<day>\\d{2})"
}

///|
/// 数字字面量模式：整数 / 小数 / 指数。
///
/// `-?\d+(\.\d+)?([eE][+-]?\d+)?`：可选负号、整数部分、可选小数部分、可选指数。
pub fn demo_number() -> String {
  "-?\\d+(\\.\\d+)?([eE][+-]?\\d+)?"
}

///|
/// 实战正则集：`(模式, 样例输入)` 数组，贯穿文档与基准复用。
pub fn demo_cases() -> Array[(String, String)] {
  [
    (demo_email(), "user_1@example.com"),
    (demo_ipv4(), "192.168.0.1"),
    (demo_iso_date(), "2026-06-12"),
    (demo_number(), "-12.5e+3"),
  ]
}
