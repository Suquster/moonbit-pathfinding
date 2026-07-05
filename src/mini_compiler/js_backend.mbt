// js_backend.mbt —— 真·JS 产物（T1.2）：把良类型 MiniML `TExpr` 编译为 Node
// 可直接执行的 JavaScript 程序，端到端结果与树遍历解释器一致。
//
// 语义对齐要点（与 `eval_ml` 逐条对标）：
// * Int 为 32 位环绕算术：`+`/`-` 用 `|0` 收窄，`*` 用 `Math.imul`；
//   除法截断且**除零 = 0**、`INT_MIN / -1` 按环绕收窄（`(a/b)|0`）。
// * 词法作用域闭包 / `let rec` 直接映射到 JS 闭包与 `const` 自指绑定。
// * 元组映射为 JS 数组。
// * 标识符统一加前缀 `v_`，避免与 JS 保留字冲突。
//
// 产物形态：`emit_js_program` 产出完整 Node 程序（表达式 + 规范化打印），
// 打印格式与 `js_show_val`（对 `Val` 的规范渲染）逐字符一致，供离线差分验证：
// `node <(emit_js_program src)` 输出 == `js_show_val(eval_ml(infer(parse src)))`。

///|
/// 把 MiniML 标识符转义为 JS 安全标识符（统一前缀，规避保留字）。
fn js_ident(x : String) -> String {
  "v_" + x
}

///|
/// 把良类型 `TExpr` 编译为单个 JS 表达式（纯表达式风格，`let` 经
/// 立即调用箭头函数实现，`let rec` 用块内 `const` 自指绑定）。
///
/// 区别于 `text_backend.mbt` 的 `emit_js`（DISPLAY-ONLY 展示用）：本函数产出
/// **语义保持**的可执行 JS（32 位环绕、除零=0），与 `eval_ml` 端到端一致。
pub fn emit_js_expr(te : TExpr) -> String {
  match te {
    TEInt(n, _, _) =>
      if n < 0 {
        "(" + n.to_string() + ")"
      } else {
        n.to_string()
      }
    TEBool(b, _, _) => if b { "true" } else { "false" }
    TEVar(x, _, _) => js_ident(x)
    TEArith(op, l, r, _, _) => {
      let a = emit_js_expr(l)
      let b = emit_js_expr(r)
      match op {
        Add => "((" + a + " + " + b + ") | 0)"
        Sub => "((" + a + " - " + b + ") | 0)"
        Mul => "Math.imul(" + a + ", " + b + ")"
        Div => "__div(" + a + ", " + b + ")"
      }
    }
    TECmp(op, l, r, _, _) => {
      let a = emit_js_expr(l)
      let b = emit_js_expr(r)
      let sym = match op {
        Lt => "<"
        Le => "<="
        Gt => ">"
        Ge => ">="
        Eq_ => "==="
        Ne => "!=="
      }
      "(" + a + " " + sym + " " + b + ")"
    }
    TELogic(op, l, r, _, _) => {
      let a = emit_js_expr(l)
      let b = emit_js_expr(r)
      let sym = match op {
        And => "&&"
        Or => "||"
      }
      "(" + a + " " + sym + " " + b + ")"
    }
    TEIf(c, t, e, _, _) =>
      "(" +
      emit_js_expr(c) +
      " ? " +
      emit_js_expr(t) +
      " : " +
      emit_js_expr(e) +
      ")"
    TELam(x, body, _, _) =>
      "((" + js_ident(x) + ") => " + emit_js_expr(body) + ")"
    TEApp(f, a, _, _) => "(" + emit_js_expr(f) + ")(" + emit_js_expr(a) + ")"
    TELet(x, e1, e2, _, _) =>
      "((" +
      js_ident(x) +
      ") => " +
      emit_js_expr(e2) +
      ")(" +
      emit_js_expr(e1) +
      ")"
    TELetRec(f, e1, e2, _, _) =>
      "(() => { const " +
      js_ident(f) +
      " = " +
      emit_js_expr(e1) +
      "; return " +
      emit_js_expr(e2) +
      "; })()"
    TETuple(items, _, _) => {
      let sb = StringBuilder::new()
      sb.write_string("[")
      for i in 0..<items.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        sb.write_string(emit_js_expr(items[i]))
      }
      sb.write_string("]")
      sb.to_string()
    }
  }
}

///|
/// JS 运行时前奏：与 `eval_ml` 对齐的截断除法（除零 = 0、环绕收窄）与
/// 规范化打印（整数十进制、布尔 true/false、闭包 `<closure>`、元组
/// `(a, b, ...)`，与 `js_show_val` 逐字符一致）。
let js_prelude : String =
  #|"use strict";
  #|const __div = (a, b) => (b === 0 ? 0 : ((a / b) | 0));
  #|const __show = (v) =>
  #|  typeof v === "function"
  #|    ? "<closure>"
  #|    : Array.isArray(v)
  #|      ? "(" + v.map(__show).join(", ") + ")"
  #|      : String(v);
  #|

///|
/// 产出完整 Node 程序：前奏 + 表达式求值 + 规范化打印到 stdout。
pub fn emit_js_program(te : TExpr) -> String {
  js_prelude + "console.log(__show(" + emit_js_expr(te) + "));\n"
}

///|
/// 对 `Val` 的规范渲染，与 JS 侧 `__show` 逐字符一致，供差分验证参照。
pub fn js_show_val(v : Val) -> String {
  match v {
    VInt(n) => n.to_string()
    VBool(b) => if b { "true" } else { "false" }
    VClosure(_, _, _) => "<closure>"
    VTuple(items) => {
      let sb = StringBuilder::new()
      sb.write_string("(")
      for i in 0..<items.length() {
        if i > 0 {
          sb.write_string(", ")
        }
        sb.write_string(js_show_val(items[i]))
      }
      sb.write_string(")")
      sb.to_string()
    }
  }
}

///|
/// 端到端便捷入口：MiniML 源码 → JS 程序文本。解析/推断失败返回 `Err(诊断)`。
pub fn compile_ml_to_js(src : String) -> Result[String, Diagnostic] {
  match lex_ml(src) {
    Err(d) => Err(d)
    Ok(toks) =>
      match parse_ml(toks) {
        Err(d) => Err(d)
        Ok(e) =>
          match infer(e) {
            Err(d) => Err(d)
            Ok((te, _)) => Ok(emit_js_program(te))
          }
      }
  }
}
