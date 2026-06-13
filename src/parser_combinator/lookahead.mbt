// lookahead.mbt —— L0 前瞻（lookahead）与否定前瞻（negative lookahead）。
//
// 对应 tasks.md 任务 3.1，落地 design.md §「组件与接口 → 3. 前瞻与否定前瞻」。
// 二者均利用既有 `Input` 的**不可变性**实现「零消费」：在成功分支用**进入时
// 的 input** 作为剩余输入返回，从而剩余输入位置与进入位置逐字段一致（R4.5）。

///|
/// `lookahead(p)`：前瞻——尝试运行 `p` 但**不消费输入**。
///
///   * `p` 在当前位置成功 → 产出 `p` 的值，但剩余输入仍为**进入时**的 `input`
///     （零消费，R4.1）；
///   * `p` 失败 → 在**进入位置**失败并报告 `p` 的期望符号，且不消费输入
///     （R4.2）。
pub fn[T] lookahead(p : Parser[T]) -> Parser[T] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Ok(v, _rest) => ParseResult::Ok(v, input) // 零消费：丢弃 p 推进后的剩余输入
      Fail(_pos, expected~) => ParseResult::Fail(input.pos, expected~)
    }
  })
}

///|
/// `not_followed_by(p)`：否定前瞻——仅当 `p` 在当前位置**失败**时成功。
///
///   * `p` 失败 → 成功，产出单位值 `()` 且不消费输入（R4.3）；
///   * `p` 成功 → 在**进入位置**失败且不消费输入（R4.4），期望符号说明此处
///     不应出现 `p` 所匹配的内容。
pub fn[T] not_followed_by(p : Parser[T]) -> Parser[Unit] {
  Parser::new(fn(input) {
    match p.parse(input) {
      Ok(_v, _rest) =>
        ParseResult::Fail(input.pos, expected=["不应出现的内容（否定前瞻）"])
      Fail(_pos, ..) => ParseResult::Ok((), input)
    }
  })
}
