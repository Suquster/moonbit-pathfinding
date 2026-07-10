// codegen_infra_proof.mbt —— Codegen_Infra（R3，复用图着色）方向的契约谓词。
//
// 复用约定（见 design.md「proofs（扩展）」）：
//   * SSA pass 流水线「保持单赋值不变量」可复用通用谓词 `preserves`；
//   * 本文件补充方向特有的纯、全（total）谓词。
//
// 升级路径：design.md 声明的 `ssa_single_assignment(p : SsaProgram) -> Bool`
// 需要 `SsaProgram` 类型（属 `codegen_infra` 包），为保持 `proofs` 为方向
// 无关的纯谓词基座，本文件以等价的 version-id 形式 `ssa_single_assignment(
// def_ids : Array[Int]) -> Bool` 落地：由 `codegen_infra` 白盒属性测试从
// `SsaProgram` 抽取定义版本号集合后调用本谓词（见任务 11.4，Property 8）。
// 基于计数的 `ssa_single_assignment_counts` 作为另一等价表述一并保留。

///|
/// SSA 单赋值不变量。
///
/// 给定各 SSA 变量的「定义次数」列表 `def_counts`，当且仅当每个变量恰好被
/// 定义一次（计数为 1）时成立。这是 SSA 形式的核心不变量。任一计数不等于 1
/// （0 表示未定义、>1 表示多重定义）即返回 `false`。空列表平凡为真。
/// 纯、全函数，对任意整数列表恒返回 `Bool`。
pub fn ssa_single_assignment_counts(def_counts : Array[Int]) -> Bool {
  let mut i = 0
  while i < def_counts.length() {
    if def_counts[i] != 1 {
      return false
    }
    i += 1
  }
  true
}

///|
/// SSA 单赋值不变量（version-id 形式，Property 8）。
///
/// 给定一个 SSA 程序中「全部定义」的版本号列表 `def_ids`（块内定义左值的
/// 版本号 + φ 目标的版本号），当且仅当这些版本号两两互不相同时成立——
/// 即每个变量恰有唯一一次静态定义（Requirement 3.5），且该不变量在任意
/// pass 序列执行后仍可由同一谓词校验（Requirement 3.6）。
///
/// 本谓词为纯、全（total）函数，且与 `codegen_infra` 包无关：调用方
/// （`codegen_infra` 的白盒属性测试）负责从 `SsaProgram` 抽取定义版本号
/// 集合，本谓词只判定核心命题「定义版本号集合两两不同 ⇒ 单赋值成立」。
pub fn ssa_single_assignment(def_ids : Array[Int]) -> Bool {
  let seen : Map[Int, Bool] = Map([])
  let mut i = 0
  while i < def_ids.length() {
    let v = def_ids[i]
    if seen.contains(v) {
      return false
    }
    seen[v] = true
    i += 1
  }
  true
}

///|
/// 寄存器分配干涉不变量。
///
/// 给定每条干涉边两端变量被分配到的寄存器编号对 `colored_edges`，当且仅当
/// 每条边两端寄存器互不相同时成立——即相邻（冲突）变量不共享寄存器。任一边
/// 两端寄存器相同即返回 `false`（暴露非法着色反例）。空边集平凡为真。
/// 纯、全函数，对任意整数对列表恒返回 `Bool`。
pub fn interference_distinct(colored_edges : Array[(Int, Int)]) -> Bool {
  let mut i = 0
  while i < colored_edges.length() {
    let (a, b) = colored_edges[i]
    if a == b {
      return false
    }
    i += 1
  }
  true
}
