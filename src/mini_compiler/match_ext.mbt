// match_ext.mbt —— 迷你编译器语言特性扩展：模式匹配（match）、元组、列表
// （design.md §「Mini-compiler 特性与优化设计」，Requirement 9.1 / 9.5；旗舰档
// 旁路新增 / bypass）。
//
// 设计动机与定位：
//   既有 `Expr` 已含 `ETuple`、`Ty` 已含 `TyTuple`、`Val` 已含 `VTuple`，但整套
//   语言**缺少** match 表达式与列表（list）特性。为遵守「只增不减 / freeze +
//   bypass」原则，本文件**不修改**任何既有公开签名，而是引入一层**扩展语法树**
//   `ExprX`：它以 `XBase(Expr)` **包裹**既有表达式（复用既有 `lex`/`parse`/
//   `infer`/`eval_ml`），并新增 `XMatch`（模式匹配）与 `XList`（列表字面量）两个
//   构造子。求值结果与类型分别用**扩展类型** `ValX` / `TyX` 表达，使列表（`TXList`
//   / `VXList`）与元组（`TXTuple` / `VXTuple`）成为**一等、可清晰表示**的形态，
//   避免用既有类型勉强编码列表（既有 `Ty` / `Val` 无 list 构造子）。
//
// 与既有 `Expr` / `infer` / `eval_ml` 的桥接规则（见各桥接函数注释）：
//   * 类型桥接 `ty_to_tyx`：`TyInt→TXInt`、`TyBool→TXBool`、`TyFun→TXFun`、
//     `TyTuple→TXTuple`；`TyVar(_)`（多态自由变量）→ 单态化默认 `TXInt`（注释边界）。
//   * 值桥接 `val_to_valx`：`VInt→VXInt`、`VBool→VXBool`、`VTuple→VXTuple`；
//     `VClosure`（函数值）→ `ValX` 不含闭包构造子，回退为 `VXInt(0)`（注释边界：
//     `ExprX` 层聚焦 match/元组/列表的一阶值，函数值经 `TXFun` 仍可**类型检查**，
//     但不投影为 `ValX`）。
//   * 模式绑定变量在 arm body（`XBase`）中的引用：`XBase` 复用既有 `infer`/
//     `eval_ml`，二者均以**自含**表达式为前提（不接收外部环境）。为此本文件对
//     `XBase` 做**环境投影**：顶层 `EVar(name)` 直接返回环境中绑定的 `ValX`/`TyX`
//     （可承载列表等任意值）；复合表达式则把环境中可表示为字面量的绑定（整数 /
//     布尔 / 元组）**代入**后，交既有 `infer`/`eval_ml` 完成（代入尊重 `let`/
//     `fun`/`let rec` 的遮蔽语义）。列表 / 函数型绑定无法代入复合算术——而对其做
//     算术本就是类型错误，故由 `check_x` 如实报 `TypeMismatch`。
//
// 行为契约（Requirement 9.1 / 9.5）：
//   * AC1：`match` / 元组 / 列表字面量的**类型检查**（`check_x`）与**求值**
//     （`eval_x`）。match 对 scrutinee 求值后依次尝试每个 arm 的 `Pattern`，首个
//     匹配成功则绑定变量并求值该 arm body；列表字面量要求元素类型一致。
//   * AC5：类型不匹配返回**同时含 `expected` 与 `actual`** 的 `TypeMismatch`
//     （携带 `Span`），覆盖：列表元素类型不一致、match 各 arm body 类型不一致、
//     模式与 scrutinee 类型不兼容。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— `eval_x` 为全函数（与既有
//     `eval_ml` 的「全函数」约定一致：穷尽且良类型的 match 必命中，退化情形回退
//     为确定值并在注释标注边界）；
//   * 无 magic number —— 占位字面量值以命名常量表达；
//   * 无循环内字符串 `+` —— 手写 `Show` 经 `logger.write_string` 直写日志缓冲；
//   * `Show` 一律手写（`derive(Eq)` + `pub impl Show ... with fn output`）以规避
//     `derive(Debug)` 弃用告警，与本仓 codegen_infra / build_tool / dst 方向一致；
//   * `pub(all)` 暴露构造子，便于宿主、属性测试（任务 10.3）直接构造与匹配。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 代入 / 桥接时用于「占位字面量」的整数值。仅用于：把某绑定的**类型**投影为一个
/// 同类型的占位 `Expr`（值无关，仅类型相关），或在退化 / 不可表示情形下保持
/// `eval_x` 为全函数。非可调阈值，仅为可读性命名（规避散落字面量）。
let placeholder_int_lit : Int = 0

///|
/// 手写 `Show` 渲染数组（元组 / 列表元素、绑定序列）时相邻元素之间的分隔符。
let show_item_sep : String = ", "

// ───────────────────────────── 模式（Pattern） ─────────────────────────────

///|
/// 模式（pattern）—— `XMatch` 各 arm 的左侧，决定能否匹配 scrutinee 并引入绑定：
///
///   * `PWild` —— 通配符 `_`，匹配任意值，不绑定；
///   * `PVar(String)` —— 变量模式，匹配任意值并把它绑定到该名字；
///   * `PInt(Int)` —— 整数字面量模式，仅匹配相等整数；
///   * `PBool(Bool)` —— 布尔字面量模式，仅匹配相等布尔；
///   * `PTuple(Array[Pattern])` —— 元组解构，按元数与各分量子模式逐一匹配；
///   * `PCons(Pattern, Pattern)` —— 列表 `head :: tail`，匹配非空列表，分别绑定
///     头元素与剩余列表；
///   * `PNil` —— 空列表模式 `[]`，仅匹配空列表。
///
/// 派生 `Eq` 支撑结构相等（测试与去重）；`Show` 手写。
pub(all) enum Pattern {
  PWild
  PVar(String)
  PInt(Int)
  PBool(Bool)
  PTuple(Array[Pattern])
  PCons(Pattern, Pattern)
  PNil
} derive(Eq)

///|
/// 把单个模式写入日志缓冲（手写 `Show` 的共享渲染器）；递归渲染嵌套模式，
/// 数组元素以 `show_item_sep` 分隔，经「首元素无前导分隔符」的布尔旗标控制，
/// 全程 `logger.write_string` 直写、无 `out = out + ...` 循环拼接。
fn write_pattern(logger : &Logger, pat : Pattern) -> Unit {
  match pat {
    PWild => logger.write_string("PWild")
    PVar(x) => {
      logger.write_string("PVar(")
      logger.write_string(x)
      logger.write_string(")")
    }
    PInt(n) => {
      logger.write_string("PInt(")
      logger.write_string(n.to_string())
      logger.write_string(")")
    }
    PBool(b) => {
      logger.write_string("PBool(")
      logger.write_string(b.to_string())
      logger.write_string(")")
    }
    PTuple(ps) => {
      logger.write_string("PTuple([")
      let mut first = true
      for p in ps {
        if !first {
          logger.write_string(show_item_sep)
        }
        first = false
        write_pattern(logger, p)
      }
      logger.write_string("])")
    }
    PCons(ph, pt) => {
      logger.write_string("PCons(")
      write_pattern(logger, ph)
      logger.write_string(show_item_sep)
      write_pattern(logger, pt)
      logger.write_string(")")
    }
    PNil => logger.write_string("PNil")
  }
}

///|
/// 以可读形式展示模式（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for Pattern with fn output(self : Pattern, logger : &Logger) -> Unit {
  write_pattern(logger, self)
}

// ───────────────────────────── 扩展语法树（ExprX） ─────────────────────────────

///|
/// 扩展表达式（extended expression）—— 在既有 `Expr` 之上旁路新增 match 与 list：
///
///   * `XBase(Expr)` —— 包裹既有表达式（整数 / 布尔 / 变量 / 算术 / 比较 / 逻辑
///     / if / lambda / 应用 / let / let rec / 元组），复用既有
///     `infer` / `eval_ml`；
///   * `XMatch(ExprX, Array[(Pattern, ExprX)], Span)` —— 模式匹配：对 scrutinee
///     求值后依次尝试各 arm 的模式，首个成功者绑定变量并求值其 body；
///   * `XList(Array[ExprX], Span)` —— 列表字面量，元素类型须一致。
///
/// 不派生 `Eq`（含 `Expr` 与函数无关的递归，比较意义有限）；如需结构比较，经
/// `check_x` / `eval_x` 的结果（`TyX` / `ValX` 均派生 `Eq`）进行。
pub(all) enum ExprX {
  XBase(Expr)
  XMatch(ExprX, Array[(Pattern, ExprX)], Span)
  XList(Array[ExprX], Span)
}

// ───────────────────────────── 扩展类型（TyX） ─────────────────────────────

///|
/// 扩展类型（extended type）—— 求值 / 检查的类型表示，使列表与元组一等：
///
///   * `TXInt` / `TXBool` —— 基础标量类型；
///   * `TXTuple(Array[TyX])` —— 元组类型（按分量类型有序排列）；
///   * `TXList(TyX)` —— 列表类型（携带元素类型）；
///   * `TXFun(TyX, TyX)` —— 函数类型（由既有 `TyFun` 桥接而来，支撑对函数型
///     `XBase` 的类型检查；其值不投影为 `ValX`）。
///
/// 派生 `Eq` 支撑类型相等判定（列表元素一致性、arm body 一致性、模式兼容性均
/// 依赖之）。
pub(all) enum TyX {
  TXInt
  TXBool
  TXTuple(Array[TyX])
  TXList(TyX)
  TXFun(TyX, TyX)
} derive(Eq)

///|
/// 把单个扩展类型写入日志缓冲（手写 `Show` 的共享渲染器）。
fn write_tyx(logger : &Logger, ty : TyX) -> Unit {
  match ty {
    TXInt => logger.write_string("TXInt")
    TXBool => logger.write_string("TXBool")
    TXTuple(ts) => {
      logger.write_string("TXTuple([")
      let mut first = true
      for t in ts {
        if !first {
          logger.write_string(show_item_sep)
        }
        first = false
        write_tyx(logger, t)
      }
      logger.write_string("])")
    }
    TXList(elem) => {
      logger.write_string("TXList(")
      write_tyx(logger, elem)
      logger.write_string(")")
    }
    TXFun(a, b) => {
      logger.write_string("TXFun(")
      write_tyx(logger, a)
      logger.write_string(show_item_sep)
      write_tyx(logger, b)
      logger.write_string(")")
    }
  }
}

///|
/// 以可读形式展示扩展类型（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for TyX with fn output(self : TyX, logger : &Logger) -> Unit {
  write_tyx(logger, self)
}

// ───────────────────────────── 扩展值（ValX） ─────────────────────────────

///|
/// 扩展运行期值（extended value）—— `eval_x` 的产物，使列表与元组一等：
///
///   * `VXInt(Int)` / `VXBool(Bool)` —— 基础标量值；
///   * `VXTuple(Array[ValX])` —— 元组值；
///   * `VXList(Array[ValX])` —— 列表值（`PNil` 即长度为 0、`PCons` 即非空）。
///
/// 不含闭包构造子（`ExprX` 层聚焦一阶值；函数值仅参与类型检查，不投影为 `ValX`）。
/// 派生 `Eq` 支撑求值结果比较（单元 / 属性测试与等价判定均依赖之）。
pub(all) enum ValX {
  VXInt(Int)
  VXBool(Bool)
  VXTuple(Array[ValX])
  VXList(Array[ValX])
} derive(Eq)

///|
/// 把单个扩展值写入日志缓冲（手写 `Show` 的共享渲染器）。
fn write_valx(logger : &Logger, v : ValX) -> Unit {
  match v {
    VXInt(n) => {
      logger.write_string("VXInt(")
      logger.write_string(n.to_string())
      logger.write_string(")")
    }
    VXBool(b) => {
      logger.write_string("VXBool(")
      logger.write_string(b.to_string())
      logger.write_string(")")
    }
    VXTuple(items) => {
      logger.write_string("VXTuple([")
      let mut first = true
      for it in items {
        if !first {
          logger.write_string(show_item_sep)
        }
        first = false
        write_valx(logger, it)
      }
      logger.write_string("])")
    }
    VXList(items) => {
      logger.write_string("VXList([")
      let mut first = true
      for it in items {
        if !first {
          logger.write_string(show_item_sep)
        }
        first = false
        write_valx(logger, it)
      }
      logger.write_string("])")
    }
  }
}

///|
/// 以可读形式展示扩展值（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for ValX with fn output(self : ValX, logger : &Logger) -> Unit {
  write_valx(logger, self)
}

// ───────────────────────────── 类型不匹配诊断（TypeMismatch） ─────────────────────────────

///|
/// 类型不匹配诊断（Requirement 9.5 / AC5）—— **同时**携带 `expected` 与 `actual`
/// 两个扩展类型以及发生位置 `span`，用于精确报告：
///   * 列表元素类型不一致（`expected` = 首元素类型，`actual` = 冲突元素类型）；
///   * match 各 arm body 类型不一致（`expected` = 首 arm body 类型，`actual` =
///     冲突 arm body 类型）；
///   * 模式与 scrutinee 类型不兼容（`expected` = scrutinee 类型，`actual` = 模式
///     所蕴含的类型 / 形状）。
///
/// 派生 `Eq` 支撑测试断言；`Show` 手写。
pub(all) struct TypeMismatch {
  expected : TyX
  actual : TyX
  span : Span
} derive(Eq)

///|
/// 以可读形式展示类型不匹配（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for TypeMismatch with fn output(
  self : TypeMismatch,
  logger : &Logger,
) -> Unit {
  logger.write_string("TypeMismatch(expected=")
  write_tyx(logger, self.expected)
  logger.write_string(", actual=")
  write_tyx(logger, self.actual)
  logger.write_string(", span=")
  logger.write_string(self.span.line.to_string())
  logger.write_string(":")
  logger.write_string(self.span.col.to_string())
  logger.write_string(")")
}

// ───────────────────────────── 既有 Expr / Ty / Val 的桥接 ─────────────────────────────

///|
/// 提取任意既有 `Expr` 的 `Span`（所有构造子均以 `Span` 作末位字段）。用于在
/// `XBase` 的边界诊断中给出位置。
fn expr_span(e : Expr) -> Span {
  match e {
    EInt(_, sp) => sp
    EBool(_, sp) => sp
    EVar(_, sp) => sp
    EArith(_, _, _, sp) => sp
    ECmp(_, _, _, sp) => sp
    ELogic(_, _, _, sp) => sp
    EIf(_, _, _, sp) => sp
    ELam(_, _, sp) => sp
    EApp(_, _, sp) => sp
    ELet(_, _, _, sp) => sp
    ELetRec(_, _, _, sp) => sp
    ETuple(_, sp) => sp
  }
}

///|
/// 类型桥接：既有 `Ty` → 扩展 `TyX`。
///
/// 规则：`TyInt→TXInt`、`TyBool→TXBool`、`TyFun→TXFun`、`TyTuple→TXTuple`。
/// 边界：`TyVar(_)`（HM 推断遗留的多态自由变量，例如裸 `fun x -> x` 的参数类型）
/// 在 `TyX` 无对应构造子，**单态化**为默认 `TXInt`——这是把多态片段嵌入扩展层时
/// 的保守选择；对一阶（int/bool/元组）`XBase` 不会触发，仅作用于多态函数型片段
/// 的类型展示。
fn ty_to_tyx(t : Ty) -> TyX {
  match t {
    TyInt => TXInt
    TyBool => TXBool
    TyVar(_) => TXInt
    TyFun(a, b) => TXFun(ty_to_tyx(a), ty_to_tyx(b))
    TyTuple(items) => {
      let out = []
      for it in items {
        out.push(ty_to_tyx(it))
      }
      TXTuple(out)
    }
  }
}

///|
/// 值桥接：既有 `Val` → 扩展 `ValX`。
///
/// 规则：`VInt→VXInt`、`VBool→VXBool`、`VTuple→VXTuple`。
/// 边界：`VClosure`（函数值）在 `ValX` 无对应构造子（扩展层聚焦一阶值），回退为
/// `VXInt(placeholder_int_lit)`；函数型片段应仅参与类型检查（经 `TXFun`），不作为
/// `eval_x` 的最终一阶产物。
fn val_to_valx(v : Val) -> ValX {
  match v {
    VInt(n) => VXInt(n)
    VBool(b) => VXBool(b)
    VTuple(items) => {
      let out = []
      for it in items {
        out.push(val_to_valx(it))
      }
      VXTuple(out)
    }
    VClosure(_, _, _) => VXInt(placeholder_int_lit)
  }
}

///|
/// 把扩展值投影为「等值的既有 `Expr` 字面量」（供 `XBase` 复合表达式的环境代入）。
///
/// 整数 / 布尔 / （递归可表示的）元组可表示为 `EInt` / `EBool` / `ETuple`；列表
/// （`VXList`）在既有 `Expr` 无字面量构造子，返回 `None`——此时该绑定无法代入复合
/// 表达式（但「顶层直接引用」路径会在 `eval_base` 中直接返回其 `ValX`，故返回列表
/// 等场景不受影响；对列表做复合算术本就是类型错误）。
fn valx_to_expr(v : ValX, sp : Span) -> Expr? {
  match v {
    VXInt(n) => Some(EInt(n, sp))
    VXBool(b) => Some(EBool(b, sp))
    VXTuple(items) => {
      let out = []
      for it in items {
        match valx_to_expr(it, sp) {
          Some(e) => out.push(e)
          None => return None
        }
      }
      Some(ETuple(out, sp))
    }
    VXList(_) => None
  }
}

///|
/// 把扩展类型投影为「该类型的占位 `Expr` 字面量」（供 `XBase` 复合表达式的类型代入；
/// 值无关，仅需类型正确）。整数 / 布尔 / 元组可表示；列表 / 函数返回 `None`（无法以
/// 既有 `Expr` 字面量表达——对其做复合算术本就是类型错误，由 `check_x` 报告）。
fn tyx_to_expr(t : TyX, sp : Span) -> Expr? {
  match t {
    TXInt => Some(EInt(placeholder_int_lit, sp))
    TXBool => Some(EBool(false, sp))
    TXTuple(items) => {
      let out = []
      for it in items {
        match tyx_to_expr(it, sp) {
          Some(e) => out.push(e)
          None => return None
        }
      }
      Some(ETuple(out, sp))
    }
    TXList(_) => None
    TXFun(_, _) => None
  }
}

// ───────────────────────────── 变量代入（尊重遮蔽） ─────────────────────────────

///|
/// 在 `Expr` 中代入自由变量：对每个 `EVar(name)`，调用 `lookup(name, span)`；返回
/// `Some(lit)` 则替换为该字面量，`None` 则保持原样。代入**尊重遮蔽**：进入绑定
/// 构造子（`ELam` / `ELet` 的 body / `ELetRec`）时，被绑定的名字在其作用域内被
/// 屏蔽（包装 `lookup` 使其对该名返回 `None`），从而不会错误替换内层同名变量。
///
/// 该函数纯结构递归、无字符串拼接，用于把模式绑定的（可字面量化的）值 / 类型代入
/// `XBase` 复合表达式，使其成为自含表达式后交既有 `infer` / `eval_ml` 处理。
fn subst_var(e : Expr, lookup : (String, Span) -> Expr?) -> Expr {
  match e {
    EInt(_, _) => e
    EBool(_, _) => e
    EVar(name, sp) =>
      match lookup(name, sp) {
        Some(lit) => lit
        None => e
      }
    EArith(op, l, r, sp) =>
      EArith(op, subst_var(l, lookup), subst_var(r, lookup), sp)
    ECmp(op, l, r, sp) =>
      ECmp(op, subst_var(l, lookup), subst_var(r, lookup), sp)
    ELogic(op, l, r, sp) =>
      ELogic(op, subst_var(l, lookup), subst_var(r, lookup), sp)
    EIf(c, a, b, sp) =>
      EIf(subst_var(c, lookup), subst_var(a, lookup), subst_var(b, lookup), sp)
    ELam(x, body, sp) => {
      let inner = fn(n : String, s : Span) -> Expr? {
        if n == x {
          None
        } else {
          lookup(n, s)
        }
      }
      ELam(x, subst_var(body, inner), sp)
    }
    EApp(f, a, sp) => EApp(subst_var(f, lookup), subst_var(a, lookup), sp)
    ELet(name, e1, e2, sp) => {
      let inner = fn(n : String, s : Span) -> Expr? {
        if n == name {
          None
        } else {
          lookup(n, s)
        }
      }
      // e1 在外层作用域代入；e2 在引入 name（屏蔽）后代入。
      ELet(name, subst_var(e1, lookup), subst_var(e2, inner), sp)
    }
    ELetRec(name, e1, e2, sp) => {
      let inner = fn(n : String, s : Span) -> Expr? {
        if n == name {
          None
        } else {
          lookup(n, s)
        }
      }
      // 递归名在 e1 与 e2 均可见（均屏蔽）。
      ELetRec(name, subst_var(e1, inner), subst_var(e2, inner), sp)
    }
    ETuple(items, sp) => {
      let out = []
      for it in items {
        out.push(subst_var(it, lookup))
      }
      ETuple(out, sp)
    }
  }
}

// ───────────────────────────── 环境助手（不可变语义） ─────────────────────────────

///|
/// 克隆扩展值环境（确保扩展绑定不污染外层作用域，模拟不可变语义）。
fn clone_valx_env(env : Map[String, ValX]) -> Map[String, ValX] {
  let m = Map([])
  for k, v in env {
    m[k] = v
  }
  m
}

///|
/// 以一组绑定扩展扩展值环境（返回新映射，外层不受影响）。
fn extend_valx_env(
  env : Map[String, ValX],
  binds : Array[(String, ValX)],
) -> Map[String, ValX] {
  let m = clone_valx_env(env)
  for b in binds {
    m[b.0] = b.1
  }
  m
}

///|
/// 克隆扩展类型环境。
fn clone_tyx_env(env : Map[String, TyX]) -> Map[String, TyX] {
  let m = Map([])
  for k, v in env {
    m[k] = v
  }
  m
}

///|
/// 以一组绑定扩展扩展类型环境（返回新映射，外层不受影响）。
fn extend_tyx_env(
  env : Map[String, TyX],
  binds : Array[(String, TyX)],
) -> Map[String, TyX] {
  let m = clone_tyx_env(env)
  for b in binds {
    m[b.0] = b.1
  }
  m
}

// ───────────────────────────── 类型检查（check_x） ─────────────────────────────

///|
/// 类型检查入口（Requirement 9.1 / 9.5）：以空类型环境检查 `ExprX`，成功返回其
/// 扩展类型 `TyX`，失败返回**同含 `expected` 与 `actual`** 的 `TypeMismatch`。
pub fn check_x(ex : ExprX) -> Result[TyX, TypeMismatch] {
  check_env(ex, Map([]))
}

///|
/// 类型检查递归核心：`tenv` 为当前可见的（变量名 → 扩展类型）环境。
fn check_env(ex : ExprX, tenv : Map[String, TyX]) -> Result[TyX, TypeMismatch] {
  match ex {
    XBase(e) => check_base(e, tenv)
    XList(elems, sp) => check_list(elems, sp, tenv)
    XMatch(scrut, arms, sp) => check_match(scrut, arms, sp, tenv)
  }
}

///|
/// 检查 `XBase`：顶层 `EVar` 直接取环境类型（可承载列表 / 元组等任意类型）；复合
/// 表达式把环境中可字面量化的绑定按类型代入后，交既有 `infer` 完成（再桥接为
/// `TyX`）。`infer` 失败（基础表达式本身类型错误）映射为一个边界 `TypeMismatch`
/// （以 `expected=TXBool`、`actual=TXInt` 标示「基础层类型错误」；基础层的精确
/// 行列诊断仍可经既有 `infer` 获取——此处仅满足扩展层 `Result` 的统一返回形态）。
fn check_base(e : Expr, tenv : Map[String, TyX]) -> Result[TyX, TypeMismatch] {
  match e {
    EVar(name, _) =>
      match tenv.get(name) {
        Some(t) => Ok(t)
        None => check_base_closed(e)
      }
    _ => {
      let closed = subst_var(e, fn(n : String, s : Span) -> Expr? {
        match tenv.get(n) {
          Some(t) => tyx_to_expr(t, s)
          None => None
        }
      })
      check_base_closed(closed)
    }
  }
}

///|
/// 对**自含**既有表达式做类型检查：复用既有 `infer`，成功桥接 `Ty→TyX`。
fn check_base_closed(e : Expr) -> Result[TyX, TypeMismatch] {
  match infer(e) {
    Ok((_, ty)) => Ok(ty_to_tyx(ty))
    Err(_) =>
      Err(TypeMismatch::{ expected: TXBool, actual: TXInt, span: expr_span(e) })
  }
}

///|
/// 检查列表字面量 `XList`：要求所有元素类型一致；空列表默认元素类型为 `TXInt`
/// （`TyX` 无类型变量，缺上下文 / 注解时采保守默认，注释标注边界；非空列表的元素
/// 类型由首元素确定）。元素类型不一致时报 `TypeMismatch`（`expected` = 首元素类型，
/// `actual` = 冲突元素类型，`span` = 列表位置）。
fn check_list(
  elems : Array[ExprX],
  sp : Span,
  tenv : Map[String, TyX],
) -> Result[TyX, TypeMismatch] {
  if elems.is_empty() {
    return Ok(TXList(TXInt))
  }
  let head_ty = match check_env(elems[0], tenv) {
    Ok(t) => t
    Err(d) => return Err(d)
  }
  let mut i = 1
  let n = elems.length()
  while i < n {
    let ti = match check_env(elems[i], tenv) {
      Ok(t) => t
      Err(d) => return Err(d)
    }
    if ti != head_ty {
      return Err(TypeMismatch::{ expected: head_ty, actual: ti, span: sp })
    }
    i = i + 1
  }
  Ok(TXList(head_ty))
}

///|
/// 检查 match 表达式 `XMatch`：先检查 scrutinee 得其类型；对每个 arm，检查模式与
/// scrutinee 类型兼容（并得到变量绑定的类型），再在扩展环境下检查 arm body；要求
/// 所有 arm body 类型一致（`expected` = 首 arm body 类型，`actual` = 冲突类型）。
/// 退化的零 arm match 报 `TypeMismatch`（`expected` = scrutinee 类型，`actual` =
/// `TXTuple([])` 作「无 arm」标记）。
fn check_match(
  scrut : ExprX,
  arms : Array[(Pattern, ExprX)],
  sp : Span,
  tenv : Map[String, TyX],
) -> Result[TyX, TypeMismatch] {
  let scrut_ty = match check_env(scrut, tenv) {
    Ok(t) => t
    Err(d) => return Err(d)
  }
  if arms.is_empty() {
    return Err(TypeMismatch::{
      expected: scrut_ty,
      actual: TXTuple([]),
      span: sp,
    })
  }
  let mut result_ty : TyX? = None
  for arm in arms {
    let (pat, body) = arm
    let binds = match check_pattern(pat, scrut_ty, sp) {
      Ok(bs) => bs
      Err(d) => return Err(d)
    }
    let body_env = extend_tyx_env(tenv, binds)
    let body_ty = match check_env(body, body_env) {
      Ok(t) => t
      Err(d) => return Err(d)
    }
    match result_ty {
      None => result_ty = Some(body_ty)
      Some(expected) =>
        if body_ty != expected {
          return Err(TypeMismatch::{ expected, actual: body_ty, span: sp })
        }
    }
  }
  // arms 非空，result_ty 必为 Some；以保守回退保持全函数（无 abort）。
  match result_ty {
    Some(t) => Ok(t)
    None => Ok(scrut_ty)
  }
}

///|
/// 检查模式与 scrutinee 类型的兼容性，并返回模式引入的（变量名 → 类型）绑定。
/// 不兼容时报 `TypeMismatch`：`expected` = scrutinee 类型，`actual` = 模式所蕴含的
/// 类型 / 形状（当 scrutinee 形状不符时，`actual` 以占位元素类型表达模式的元数 /
/// 列表形状，best-effort 标识不匹配方向）。
fn check_pattern(
  pat : Pattern,
  ty : TyX,
  sp : Span,
) -> Result[Array[(String, TyX)], TypeMismatch] {
  match pat {
    PWild => Ok([])
    PVar(x) => Ok([(x, ty)])
    PInt(_) =>
      if ty == TXInt {
        Ok([])
      } else {
        Err(TypeMismatch::{ expected: ty, actual: TXInt, span: sp })
      }
    PBool(_) =>
      if ty == TXBool {
        Ok([])
      } else {
        Err(TypeMismatch::{ expected: ty, actual: TXBool, span: sp })
      }
    PTuple(ps) =>
      match ty {
        TXTuple(ts) =>
          if ts.length() == ps.length() {
            let binds = []
            let mut i = 0
            let n = ps.length()
            while i < n {
              match check_pattern(ps[i], ts[i], sp) {
                Ok(bs) =>
                  for b in bs {
                    binds.push(b)
                  }
                Err(d) => return Err(d)
              }
              i = i + 1
            }
            Ok(binds)
          } else {
            Err(TypeMismatch::{
              expected: ty,
              actual: tuple_shape(ps.length()),
              span: sp,
            })
          }
        _ =>
          Err(TypeMismatch::{
            expected: ty,
            actual: tuple_shape(ps.length()),
            span: sp,
          })
      }
    PNil =>
      match ty {
        TXList(_) => Ok([])
        _ =>
          Err(TypeMismatch::{ expected: ty, actual: TXList(TXInt), span: sp })
      }
    PCons(ph, pt) =>
      match ty {
        TXList(elem) => {
          let head_binds = match check_pattern(ph, elem, sp) {
            Ok(bs) => bs
            Err(d) => return Err(d)
          }
          let tail_binds = match check_pattern(pt, TXList(elem), sp) {
            Ok(bs) => bs
            Err(d) => return Err(d)
          }
          let binds = []
          for b in head_binds {
            binds.push(b)
          }
          for b in tail_binds {
            binds.push(b)
          }
          Ok(binds)
        }
        _ =>
          Err(TypeMismatch::{ expected: ty, actual: TXList(TXInt), span: sp })
      }
  }
}

///|
/// 构造一个表示「`n` 元元组形状」的占位类型（各分量以 `TXInt` 占位），用于模式与
/// scrutinee 形状不符时在 `TypeMismatch.actual` 中标识模式的元数。
fn tuple_shape(n : Int) -> TyX {
  let out = []
  let mut i = 0
  while i < n {
    out.push(TXInt)
    i = i + 1
  }
  TXTuple(out)
}

// ───────────────────────────── 求值（eval_x） ─────────────────────────────

///|
/// 求值入口（Requirement 9.1）：以空环境对 `ExprX` 求值，产出扩展值 `ValX`。
///
/// 与既有 `eval_ml` 一致地约定为**全函数**：输入通常应先通过 `check_x`；穷尽且
/// 良类型的 match 必命中某 arm。退化 / 不可表示情形（无 arm 命中、函数值投影等）
/// 回退为确定值（`VXInt(placeholder_int_lit)`），保持全函数且三后端一致（无
/// `abort` / `panic`）。
pub fn eval_x(ex : ExprX) -> ValX {
  eval_x_env(ex, Map([]))
}

///|
/// 求值递归核心：`env` 为当前可见的（变量名 → 扩展值）环境。
fn eval_x_env(ex : ExprX, env : Map[String, ValX]) -> ValX {
  match ex {
    XBase(e) => eval_base(e, env)
    XList(elems, _) => {
      let out = []
      for el in elems {
        out.push(eval_x_env(el, env))
      }
      VXList(out)
    }
    XMatch(scrut, arms, _) => {
      let value = eval_x_env(scrut, env)
      eval_match(value, arms, env)
    }
  }
}

///|
/// 求值 `XBase`：顶层 `EVar` 直接返回环境绑定的 `ValX`（可承载列表 / 元组等任意
/// 值）；复合表达式把环境中可字面量化的绑定（整数 / 布尔 / 元组）代入后，交既有
/// `infer` + `eval_ml` 求值并桥接为 `ValX`。
fn eval_base(e : Expr, env : Map[String, ValX]) -> ValX {
  match e {
    EVar(name, _) =>
      match env.get(name) {
        Some(v) => v
        None => eval_base_closed(e)
      }
    _ => {
      let closed = subst_var(e, fn(n : String, s : Span) -> Expr? {
        match env.get(n) {
          Some(v) => valx_to_expr(v, s)
          None => None
        }
      })
      eval_base_closed(closed)
    }
  }
}

///|
/// 对**自含**既有表达式求值：复用既有 `infer` + `eval_ml`，再桥接 `Val→ValX`。
/// `infer` 失败（理论上 `check_x` 已拦截）回退为 `VXInt(placeholder_int_lit)` 以
/// 保持全函数。
fn eval_base_closed(e : Expr) -> ValX {
  match infer(e) {
    Ok((te, _)) => val_to_valx(eval_ml(te))
    Err(_) => VXInt(placeholder_int_lit)
  }
}

///|
/// 依次尝试各 arm 的模式匹配 scrutinee 值，首个成功者绑定变量并求值其 body；
/// 无任一 arm 命中时回退为 `VXInt(placeholder_int_lit)`（穷尽且良类型的 match 不
/// 触发，仅为全函数保证）。
fn eval_match(
  value : ValX,
  arms : Array[(Pattern, ExprX)],
  env : Map[String, ValX],
) -> ValX {
  for arm in arms {
    let (pat, body) = arm
    match match_pattern(pat, value) {
      Some(binds) => {
        let body_env = extend_valx_env(env, binds)
        return eval_x_env(body, body_env)
      }
      None => continue
    }
  }
  VXInt(placeholder_int_lit)
}

///|
/// 尝试以模式 `pat` 匹配扩展值 `value`：成功返回引入的（变量名 → 扩展值）绑定，
/// 失败返回 `None`。语义：
///   * `PWild` 匹配任意值（无绑定）；`PVar(x)` 匹配任意值并绑定 `x`；
///   * `PInt` / `PBool` 仅匹配相等的标量；
///   * `PTuple(ps)` 匹配同元数元组并逐分量递归；
///   * `PNil` 仅匹配空列表；`PCons(ph, pt)` 仅匹配非空列表，分别匹配头元素与
///     剩余列表。
fn match_pattern(pat : Pattern, value : ValX) -> Array[(String, ValX)]? {
  match pat {
    PWild => Some([])
    PVar(x) => Some([(x, value)])
    PInt(n) =>
      match value {
        VXInt(m) => if m == n { Some([]) } else { None }
        _ => None
      }
    PBool(b) =>
      match value {
        VXBool(c) => if c == b { Some([]) } else { None }
        _ => None
      }
    PTuple(ps) =>
      match value {
        VXTuple(vs) =>
          if vs.length() == ps.length() {
            match_seq(ps, vs)
          } else {
            None
          }
        _ => None
      }
    PNil =>
      match value {
        VXList(vs) => if vs.is_empty() { Some([]) } else { None }
        _ => None
      }
    PCons(ph, pt) =>
      match value {
        VXList(vs) =>
          if vs.is_empty() {
            None
          } else {
            let head = vs[0]
            let tail = VXList(list_tail(vs))
            match match_pattern(ph, head) {
              Some(hb) =>
                match match_pattern(pt, tail) {
                  Some(tb) => {
                    let binds = []
                    for b in hb {
                      binds.push(b)
                    }
                    for b in tb {
                      binds.push(b)
                    }
                    Some(binds)
                  }
                  None => None
                }
              None => None
            }
          }
        _ => None
      }
  }
}

///|
/// 逐分量匹配「模式数组」与「值数组」（两者等长，用于 `PTuple`）：全部成功则汇总
/// 绑定，任一失败即整体失败。
fn match_seq(ps : Array[Pattern], vs : Array[ValX]) -> Array[(String, ValX)]? {
  let binds = []
  let mut i = 0
  let n = ps.length()
  while i < n {
    match match_pattern(ps[i], vs[i]) {
      Some(bs) =>
        for b in bs {
          binds.push(b)
        }
      None => return None
    }
    i = i + 1
  }
  Some(binds)
}

///|
/// 返回列表（值数组）去掉首元素后的剩余部分（用于 `PCons` 的 tail 绑定）；以索引
/// 复制构造新数组，无字符串拼接。
fn list_tail(items : Array[ValX]) -> Array[ValX] {
  let out = []
  let mut i = 1
  let n = items.length()
  while i < n {
    out.push(items[i])
    i = i + 1
  }
  out
}
