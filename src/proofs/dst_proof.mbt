// dst_proof.mbt —— DST_Framework（R8，复用 infra_pbt 随机源）方向的契约谓词。
//
// 复用约定：同种子可重放性质复用通用谓词 `seq_eq`（序列逐元素相等）。
// 真实 `Rng` / `Sim` 的运行轨迹由 DST 属性测试投影后交给本纯、全谓词比较。

///|
/// 确定性可重放。
///
/// 同一种子的两次运行应产生逐元素一致的调度序列。直接复用 `seq_eq`。
/// 参数 `run1` / `run2` 为两次运行记录的调度事件序列；二者完全相等即返回
/// `true`，任一位置不同即返回 `false`（如实暴露不确定性反例）。纯、全函数，
/// 对任意长度组合恒返回 `Bool`，可被 ≥100 次随机种子的属性测试驱动。
pub fn deterministic_replay(run1 : Array[Int], run2 : Array[Int]) -> Bool {
  seq_eq(run1, run2)
}
