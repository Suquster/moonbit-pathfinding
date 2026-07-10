// types.mbt —— Mini_Compiler 的核心类型定义。
//
// 设计依据（design.md §「方向一：Mini_Compiler」核心类型与流水线）：
//
//   pub enum Token { ... }                      // 词法单元
//   pub enum Ast { ... }                         // 抽象语法树
//   pub struct Diagnostic { kind; line; col; msg } // 诊断（含行列位置）
//   pub enum TypedAst { ... }                    // 带类型标注 AST
//   pub fn eval(ast : TypedAst) -> Value         // 求值产物为 Value
//
// 本文件锁定数据模型与「含行列位置的诊断」模型（R1.1 / R1.3）。流水线函数
// （lex / parse / check / eval / print_ast / compile）分别落在 lexer.mbt /
// parser.mbt / printer.mbt / semantics.mbt。

///|
/// 词法单元（token）。
///
/// 对应目标语言 MiniLet 的终结符集合（见 moon.pkg 文法声明）：整数字面量、
/// 标识符、关键字 `let` / `in` 与算术 / 分组 / 赋值符号。`Token` 本身不携带
/// 位置：词法阶段 `lex` 在内部以 @pc 的不可变游标跟踪行列，仅在词法错误时
/// 将位置写入 `Diagnostic`（R1.3）。
pub(all) enum Token {
  /// 整数字面量，如 `42`。
  IntLit(Int)
  /// 标识符（变量名），如 `x`、`foo_1`。
  Ident(String)
  /// 关键字 `let`。
  KwLet
  /// 关键字 `in`。
  KwIn
  /// 加号 `+`。
  Plus
  /// 减号 `-`。
  Minus
  /// 乘号 `*`。
  Star
  /// 除号 `/`。
  Slash
  /// 左括号 `(`。
  LParen
  /// 右括号 `)`。
  RParen
  /// 赋值符 `=`（用于 `let x = e`）。
  Assign
} derive(Eq)

///|
/// 二元算术运算符（binary operator）。
pub(all) enum BinOp {
  /// 加 `+`。
  Add
  /// 减 `-`。
  Sub
  /// 乘 `*`。
  Mul
  /// 除 `/`。
  Div
} derive(Eq)

///|
/// 抽象语法树（abstract syntax tree）。
///
/// 严格对应 MiniLet 文法（见 moon.pkg）：整数字面量、变量引用、二元算术运算
/// 与 `let` 绑定。`parse` 产出 `Ast`（R1.2），`print_ast` 将其打印回源串以
/// 支撑「打印再解析」往返（任务 15.3 的 Property 1）。
pub(all) enum Ast {
  /// 整数字面量节点。
  Int(Int)
  /// 变量引用节点。
  Var(String)
  /// 二元算术运算节点 `lhs op rhs`。
  Bin(BinOp, Ast, Ast)
  /// `let name = bound in body` 绑定节点。
  Let(String, Ast, Ast)
} derive(Eq)

///|
/// 类型（type）。
///
/// MiniLet 骨架阶段仅有整数类型 `IntT`；后续方向迭代可在独立子 spec 中扩展
/// 布尔 / 函数等类型。
pub(all) enum Type {
  /// 整数类型。
  IntT
} derive(Eq)

///|
/// 带类型标注的抽象语法树（typed AST）。
///
/// 与 `Ast` 同构，但每个节点附带其推断/检查得到的 `Type`。`check` 产出
/// `TypedAst`（R1.4），`eval` 以 `TypedAst` 为输入产出 `Value`。
pub(all) enum TypedAst {
  /// 整数字面量（类型恒为 `IntT`）。
  TInt(Int)
  /// 变量引用，携带其类型。
  TVar(String, Type)
  /// 二元运算，携带结果类型。
  TBin(BinOp, TypedAst, TypedAst, Type)
  /// `let` 绑定，携带 body（亦即整体）的类型。
  TLet(String, TypedAst, TypedAst, Type)
} derive(Eq)

///|
/// 运行期值（runtime value）。
///
/// `eval` 的产物。MiniLet 骨架阶段仅有整数值 `IntV`。
pub(all) enum Value {
  /// 整数值。
  IntV(Int)
} derive(Eq)

///|
/// 诊断类别（diagnostic kind）。
///
/// 区分流水线各阶段产生的诊断：词法错误、语法错误与类型错误。便于上层按
/// 类别分流处理，并在测试中精确断言（R1.3 / R1.5）。
pub(all) enum DiagKind {
  /// 词法错误（非法字符等）。
  LexError
  /// 语法错误（不符合文法）。
  SyntaxError
  /// 类型错误（类型不一致）。
  TypeError
} derive(Eq)

///|
/// 诊断（diagnostic）。
///
/// 严格对应 design.md 的 `Diagnostic { kind; line; col; msg }`：携带错误类别
/// 与**行列位置**（1 起始），满足 R1.3「返回包含错误类别、行号与列号的诊断
/// 结果，且不产生 AST」。`line` / `col` 沿用 @pc.Pos 的 1 起始约定。
pub(all) struct Diagnostic {
  kind : DiagKind
  line : Int
  col : Int
  msg : String
} derive(Eq)

///|
/// 以 `类别 @ 行:列 — 消息` 形式构造诊断，便于阅读与测试快照。
pub fn Diagnostic::new(
  kind : DiagKind,
  line : Int,
  col : Int,
  msg : String,
) -> Diagnostic {
  { kind, line, col, msg }
}

///|
/// 编译后端目标（compile backend target）。
///
/// 对应 design.md `compile(ast : TypedAst, target : Backend) -> Bytes` 的
/// `Backend` 参数。`Wasm` 产出可直接实例化的 WebAssembly 二进制模块；
/// `Js` 产出可由 Node.js 直接执行的 UTF-8 JavaScript 程序。
pub(all) enum Backend {
  /// 编译到 WebAssembly 目标。
  Wasm
  /// 编译到 JavaScript 目标。
  Js
} derive(Eq)
