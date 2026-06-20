// demo_unit_test.mbt —— 旗舰端到端示例（demo.mbt）黑盒单元测试，覆盖
// R9.2 / R9.3 / R9.4（任务 12.2）。
//
// 本文件为黑盒测试（`_test.mbt`），仅通过本包 `pub` / `pub(all)` 接口
// （`demo_factorial_src` / `demo_fib_src` / `run_demo` / `DemoTrace` / `Ty` /
// `Val`）观察端到端各阶段产物，不触碰内部实现，亦不修改任何源文件。
//
// 断言三件事，逐条对齐 demo.mbt 文档声明：
//   1. 推断主类型与文档一致（R9.4）：两示例顶层结果均为 `TyInt`。
//   2. 优化后形态与文档一致（R9.2）：`optimized_form` 为 `print_expr(optimize(e))`
//      所得源串，断言其与下方精确字符串相符（实跑校准）。
//   3. 解释结果与 VM 结果彼此相等且与文档声明的运行期值相符（R9.2 / R9.3）：
//      阶乘 `fact 5 = 120`、斐波那契 `fib 10 = 55`，两路 `interp_result ==
//      vm_result`。
//
// 注：`Ty` 派生 `Eq + Show`、`Val` 仅派生 `Eq`（无 `Show`），故对 `Ty` / `Val`
// 的相等性统一以 `assert_true(... == ...)` 比较；`optimized_form` 为 `String`，
// 以 `assert_eq` 比较以便失配时打印实际差异。
//
// 运行 native 后端前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

///|
/// 阶乘示例端到端断言（R9.2 / R9.3 / R9.4）。
///
/// `let rec fact = fun n -> if n <= 1 then 1 else n * fact (n - 1) in fact 5`
/// 主类型为 `TyInt`（R9.4），优化后形态与下方精确串相符（R9.2），解释路径与
/// 编译—执行路径均产出 `VInt(120)` 且彼此相等（R9.2 / R9.3）。
test "demo: factorial end-to-end trace matches documented products" {
  let t = run_demo(demo_factorial_src)
  // R9.4：推断主类型与文档一致。
  assert_true(t.principal_type == TyInt)
  // R9.2：解释结果与文档声明的运行期值相符（fact 5 = 120）。
  assert_true(t.interp_result == VInt(120))
  // R9.3：编译—执行结果与文档声明的运行期值相符。
  assert_true(t.vm_result == VInt(120))
  // R9.3：两路对同一示例产出相等的 Val（解释 == VM）。
  assert_true(t.interp_result == t.vm_result)
  // R9.2：优化后形态与文档声明的源串形态精确相符（实跑校准）。
  assert_eq(
    t.optimized_form,
    "(let rec fact = (fun n -> (if (n <= 1) then 1 else (n * (fact (n - 1))))) in (fact 5))",
  )
}

///|
/// 斐波那契示例端到端断言（R9.2 / R9.3 / R9.4）。
///
/// `let rec fib = fun n -> if n <= 1 then n else fib (n - 1) + fib (n - 2) in fib 10`
/// 主类型为 `TyInt`（R9.4），优化后形态与下方精确串相符（R9.2），解释路径与
/// 编译—执行路径均产出 `VInt(55)` 且彼此相等（R9.2 / R9.3）。
test "demo: fibonacci end-to-end trace matches documented products" {
  let t = run_demo(demo_fib_src)
  // R9.4：推断主类型与文档一致。
  assert_true(t.principal_type == TyInt)
  // R9.2：解释结果与文档声明的运行期值相符（fib 10 = 55）。
  assert_true(t.interp_result == VInt(55))
  // R9.3：编译—执行结果与文档声明的运行期值相符。
  assert_true(t.vm_result == VInt(55))
  // R9.3：两路对同一示例产出相等的 Val（解释 == VM）。
  assert_true(t.interp_result == t.vm_result)
  // R9.2：优化后形态与文档声明的源串形态精确相符（实跑校准）。
  assert_eq(
    t.optimized_form,
    "(let rec fib = (fun n -> (if (n <= 1) then n else ((fib (n - 1)) + (fib (n - 2))))) in (fib 10))",
  )
}

///|
/// 两路一致性（R9.3）与主类型如文档声明（R9.4）的通用断言。
///
/// 对两示例统一断言：解释路径与编译—执行路径产出彼此相等的 `Val`（端到端两路
/// 一致，R9.3），且推断主类型恒为文档声明的 `TyInt`（R9.4）。这是对上面逐示例
/// 断言的归纳式复述，确保「两路一致 + 主类型如声明」作为示例不变量成立。
test "demo: both paths agree (R9.3) and principal type is as documented (R9.4)" {
  for src in [demo_factorial_src, demo_fib_src] {
    let t = run_demo(src)
    // R9.3：解释路径与编译—执行路径对同一良类型示例产出相等的 Val。
    assert_true(t.interp_result == t.vm_result)
    // R9.4：示例顶层结果主类型如文档声明，为基类型 TyInt。
    assert_true(t.principal_type == TyInt)
  }
}
