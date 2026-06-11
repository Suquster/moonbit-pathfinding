// actor_proof.mbt —— Actor_Framework（R10，基于 moonbitlang/async）方向的证明谓词占位。
//
// 复用约定：FIFO 顺序不变量复用通用谓词 `seq_eq`；本文件补充方向特有的
// 「错误隔离」最小占位谓词。谓词均为纯、全（total）。
// 升级路径：任务 16.x 引入真实 `ActorRef` / `Mailbox` 后替换占位。

///|
/// 邮箱 FIFO 顺序保持（占位）。
///
/// 单个 actor 的消息处理顺序应与发送顺序一致。直接复用 `seq_eq`。
pub fn fifo_order_preserved(sent : Array[Int], processed : Array[Int]) -> Bool {
  seq_eq(sent, processed)
}

///|
/// 错误隔离（占位）。
///
/// 某个 actor（标识为 `crashed`）崩溃后，存活集合应恰为崩溃前集合移除该
/// actor 的结果（顺序保持），其余 actor 不受影响。
pub fn error_isolation(
  alive_before : Array[Int],
  crashed : Int,
  alive_after : Array[Int],
) -> Bool {
  let expected : Array[Int] = []
  let mut i = 0
  while i < alive_before.length() {
    if alive_before[i] != crashed {
      expected.push(alive_before[i])
    }
    i += 1
  }
  seq_eq(expected, alive_after)
}
