// text_backend.mbt —— 额外文本后端（design.md §「组件与接口 → 10. 额外文本
// 后端」，覆盖可选特性 R6.4）。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增。提供两个把带类型标注语法树
// `TExpr` 渲染为文本源串的函数：`emit_js`（JavaScript 源串）与 `emit_wat`
// （WebAssembly 文本格式 / WAT S-表达式串）。
//
// ===========================================================================
// 重要边界声明（DISPLAY-ONLY，R6.4 / requirements.md §6 验收标准 4）
// ===========================================================================
//   这两个渲染器的输出**仅供展示**（illustrative），用于直观呈现一棵 MiniML
//   语法树在「类 JS 表达式」与「类 WAT S-表达式」两种目标记法下的近似形态。
//   它们**不保证可被外部工具链消费**：
//     * 既不生成原生可执行文件，也不汇编 / 链接 / 绑定具体 ISA；
//     * `emit_wat` 产出的是反映语法树**结构**的可读 S-表达式，而非一份合法、
//       可被 `wat2wasm` 等工具消费的完整 wasm 模块（核心 wasm 无一等闭包，故
//       `lambda` / 应用 / 闭包 / 元组以**可读占位符**呈现）；
//     * `emit_js` 产出的是**结构对应**的 JS 表达式串，力求形态合理（plausible），
//       但不对其在任意 JS 引擎下的可执行性 / 语义等价性作任何保证。
//   语义保持的正式保证由「字节码编译 + VM 执行」路径（bytecode.mbt / vm.mbt）
//   与编译—执行等价属性（Property 10）承载；本文本后端独立于该正确性链条。
//
//   两个渲染器对 `TExpr` 的**全部**构造子都有定义（total），不会在任何良构输入
//   上卡住。

// ---------------------------------------------------------------------------
// JavaScript 文本后端（emit_js，R6.4）
// ---------------------------------------------------------------------------

///|
/// 既有冻结 `BinOp`（Add/Sub/Mul/Div）→ JS 算符符号。
fn js_binop_sym(op : BinOp) -> String {
  match op {
    Add => "+"
    Sub => "-"
    Mul => "*"
    Div => "/"
  }
}

///|
/// `CmpOp` → JS 比较算符符号（相等 / 不等采用严格比较 `===` / `!==`）。
fn js_cmpop_sym(op : CmpOp) -> String {
  match op {
    Lt => "<"
    Le => "<="
    Gt => ">"
    Ge => ">="
    Eq_ => "==="
    Ne => "!=="
  }
}

///|
/// `LogicOp` → JS 逻辑算符符号。
fn js_logicop_sym(op : LogicOp) -> String {
  match op {
    And => "&&"
    Or => "||"
  }
}

///|
/// 把 `TExpr` 渲染为 JavaScript 表达式串（仅供展示，R6.4）。
///
/// 渲染方案（每个节点都完全括号化以消除优先级歧义）：
/// - `TEInt(n)` → `n`；`TEBool(b)` → `true` / `false`；`TEVar(x)` → `x`。
/// - `TEArith(op,l,r)` → `(l op r)`。除法直接渲染为 `(l / r)`：JS 的 `/` 为浮点
///   除且不反映 MiniML「整数除、除零=0」语义，故仅作展示（见文件头边界声明）。
/// - `TECmp(op,l,r)` → `(l op r)`（相等用 `===` / `!==`）。
/// - `TELogic(op,l,r)` → `(l op r)`。
/// - `TEIf(c,a,b)` → `(c ? a : b)`（三元表达式）。
/// - `TELam(x,body)` → `((x) => body)`（箭头函数）。
/// - `TEApp(f,a)` → `f(a)`。
/// - `TELet(x,e1,e2)` → `((x) => e2)(e1)`（IIFE 降低 let）。
/// - `TELetRec(f,e1,e2)` → `((f) => e2)(function f(...){...})`：把递归绑定渲染为
///   命名函数表达式以便体内引用自身（展示用，不保证可执行）。
/// - `TETuple(items)` → `[i0, i1, ...]`（JS 数组表示元组）。
pub fn emit_js(te : TExpr) -> String {
  match te {
    TEInt(n, _, _) => n.to_string()
    TEBool(b, _, _) => if b { "true" } else { "false" }
    TEVar(x, _, _) => x
    TEArith(op, l, r, _, _) =>
      "(" + emit_js(l) + " " + js_binop_sym(op) + " " + emit_js(r) + ")"
    TECmp(op, l, r, _, _) =>
      "(" + emit_js(l) + " " + js_cmpop_sym(op) + " " + emit_js(r) + ")"
    TELogic(op, l, r, _, _) =>
      "(" + emit_js(l) + " " + js_logicop_sym(op) + " " + emit_js(r) + ")"
    TEIf(c, a, b, _, _) =>
      "(" + emit_js(c) + " ? " + emit_js(a) + " : " + emit_js(b) + ")"
    TELam(x, body, _, _) => "((" + x + ") => " + emit_js(body) + ")"
    TEApp(f, a, _, _) => emit_js(f) + "(" + emit_js(a) + ")"
    TELet(x, e1, e2, _, _) =>
      "((" + x + ") => " + emit_js(e2) + ")(" + emit_js(e1) + ")"
    TELetRec(f, e1, e2, _, _) =>
      // 命名函数表达式承载自指递归（展示用）。若 e1 为 lambda，则渲染为
      // `function f(x){ return <body> }`；否则退化为普通值绑定。
      "((" + f + ") => " + emit_js(e2) + ")(" + js_rec_binding(f, e1) + ")"
    TETuple(items, _, _) => {
      let parts = items.map(emit_js)
      "[" + parts.join(", ") + "]"
    }
  }
}

///|
/// 渲染 `let rec f = e1` 中的绑定体为 JS：当 `e1` 为字面 lambda 时产出命名函数
/// 表达式 `function f(x){ return <body> }`（使体内可引用 `f` 实现递归，展示用）；
/// 否则退化为对 `e1` 的普通渲染。
fn js_rec_binding(f : String, e1 : TExpr) -> String {
  match e1 {
    TELam(x, body, _, _) =>
      "function " + f + "(" + x + ") { return " + emit_js(body) + "; }"
    _ => emit_js(e1)
  }
}

// ---------------------------------------------------------------------------
// WebAssembly 文本后端（emit_wat，R6.4）
// ---------------------------------------------------------------------------

///|
/// 既有冻结 `BinOp` → WAT i32 算术指令助记符（除法用有符号 `i32.div_s`）。
fn wat_arith_op(op : BinOp) -> String {
  match op {
    Add => "i32.add"
    Sub => "i32.sub"
    Mul => "i32.mul"
    Div => "i32.div_s"
  }
}

///|
/// `CmpOp` → WAT i32 比较指令助记符（有符号比较）。
fn wat_cmp_op(op : CmpOp) -> String {
  match op {
    Lt => "i32.lt_s"
    Le => "i32.le_s"
    Gt => "i32.gt_s"
    Ge => "i32.ge_s"
    Eq_ => "i32.eq"
    Ne => "i32.ne"
  }
}

///|
/// `LogicOp` → WAT i32 位运算指令助记符（布尔以 0 / 1 的 i32 建模）。
fn wat_logic_op(op : LogicOp) -> String {
  match op {
    And => "i32.and"
    Or => "i32.or"
  }
}

///|
/// 把 `TExpr` 渲染为 WebAssembly 文本格式（WAT）S-表达式串（仅供展示，R6.4）。
///
/// 渲染方案（结构对应，反映语法树形态而非可消费的完整 wasm 模块）：
/// - `TEInt(n)` → `(i32.const n)`；`TEBool(b)` → `(i32.const 1)` / `(i32.const 0)`。
/// - `TEVar(x)` → `(local.get $x)`。
/// - `TEArith(op,l,r)` → `(i32.add l r)` 等（除法 `i32.div_s`）。
/// - `TECmp(op,l,r)` → `(i32.lt_s l r)` 等。
/// - `TELogic(op,l,r)` → `(i32.and l r)` / `(i32.or l r)`。
/// - `TEIf(c,a,b)` → `(if (result i32) c (then a) (else b))`。
/// - `TELam(x,body)` → `(; lambda $x ;) (func (param $x i32) (result i32) body)`
///   —— 核心 wasm 无一等闭包，故以**可读占位符**呈现（见文件头边界声明）。
/// - `TEApp(f,a)` → `(call (; closure ;) f a)` —— 占位符，反映调用结构。
/// - `TELet(x,e1,e2)` → `(local $x (; = ;) e1) e2` 风格的可读嵌套形。
/// - `TELetRec(f,e1,e2)` → `(; letrec $f ;) (local $f e1) e2` 占位符。
/// - `TETuple(items)` → `(; tuple ;) (i0 i1 ...)` 占位符（核心 wasm 无元组）。
pub fn emit_wat(te : TExpr) -> String {
  match te {
    TEInt(n, _, _) => "(i32.const " + n.to_string() + ")"
    TEBool(b, _, _) => if b { "(i32.const 1)" } else { "(i32.const 0)" }
    TEVar(x, _, _) => "(local.get $" + x + ")"
    TEArith(op, l, r, _, _) =>
      "(" + wat_arith_op(op) + " " + emit_wat(l) + " " + emit_wat(r) + ")"
    TECmp(op, l, r, _, _) =>
      "(" + wat_cmp_op(op) + " " + emit_wat(l) + " " + emit_wat(r) + ")"
    TELogic(op, l, r, _, _) =>
      "(" + wat_logic_op(op) + " " + emit_wat(l) + " " + emit_wat(r) + ")"
    TEIf(c, a, b, _, _) =>
      "(if (result i32) " +
      emit_wat(c) +
      " (then " +
      emit_wat(a) +
      ") (else " +
      emit_wat(b) +
      "))"
    TELam(x, body, _, _) =>
      // 闭包非核心 wasm 一等公民：以可读 func 占位符呈现。
      "(; lambda $" +
      x +
      " ;) (func (param $" +
      x +
      " i32) (result i32) " +
      emit_wat(body) +
      ")"
    TEApp(f, a, _, _) =>
      // 调用结构占位符（无真实函数索引）。
      "(call (; closure ;) " + emit_wat(f) + " " + emit_wat(a) + ")"
    TELet(x, e1, e2, _, _) =>
      // 可读嵌套形：声明局部并初始化，再求值体。
      "(local $" + x + " (; = ;) " + emit_wat(e1) + ") " + emit_wat(e2)
    TELetRec(f, e1, e2, _, _) =>
      "(; letrec $" +
      f +
      " ;) (local $" +
      f +
      " " +
      emit_wat(e1) +
      ") " +
      emit_wat(e2)
    TETuple(items, _, _) => {
      let parts = items.map(emit_wat)
      "(; tuple ;) (" + parts.join(" ") + ")"
    }
  }
}
