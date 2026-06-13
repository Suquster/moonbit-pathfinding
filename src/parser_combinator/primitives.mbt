// primitives.mbt —— 基础解析原语（primitives）。
//
// 对应任务 5.1 的"基础原语桩：pchar、字符/词法单元匹配"。这些原语是终结符
// （terminal）匹配器，构成组合子（任务 5.2 的 seq / alt / many ...）的叶子。
//
// design.md 签名：`pub fn pchar(c : Char) -> Parser[Char]`。本文件在此基础上
// 补充 `satisfy`（按谓词匹配字符）、`any_char`（匹配任意字符）与 `ptoken`
// （匹配字面词法单元），覆盖 R4.1 所要求的"字符/词法单元匹配"原语。
//
// 失败契约（R4.3）：任一原语匹配失败时返回 `Fail(pos, expected~)`，其中 `pos`
// 为失败发生处位置、`expected` 为期望符号；失败不消费输入（`ParseResult` 仅在
// `Ok` 分支携带剩余输入，`Fail` 分支不携带，天然满足"不消费输入"）。

///|
/// 按谓词匹配单个字符（character predicate matcher）。
///
/// 当前游标处存在字符且满足 `pred` 时成功，产出该字符并前进一位；否则
/// （字符不满足或已到末尾）失败，期望符号取 `label`。这是其余字符原语
/// （`pchar` / `any_char`）的公共基座。
pub fn satisfy(pred : (Char) -> Bool, label~ : String) -> Parser[Char] {
  Parser::new(fn(input) {
    match input.peek() {
      Some(c) =>
        if pred(c) {
          ParseResult::Ok(c, input.advance())
        } else {
          ParseResult::Fail(input.pos, expected=[label])
        }
      None => ParseResult::Fail(input.pos, expected=[label])
    }
  })
}

///|
/// 匹配指定字符 `c`（design.md 核心原语 `pchar`）。
///
/// 成功时产出该字符并消费一位；失败时报告期望该字符。构建于 `satisfy`。
pub fn pchar(c : Char) -> Parser[Char] {
  satisfy(fn(x) { x == c }, label="'\{c}'")
}

///|
/// 匹配任意单个字符（仅在抵达输入末尾时失败）。
pub fn any_char() -> Parser[Char] {
  satisfy(fn(_x) { true }, label="任意字符")
}

///|
/// 匹配一个字面词法单元（literal token）。
///
/// 逐字符比对 `literal`：全部匹配时成功，产出整个词法单元并把游标推进到其
/// 末尾之后；任一字符不匹配（或中途到达输入末尾）时失败，失败位置取词法
/// 单元起始处且不消费输入（R4.3）。空串 `literal` 视为立即成功且不消费。
pub fn ptoken(literal : String) -> Parser[String] {
  let wanted = literal.iter().to_array()
  Parser::new(fn(start) {
    let mut cur = start
    let mut i = 0
    while i < wanted.length() {
      match cur.peek() {
        Some(c) =>
          if c == wanted[i] {
            cur = cur.advance()
            i = i + 1
          } else {
            return ParseResult::Fail(start.pos, expected=["\"\{literal}\""])
          }
        None => return ParseResult::Fail(start.pos, expected=["\"\{literal}\""])
      }
    }
    ParseResult::Ok(literal, cur)
  })
}
