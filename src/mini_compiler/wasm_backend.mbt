// wasm_backend.mbt —— 真·WebAssembly 产物（T1.1）：把良类型 MiniML `TExpr`
// 编译为**合法、可被 wat2wasm 汇编并被真实 wasm 运行时执行**的完整 wat 模块，
// 端到端结果与树遍历解释器一致。
//
// 区别于 `text_backend.mbt` 的 `emit_wat`（DISPLAY-ONLY 结构展示）：本后端做
// 真实 lowering——核心 wasm 无一等闭包，故：
// * **lambda 提升**：每个 `TELam` 提升为模块级函数 `(param $env i32)(result i32)`，
//   经 funcref 表 `call_indirect` 调用；
// * **线性内存堆 + bump 分配**：环境为不可变链表结点 `[val:i32, next:i32]`，
//   闭包为 `[funcidx:i32, envptr:i32, isrec:i32]`，元组为 `[len:i32, elems...]`；
// * **词法寻址**：变量在编译期解析为 de Bruijn 下标，运行期沿 env 链走 `next`
//   取 `val`——环境布局完全静态可知；
// * **递归闭包**：`isrec` 标记；`$apply` 调用时把闭包自身先于实参 cons 进环境，
//   与 `eval_ml` 的按名自指语义一致；
// * **数值语义**：i32 环绕算术天然对齐；`$div` 定义除零 = 0、`INT_MIN / -1`
//   环绕（规避 `i32.div_s` 陷阱），与 JS 后端 / 解释器一致。
//
// 产物验证路径（离线证据，见 docs/evidence）：`compile_ml_to_wat` → `wat2wasm`
// → Node `WebAssembly.instantiate` 执行 `main()`，按静态结果类型形状
// （`ty_shape`）渲染，与 `js_show_val(eval_ml(..))` 逐字符对比。

///|
/// wat 模块级编译状态：提升出的函数体集合（下标即 funcref 表索引）。
priv struct WatCtx {
  funcs : Array[String]
}

///|
/// 单函数编译状态：临时局部变量计数（用于 let / 元组的中间指针）。
priv struct WatFnCtx {
  mut ntmp : Int
}

///|
/// 申请一个新的 i32 临时局部，返回其名字（`$t0`、`$t1`…）。
fn WatFnCtx::fresh(self : WatFnCtx) -> String {
  let name = "$t" + self.ntmp.to_string()
  self.ntmp = self.ntmp + 1
  name
}

///|
/// 在作用域名表（最内层在前）中解析变量的 de Bruijn 下标。
fn wat_lookup(scope : Array[String], x : String) -> Int {
  for i in 0..<scope.length() {
    if scope[i] == x {
      return i
    }
  }
  // 良类型程序变量必在作用域（scope_check 保证）；回退 0 保持全函数。
  0
}

///|
/// 生成「沿 env 链走 `depth` 次 next 后取 val」的折叠表达式。
fn wat_var(env_expr : String, depth : Int) -> String {
  let mut e = env_expr
  for _i in 0..<depth {
    e = "(i32.load offset=4 " + e + ")"
  }
  "(i32.load " + e + ")"
}

///|
/// 把 `TExpr` 编译为求值后在栈顶留下一个 i32 的折叠 wat 表达式。
///
/// * `scope`：当前词法作用域名表（最内层在前），与运行期 env 链逐位对应。
/// * `env`：承载当前环境链表头指针的折叠表达式（局部变量读取）。
fn wat_expr(
  te : TExpr,
  scope : Array[String],
  env : String,
  ctx : WatCtx,
  fctx : WatFnCtx,
) -> String {
  match te {
    TEInt(n, _, _) => "(i32.const " + n.to_string() + ")"
    TEBool(b, _, _) => if b { "(i32.const 1)" } else { "(i32.const 0)" }
    TEVar(x, _, _) => wat_var(env, wat_lookup(scope, x))
    TEArith(op, l, r, _, _) => {
      let a = wat_expr(l, scope, env, ctx, fctx)
      let b = wat_expr(r, scope, env, ctx, fctx)
      match op {
        Add => "(i32.add " + a + " " + b + ")"
        Sub => "(i32.sub " + a + " " + b + ")"
        Mul => "(i32.mul " + a + " " + b + ")"
        Div => "(call $div " + a + " " + b + ")"
      }
    }
    TECmp(op, l, r, _, _) => {
      let a = wat_expr(l, scope, env, ctx, fctx)
      let b = wat_expr(r, scope, env, ctx, fctx)
      let ins = match op {
        Lt => "i32.lt_s"
        Le => "i32.le_s"
        Gt => "i32.gt_s"
        Ge => "i32.ge_s"
        Eq_ => "i32.eq"
        Ne => "i32.ne"
      }
      "(" + ins + " " + a + " " + b + ")"
    }
    TELogic(op, l, r, _, _) => {
      let a = wat_expr(l, scope, env, ctx, fctx)
      let b = wat_expr(r, scope, env, ctx, fctx)
      let ins = match op {
        And => "i32.and"
        Or => "i32.or"
      }
      "(" + ins + " " + a + " " + b + ")"
    }
    TEIf(c, t, e, _, _) =>
      "(if (result i32) " +
      wat_expr(c, scope, env, ctx, fctx) +
      " (then " +
      wat_expr(t, scope, env, ctx, fctx) +
      ") (else " +
      wat_expr(e, scope, env, ctx, fctx) +
      "))"
    TELam(x, body, _, _) => {
      let fidx = wat_lift_lambda(x, body, scope, ctx, is_rec=false)
      "(call $mkclosure (i32.const " +
      fidx.to_string() +
      ") " +
      env +
      " (i32.const 0))"
    }
    TEApp(f, a, _, _) =>
      "(call $apply " +
      wat_expr(f, scope, env, ctx, fctx) +
      " " +
      wat_expr(a, scope, env, ctx, fctx) +
      ")"
    TELet(x, e1, e2, _, _) => {
      let v = wat_expr(e1, scope, env, ctx, fctx)
      let t = fctx.fresh()
      let scope2 = [x] + scope
      let body = wat_expr(e2, scope2, "(local.get " + t + ")", ctx, fctx)
      "(block (result i32) (local.set " +
      t +
      " (call $cons " +
      v +
      " " +
      env +
      ")) " +
      body +
      ")"
    }
    TELetRec(f, e1, e2, _, _) =>
      match e1 {
        TELam(px, pbody, _, _) => {
          // 体函数作用域 = 形参 :: 自身名 :: 创建处作用域（$apply 依 isrec
          // 依次 cons 自身与实参，运行期布局与此逐位对应）。
          let fidx = wat_lift_lambda(px, pbody, [f] + scope, ctx, is_rec=true)
          let clos = "(call $mkclosure (i32.const " +
            fidx.to_string() +
            ") " +
            env +
            " (i32.const 1))"
          let t = fctx.fresh()
          let scope2 = [f] + scope
          let body = wat_expr(e2, scope2, "(local.get " + t + ")", ctx, fctx)
          "(block (result i32) (local.set " +
          t +
          " (call $cons " +
          clos +
          " " +
          env +
          ")) " +
          body +
          ")"
        }
        // 非函数绑定退化为普通 let（与 `bind_rec` 一致）。
        _ =>
          wat_expr(
            TELet(f, e1, e2, TyInt, Span::{ line: 0, col: 0 }),
            scope,
            env,
            ctx,
            fctx,
          )
      }
    TETuple(items, _, _) => {
      let t = fctx.fresh()
      let sb = StringBuilder::new()
      sb.write_string("(block (result i32) (local.set " + t)
      sb.write_string(
        " (call $alloc (i32.const " +
        ((items.length() + 1) * 4).to_string() +
        ")))",
      )
      sb.write_string(
        " (i32.store (local.get " +
        t +
        ") (i32.const " +
        items.length().to_string() +
        "))",
      )
      for i in 0..<items.length() {
        sb.write_string(
          " (i32.store offset=" +
          ((i + 1) * 4).to_string() +
          " (local.get " +
          t +
          ") " +
          wat_expr(items[i], scope, env, ctx, fctx) +
          ")",
        )
      }
      sb.write_string(" (local.get " + t + "))")
      sb.to_string()
    }
  }
}

///|
/// 把 lambda 体提升为模块级函数，返回其 funcref 表索引。
///
/// 提升出的函数形如 `(func $lN (param $env i32) (result i32) ...)`：调用方
/// （`$apply`）已把实参（及递归闭包自身）cons 进 `$env`，故体作用域名表为
/// `param ::（自身名 ::）创建处作用域`。
fn wat_lift_lambda(
  param : String,
  body : TExpr,
  outer_scope : Array[String],
  ctx : WatCtx,
  is_rec~ : Bool,
) -> Int {
  let fidx = ctx.funcs.length()
  // 先占位，保证嵌套 lambda 的索引分配次序稳定（外层先于内层）。
  ctx.funcs.push("")
  let scope = [param] + outer_scope
  ignore(is_rec)
  let fctx = WatFnCtx::{ ntmp: 0 }
  let code = wat_expr(body, scope, "(local.get $env)", ctx, fctx)
  let sb = StringBuilder::new()
  sb.write_string(
    "  (func $l" +
    fidx.to_string() +
    " (type $fn) (param $env i32) (result i32)",
  )
  for i in 0..<fctx.ntmp {
    sb.write_string(" (local $t" + i.to_string() + " i32)")
  }
  sb.write_string("\n    " + code + ")\n")
  ctx.funcs[fidx] = sb.to_string()
  fidx
}

///|
/// wat 运行时前奏：bump 分配器、环境 cons、闭包构造与 `$apply`、对齐语义的
/// `$div`。内存 16 页（1 MiB），堆自地址 8 起（0 保留为「空环境」哨兵）。
let wat_runtime : String =
  #|  (type $fn (func (param i32) (result i32)))
  #|  (memory (export "memory") 16)
  #|  (global $hp (mut i32) (i32.const 8))
  #|  (func $alloc (param $n i32) (result i32)
  #|    (local $p i32)
  #|    (local.set $p (global.get $hp))
  #|    (global.set $hp (i32.add (global.get $hp) (local.get $n)))
  #|    (local.get $p))
  #|  (func $cons (param $v i32) (param $next i32) (result i32)
  #|    (local $p i32)
  #|    (local.set $p (call $alloc (i32.const 8)))
  #|    (i32.store (local.get $p) (local.get $v))
  #|    (i32.store offset=4 (local.get $p) (local.get $next))
  #|    (local.get $p))
  #|  (func $mkclosure (param $f i32) (param $env i32) (param $r i32) (result i32)
  #|    (local $p i32)
  #|    (local.set $p (call $alloc (i32.const 12)))
  #|    (i32.store (local.get $p) (local.get $f))
  #|    (i32.store offset=4 (local.get $p) (local.get $env))
  #|    (i32.store offset=8 (local.get $p) (local.get $r))
  #|    (local.get $p))
  #|  (func $apply (param $c i32) (param $a i32) (result i32)
  #|    (local $env i32)
  #|    (local.set $env (i32.load offset=4 (local.get $c)))
  #|    (if (i32.load offset=8 (local.get $c))
  #|      (then (local.set $env (call $cons (local.get $c) (local.get $env)))))
  #|    (local.set $env (call $cons (local.get $a) (local.get $env)))
  #|    (call_indirect (type $fn) (local.get $env) (i32.load (local.get $c))))
  #|  (func $div (param $a i32) (param $b i32) (result i32)
  #|    (if (result i32) (i32.eqz (local.get $b))
  #|      (then (i32.const 0))
  #|      (else (if (result i32) (i32.eq (local.get $b) (i32.const -1))
  #|        (then (i32.sub (i32.const 0) (local.get $a)))
  #|        (else (i32.div_s (local.get $a) (local.get $b)))))))
  #|

///|
/// 把良类型 `TExpr` 编译为完整 wat 模块（合法、可被 wat2wasm 汇编）。
/// 导出 `main : () -> i32` 与线性内存 `memory`（供宿主按类型形状读取元组）。
pub fn emit_wat_module(te : TExpr) -> String {
  let ctx = WatCtx::{ funcs: [] }
  let fctx = WatFnCtx::{ ntmp: 0 }
  let code = wat_expr(te, [], "(i32.const 0)", ctx, fctx)
  let sb = StringBuilder::new()
  sb.write_string("(module\n")
  sb.write_string(wat_runtime)
  for f in ctx.funcs {
    sb.write_string(f)
  }
  let n = ctx.funcs.length()
  sb.write_string("  (table " + n.to_string() + " funcref)\n")
  if n > 0 {
    sb.write_string("  (elem (i32.const 0)")
    for i in 0..<n {
      sb.write_string(" $l" + i.to_string())
    }
    sb.write_string(")\n")
  }
  sb.write_string("  (func $main (export \"main\") (result i32)")
  for i in 0..<fctx.ntmp {
    sb.write_string(" (local $t" + i.to_string() + " i32)")
  }
  sb.write_string("\n    " + code + ")\n)\n")
  sb.to_string()
}

///|
/// 静态结果类型的形状描述（JSON），供宿主渲染 wasm 返回值：
/// `"int"` / `"bool"` / `"fun"`（含类型变量的多态值按闭包渲染）/
/// `["tuple", shape...]`。与 `js_show_val` 的渲染约定一致。
pub fn ty_shape(ty : Ty) -> String {
  match ty {
    TyInt => "\"int\""
    TyBool => "\"bool\""
    TyFun(_, _) => "\"fun\""
    TyVar(_) => "\"fun\""
    TyTuple(items) => {
      let sb = StringBuilder::new()
      sb.write_string("[\"tuple\"")
      for t in items {
        sb.write_string(", " + ty_shape(t))
      }
      sb.write_string("]")
      sb.to_string()
    }
  }
}

///|
/// 端到端便捷入口：MiniML 源码 → (wat 模块文本, 结果类型形状 JSON)。
pub fn compile_ml_to_wat(src : String) -> Result[(String, String), Diagnostic] {
  match lex_ml(src) {
    Err(d) => Err(d)
    Ok(toks) =>
      match parse_ml(toks) {
        Err(d) => Err(d)
        Ok(e) =>
          match infer(e) {
            Err(d) => Err(d)
            Ok((te, ty)) => Ok((emit_wat_module(te), ty_shape(ty)))
          }
      }
  }
}
