// semantics.mbt —— 类型检查 / 求值 / 编译流水线（`check` / `eval` / `compile`）。
//
// 对应任务 15.2：在 15.1 锁定的数据模型与桩之上，落地
//   * `check`：带**作用域检查**的类型检查器——遍历 `Ast`，在词法作用域内
//     解析变量引用；自由变量（未绑定变量）以 `TypeError` 诊断报告（含冲突
//     类型与节点位置信息），通过检查则产出带类型标注的 `TypedAst`（R1.4 /
//     R1.5）。
//   * `eval`：完整的**树遍历解释器**（tree-walking interpreter）——以不可变
//     求值环境承载 `let` 绑定与变量查找，对整数算术给出与语义规范一致的
//     确定性结果（R1.6）。
//   * `compile`：把闭合的 `TypedAst` 编译为可直接执行的 wasm 二进制或
//     JavaScript 程序。MiniLet 是无输入、无副作用的整数表达式语言，因此
//     wasm 后端可在编译期求值并把结果写入导出的 `main() -> i32`；JS 后端
//     保留表达式结构并输出同一整数语义。
//
// ===========================================================================
// MiniLet 语义规范（informative，对应 R1.6）
// ===========================================================================
//
//   * 整数字面量 `Int(n)` 求值为 `IntV(n)`。
//   * 二元算术 `Bin(op, a, b)`：先求值左、右子表达式（左到右、确定性），
//     再按 `op` 施加整数运算：
//       - `Add` / `Sub` / `Mul`：通常的 32 位整数算术（溢出按 MoonBit `Int`
//         环绕语义，三后端一致）。
//       - `Div`：整数截断除法；**除零定义为返回 `0`**——为保证 `eval` 为
//         全函数（total）、求值确定且三后端结果一致（避免各后端对硬件除零
//         陷阱的差异），MiniLet 明确将 `x / 0` 的语义规定为 `0`，而非运行
//         时陷阱。该约定记录在此并由单元测试固定。
//   * `let x = e1 in e2`：在 `e1` 的求值结果上将 `x` 绑定，并在该绑定可见的
//     作用域内求值 `e2`（非递归 let——`x` 不在 `e1` 自身的作用域内）。内层
//     同名绑定遮蔽（shadow）外层绑定。
//
// 作用域与类型检查（对应 R1.5 / R1.9）：唯一类型为 `IntT`，故经典意义上的
// 类型冲突在骨架文法中不会出现；可在静态阶段判定的语义错误为**自由变量**
// （引用了当前作用域内未绑定的名字）。`check` 据此做作用域检查，对自由变量
// 返回 `TypeError`：该名字缺少类型，与其所在的 `Int` 上下文冲突。
//
// 关于位置（line/col）：15.1 锁定的 `Ast` 不保留源码跨度（span），解析阶段
// 已剥离位置信息。为不破坏 15.1 已完成的数据模型与往返性质，本阶段
// `check` 诊断的位置以 `(0, 0)` 作为「AST 级、无源码跨度」哨兵，并在 `msg`
// 中显式标注出错节点（变量名）；后续若需精确行列，可在独立子任务中为 `Ast`
// 增补 span 字段并回填。

///|
/// AST 级类型检查诊断的位置哨兵：`Ast` 不保留源码跨度，故行列以 `0` 表示
/// 「无可用源码位置」（见文件头说明）。
const NO_SPAN : Int = 0

///|
/// 类型检查：在词法作用域内检查 `Ast` 并标注类型，产出 `TypedAst`（R1.4）。
///
/// 遍历过程维护一个**作用域名字栈**（被 `let` 引入的可见绑定）。遇到变量
/// 引用时若名字不在作用域内，则返回 `TypeError` 诊断（R1.5）：自由变量无
/// 类型，与其所在的 `Int` 上下文冲突；诊断 `msg` 标注出错的变量名。全部
/// 变量均有绑定时，返回与输入同构、各节点标注为 `IntT` 的 `TypedAst`。
pub fn check(ast : Ast) -> Result[TypedAst, Diagnostic] {
  check_scoped(ast, [])
}

///|
/// 作用域内类型检查助手：`scope` 为当前可见的绑定名（最近引入者在末尾）。
fn check_scoped(
  ast : Ast,
  scope : Array[String],
) -> Result[TypedAst, Diagnostic] {
  match ast {
    Int(n) => Ok(TInt(n))
    Var(name) =>
      // 作用域检查：自由变量 → 类型错误（缺类型，与 Int 上下文冲突，R1.5）。
      if scope_contains(scope, name) {
        Ok(TVar(name, IntT))
      } else {
        Err(
          Diagnostic::new(
            TypeError,
            NO_SPAN,
            NO_SPAN,
            "未绑定变量 '\{name}'：自由变量无类型，与期望的 Int 上下文冲突",
          ),
        )
      }
    Bin(op, lhs, rhs) =>
      // 子表达式逐一检查并向上传播首个诊断。
      match check_scoped(lhs, scope) {
        Err(d) => Err(d)
        Ok(tl) =>
          match check_scoped(rhs, scope) {
            Err(d) => Err(d)
            Ok(tr) => Ok(TBin(op, tl, tr, IntT))
          }
      }
    Let(name, bound, body) =>
      // 非递归 let：被绑定表达式在**外层**作用域检查；body 在引入 `name`
      // 后的扩展作用域检查。
      match check_scoped(bound, scope) {
        Err(d) => Err(d)
        Ok(tbound) =>
          match check_scoped(body, scope_extend(scope, name)) {
            Err(d) => Err(d)
            Ok(tbody) => Ok(TLet(name, tbound, tbody, IntT))
          }
      }
  }
}

///|
/// 作用域是否包含给定名字（从末尾向前查找，最近绑定优先）。
fn scope_contains(scope : Array[String], name : String) -> Bool {
  let mut i = scope.length() - 1
  while i >= 0 {
    if scope[i] == name {
      return true
    }
    i = i - 1
  }
  false
}

///|
/// 返回在末尾追加 `name` 后的**新**作用域（不可变更新，保持检查无副作用）。
fn scope_extend(scope : Array[String], name : String) -> Array[String] {
  let out : Array[String] = []
  for n in scope {
    out.push(n)
  }
  out.push(name)
  out
}

///|
/// 求值：对带类型标注的 AST 做树遍历解释，产出运行期值（R1.6）。
///
/// 以空环境启动；完整语义见文件头「MiniLet 语义规范」。
pub fn eval(ast : TypedAst) -> Value {
  eval_in(ast, [])
}

///|
/// 树遍历解释助手：`env` 为不可变求值环境（`(名字, 值)` 序列，最近绑定在
/// 末尾）。每个 `let` 在扩展环境上求值其 body，从而实现词法作用域与遮蔽。
fn eval_in(ast : TypedAst, env : Array[(String, Value)]) -> Value {
  match ast {
    TInt(n) => IntV(n)
    TVar(name, _) => env_lookup(env, name)
    TBin(op, lhs, rhs, _) => {
      let a = match eval_in(lhs, env) {
        IntV(x) => x
      }
      let b = match eval_in(rhs, env) {
        IntV(x) => x
      }
      IntV(apply_binop(op, a, b))
    }
    TLet(name, bound, body, _) => {
      let v = eval_in(bound, env)
      eval_in(body, env_extend(env, name, v))
    }
  }
}

///|
/// 施加二元整数运算；除零按 MiniLet 语义规范定义为 `0`（见文件头）。
fn apply_binop(op : BinOp, a : Int, b : Int) -> Int {
  match op {
    Add => a + b
    Sub => a - b
    Mul => a * b
    // 除零定义为 0，保证 eval 为全函数且三后端一致（见文件头说明）。
    Div =>
      if b == 0 {
        0
      } else if b == -1 {
        // INT_MIN / -1 不可表示（trap）；按环绕语义定义为 0 - a（与 ml_eval 一致）。
        0 - a
      } else {
        a / b
      }
  }
}

///|
/// 环境查找：从末尾向前找首个匹配名字的绑定。
///
/// 经 `check` 的程序不会出现自由变量；为保持 `eval` 为全函数，对（不应发生
/// 的）未绑定名字回退为 `IntV(0)`。
fn env_lookup(env : Array[(String, Value)], name : String) -> Value {
  let mut i = env.length() - 1
  while i >= 0 {
    let (k, v) = env[i]
    if k == name {
      return v
    }
    i = i - 1
  }
  IntV(0)
}

///|
/// 返回在末尾追加 `(name, value)` 后的**新**环境（不可变更新）。
fn env_extend(
  env : Array[(String, Value)],
  name : String,
  value : Value,
) -> Array[(String, Value)] {
  let out : Array[(String, Value)] = []
  for pair in env {
    out.push(pair)
  }
  out.push((name, value))
  out
}

///|
/// 将通过类型检查的 MiniLet 程序编译为目标产物。
///
/// - `Wasm`：返回标准 wasm 二进制，导出 `main() -> i32`。MiniLet 程序闭合、
///   纯且无输入，后端先按语言语义常量折叠，再生成最小可执行模块。
/// - `Js`：返回 UTF-8 Node.js 程序，保留 let / 算术结构并打印求值结果。
///
/// 两个后端都保持 32 位环绕、截断除法、除零为 0 与 `INT_MIN / -1` 环绕语义，
/// 与 `eval` 一致。
pub fn compile(ast : TypedAst, target : Backend) -> Bytes {
  match target {
    Wasm => compile_wasm(ast)
    Js => text_bytes(compile_js(ast))
  }
}

///|
/// 把 ASCII/UTF-8 源文本编码为字节。编译器生成的语法固定为 ASCII；标识符来自
/// MiniLet 词法器的 ASCII 标识符集合。
fn text_bytes(text : String) -> Bytes {
  let out : Array[Byte] = []
  for c in text {
    out.push(c.to_int().to_byte())
  }
  Bytes::from_array(out)
}

///|
/// 为 JavaScript 后端生成不会与关键字冲突的标识符。
fn js_name(name : String) -> String {
  "v_" + name
}

///|
/// 把 MiniLet typed AST lower 为 JavaScript 表达式。
fn js_expr(ast : TypedAst) -> String {
  match ast {
    TInt(n) => if n < 0 { "(" + n.to_string() + ")" } else { n.to_string() }
    TVar(name, _) => js_name(name)
    TBin(op, lhs, rhs, _) => {
      let a = js_expr(lhs)
      let b = js_expr(rhs)
      match op {
        Add => "((" + a + " + " + b + ") | 0)"
        Sub => "((" + a + " - " + b + ") | 0)"
        Mul => "Math.imul(" + a + ", " + b + ")"
        Div => "__div(" + a + ", " + b + ")"
      }
    }
    TLet(name, bound, body, _) =>
      "((" +
      js_name(name) +
      ") => " +
      js_expr(body) +
      ")(" +
      js_expr(bound) +
      ")"
  }
}

///|
/// 生成可由 Node.js 直接执行的完整程序。
fn compile_js(ast : TypedAst) -> String {
  "\"use strict\";\n" +
  "const __div = (a, b) => (b === 0 ? 0 : ((a / b) | 0));\n" +
  "console.log(" +
  js_expr(ast) +
  ");\n"
}

///|
/// 向字节缓冲写入无符号 LEB128。
fn push_uleb(out : Array[Byte], value : Int) -> Unit {
  let mut v = value
  while true {
    let mut byte = v & 0x7f
    v = v >> 7
    if v != 0 {
      byte = byte | 0x80
    }
    out.push(byte.to_byte())
    if v == 0 {
      break
    }
  }
}

///|
/// 向字节缓冲写入 i32 有符号 LEB128。
fn push_sleb_i32(out : Array[Byte], value : Int) -> Unit {
  let mut v = value
  while true {
    let mut byte = v & 0x7f
    v = v >> 7
    let sign_set = (byte & 0x40) != 0
    let done = (v == 0 && !sign_set) || (v == -1 && sign_set)
    if !done {
      byte = byte | 0x80
    }
    out.push(byte.to_byte())
    if done {
      break
    }
  }
}

///|
/// 写入一个 wasm section（section id + payload length + payload）。
fn push_section(out : Array[Byte], id : Int, payload : Array[Byte]) -> Unit {
  out.push(id.to_byte())
  push_uleb(out, payload.length())
  for byte in payload {
    out.push(byte)
  }
}

///|
/// 生成导出 `main() -> i32` 的最小 WebAssembly 二进制模块。
fn compile_wasm(ast : TypedAst) -> Bytes {
  let result = match eval(ast) {
    IntV(n) => n
  }
  let out : Array[Byte] = [0x00, 0x61, 0x73, 0x6d, 0x01, 0x00, 0x00, 0x00]

  let type_section : Array[Byte] = [0x01, 0x60, 0x00, 0x01, 0x7f]
  push_section(out, 1, type_section)

  let function_section : Array[Byte] = [0x01, 0x00]
  push_section(out, 3, function_section)

  let export_section : Array[Byte] = [
    0x01, 0x04, 0x6d, 0x61, 0x69, 0x6e, 0x00, 0x00,
  ]
  push_section(out, 7, export_section)

  let body : Array[Byte] = [0x00, 0x41]
  push_sleb_i32(body, result)
  body.push(0x0b)
  let code_section : Array[Byte] = [0x01]
  push_uleb(code_section, body.length())
  for byte in body {
    code_section.push(byte)
  }
  push_section(out, 10, code_section)
  Bytes::from_array(out)
}
