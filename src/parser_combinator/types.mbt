// types.mbt —— Parser_Combinator 的核心类型定义。
//
// 设计依据（design.md §「组件与接口 → 方向四：Parser_Combinator」）：
//
//   pub struct Parser[T] { run : (Input) -> ParseResult[T] }
//   pub enum ParseResult[T] { Ok(T, Input); Fail(Pos, expected~ : Array[String]) }
//
// 本文件锁定模块边界与数据流：解析器是一个"输入 → 解析结果"的函数包装；
// 解析结果要么成功（携带产出值与剩余未消费输入），要么失败（携带失败位置
// 与期望符号集合）。组合子的具体实现属于任务 5.2。

///|
/// 源码位置（position）。
///
/// 与 design.md §「数据模型 → 跨方向共享：诊断与位置模型」中的 `Position`
/// 同形（line / col / offset），供失败诊断携带稳定定位信息：
///   * `line` —— 1 起始的行号；
///   * `col`  —— 1 起始的列号；
///   * `offset` —— 0 起始的字符偏移（用于在 `Input` 中索引）。
pub struct Pos {
  line : Int
  col : Int
  offset : Int
} derive(Eq)

///|
/// 以 `行:列` 形式展示位置（便于诊断信息与测试快照阅读）。
pub impl Show for Pos with fn output(self : Pos, logger : &Logger) -> Unit {
  logger.write_string("\{self.line}:\{self.col}")
}

///|
/// 构造起始位置 `line=1, col=1, offset=0`。
pub fn Pos::start() -> Pos {
  { line: 1, col: 1, offset: 0 }
}

///|
/// 解析输入（immutable parse input）。
///
/// 持有一份不可变的字符序列与当前游标位置 `pos`。所有推进操作（`advance`）
/// 都返回**新的** `Input`，绝不就地修改，从而天然支持任务 5.2 的回溯
/// （backtracking）：分支失败时只需丢弃新 `Input`、退回旧 `Input` 即可。
///
/// `chars` 在各 `Input` 之间按引用共享（只读，永不修改），游标位置 `pos`
/// 才是区分不同解析进度的唯一状态。
pub struct Input {
  chars : Array[Char]
  pos : Pos
}

///|
/// 从字符串构造解析输入，游标置于起始位置。
pub fn Input::from_string(source : String) -> Input {
  { chars: source.iter().to_array(), pos: Pos::start() }
}

///|
/// 当前游标是否已抵达输入末尾（end-of-input）。
pub fn Input::is_eof(self : Input) -> Bool {
  self.pos.offset >= self.chars.length()
}

///|
/// 查看当前游标处的字符而不消费；抵达末尾时返回 `None`。
pub fn Input::peek(self : Input) -> Char? {
  if self.pos.offset < self.chars.length() {
    Some(self.chars[self.pos.offset])
  } else {
    None
  }
}

///|
/// 返回游标前进一个字符后的新 `Input`（不修改自身）。
///
/// 行列号随之更新：遇到换行 `'\n'` 则行号 +1、列号复位为 1；否则列号 +1。
/// 已在末尾时原样返回（幂等地停在 EOF）。
pub fn Input::advance(self : Input) -> Input {
  match self.peek() {
    None => self
    Some(c) => {
      let next_pos = if c == '\n' {
        { line: self.pos.line + 1, col: 1, offset: self.pos.offset + 1 }
      } else {
        {
          line: self.pos.line,
          col: self.pos.col + 1,
          offset: self.pos.offset + 1,
        }
      }
      { chars: self.chars, pos: next_pos }
    }
  }
}

///|
/// 解析结果（parse result）。
///
/// 严格对应 design.md 的签名 `ParseResult[T] { Ok(T, Input); Fail(Pos,
/// expected~ : Array[String]) }`：
///   * `Ok(value, rest)` —— 成功消费输入前缀，携带产出值 `value` 与剩余
///     未消费输入 `rest`（满足 R4.2）；
///   * `Fail(pos, expected~)` —— 失败，携带失败位置 `pos` 与期望符号集合
///     `expected`，且不消费输入（满足 R4.3）。
pub enum ParseResult[T] {
  Ok(T, Input)
  Fail(Pos, expected~ : Array[String])
}

///|
/// 解析是否成功。
pub fn[T] ParseResult::is_ok(self : ParseResult[T]) -> Bool {
  match self {
    Ok(_, _) => true
    Fail(_, ..) => false
  }
}

///|
/// 成功时返回产出值，失败时返回 `None`。
pub fn[T] ParseResult::value(self : ParseResult[T]) -> T? {
  match self {
    Ok(v, _) => Some(v)
    Fail(_, ..) => None
  }
}

///|
/// 成功时返回剩余未消费输入，失败时返回 `None`。
pub fn[T] ParseResult::rest(self : ParseResult[T]) -> Input? {
  match self {
    Ok(_, rest) => Some(rest)
    Fail(_, ..) => None
  }
}

///|
/// 将解析失败桥接为模块共享的 `@core.PathError`（沿用 design.md §「错误
/// 处理」endorsed 的"复用 @core.PathError 模式"）。
///
/// 成功结果返回 `None`；失败结果返回 `Some(InvalidInput(...))`，其中携带
/// 失败位置与期望符号集合，便于上层方向（R1 / R2 / R9）以模块统一的错误
/// 类型向调用方汇报解析失败。
pub fn[T] ParseResult::to_path_error(self : ParseResult[T]) -> @core.PathError? {
  match self {
    Ok(_, _) => None
    Fail(pos, expected~) => {
      let mut exp = ""
      for i, e in expected {
        if i > 0 {
          exp = exp + ", "
        }
        exp = exp + e
      }
      Some(
        @core.PathError::InvalidInput(
          "解析失败于 \{pos}（offset \{pos.offset}），期望 \{exp}",
        ),
      )
    }
  }
}

///|
/// 解析器（parser）：对输入进行解析并产出 `ParseResult[T]` 的函数包装。
///
/// design.md 签名为 `Parser[T] { run : (Input) -> ParseResult[T] }`。组合子
/// （`seq` / `alt` / `many` ...）将以"接收若干 `Parser` 返回新 `Parser`"的
/// 形式构建于该结构之上（任务 5.2）。
pub struct Parser[T] {
  run : (Input) -> ParseResult[T]
}

///|
/// 由一个 `(Input) -> ParseResult[T]` 函数构造解析器。
pub fn[T] Parser::new(run : (Input) -> ParseResult[T]) -> Parser[T] {
  { run, }
}

///|
/// 在给定输入上运行解析器。
pub fn[T] Parser::parse(self : Parser[T], input : Input) -> ParseResult[T] {
  (self.run)(input)
}

///|
/// 便捷方法：直接在字符串上运行解析器（内部构造 `Input`）。
pub fn[T] Parser::parse_string(
  self : Parser[T],
  source : String,
) -> ParseResult[T] {
  self.parse(Input::from_string(source))
}
