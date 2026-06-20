// peephole_tco_smoke_test.mbt —— 任务 10.2 的极少量内联烟雾测试（系统化的属性测试
// 见任务 10.3）。验证三件事，对齐 design.md AC2 / AC3 / AC4（R9.2 / R9.3 / R9.4）：
//   (1) peephole_opt：对含「可删冗余」的字节码，VM::run 结果不变且指令数严格减少；
//       对一般程序结果不变且指令数不增。
//   (2) tco_opt + run_tco：尾递归 countdown 在不同深度 N 下最大活动帧深为与 N 无关
//       的小常数（帧数不随 N 线性增长）。
//   (3) run_tco(tco_opt(bc)) 与既有 VM::run(bc) 结果逐位相等（优化路径等价）。
//
// 旁路新增 API（本文件只调用、不修改）：peephole_opt / tco_opt / run_tco /
// run_tco_with_depth（peephole.mbt / tco.mbt）；既有 compile_ml / VM::run /
// ml_env_empty / lex_ml / parse_ml / infer（只读复用）。

// ---------------------------------------------------------------------------
// 夹具
// ---------------------------------------------------------------------------

///|
/// 源串 → 词法 → 语法 → 推断，得良类型 `TExpr`（夹具均为合法、良类型源串）。
fn pt_te(src : String) -> TExpr {
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

// ---------------------------------------------------------------------------
// (1) peephole：含冗余的手工字节码 —— 结果不变、指令数严格减少
// ---------------------------------------------------------------------------

///|
/// 手工构造含「不可达指令 + 可消除跳转」的字节码：
///   0: PushInt(5)
///   1: Jump(3)        // 跳过下标 2
///   2: PushInt(999)   // 不可达
///   3: PushInt(7)
///   4: Arith(Add)
/// 求值：5 与 7 相加 = 12。窥孔优化应消除不可达的 `PushInt(999)`，并在重定位后把
/// `Jump` 规整为「跳到下一条」继而删除，最终降至 `[PushInt 5, PushInt 7, Arith Add]`
/// （3 条），结果仍为 12。
test "peephole_opt: 消除不可达与冗余跳转，结果不变且指令数严格减少" {
  let original = Bytecode::{
    instrs: [PushInt(5), Jump(3), PushInt(999), PushInt(7), Arith(Add)],
  }
  let optimized = peephole_opt(original)
  // 结果不变（AC4）。
  assert_true(
    VM::run(optimized, ml_env_empty()) == VM::run(original, ml_env_empty()),
  )
  assert_true(VM::run(optimized, ml_env_empty()) == VInt(12))
  // 指令数严格减少（AC2，本例可证可优化）。
  assert_true(optimized.instrs.length() < original.instrs.length())
  assert_true(optimized.instrs == [PushInt(5), PushInt(7), Arith(Add)])
}

///|
/// 对一组真实程序：peephole_opt 后 VM::run 结果不变且指令数不增（AC2 / AC4）。
test "peephole_opt: 真实程序结果不变且指令数不增" {
  let srcs = [
    "1 + 2 * 3", "if 1 < 2 then 10 else 20", "(fun x -> x + 1) 41", "let f = fun x -> x * 2 in f 21",
    "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5",
  ]
  for src in srcs {
    let bc = compile_ml(pt_te(src))
    let opt = peephole_opt(bc)
    assert_true(VM::run(opt, ml_env_empty()) == VM::run(bc, ml_env_empty()))
    assert_true(opt.instrs.length() <= bc.instrs.length())
  }
}

// ---------------------------------------------------------------------------
// (2) TCO：尾递归 countdown 帧深与 N 无关
// ---------------------------------------------------------------------------

///|
/// 尾递归 countdown：`let rec f = fun n -> if n <= 0 then 0 else f (n - 1) in f N`
/// 的尾调用 `f (n - 1)` 处于尾位置。经 tco_opt 规范化后用 run_tco 执行，对不同 N
/// 测得的**最大活动帧深应相等**（与 N 无关的小常数），佐证帧数不随 N 线性增长（AC3）。
test "run_tco: 尾递归帧深不随 N 线性增长" {
  fn countdown_src(n : Int) -> String {
    "let rec f = fun n -> if n <= 0 then 0 else f (n - 1) in f " + n.to_string()
  }

  let bc_small = tco_opt(compile_ml(pt_te(countdown_src(20))))
  let bc_large = tco_opt(compile_ml(pt_te(countdown_src(200))))
  let (r_small, d_small) = run_tco_with_depth(bc_small, ml_env_empty())
  let (r_large, d_large) = run_tco_with_depth(bc_large, ml_env_empty())
  // 结果均为 0。
  assert_true(r_small == VInt(0))
  assert_true(r_large == VInt(0))
  // 帧深与 N 无关：N=20 与 N=200 测得相同最大帧深。
  assert_true(d_small == d_large)
  // 进一步确认帧深为小常数（远小于 N=200）。
  assert_true(d_large < 20)
}

// ---------------------------------------------------------------------------
// (3) 优化路径等价：run_tco(tco_opt(bc)) == VM::run(bc)
// ---------------------------------------------------------------------------

///|
/// 对一组程序（含尾递归 / 非尾递归 / 高阶），run_tco(tco_opt(compile_ml)) 与既有
/// VM::run(compile_ml) 结果逐位相等（AC4 / R9.4）。
test "run_tco + tco_opt: 与既有 VM::run 结果等价" {
  let srcs = [
    "1 + 2 * 3", "if 1 > 2 then 10 else 20", "(fun x -> x + 1) 41", "let twice = fun f -> fun x -> f (f x) in let inc = fun n -> n + 1 in twice inc 10",
    "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5", "let rec g = fun n -> if n <= 0 then 7 else g (n - 1) in g 50",
  ]
  for src in srcs {
    let bc = compile_ml(pt_te(src))
    let tco_result = run_tco(tco_opt(bc), ml_env_empty())
    let vm_result = VM::run(bc, ml_env_empty())
    assert_true(tco_result == vm_result)
  }
}
