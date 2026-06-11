// mini_compiler_proof_test.mbt —— Mini_Compiler 作用域绑定一致性谓词运行期测试。
//
// 校验 `scope_binding_consistent` 谓词的正反例，使证明脚手架（R1.9 / design.md
// Property 3）在运行时也得到验证。配合 `src/mini_compiler/prop_eval_test.mbt`
// （Property 3 属性测试，经真实 check/eval 流水线）共同覆盖「作用域不变量 +
// 求值确定性」两面。proofs 与 mini_compiler 为不同包，本谓词为方向无关纯函数。
// **Validates: Requirements 1.9**

///|
/// 使用集合为空时平凡成立（无被引用名字 ⇒ 无自由变量）。
test "scope_binding_consistent 空使用集合平凡成立" {
  inspect(scope_binding_consistent([], []), content="true")
  inspect(scope_binding_consistent(["x", "y"], []), content="true")
}

///|
/// 全部被使用名字都在绑定集合内时成立。
test "scope_binding_consistent 全部使用名字均已绑定时成立" {
  inspect(
    scope_binding_consistent(["x", "y", "z"], ["x", "z", "y"]),
    content="true",
  )
}

///|
/// 重复使用同一已绑定名字仍成立（绑定集合可被多次引用）。
test "scope_binding_consistent 重复引用已绑定名字仍成立" {
  inspect(scope_binding_consistent(["a"], ["a", "a", "a"]), content="true")
}

///|
/// 存在自由变量（使用名字不在绑定集合内）时失败。
test "scope_binding_consistent 存在自由变量时失败" {
  inspect(scope_binding_consistent(["x"], ["x", "y"]), content="false")
}

///|
/// 绑定集合为空但仍有被使用名字时失败（典型未绑定引用）。
test "scope_binding_consistent 空绑定集合下任意引用失败" {
  inspect(scope_binding_consistent([], ["x"]), content="false")
}
