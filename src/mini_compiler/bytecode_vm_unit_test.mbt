// bytecode_vm_unit_test.mbt —— 字节码 / VM 单元测试（任务 8.5；R6.1 / R6.2 / R6.3）。
//
// 目的：以一组**固定**源串，逐字断言旁路新增的字节码后端两件套
//   * `compile_ml(TExpr) -> Bytecode`（bytecode.mbt，R6.1 / R6.2）
//   * `VM::run(Bytecode, Env) -> Val`（vm.mbt，R6.3）
// 的具体行为：
//   (A) 字节码结构（R6.1 / R6.2）：对布局确定的简单表达式，断言 `compile_ml(...)`
//       产出的指令数组逐条等于精确期望（常量 / 算术 / 比较 / 逻辑 / if 跳转的
//       绝对索引回填 / 闭包构造 / 应用）。
//   (B) VM 执行（R6.3）：断言 `VM::run(compile_ml(te(src)), ml_env_empty())` 等于
//       期望 `Val`，并与 `eval_ml(te(src))` 交叉一致（编译—执行 ≡ 树遍历求值，
//       覆盖常量 / 算术 / 除零=0 / 比较 / 逻辑 / if 跳转 / 闭包构造与调用 /
//       高阶函数 / 递归 MkRecClosure）。
//
// 构造 `TExpr` 的方式：PARSE 源串（`lex_ml` + `parse_ml`）→ `infer`，比手工构造
// 带类型标注语法树更简洁可靠。期望值据 bytecode.mbt / vm.mbt（已验证真值来源）
// 的实际输出对齐。本文件为旁路新增的黑盒 `_test.mbt`，不修改任何既有源文件。

// ---------------------------------------------------------------------------
// 测试夹具（fixtures）
// ---------------------------------------------------------------------------

///|
/// 源串 → 词法 → 语法 → 推断，得到良类型 `TExpr`；任何前置失败均中止（夹具均为
/// 合法、良类型源串）。MoonBit 无 `unwrap`，用 `match` + `abort` 解 `Result`。
fn bv_te(src : String) -> TExpr {
  let tokens = match lex_ml(src) {
    Ok(ts) => ts
    Err(d) => abort("词法分析意外失败：\{d.msg}")
  }
  let e = match parse_ml(tokens) {
    Ok(ex) => ex
    Err(d) => abort("语法分析意外失败：\{d.msg}")
  }
  match infer(e) {
    Ok((t, _)) => t
    Err(d) => abort("infer 意外失败：\{d.msg}")
  }
}

///|
/// 在空环境下编译并执行源串，得到运行期 `Val`（编译—执行路径）。
fn bv_run(src : String) -> Val {
  VM::run(compile_ml(bv_te(src)), ml_env_empty())
}

// ===========================================================================
// (A) 字节码结构断言（R6.1 / R6.2）
// ===========================================================================

///|
/// 算术：`1 + 2` → 左先压、右后压、再运算（右在栈顶）。
test "compile_ml: '1 + 2' lowers to [PushInt 1, PushInt 2, Arith Add]" {
  assert_true(
    compile_ml(bv_te("1 + 2")).instrs == [PushInt(1), PushInt(2), Arith(Add)],
  )
}

///|
/// 比较：`1 < 2` → [PushInt 1, PushInt 2, Cmp Lt]。
test "compile_ml: '1 < 2' lowers to [PushInt 1, PushInt 2, Cmp Lt]" {
  assert_true(
    compile_ml(bv_te("1 < 2")).instrs == [PushInt(1), PushInt(2), Cmp(Lt)],
  )
}

///|
/// 逻辑：`true && false` → [PushBool true, PushBool false, Logic And]。
test "compile_ml: 'true && false' lowers to [PushBool, PushBool, Logic And]" {
  assert_true(
    compile_ml(bv_te("true && false")).instrs ==
    [PushBool(true), PushBool(false), Logic(And)],
  )
}

///|
/// 条件：`if true then 1 else 2` → 绝对索引回填。
///   下标：PushBool=0, JumpIfFalse=1, PushInt(1)=2, Jump=3, PushInt(2)=4；
///   故 else_start=4、end=5，得 [PushBool true, JumpIfFalse 4, PushInt 1,
///   Jump 5, PushInt 2]。
test "compile_ml: if-then-else backpatches absolute jump targets" {
  assert_true(
    compile_ml(bv_te("if true then 1 else 2")).instrs ==
    [PushBool(true), JumpIfFalse(4), PushInt(1), Jump(5), PushInt(2)],
  )
}

///|
/// 函数抽象：`fun x -> x + 1` → 单条 MkClosure，体字节码末尾追加 Ret。
/// （Bytecode / Instr 均 derive(Eq)，可整体比较嵌套结构。）
test "compile_ml: lambda builds MkClosure with Ret-terminated body" {
  let expected_body = Bytecode::{
    instrs: [LoadVar("x"), PushInt(1), Arith(Add), Ret],
  }
  assert_true(
    compile_ml(bv_te("fun x -> x + 1")).instrs ==
    [MkClosure("x", expected_body)],
  )
}

///|
/// 应用：`(fun x -> x) 5` → 先压闭包（深）、再压实参（顶），最后 Call。
test "compile_ml: application emits MkClosure then arg then Call" {
  let id_body = Bytecode::{ instrs: [LoadVar("x"), Ret] }
  assert_true(
    compile_ml(bv_te("(fun x -> x) 5")).instrs ==
    [MkClosure("x", id_body), PushInt(5), Call],
  )
}

// ===========================================================================
// (B) VM 执行断言（R6.3）—— 每例均与 eval_ml 交叉一致
// ===========================================================================

///|
/// 常量：整数与布尔字面量直接产出对应 `Val`。
test "VM::run: integer and boolean constants" {
  assert_true(bv_run("42") == VInt(42))
  assert_true(bv_run("42") == eval_ml(bv_te("42")))
  assert_true(bv_run("true") == VBool(true))
  assert_true(bv_run("true") == eval_ml(bv_te("true")))
}

///|
/// 算术：优先级、左结合与括号；除零定义为 0（与 ml_eval 一致，R5.4）。
test "VM::run: arithmetic with precedence, grouping and div-by-zero=0" {
  assert_true(bv_run("1 + 2 * 3") == VInt(7))
  assert_true(bv_run("1 + 2 * 3") == eval_ml(bv_te("1 + 2 * 3")))
  assert_true(bv_run("(10 - 4) / 2") == VInt(3))
  assert_true(bv_run("(10 - 4) / 2") == eval_ml(bv_te("(10 - 4) / 2")))
  assert_true(bv_run("5 / 0") == VInt(0))
  assert_true(bv_run("5 / 0") == eval_ml(bv_te("5 / 0")))
}

///|
/// 比较：`<=` 与 `==` 产出布尔。
test "VM::run: comparison operators" {
  assert_true(bv_run("3 <= 3") == VBool(true))
  assert_true(bv_run("3 <= 3") == eval_ml(bv_te("3 <= 3")))
  assert_true(bv_run("2 == 3") == VBool(false))
  assert_true(bv_run("2 == 3") == eval_ml(bv_te("2 == 3")))
}

///|
/// 逻辑：`&&` / `||` 产出布尔。
test "VM::run: logic operators" {
  assert_true(bv_run("true && false") == VBool(false))
  assert_true(bv_run("true && false") == eval_ml(bv_te("true && false")))
  assert_true(bv_run("false || true") == VBool(true))
  assert_true(bv_run("false || true") == eval_ml(bv_te("false || true")))
}

///|
/// if 跳转：条件真取 then 分支、条件假取 else 分支（绝对索引跳转正确执行）。
test "VM::run: if jumps select the right branch" {
  assert_true(bv_run("if 1 < 2 then 10 else 20") == VInt(10))
  assert_true(
    bv_run("if 1 < 2 then 10 else 20") ==
    eval_ml(bv_te("if 1 < 2 then 10 else 20")),
  )
  assert_true(bv_run("if 1 > 2 then 10 else 20") == VInt(20))
  assert_true(
    bv_run("if 1 > 2 then 10 else 20") ==
    eval_ml(bv_te("if 1 > 2 then 10 else 20")),
  )
}

///|
/// 闭包构造与调用：直接应用、let 绑定的闭包调用。
test "VM::run: closure construction and call" {
  assert_true(bv_run("(fun x -> x + 1) 41") == VInt(42))
  assert_true(
    bv_run("(fun x -> x + 1) 41") == eval_ml(bv_te("(fun x -> x + 1) 41")),
  )
  assert_true(bv_run("let f = fun x -> x * 2 in f 21") == VInt(42))
  assert_true(
    bv_run("let f = fun x -> x * 2 in f 21") ==
    eval_ml(bv_te("let f = fun x -> x * 2 in f 21")),
  )
}

///|
/// 高阶函数：`twice inc 10` —— 嵌套闭包捕获与多次调用。
test "VM::run: higher-order function (twice inc)" {
  let src = "let twice = fun f -> fun x -> f (f x) in let inc = fun n -> n + 1 in twice inc 10"
  assert_true(bv_run(src) == VInt(12))
  assert_true(bv_run(src) == eval_ml(bv_te(src)))
}

///|
/// 递归（MkRecClosure 自指绑定）：阶乘 `f 5 = 120`。
test "VM::run: recursion via MkRecClosure (factorial)" {
  let src = "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5"
  assert_true(bv_run(src) == VInt(120))
  assert_true(bv_run(src) == eval_ml(bv_te(src)))
}
