// mini_compiler_proof.mbt —— Mini_Compiler（R1）方向的证明谓词。
//
// 复用约定（见 design.md「proofs（扩展）」）：
//   * 方向核心不变量编码为纯、全（total）的 `pub fn ... -> Bool` 谓词；
//   * 优先复用 `predicates.mbt` 中的通用谓词：AST 往返用 `round_trip_eq`，
//     求值确定性用 `seq_eq`；本文件补充方向特有的作用域不变量谓词；
//   * 包已启用 `options("proof-enabled": true)`，预留 `moon prove` 升级路径。
//
// 对应任务 15.5（design.md Property 3「Mini_Compiler 求值确定性与作用域
// 不变量」）：本文件确认 `scope_binding_consistent` 为作用域绑定一致性的
// 证明谓词——它刻画 R1.9 的核心命题「被使用的名字都在绑定集合内 ⇒ 无自由
// 变量」。该谓词为方向无关的纯函数：`proofs` 与 `mini_compiler` 为不同包，
// 故谓词不直接依赖 `Ast` / `TypedAst`，而由调用方（mini_compiler 的属性测试
// 经真实 `check` / `eval`；proofs 的运行期测试经正反例）从结构中抽取「绑定
// 集合」与「使用集合」后调用。其正反例由 `src/proofs` 的运行期测试校验
// （见 `mini_compiler_proof_test.mbt` 与 `direction_proofs_test.mbt`）。

///|
/// 作用域绑定一致性（scope binding consistency）。
///
/// 给定「已绑定标识符集合」`bound` 与「被使用标识符序列」`used`，当且仅当
/// 每个被使用的标识符都出现在 `bound` 中时成立——即不存在自由变量。这是
/// Mini_Compiler 求值器作用域语义的关键不变量（R1.9）：通过 `check` 的程序
/// 其使用集合必为绑定集合的子集。
///
/// 本谓词为纯、全（total）函数：`used` 为空时平凡成立；对每个被使用名字做
/// 一次线性查找，全部命中才返回 `true`。
pub fn scope_binding_consistent(
  bound : Array[String],
  used : Array[String],
) -> Bool {
  let mut i = 0
  while i < used.length() {
    let name = used[i]
    let mut found = false
    let mut j = 0
    while j < bound.length() {
      if bound[j] == name {
        found = true
        break
      }
      j += 1
    }
    if !found {
      return false
    }
    i += 1
  }
  true
}
