// codegen_infra_proof_test.mbt —— Codegen_Infra 证明谓词运行时测试。
//
// 校验 SSA 单赋值不变量谓词的正反例，使证明脚手架（R8）在运行时也得到验证。
// 配合 `src/codegen_infra/prop_ssa_wbtest.mbt`（Property 8 属性测试）共同覆盖
// 「建立与保持」两面。
// **Validates: Requirements 3.5, 3.6**

///|
/// 空程序无任何定义，单赋值不变量平凡成立。
test "ssa_single_assignment 空定义集合平凡成立" {
  inspect(ssa_single_assignment([]), content="true")
}

///|
/// 定义版本号两两互不相同（典型 build_ssa 产出）时成立。
test "ssa_single_assignment 版本号两两不同时成立" {
  inspect(ssa_single_assignment([0, 1, 2, 3, 4]), content="true")
}

///|
/// 存在重复定义版本号（违反单赋值）时失败。
test "ssa_single_assignment 存在重复定义版本号时失败" {
  inspect(ssa_single_assignment([0, 1, 1, 2]), content="false")
}

///|
/// 相邻重复亦被检出。
test "ssa_single_assignment 相邻重复版本号失败" {
  inspect(ssa_single_assignment([5, 5]), content="false")
}

///|
/// 等价的计数形式谓词：每个变量恰好定义一次时成立。
test "ssa_single_assignment_counts 每变量恰定义一次时成立" {
  inspect(ssa_single_assignment_counts([1, 1, 1]), content="true")
}

///|
/// 等价的计数形式谓词：存在被定义两次的变量时失败。
test "ssa_single_assignment_counts 存在重复定义时失败" {
  inspect(ssa_single_assignment_counts([1, 2, 1]), content="false")
}
