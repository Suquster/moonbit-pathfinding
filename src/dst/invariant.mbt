// invariant.mbt —— DST_Framework 旗舰深化：运行时不变量（旁路新增，设计 4.10）。
//
// 运行时不变量（runtime invariant）是对**可观测全局状态**的布尔断言。DES 引擎
// （`des_sim.mbt` 的 `World`）在每个可观测状态求值场景附带的全部不变量；任一为
// 假即令运行以 `Failed(reason)` 终止，原因标识被违反的不变量名称与发生的逻辑
// 时间戳（R7.1 / R7.2 / R7.3）。
//
// 落点说明（设计 4.6 / 4.10）：运行时不变量的每步求值是 DES 核心循环的内在组成
// （收缩 / 探索 / DPOR 均依赖「不变量违反 → `Failed`」作为失败来源），故与 DES
// 核心循环同波次落地。线性一致性检查（Wing & Gong）属后续阶段（linearizability.mbt）。

///|
/// 运行时不变量：对可观测全局状态 `World` 的布尔断言。
///
///   * `name`  —— 不变量名称（违反时写入失败原因，便于诊断）；
///   * `check` —— 断言函数：对当前世界状态求值，`true` 表示成立。
///
/// 含函数值字段，故不派生。
pub struct Invariant {
  name : String
  check : (World) -> Bool
}

///|
/// 由名称与断言函数构造一个运行时不变量。
pub fn Invariant::new(name : String, check : (World) -> Bool) -> Invariant {
  { name, check }
}

///|
/// 在当前世界状态上求值全部不变量；返回首个被违反不变量的失败原因，全部成立
/// 返回 `None`。
///
/// 失败原因标识被违反的不变量名称与发生的逻辑时间戳（R7.3）：
/// 「不变量 `<name>` 于逻辑时间 `<t>` 被违反」。
pub fn eval_invariants(world : World) -> String? {
  for inv in world.invariants {
    if !(inv.check)(world) {
      return Some(
        "不变量 \{inv.name} 于逻辑时间 \{world.clock} 被违反",
      )
    }
  }
  None
}
