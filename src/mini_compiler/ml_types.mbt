// ml_types.mbt —— MiniML 旁路类型层与 of_minilet 提升桥（design.md §「组件与
// 接口 → 1. MiniML 旁路类型层」，覆盖 R1.1 / R1.2 / R1.3 / R1.4 / R1.5 与
// R12.1 / R12.4）。
//
// 设计策略：增量式、严格向后兼容的旁路扩展。本文件**不修改** types.mbt 等任何
// 既有文件，也**不扩容**既有 `pub(all)` 枚举（`Token` / `BinOp` / `Ast` /
// `Type` / `TypedAst` / `Value` / `Diagnostic` / `DiagKind` / `Backend`）的构造
// 子与派生语义。MiniML 的全部新增类型（`Span` / `MlToken` / `CmpOp` /
// `LogicOp` / `Expr` / `Ty` / `Scheme` / `TExpr` / `Val` / `Env` / `Subst` /
// `TyEnv`）平行新增于此，算术运算复用既有冻结的 `BinOp`（Add/Sub/Mul/Div），
// 不重复定义（R1.1）。
//
// 集合类型说明（与 design.md 的偏差，已记录）：design.md 记述 `Env` / `TyEnv`
// 使用 `@immut/list.T`、`Subst` 使用 `@immut/sorted_map.T`。当前 moonbitlang/core
// 版本中并不存在 `immut/list` 子包，不可变单链表已迁移为 `moonbitlang/core/list`
// 的 `@list.List`（其 `.T` 别名已弃用）；不可变有序映射为
// `moonbitlang/core/immut/sorted_map` 的 `@sorted_map.SortedMap`（`.T` 别名亦
// 弃用）。因此本文件采用 `@list.List` 与 `@sorted_map.SortedMap`——二者均为
// 持久化不可变集合，完全契合 design.md 的「不可变使用」意图，仅路径/类型名随
// 上游演进而调整。

///|
/// 源码跨度：1 起始行列（沿用 @pc.Pos 约定）。挂载于每个 `Expr` 节点（R1.2），
/// 使后续阶段产生的诊断可定位到源码位置。
pub(all) struct Span {
  line : Int
  col : Int
} derive(Eq, Show)

///|
/// MiniML 词法单元（携带 span）。旁路新增，独立于既有冻结 `Token`（R12.1）。
pub(all) enum MlToken {
  /// 整数字面量及其 span。
  TkInt(Int, Span)
  /// 布尔字面量（`true` / `false` 归一于此）及其 span。
  TkBool(Bool, Span)
  /// 标识符（变量名）及其 span。
  TkIdent(String, Span)
  /// 关键字：`let` / `rec` / `in` / `if` / `then` / `else` / `fun` / `lambda`。
  TkKw(String, Span)
  /// 算符：`+ - * / < <= > >= == != && || ->`。
  TkOp(String, Span)
  /// 左括号 `(`。
  TkLParen(Span)
  /// 右括号 `)`。
  TkRParen(Span)
} derive(Eq)

///|
/// 比较运算符（旁路新增，不扩容既有 `BinOp`）。
pub(all) enum CmpOp {
  /// 小于 `<`。
  Lt
  /// 小于等于 `<=`。
  Le
  /// 大于 `>`。
  Gt
  /// 大于等于 `>=`。
  Ge
  /// 等于 `==`。
  Eq_
  /// 不等于 `!=`。
  Ne
} derive(Eq, Show)

///|
/// 逻辑运算符（旁路新增）。
pub(all) enum LogicOp {
  /// 逻辑与 `&&`。
  And
  /// 逻辑或 `||`。
  Or
} derive(Eq, Show)

///|
/// MiniML 抽象语法树。每个节点携带 span（R1.1, R1.2）。既有算术运算复用冻结的
/// `BinOp`（Add/Sub/Mul/Div），不重复定义。
pub(all) enum Expr {
  /// 整数字面量节点。
  EInt(Int, Span)
  /// 布尔字面量节点。
  EBool(Bool, Span)
  /// 变量引用节点。
  EVar(String, Span)
  /// 二元算术节点 `lhs op rhs`（复用既有 `BinOp`）。
  EArith(BinOp, Expr, Expr, Span)
  /// 比较节点 `lhs op rhs`。
  ECmp(CmpOp, Expr, Expr, Span)
  /// 逻辑节点 `lhs op rhs`。
  ELogic(LogicOp, Expr, Expr, Span)
  /// 条件 `if c then a else b`。
  EIf(Expr, Expr, Expr, Span)
  /// 函数抽象（`lambda` / `fun`）：单参抽象 `λx. body`。
  ELam(String, Expr, Span)
  /// 函数应用 `f e`。
  EApp(Expr, Expr, Span)
  /// `let x = e1 in e2` 绑定。
  ELet(String, Expr, Expr, Span)
  /// `let rec f = e1 in e2` 递归绑定。
  ELetRec(String, Expr, Expr, Span)
  /// 元组构造（可选特性 R1.5）。
  ETuple(Array[Expr], Span)
} derive(Eq)

///|
/// MiniML 类型项（R1.3）。
pub(all) enum Ty {
  /// 整数类型。
  TyInt
  /// 布尔类型。
  TyBool
  /// 类型变量（以稳定整数 id 表示）。
  TyVar(Int)
  /// 函数类型 `t1 -> t2`。
  TyFun(Ty, Ty)
  /// 元组类型（可选特性 R1.5）。
  TyTuple(Array[Ty])
} derive(Eq, Show)

///|
/// 类型方案 `∀a1..an. t`（let 多态，R4）。`vars` 为被全称量化的类型变量 id。
pub(all) struct Scheme {
  vars : Array[Int]
  body : Ty
} derive(Eq)

///|
/// 带类型标注 AST：与 `Expr` 同构，每节点附推断所得 `Ty`（R4.1）。
pub(all) enum TExpr {
  /// 整数字面量（携带类型）。
  TEInt(Int, Ty, Span)
  /// 布尔字面量（携带类型）。
  TEBool(Bool, Ty, Span)
  /// 变量引用（携带类型）。
  TEVar(String, Ty, Span)
  /// 二元算术（携带结果类型）。
  TEArith(BinOp, TExpr, TExpr, Ty, Span)
  /// 比较（携带结果类型）。
  TECmp(CmpOp, TExpr, TExpr, Ty, Span)
  /// 逻辑（携带结果类型）。
  TELogic(LogicOp, TExpr, TExpr, Ty, Span)
  /// 条件（携带整体类型）。
  TEIf(TExpr, TExpr, TExpr, Ty, Span)
  /// 函数抽象（携带函数类型）。
  TELam(String, TExpr, Ty, Span)
  /// 函数应用（携带结果类型）。
  TEApp(TExpr, TExpr, Ty, Span)
  /// `let` 绑定（携带 body 类型）。
  TELet(String, TExpr, TExpr, Ty, Span)
  /// `let rec` 递归绑定（携带 body 类型）。
  TELetRec(String, TExpr, TExpr, Ty, Span)
  /// 元组（携带元组类型）。
  TETuple(Array[TExpr], Ty, Span)
} derive(Eq)

///|
/// MiniML 运行期值（R5）。闭包捕获定义处环境（词法作用域）。
pub(all) enum Val {
  /// 整数值。
  VInt(Int)
  /// 布尔值。
  VBool(Bool)
  /// 闭包：形参、函数体、捕获环境。
  VClosure(String, TExpr, Env)
  /// 元组值（可选特性 R1.5）。
  VTuple(Array[Val])
} derive(Eq)

///|
/// 不可变求值环境：(名字, 值) 序列，最近绑定在表头（遮蔽语义，R5.5）。
///
/// 注：design.md 记述字段类型为 `@immut/list.T[(String, Val)]`；当前 core 中
/// 不可变单链表为 `@list.List`（见文件头说明）。本结构派生 `Eq` 以支撑 `Val`
/// 的 `derive(Eq)`（`VClosure` 内含 `Env`）——这是相对 design.md 文本的必要补充。
pub(all) struct Env {
  bindings : @list.List[(String, Val)]
} derive(Eq)

///|
/// 替换：类型变量 id → 类型项 的有限映射（R3.4）。
///
/// 注：design.md 记述字段类型为 `@immut/sorted_map.T[Int, Ty]`；当前 core 中
/// 不可变有序映射为 `@sorted_map.SortedMap`（见文件头说明）。
pub(all) struct Subst {
  map : @sorted_map.SortedMap[Int, Ty]
} derive(Eq)

///|
/// 类型环境：变量名 → 类型方案（R4.2）。最近绑定在表头（遮蔽）。
pub(all) struct TyEnv {
  schemes : @list.List[(String, Scheme)]
} derive(Eq)

///|
/// 提升桥：既有 MiniLet `Ast` → 等价 MiniML `Expr` 子集（R1.4）。
///
/// 整数 / 变量 / 算术 / `let` 一一对应；既有 `Ast` 无源码跨度，故 span 一律以
/// 哨兵 `Span{line:0, col:0}` 填充。该桥单向只读，不回写既有结构（R12.4）。
pub fn of_minilet(ast : Ast) -> Expr {
  let sentinel = Span::{ line: 0, col: 0 }
  match ast {
    Int(n) => EInt(n, sentinel)
    Var(s) => EVar(s, sentinel)
    Bin(op, lhs, rhs) => EArith(op, of_minilet(lhs), of_minilet(rhs), sentinel)
    Let(name, bound, body) =>
      ELet(name, of_minilet(bound), of_minilet(body), sentinel)
  }
}
