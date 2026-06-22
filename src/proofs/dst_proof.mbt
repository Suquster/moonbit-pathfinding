// dst_proof.mbt —— DST_Framework（R8，复用 infra_pbt 随机源）方向的证明谓词占位。
//
// 复用约定：同种子可重放性质复用通用谓词 `seq_eq`（序列逐元素相等）。
// 谓词均为纯、全（total）。升级路径：任务 13.x 引入真实 `Rng` / `Sim` 后替换占位。

///|
/// 确定性可重放（占位）。
///
/// 同一种子的两次运行应产生逐元素一致的调度序列。直接复用 `seq_eq`。
/// 参数 `run1` / `run2` 为两次运行记录的调度事件序列；二者完全相等即返回
/// `true`，任一位置不同即返回 `false`（如实暴露不确定性反例）。纯、全函数，
/// 对任意长度组合恒返回 `Bool`，可被 ≥100 次随机种子的属性测试驱动。
pub fn deterministic_replay(run1 : Array[Int], run2 : Array[Int]) -> Bool {
  seq_eq(run1, run2)
}
