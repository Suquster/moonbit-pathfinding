// benches/mini_compiler_bench — MiniML 编译器各阶段在递增规模程序上的基准。
//
// 五类工作负载，逐阶段计时（R10.1）：
//   - bench_lex        : `lex_ml(src)`                                    词法
//   - bench_parse      : `parse_ml(tokens)`（预先词法化）                 语法
//   - bench_infer      : `infer(expr)`（预先解析）                        类型推断
//   - bench_eval       : `eval_ml(texpr)`（预先推断）                     树遍历求值
//   - bench_compile_vm : `VM::run(compile_ml(texpr), ml_env_empty())`     编译 + 栈式 VM
//
// 规模参数（R10.2 / R10.5）：
//   - arith chain  `1 + 1 + ... + 1`（n 个操作数，节点数递增）：16 / 64 / 256
//   - let nest     `let x0=1 in ... in x{n-1}`（n 个绑定，绑定数递增）：8 / 16 / 32
//   - app depth    `(fun x -> x + 1) (...(0))`（应用嵌套深度递增）：8 / 16 / 32
//
// native 后端运行前必须先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R10.4）。
// 工件 / 基线比较 / 回归报告由 scripts/benchmark_native*.ps1 产出（详见 moon.pkg 头注释）。
//
// _Requirements: 10.1, 10.2, 10.3, 10.4, 10.5_

///|
/// 构造长加法链 `1 + 1 + ... + 1`（n 个操作数，n >= 1）——节点数递增工作负载。
/// 闭合且良类型（结果类型 Int，值为 n）。
fn make_arith_chain(n : Int) -> String {
  let mut s = "1"
  let mut i = 1
  while i < n {
    s = s + " + 1"
    i = i + 1
  }
  s
}

///|
/// 构造嵌套 let 绑定 `let x0 = 1 in let x1 = x0 + 1 in ... in x{n-1}`
/// （n 个绑定，n >= 1）——绑定数递增工作负载。闭合且良类型（结果 Int，值为 n）。
fn make_let_nest(n : Int) -> String {
  let mut s = "let x0 = 1 in "
  let mut i = 1
  while i < n {
    s = s + "let x\{i} = x\{i - 1} + 1 in "
    i = i + 1
  }
  s + "x\{n - 1}"
}

///|
/// 构造深度应用 `(fun x -> x + 1) ((fun x -> x + 1) (...(0)))`
/// （应用嵌套深度 d，d >= 0）——应用 / 嵌套深度递增工作负载。
/// 闭合且良类型（结果 Int，值为 d）。
fn make_app_depth(d : Int) -> String {
  let mut s = "0"
  let mut i = 0
  while i < d {
    s = "(fun x -> x + 1) (\{s})"
    i = i + 1
  }
  s
}

///|
/// 将工作负载源串词法化为 token 数组；工作负载已知良构，失败即基准设置错误。
fn prepare_tokens(src : String) -> Array[@mc.MlToken] {
  match @mc.lex_ml(src) {
    Ok(toks) => toks
    Err(_) => abort("bench workload failed to lex: \{src}")
  }
}

///|
/// 将工作负载源串解析为 `Expr`。
fn prepare_expr(src : String) -> @mc.Expr {
  match @mc.parse_ml(prepare_tokens(src)) {
    Ok(e) => e
    Err(_) => abort("bench workload failed to parse: \{src}")
  }
}

///|
/// 将工作负载源串推断为带类型语法树 `TExpr`。
fn prepare_texpr(src : String) -> @mc.TExpr {
  match @mc.infer(prepare_expr(src)) {
    Ok((te, _)) => te
    Err(_) => abort("bench workload failed to infer: \{src}")
  }
}

///|
/// bench_lex（R10.1）：对各规模源串计时 `lex_ml`。
fn bench_lex(b : @bench.T, label : String, srcs : Array[String]) -> Unit {
  for src in srcs {
    let input = src
    b.bench(name="lex_\{label}", fn() { b.keep(@mc.lex_ml(input)) })
  }
}

///|
/// bench_parse（R10.1）：预先词法化，仅对 `parse_ml` 计时。
fn bench_parse(b : @bench.T, label : String, srcs : Array[String]) -> Unit {
  for src in srcs {
    let toks = prepare_tokens(src)
    b.bench(name="parse_\{label}", fn() { b.keep(@mc.parse_ml(toks)) })
  }
}

///|
/// bench_infer（R10.1）：预先解析，仅对 `infer` 计时。
fn bench_infer(b : @bench.T, label : String, srcs : Array[String]) -> Unit {
  for src in srcs {
    let expr = prepare_expr(src)
    b.bench(name="infer_\{label}", fn() { b.keep(@mc.infer(expr)) })
  }
}

///|
/// bench_eval（R10.1）：预先推断，仅对树遍历求值 `eval_ml` 计时。
fn bench_eval(b : @bench.T, label : String, srcs : Array[String]) -> Unit {
  for src in srcs {
    let te = prepare_texpr(src)
    b.bench(name="eval_\{label}", fn() { b.keep(@mc.eval_ml(te)) })
  }
}

///|
/// bench_compile_vm（R10.1）：预先推断，对编译 + 栈式 VM 执行计时。
fn bench_compile_vm(b : @bench.T, label : String, srcs : Array[String]) -> Unit {
  for src in srcs {
    let te = prepare_texpr(src)
    b.bench(name="compile_vm_\{label}", fn() {
      b.keep(@mc.VM::run(@mc.compile_ml(te), @mc.ml_env_empty()))
    })
  }
}

///|
/// Smoke guard：代表性规模下，工作负载端到端 lex→parse→infer→eval 与
/// compile+VM 均成功，且两路求值结果一致（保证基准工作负载有效）。
test "smoke: mini_compiler bench workloads run end-to-end" {
  let srcs = [make_arith_chain(16), make_let_nest(8), make_app_depth(8)]
  // 每个工作负载的期望整数结果：链长 16 -> 16，绑定数 8 -> 8，应用深度 8 -> 8。
  let expected = [16, 8, 8]
  let mut idx = 0
  for src in srcs {
    // lex
    let toks = match @mc.lex_ml(src) {
      Ok(t) => t
      Err(_) => {
        fail("lex failed: \{src}")
        return
      }
    }
    // parse
    let expr = match @mc.parse_ml(toks) {
      Ok(e) => e
      Err(_) => {
        fail("parse failed: \{src}")
        return
      }
    }
    // infer
    let te = match @mc.infer(expr) {
      Ok((te, _)) => te
      Err(_) => {
        fail("infer failed: \{src}")
        return
      }
    }
    // eval（树遍历） 与 compile+VM 两路求值
    let interp = @mc.eval_ml(te)
    let vm = @mc.VM::run(@mc.compile_ml(te), @mc.ml_env_empty())
    // 两路结果一致
    assert_true(interp == vm)
    // 与期望整数值一致
    assert_true(interp == @mc.Val::VInt(expected[idx]))
    idx = idx + 1
  }
}

///|
/// Native benchmark：五类阶段工作负载在递增规模程序上的计时（R10.1）。
test "bench: mini_compiler stages over increasing sizes" (b : @bench.T) {
  // 节点数递增：长加法链。
  let chain_sizes = [16, 64, 256]
  // 绑定数 / 应用深度递增。
  let nest_sizes = [8, 16, 32]
  let chain_srcs = chain_sizes.map(make_arith_chain)
  let let_srcs = nest_sizes.map(make_let_nest)
  let app_srcs = nest_sizes.map(make_app_depth)

  // 每个阶段族分别在三类规模工作负载上注册基准，名称编码阶段 + 规模类别 + 规模值。
  for
    entry in [
      ("chain", chain_sizes, chain_srcs),
      ("letnest", nest_sizes, let_srcs),
      ("appdepth", nest_sizes, app_srcs),
    ] {
    let (kind, sizes, srcs) = entry
    let mut i = 0
    for src in srcs {
      let label = "\{kind}_\{sizes[i]}"
      bench_lex(b, label, [src])
      bench_parse(b, label, [src])
      bench_infer(b, label, [src])
      bench_eval(b, label, [src])
      bench_compile_vm(b, label, [src])
      i = i + 1
    }
  }
}
