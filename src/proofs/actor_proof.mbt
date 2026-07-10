// actor_proof.mbt —— Actor_Framework（R10）方向的契约谓词。
//
// 复用约定：FIFO 顺序不变量复用通用谓词 `seq_eq`；本文件补充方向特有的
// 「错误隔离」谓词。生产运行时属性测试从真实 `ActorRef` / `Mailbox` 执行
// 轨迹投影出输入，谓词保持纯、全（total），便于收缩反例。

///|
/// 邮箱 FIFO 顺序保持。
///
/// 单个 actor 的消息处理顺序应与发送顺序一致。直接复用 `seq_eq`。
/// 参数 `sent` 为发送序列、`processed` 为处理序列；二者逐元素相等即返回
/// `true`。该谓词为纯、全（total）函数，对任意输入恒返回 `Bool`，可被
/// 属性测试以 ≥100 随机序列驱动验证（不会 abort）。
pub fn fifo_order_preserved(sent : Array[Int], processed : Array[Int]) -> Bool {
  seq_eq(sent, processed)
}

///|
/// 错误隔离。
///
/// 某个 actor（标识为 `crashed`）崩溃后，存活集合应恰为崩溃前集合移除该
/// actor 的结果（顺序保持），其余 actor 不受影响。本谓词按原顺序过滤掉
/// `crashed` 后与 `alive_after` 逐元素比较。纯、全函数：即使 `crashed`
/// 不在 `alive_before` 中（过滤为恒等），亦正常返回布尔结果而不报错。
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
