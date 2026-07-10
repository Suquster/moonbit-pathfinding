// parser_combinator_proof.mbt —— Parser_Combinator（R4，地基）方向的契约谓词。
//
// 复用约定：语法结构往返复用 `round_trip_eq`；本文件补充方向特有的
// 「失败不消费输入」契约谓词。真实 `Parser[T]` / `ParseResult[T]` 属性测试
// 投影成功状态与前后位置；谓词保持纯、全（total）。

///|
/// 失败不消费输入。
///
/// 解析组合子的回溯契约：当解析失败（`success == false`）时，输入位置必须
/// 保持不变（`pos_before == pos_after`）；成功时不约束位置。实现为
/// `success || pos_before == pos_after`，即蕴含「失败 ⇒ 位置不变」。
/// 纯、全函数，对任意布尔与整数位置组合恒返回 `Bool`。
pub fn fail_does_not_consume(
  success : Bool,
  pos_before : Int,
  pos_after : Int,
) -> Bool {
  success || pos_before == pos_after
}
