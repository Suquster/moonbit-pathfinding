# 设计文档（Design Document）

## 概述（Overview）

本设计文档定义 **Mini_Compiler（方向一）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的技术实现方案，覆盖 `requirements.md` 的 Requirement 1–14。

核心策略是 **增量式、严格向后兼容的旁路扩展**：在已发布的 `0.1.0` MiniLet 骨架之上，**不改写、不扩容**任何既有 `pub(all)` 公开类型（`Token` / `BinOp` / `Ast` / `Type` / `TypedAst` / `Value` / `Diagnostic` / `DiagKind` / `Backend`），**冻结**全部既有接口（`lex` / `parse` / `check` / `eval` / `print_ast` / `compile` / `Diagnostic::new`）的签名与逐字行为，转而在**旁路新增**一组 `.mbt` 文件，实现一套对标教学/研究级编译器（OCaml、Haskell、Rust 教学实现与《Write You a Haskell》）的旗舰级 **MiniML 语言前端 + Hindley-Milner 类型推断 + 树遍历解释器 + 字节码编译后端**。既有 MiniLet `Ast` 通过 `of_minilet` 桥被无损提升为 MiniML `Expr` 子集，从而复用既有流水线又解锁新能力。

### 实现边界（显式声明，对应 R11.4）

Mini_Compiler 是一门**玩具/教学语言**的编译器与解释器模型层，停留在「词法 → 语法 → 类型推断 → 优化 → 求值 / 字节码编译 → 虚拟机执行」这一抽象层：

- 字节码虚拟机 `VM` 是一台**内存中的栈式抽象机**——以操作数栈与调用帧解释 `Bytecode`，产出 `Val`。
- **不**生成原生可执行文件、**不**汇编或链接、**不**绑定任何具体指令集架构（ISA）。
- 可选的 wasm 文本 / js 源输出仅作为**额外文本后端**，仅供展示，**不**保证可被外部工具链消费。

该边界使核心算法（合一、Algorithm W、求值、编译—执行等价）可被属性测试穷尽校验，且在 `wasm-gc` / `js` / `native` 三后端上行为一致。

### 设计目标与非目标

| 类别 | 内容 |
| --- | --- |
| 目标 | MiniML 前端（含 span）、HM 类型推断（Algorithm W + 合一 + let 多态）、树遍历解释器、栈式字节码 VM、AST 优化、定位精确的错误处理、端到端流水线、基准、可执行文档、三后端一致、严格向后兼容 |
| 非目标 | 原生代码生成、汇编/链接、ISA 绑定、GC/内存管理实现、可消费的 wasm/js 工具链产物、并发/IO/副作用、模块系统 |

---

## 架构（Architecture）

### 分层视图

MiniML 旁路流水线分为五层，全部构建于既有共享基座之上：

```
源串 (MiniML source)
   │  lex_ml        （ml_lexer.mbt，基于 @pc.Input 不可变游标）
   ▼
MlToken[] + span
   │  parse_ml      （ml_parser.mbt，递归下降 + 优先级）
   ▼
Expr  (携带 span)  ──── print_expr ───▶ 源串   （ml_printer.mbt，往返）
   │  infer         （infer.mbt，Algorithm W；调用 unify.mbt）
   ▼
TExpr (携带 Ty)  +  principal Ty
   │  optimize      （optimize.mbt，常量折叠 / 死 let 消除 / 可选 beta）
   ▼
TExpr' (良类型、语义等价)
   ├── eval_ml      （ml_eval.mbt，树遍历解释器）──▶ Val
   └── compile      （bytecode.mbt）──▶ Bytecode ──▶ vm.mbt (VM::run) ──▶ Val
```

两条求值路径（解释器 / 编译—执行）对相同良类型输入产出相等的 `Val`，由属性测试（13.4 / 6.5）守护。

### 与既有资产的关系（依赖方向）

```
                 ┌─────────────────────────────────────────┐
                 │   既有 MiniLet 骨架（冻结，0.1.0）        │
                 │   types / lexer / parser / printer /     │
                 │   semantics / release                    │
                 └───────────────┬─────────────────────────┘
                                 │  of_minilet 桥（只读提升，单向）
                                 ▼
   @pc ──▶ ┌──────────────────────────────────────────────┐ ◀── @release_meta
（不可变    │   MiniML 旁路新增层（本设计新增 .mbt）         │
 游标）     │   ml_types / ml_lexer / ml_parser /          │
           │   ml_printer / unify / infer / ml_eval /      │
   @infra_pbt（仅 test）│   bytecode / vm / optimize / pipeline / demo  │
           └──────────────────────────────────────────────┘
```

- **依赖单向**：新增层 `import` 既有同包符号与 `@pc` / `@release_meta`；既有骨架文件**不被修改**，不反向依赖新增层。
- **同包共享**：MiniML 新增文件与既有骨架同属包 `Suquster/moonbit-pathfinding/src/mini_compiler`，因此可直接复用既有 `Ast` / `BinOp` / `Diagnostic` / `DiagKind` 等类型与 `scan_int` / `scan_ident` / `is_alpha` 等纯助手（无需跨包导出）。
- `of_minilet` 是唯一的「既有 → 新增」语义桥，单向只读，不回写既有结构。

### 关键设计权衡（Design Trade-offs）

1. **旁路新增 vs 扩容既有枚举**：既有 `Ast` / `Value` 为 `pub(all)`，扩容其构造子会改变 `derive(Eq)` 语义并破坏既有 `match` 穷尽性与下游调用方。**决策**：旁路新增平行类型 `Expr` / `Ty` / `TExpr` / `Val`，以 `of_minilet` 桥接。代价是存在两套 AST，收益是 0.1.0 契约逐字冻结（R12）。
2. **scannerless 复用 vs 独立词法器**：既有 `parse` 采用「tokens→规范源串→@pc.Input 递归下降」的 scannerless 策略。MiniML 因含布尔/比较/箭头/关键字更多，且需为每个节点附 span，**决策**：`lex_ml` 产出携带 span 的 `MlToken[]`，`parse_ml` 直接在 `MlToken[]` 上递归下降（带 token 游标），不再回退源串——以获得精确 span（R1.2 / R8）。
3. **基于替换的合一 vs union-find**：union-find 性能更优但实现与可测性更重。**决策**：教学清晰优先，采用**不可变替换映射 + 复合（compose）**的经典 Algorithm W 表述（对标《Write You a Haskell》），并以幂等替换（R3.7）与 occurs-check（R3.6）保证正确与可终止。
4. **除零=0 全函数约定**：沿用 MiniLet 既有语义（`semantics.mbt` 已固定 `x/0=0`），使 `eval_ml` 为全函数、三后端一致、且「良类型不卡住」（R5.8）可被属性测试穷尽验证。该差异在对标小节显式声明。
5. **栈式 VM vs 寄存器 VM**：栈式 VM 编译规则更直观、与 TExpr 结构对应清晰（对标 Crafting Interpreters 的 clox / Appel）。**决策**：栈式，闭包以 `MkClosure` 指令 + 帧实现。

---

## 文件划分（Module Layout）

全部新增文件位于 `src/mini_compiler/`（与既有骨架同包），基准位于新增 `benches/` 子包。既有文件保持不变。

| 文件 | 职责 | 主要符号 | 覆盖需求 |
| --- | --- | --- | --- |
| `ml_types.mbt`（新增） | MiniML 旁路类型层 | `Span` `MlToken` `Expr` `Ty` `Scheme` `TExpr` `Val` `Subst` `TyEnv`；`of_minilet` | R1, R3, R4, R5 |
| `ml_lexer.mbt`（新增） | MiniML 词法分析 | `lex_ml` + 内部扫描助手（复用既有 `scan_int`/`scan_ident`） | R2.1, R8.1 |
| `ml_parser.mbt`（新增） | MiniML 递归下降语法分析（含优先级、span） | `parse_ml` + 各优先级层函数 | R2.2, R2.3, R8.2 |
| `ml_printer.mbt`（新增） | `Expr` → 源串（往返配套，足量括号化） | `print_expr` `erase_span` | R2.4, R2.5 |
| `unify.mbt`（新增） | 合一、替换、occurs-check | `unify` `apply_subst` `apply_scheme` `compose` `occurs` `ftv` | R3 |
| `infer.mbt`（新增） | Algorithm W（泛化/实例化/主类型/let rec） | `infer` `generalize` `instantiate` `infer_w` | R4, R8.3, R8.4 |
| `ml_eval.mbt`（新增） | 树遍历解释器（闭包/递归/除零=0） | `eval_ml` `eval_env` `scope_check_ml` | R5, R8.4, R8.6 |
| `bytecode.mbt`（新增） | 字节码模型与编译器 `TExpr → Bytecode` | `Instr` `Bytecode` `compile_ml` | R6.1, R6.2 |
| `vm.mbt`（新增） | 栈式虚拟机执行 `Bytecode → Val` | `VM` `VM::run` `Frame` | R6.3 |
| `text_backend.mbt`（新增，可选） | 额外文本后端（wasm 文本 / js 源） | `emit_wat` `emit_js` | R6.4 |
| `optimize.mbt`（新增） | 常量折叠 / 死 let 消除 / 可选 beta | `optimize` `const_fold` `dead_let_elim` `beta_reduce` | R7 |
| `pipeline.mbt`（新增） | 统一流水线入口（解释路径 / 编译路径） | `run_interp` `run_compiled` `PipelineResult` | R13 |
| `demo.mbt`（新增） | 旗舰端到端示例程序与各阶段产物 | `demo_factorial_src` `demo_fib_src` `run_demo` | R9 |
| `README.mbt.md`（扩充既有） | 可执行文档覆盖全链路 + 对标 + 边界 | 文档块 | R9.5, R11, R14.3 |
| `CHANGELOG.md`（更新既有） | SemVer 推进记录 | — | R14.5 |
| `benches/mini_compiler_bench/`（新增包） | lex/parse/infer/eval/compile+VM 基准 + guard | `bench_lex` … `bench_compile_vm` | R10 |

测试文件（旁路新增，`for "test"`）：`prop_lift_test.mbt`、`prop_ml_roundtrip_test.mbt`、`prop_unify_test.mbt`、`prop_infer_test.mbt`、`prop_eval_test.mbt`、`prop_compile_vm_test.mbt`、`prop_optimize_test.mbt`、`prop_scope_test.mbt`、`prop_pipeline_test.mbt`、`ml_unit_test.mbt`、`error_unit_test.mbt`。既有测试文件（`prop_roundtrip_test.mbt` 等）保持不变。

---

## 组件与接口（Components and Interfaces）

### 1. MiniML 旁路类型层（`ml_types.mbt`，R1）

```moonbit
/// 源码跨度：1 起始行列（沿用 @pc.Pos 约定）。挂载于每个 Expr 节点（R1.2）。
pub(all) struct Span {
  line : Int
  col : Int
} derive(Eq, Show)

/// MiniML 词法单元（携带 span）。旁路新增，独立于既有冻结 Token（R12.1）。
pub(all) enum MlToken {
  TkInt(Int, Span)
  TkBool(Bool, Span)
  TkIdent(String, Span)
  TkKw(String, Span)        // let / rec / in / if / then / else / fun / lambda
  TkOp(String, Span)        // + - * / < <= > >= == != && || ->
  TkLParen(Span)
  TkRParen(Span)
} derive(Eq)

/// 比较 / 逻辑运算符（旁路新增，不扩容既有 BinOp）。
pub(all) enum CmpOp { Lt; Le; Gt; Ge; Eq_; Ne } derive(Eq, Show)
pub(all) enum LogicOp { And; Or } derive(Eq, Show)

/// MiniML 抽象语法树。每个节点携带 span（R1.1, R1.2）。
/// 既有算术运算复用冻结的 BinOp（Add/Sub/Mul/Div），不重复定义。
pub(all) enum Expr {
  EInt(Int, Span)
  EBool(Bool, Span)
  EVar(String, Span)
  EArith(BinOp, Expr, Expr, Span)        // 复用既有 BinOp
  ECmp(CmpOp, Expr, Expr, Span)
  ELogic(LogicOp, Expr, Expr, Span)
  EIf(Expr, Expr, Expr, Span)
  ELam(String, Expr, Span)               // lambda / fun：单参抽象
  EApp(Expr, Expr, Span)
  ELet(String, Expr, Expr, Span)         // let x = e1 in e2
  ELetRec(String, Expr, Expr, Span)      // let rec f = e1 in e2
  ETuple(Array[Expr], Span)              // 可选元组（R1.5）
} derive(Eq)

/// MiniML 类型项（R1.3）。
pub(all) enum Ty {
  TyInt
  TyBool
  TyVar(Int)                 // 类型变量以稳定整数 id 表示
  TyFun(Ty, Ty)              // t1 -> t2
  TyTuple(Array[Ty])         // 可选元组类型（R1.5）
} derive(Eq, Show)

/// 类型方案 ∀a1..an. t（let 多态，R4）。
pub(all) struct Scheme {
  vars : Array[Int]          // 被全称量化的类型变量 id
  body : Ty
} derive(Eq)

/// 带类型标注 AST：与 Expr 同构，每节点附推断所得 Ty（R4.1）。
pub(all) enum TExpr {
  TEInt(Int, Ty, Span)
  TEBool(Bool, Ty, Span)
  TEVar(String, Ty, Span)
  TEArith(BinOp, TExpr, TExpr, Ty, Span)
  TECmp(CmpOp, TExpr, TExpr, Ty, Span)
  TELogic(LogicOp, TExpr, TExpr, Ty, Span)
  TEIf(TExpr, TExpr, TExpr, Ty, Span)
  TELam(String, TExpr, Ty, Span)
  TEApp(TExpr, TExpr, Ty, Span)
  TELet(String, TExpr, TExpr, Ty, Span)
  TELetRec(String, TExpr, TExpr, Ty, Span)
  TETuple(Array[TExpr], Ty, Span)
} derive(Eq)

/// MiniML 运行期值（R5）。闭包捕获定义处环境（词法作用域）。
pub(all) enum Val {
  VInt(Int)
  VBool(Bool)
  VClosure(String, TExpr, Env)     // 形参、函数体、捕获环境
  VTuple(Array[Val])               // 可选元组值（R1.5）
} derive(Eq)

/// 不可变求值环境：(名字, 值) 序列，最近绑定在末尾（遮蔽语义，R5.5）。
pub(all) struct Env {
  bindings : @immut/list.T[(String, Val)]
}

/// 替换：类型变量 id → 类型项 的有限映射（R3.4）。
pub(all) struct Subst {
  map : @immut/sorted_map.T[Int, Ty]
}

/// 类型环境：变量名 → 类型方案（R4.2）。
pub(all) struct TyEnv {
  schemes : @immut/list.T[(String, Scheme)]
}

/// 提升桥：既有 MiniLet Ast → 等价 MiniML Expr 子集（R1.4）。
/// 整数/变量/算术/let 一一对应；span 以哨兵 Span{line:0,col:0} 填充
/// （既有 Ast 无源码跨度）。
pub fn of_minilet(ast : Ast) -> Expr
```

**约束**：既有 `Token` / `BinOp` / `Ast` / `Type` / `TypedAst` / `Value` 等定义文件（`types.mbt`）**一行不改**（R12.1）。新增的比较/逻辑运算符、布尔、函数、元组全部落在 `ml_types.mbt`。

### 2. 词法分析（`ml_lexer.mbt`，R2.1 / R8.1）

```moonbit
/// MiniML 词法分析：源串 → 携带 span 的词法单元序列。
/// 基于 @pc.Input 不可变游标（peek/advance/pos，1 起始行列，R12.5）。
/// 复用既有 lexer.mbt 的 scan_int / scan_ident / is_alpha / is_digit / is_space。
/// 多字符算符（<= >= == != && || ->）按最长匹配扫描。
/// 遇非 MiniML 字母表字符 → 返回 LexError 诊断且不产出后续（R8.1）。
pub fn lex_ml(src : String) -> Result[Array[MlToken], Diagnostic]
```

关键字集合：`let` `rec` `in` `if` `then` `else` `fun` `lambda` `true` `false`。`true`/`false` 归一为 `TkBool`。

### 3. 语法分析（`ml_parser.mbt`，R2.2 / R2.3 / R8.2）

递归下降，运算符优先级自低到高严格遵循 R2.2：

```
expr    ::= "let" ["rec"] IDENT "=" expr "in" expr
          | "if" expr "then" expr "else" expr
          | ("lambda" | "fun") IDENT "->" expr
          | or_expr
or_expr  ::= and_expr ("||" and_expr)*           // 左结合
and_expr ::= cmp_expr ("&&" cmp_expr)*           // 左结合
cmp_expr ::= add_expr (("<"|"<="|">"|">="|"=="|"!=") add_expr)?   // 非结合
add_expr ::= mul_expr (("+"|"-") mul_expr)*      // 左结合
mul_expr ::= app_expr (("*"|"/") app_expr)*      // 左结合
app_expr ::= atom atom*                          // 函数应用，左结合
atom     ::= INT | BOOL | IDENT | "(" expr ")" | "(" expr ("," expr)+ ")"
```

```moonbit
/// 词法单元序列 → 携带 span 的 Expr（R2.2）。在 MlToken 数组上以
/// 不可变 token 游标递归下降；分支失败丢弃推进后的游标（回溯）。
/// 顶层解析后仍有未消费的非空白 token → SyntaxError 且不产树（R2.3）。
pub fn parse_ml(tokens : Array[MlToken]) -> Result[Expr, Diagnostic]
```

每个产生式在构造节点时取**起始 token 的 span**作为节点 span，使诊断可定位（R8.2/8.3/8.4）。

### 4. 打印器（`ml_printer.mbt`，R2.4 / R2.5）

```moonbit
/// Expr → MiniML 源串。对二元/比较/逻辑/应用节点完全括号化以消除优先级歧义，
/// 保证「打印再解析」与优先级/结合性无关地还原同一树形（R2.4）。
pub fn print_expr(e : Expr) -> String

/// 去除全部 span（置零），用于往返等价比较（R2.5 / R1.6 / R12.7）。
pub fn erase_span(e : Expr) -> Expr
```

### 5. 合一与替换（`unify.mbt`，R3）

```moonbit
/// 对类型项施加替换：递归替换其中出现的每个被映射类型变量（R3.4）。
pub fn apply_subst(s : Subst, t : Ty) -> Ty

/// 对类型方案施加替换（仅替换其自由变量，保护被量化变量）。
pub fn apply_scheme(s : Subst, sc : Scheme) -> Scheme

/// 替换复合：compose(s1, s2) 等价于先施 s2 再施 s1。
pub fn compose(s1 : Subst, s2 : Subst) -> Subst

/// 类型项的自由类型变量集合。
pub fn ftv(t : Ty) -> @immut/sorted_set.T[Int]

/// occurs-check：类型变量 v 是否出现于类型项 t 中（R3.2 / R3.6）。
pub fn occurs(v : Int, t : Ty) -> Bool

/// 合一两个类型项，产出最一般合一子（mgu）或类型错误诊断（R3.1）。
/// - 合一函数类型 a1->b1 与 a2->b2：先合一参数、再在所得替换下合一结果，
///   返回二者复合替换（R3.3）。
/// - 合一类型变量与类型项：先做 occurs-check，出现且不等则报错（R3.2）。
/// 失败时返回 kind=TypeError、msg 标注冲突两类型的 Diagnostic（R8.3）。
pub fn unify(t1 : Ty, t2 : Ty) -> Result[Subst, Diagnostic]
```

### 6. Algorithm W 类型推断（`infer.mbt`，R4）

```moonbit
/// 实例化类型方案：以新鲜类型变量替换其被量化变量（R4.3）。
pub fn instantiate(sc : Scheme, fresh : FreshGen) -> Ty

/// 泛化：把类型 t 中不被环境 env 约束的自由类型变量全称量化为方案（R4.2）。
pub fn generalize(env : TyEnv, t : Ty) -> Scheme

/// Algorithm W 核心：自底向上同时产出替换与类型。
/// 处理 let（泛化）、let rec（先以新鲜变量引入 f，R4.6）、
/// if（条件合一 Bool、两分支互相合一，R4.4）、
/// 应用（引入新鲜 r，f 合一 (typeof e)->r，R4.5）。
fn infer_w(env : TyEnv, e : Expr, fresh : FreshGen) -> Result[(Subst, TExpr), Diagnostic]

/// 推断入口：成功返回携带类型标注的 TExpr 与其主类型（R4.1）。
/// 失败返回携带 span 与冲突类型的 TypeError 诊断（R4.7 / R8.3）。
pub fn infer(e : Expr) -> Result[(TExpr, Ty), Diagnostic]

/// 取 TExpr 根节点类型（主类型）。
pub fn type_of(te : TExpr) -> Ty
```

`FreshGen` 为新鲜类型变量发生器（封装一个可变计数器），保证类型变量 id 全局唯一。

### 7. 树遍历解释器（`ml_eval.mbt`，R5）

```moonbit
/// 求值：对带类型标注 TExpr 做树遍历解释，以不可变环境承载绑定（R5.1）。
/// - 函数抽象 → 捕获当前环境的 VClosure（R5.2，词法作用域）。
/// - 应用 → 在闭包捕获环境上扩展形参绑定后求值体（R5.3）。
/// - 除法除零 → VInt(0)（沿用 MiniLet 约定，R5.4，保证全函数）。
/// - 同名内层遮蔽外层（R5.5）。
/// - let rec → 在环境中引入自指闭包，使其体内可递归调用（R5.6）。
pub fn eval_ml(te : TExpr) -> Val

/// 在给定环境求值（内部递归助手）。
fn eval_env(te : TExpr, env : Env) -> Val

/// 作用域检查：返回 Expr 的全部变量引用是否都能解析到某绑定（R8.6）。
/// 用于在推断前后独立验证闭合性，并支撑作用域属性测试。
pub fn scope_check_ml(e : Expr) -> Result[Unit, Diagnostic]
```

`let rec` 闭包的自指通过「在扩展环境中先放入指向自身函数体与该扩展环境的闭包」实现（环境为不可变列表，自指以延迟查找名字而非物理回边实现，保证三后端一致且无循环引用）。

### 8. 字节码编译后端（`bytecode.mbt`，R6.1 / R6.2）

```moonbit
/// 栈式虚拟机指令集（旁路新增，R6.1）。
pub(all) enum Instr {
  PushInt(Int)            // 压入整型常量
  PushBool(Bool)          // 压入布尔常量
  LoadVar(String)         // 变量取值（从帧环境）
  Arith(BinOp)            // 弹两栈顶做算术，压回结果（除零=0）
  Cmp(CmpOp)              // 比较，压回布尔
  Logic(LogicOp)          // 逻辑，压回布尔
  JumpIfFalse(Int)        // 条件跳转（if）
  Jump(Int)               // 无条件跳转
  MkClosure(String, Bytecode)   // 构造闭包（形参、体字节码、捕获当前环境）
  Call                    // 调用：弹实参与闭包，建新帧执行
  Ret                     // 返回：结束当前帧，结果留栈顶
  MkTuple(Int)            // 构造 n 元组（可选）
}

/// 线性字节码序列。
pub(all) struct Bytecode {
  instrs : Array[Instr]
} derive(Eq)

/// 编译：TExpr → 覆盖全部子表达式的线性 Bytecode，不留未编译节点（R6.2）。
pub fn compile_ml(te : TExpr) -> Bytecode
```

> 注：既有 `compile(TypedAst, Backend) -> Bytes` 桩签名**冻结不动**（R12.2）；MiniML 编译路径以**新函数** `compile_ml` 提供，避免与既有契约冲突。

### 9. 栈式虚拟机（`vm.mbt`，R6.3）

```moonbit
/// 调用帧：局部环境 + 返回地址。
struct Frame {
  env : Env
  return_pc : Int
}

/// 栈式虚拟机：以操作数栈与调用帧解释 Bytecode（R6.3）。
pub struct VM {
  mut stack : Array[Val]
  mut frames : Array[Frame]
}

/// 执行字节码，程序结束时产出栈顶 Val（R6.3）。
pub fn VM::run(bc : Bytecode, env : Env) -> Val
```

### 10. 额外文本后端（`text_backend.mbt`，可选，R6.4）

```moonbit
/// 渲染 TExpr 为 WebAssembly 文本格式串（仅供展示，不保证可被工具链消费）。
pub fn emit_wat(te : TExpr) -> String

/// 渲染 TExpr 为 JavaScript 源串（仅供展示）。
pub fn emit_js(te : TExpr) -> String
```

### 11. AST 优化（`optimize.mbt`，R7）

```moonbit
/// 常量折叠：仅由常量构成的算术/比较/逻辑子表达式预求值为字面量节点（R7.1）。
pub fn const_fold(e : Expr) -> Expr

/// 死 let 消除：删除绑定变量在 body 中从不被引用且绑定体无可观察副作用的
/// let，并以其 body 取代之（R7.2）。MiniML 纯求值，故「无副作用」恒成立。
pub fn dead_let_elim(e : Expr) -> Expr

/// 可选 beta 化简：对字面 lambda 的应用 (λx.e) v 做捕获避免替换（R7.3）。
pub fn beta_reduce(e : Expr) -> Expr

/// 组合优化管线：const_fold ∘ dead_let_elim（默认不含 beta）。保证输出仍良类型
/// （R7.4）且与输入语义等价（R7.5）。
pub fn optimize(e : Expr) -> Expr
```

### 12. 统一流水线（`pipeline.mbt`，R13）

```moonbit
/// 流水线结果：值或诊断。
pub enum PipelineResult {
  Produced(Val)
  Failed(Diagnostic)
}

/// 解释路径：lex_ml → parse_ml → infer → (可选)optimize → eval_ml。
/// 任一前置阶段返回诊断则短路并向上传播（R13.1 / R13.2）。
pub fn run_interp(src : String, optimize~ : Bool = false) -> PipelineResult

/// 编译—执行路径：lex_ml → parse_ml → infer → (可选)optimize → compile_ml → VM::run。
/// 与解释路径接受相同的良类型输入（R13.3）。
pub fn run_compiled(src : String, optimize~ : Bool = false) -> PipelineResult
```

### 13. 旗舰端到端示例（`demo.mbt`，R9）

```moonbit
/// 阶乘示例（let rec + if + 比较 + 应用）。
pub let demo_factorial_src : String =
  "let rec fact = fun n -> if n <= 1 then 1 else n * fact (n - 1) in fact 5"

/// 斐波那契示例。
pub let demo_fib_src : String =
  "let rec fib = fun n -> if n <= 1 then n else fib (n - 1) + fib (n - 2) in fib 10"

/// 跑通示例并返回各阶段产物（推断类型、优化后形态、解释结果、VM 结果）。
pub fn run_demo(src : String) -> DemoTrace
```

---

## 数据模型（Data Models）

### 类型与值的关系

| 阶段 | 输入 | 输出 | 关键不变式 |
| --- | --- | --- | --- |
| `lex_ml` | `String` | `Array[MlToken]` | 每 token 携带准确 span |
| `parse_ml` | `Array[MlToken]` | `Expr` | 节点 span = 起始 token span；优先级正确 |
| `infer` | `Expr` | `(TExpr, Ty)` | TExpr 同构于 Expr 且每节点带 Ty；主类型在最终替换下封闭（R4.9） |
| `optimize` | `Expr`（或 `TExpr`） | `Expr`（语义等价） | 良类型保持（R7.4）；语义保持（R7.5） |
| `eval_ml` | `TExpr` | `Val` | 确定性（R5.7）；不卡住（R5.8） |
| `compile_ml` | `TExpr` | `Bytecode` | 覆盖全部子表达式（R6.2） |
| `VM::run` | `Bytecode` | `Val` | 与解释器等价（R6.5） |

### 替换与类型环境

- `Subst` 用不可变有序映射（`@immut/sorted_map`）表示，保证 `compose` 与 `apply_subst` 无副作用、可比较、三后端一致。
- 幂等性（R3.7）：`unify` 产出的替换经规范化（对值域反复施加直至不动点）后满足 `apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)`。
- `TyEnv` 用不可变列表，`let` 引入新方案时前插，查找时取最近（遮蔽）。

### 发布元数据（复用既有 `release.mbt`，R14.5）

- 既有 `release.mbt` 的 `mini_compiler_version` 自 `0.1.0` 推进为本次旗舰深化的次版本（如 `0.2.0`）。
- `release_info_with_gates(QualityGates)` 复用既有签名，按三后端测试 / 属性测试 / 可执行文档三要素聚合 `release_ready`（R14.6）。

---

## 错误处理（Error Handling，R8）

全部错误统一复用既有 `Diagnostic { kind; line; col; msg }` 与 `DiagKind`（`LexError` / `SyntaxError` / `TypeError`），不新增诊断类型（R12.1）。MiniML 阶段填入**真实 span 行列**（既有 MiniLet `check` 因 `Ast` 无 span 使用 `(0,0)` 哨兵，MiniML 则有精确位置）。

| 阶段 | 触发条件 | kind | 位置 | 消息要点 |
| --- | --- | --- | --- | --- |
| `lex_ml` | 非 MiniML 字母表字符（R8.1） | `LexError` | 该字符行列 | 非法字符 |
| `parse_ml` | 不符文法 / 顶层有残余 token（R8.2, R2.3） | `SyntaxError` | 出错 token 行列 | 期望何种结构 |
| `infer` / `unify` | 不可合一（R8.3） | `TypeError` | 出错节点 span | 标注冲突两类型 |
| `infer` / `scope_check_ml` | 引用未绑定变量（R8.4） | `TypeError` | 该变量 span | 标注变量名 |

- **短路传播**（R13.2）：`run_interp` / `run_compiled` 一旦某阶段返回 `Err(d)`，立即以 `Failed(d)` 短路，不进入后续阶段。
- **可选错误恢复**（R8.5）：`parse_ml` 可在 `WHERE` 启用恢复模式下跳到同步点（`in` / `)` / `then` / `else`）继续解析，单次收集多条诊断；默认关闭以保持往返性质简单。
- **全函数求值**：`eval_ml` 不抛错——经 `infer` 的程序无自由变量、除零=0，保证「良类型不卡住」（R5.8）。

---

## 测试策略（Testing Strategy）

### 双轨测试

- **属性测试（PBT）**：复用 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all` / `round_trip`（R12.6），每条核心属性 **≥100 次迭代**（R14.2）。需要 MiniML `Expr` 生成器、良类型 `Expr` 生成器（按类型自顶向下生成保证良类型）、`Ty` 生成器、可合一类型对生成器、幂等 `Subst` 生成器、MiniLet `Ast` 生成器。
- **单元测试**：覆盖具体样例、边界（除零、空白、深嵌套）、错误路径（各类诊断的 kind/line/col/msg）、向后兼容黄金样例（R12.3）。
- **可执行文档**：`README.mbt.md` 经 `moon test *.mbt.md` 验证全链路示例（R9.5 / R14.3）。

### 三后端一致（R14.1）

同一套件在 `wasm-gc` / `js` / `native` 运行；任一后端输出分歧判定为构建失败。**native 后端测试/基准前必须先执行：**

```bash
export LIBRARY_PATH=/usr/lib64:/usr/lib
```

该约定写入 `README.mbt.md`、基准脚本与 CHANGELOG（R10.4 / R14.4）。

### 基准（R10）

`benches/mini_compiler_bench/` 覆盖 lex / parse / infer / eval / compile+VM 五类工作负载，在递增规模程序（节点数 / 绑定数 / 应用深度递增）上运行，输出含机器标识、后端目标、规模参数与计时统计的 JSON/Markdown 工件，并与基线中位数比较、超容差给出回归失败报告。

### 属性测试标签格式

每条属性测试以注释标注，便于追溯设计属性：

```
**Feature: mini-compiler, Property {number}: {property_text}**
```

---

## paper-to-code 可追溯与开源对标（R11）

### 论文 / 教材追溯

| 组件 | 来源 |
| --- | --- |
| Hindley-Milner 类型推断、Algorithm W | Hindley (1969)、Milner (1978)、Damas & Milner (1982) |
| 合一、occurs-check、替换 | Robinson 合一；Damas-Milner Algorithm W |
| 类型系统与求值模型 | Pierce《Types and Programming Languages》 |
| 树遍历解释器、闭包、字节码 VM | Nystrom《Crafting Interpreters》（jlox/clox） |
| 编译链路与栈式代码生成 | Appel《Modern Compiler Implementation》 |
| 整体工程组织与 HM 实现风格 | 《Write You a Haskell》 |

### 开源对标（covering 类型推断 / 求值 / 编译模型差异）

| 维度 | OCaml | Haskell（GHC/WYAH） | Rust 教学编译器 | 本方向 Mini_Compiler |
| --- | --- | --- | --- | --- |
| 类型推断 | HM + 行多态/模块 | HM + 类型类 + 约束求解 | 多为单态/无 HM | HM/Algorithm W + let 多态（无类型类） |
| 求值 | 编译为原生/字节码 | 惰性图归约 | 取决于实现 | 严格、树遍历 + 栈式字节码 VM |
| 编译目标 | 原生 / bytecode | 原生（STG） | 原生/LLVM | 内存栈式 VM（不生成原生码） |
| 除零 | 异常 | 异常 | panic | 定义为 0（全函数，三后端一致） |
| 求值顺序 | 严格 | 惰性 | 严格 | 严格、左到右、确定性 |

### 显式差异声明（R11.5）

- **除零 = 0**：与 OCaml/Haskell/Rust 的异常/panic 不同，定义为返回 `0`，以保证 `eval` 为全函数、求值确定、三后端一致，并使「良类型不卡住」可被属性测试穷尽验证。
- **可选特性取舍**：元组、beta 化简、错误恢复、文本后端均为 `WHERE` 可选，默认关闭以保持核心性质（往返、两路一致）简单可测。
- **实现边界**：见「概述 → 实现边界」——内存栈式抽象机，不生成原生可执行、不汇编/链接、不绑定 ISA。

---

## 向后兼容策略（R12）

1. **类型冻结**：`types.mbt` 中既有 `pub(all)` 枚举/结构（`Token` / `BinOp` / `Ast` / `Type` / `TypedAst` / `Value` / `Diagnostic` / `DiagKind` / `Backend`）字段、构造子、`derive` 一行不改（R12.1）。
2. **接口冻结**：`lex` / `parse` / `check` / `eval` / `print_ast` / `compile` / `Diagnostic::new` 的公开签名与逐字行为不变（R12.2 / R12.3）；新增能力一律以**新函数**（`lex_ml` / `parse_ml` / `infer` / `eval_ml` / `compile_ml` …）旁路提供（R12.4）。
3. **基座复用**：MiniML 词法/语法构建于 `@pc.Input`（R12.5）；属性测试复用 `@infra_pbt`（R12.6）。
4. **黄金样例**：固定 MiniLet 程序断言 `lex`/`parse`/`check`/`eval`/`print_ast` 产物与 `0.1.0` 逐字一致（R12.3）。
5. **mbti 守护**：`pkg.generated.mbti` 中既有条目保持不变（只新增条目）。

---

## 正确性属性（Correctness Properties）

*属性是应在系统所有有效执行中保持为真的特征或行为——是介于人类可读规格与机器可验证保证之间的桥梁。* 下列属性源自上文 prework 分析（已去冗余），每条以全称量化（「对任意 / 对所有」）陈述，并标注其验证的需求条款。全部以 `@infra_pbt` 实现、每条 **≥100 次迭代**（R14.2）。

### Property 1：提升保持语义（of_minilet）

对任意由生成器产生的 MiniLet `Ast`，经 `of_minilet` 提升为 MiniML `Expr` 后按 MiniML 语义（`infer` → `eval_ml`）求值所得整数结果，与既有 MiniLet `eval(check(ast))` 求值所得 `Value` 相等。

**Validates: Requirements 1.6**

### Property 2：MiniML 解析 / 打印往返

对任意由生成器产生的合法 `Expr` `e`，对 `print_expr(e)` 重新执行 `lex_ml` → `parse_ml` 所得 `Expr` 在去除 span 后与 `erase_span(e)` 相等。

**Validates: Requirements 2.5**

### Property 3：合一正确性

对任意由生成器产生的可合一类型项对 `(t1, t2)`，`unify(t1, t2)` 成功且把所得替换分别施加于 `t1` 与 `t2` 后得到的类型项相等。

**Validates: Requirements 3.5**

### Property 4：occurs-check 正确性

对任意类型变量 `v` 与任意包含 `v` 且不等于 `v` 的类型项 `t`，`unify(TyVar(v), t)` 失败并返回 `TypeError` 诊断（拒绝构造无限类型）。

**Validates: Requirements 3.6**

### Property 5：替换幂等

对任意由生成器产生的（规范化）替换 `s` 与任意类型项 `t`，对 `t` 施加 `s` 一次与施加两次结果相等：`apply_subst(s, apply_subst(s, t)) == apply_subst(s, t)`。

**Validates: Requirements 3.7**

### Property 6：主类型存在性

对任意由生成器产生的良类型 `Expr`，`infer` 成功并返回一个类型。

**Validates: Requirements 4.8**

### Property 7：推断幂等（类型在最终替换下封闭）

对任意由生成器产生的良类型 `Expr`，对推断所得类型再施加推断结果替换不改变该类型。

**Validates: Requirements 4.9**

### Property 8：求值确定性

对任意由生成器产生的良类型 `Expr`，对同一程序重复求值（`eval_ml`）得到相等结果。

**Validates: Requirements 5.7**

### Property 9：良类型不卡住（类型可靠性）

对任意由生成器产生的良类型 `Expr`，`eval_ml` 要么产出一个 `Val`、要么按除零等全函数约定终止，而不进入无规则可用的卡住状态。

**Validates: Requirements 5.8**

### Property 10：编译—执行等价（语义保持）

对任意由生成器产生的良类型 `Expr`，`VM::run(compile_ml(infer(e)))` 所得 `Val` 与树遍历解释器 `eval_ml(infer(e))` 所得 `Val` 相等。

**Validates: Requirements 6.5**

### Property 11：优化保持可推断性

对任意由生成器产生的良类型 `Expr`，`optimize(e)` 后仍可被 `infer` 成功推断且其主类型与优化前一致。

**Validates: Requirements 7.4**

### Property 12：优化保持语义

对任意由生成器产生的良类型 `Expr`，常量折叠与死 `let` 消除前后程序的求值结果相等：`eval_ml(infer(optimize(e))) == eval_ml(infer(e))`。

**Validates: Requirements 7.5**

### Property 13：捕获避免替换正确

对任意由生成器产生的、含字面 `lambda` 应用的良类型 `Expr`，在启用 beta 化简时，化简使用捕获避免替换，从而 `eval_ml` 结果与化简前相等。

**Validates: Requirements 7.6**

### Property 14：作用域检查正确

对任意由生成器产生的 `Expr`，`scope_check_ml` 恰好接受其全部变量引用都能解析到某绑定的程序、并拒绝含自由变量的程序。

**Validates: Requirements 8.6**

### Property 15：MiniLet 向后兼容

对任意由生成器产生的 MiniLet `Ast`，「打印再解析再检查再求值」往返结果与 `0.1.0` 骨架既有行为一致：`eval(check(parse(lex(print_ast(ast)))))` 与 `eval(check(ast))` 相等（且中途无诊断）。

**Validates: Requirements 12.7**

### Property 16：端到端两路一致

对任意由生成器产生的良类型 MiniML 源串，解释路径 `run_interp(src)` 与编译—执行路径 `run_compiled(src)` 对同一源串产出相等的 `Val`。

**Validates: Requirements 13.4**

---

## 需求覆盖映射（Requirements Traceability）

| 需求 | 设计落点 | 验证方式 |
| --- | --- | --- |
| R1 旁路语言层 + of_minilet | `ml_types.mbt` | Property 1 + 单元 |
| R2 词法/语法 + 往返 | `ml_lexer/ml_parser/ml_printer` | Property 2 + 单元 |
| R3 合一/替换/occurs-check | `unify.mbt` | Property 3/4/5 + 单元 |
| R4 Algorithm W | `infer.mbt` | Property 6/7 + 单元 |
| R5 解释器 | `ml_eval.mbt` | Property 8/9 + 单元 |
| R6 字节码 + VM | `bytecode.mbt/vm.mbt` | Property 10 + 单元 |
| R7 优化 | `optimize.mbt` | Property 11/12/13 + 单元 |
| R8 错误处理 | 各阶段 + `Diagnostic` | Property 14 + 错误单元 |
| R9 端到端示例 | `demo.mbt` + `README.mbt.md` | 可执行文档（SMOKE） |
| R10 基准 | `benches/mini_compiler_bench/` | 基准运行 + guard |
| R11 可解释性/对标 | `README.mbt.md` 文档小节 | 文档审查 |
| R12 向后兼容 | 冻结既有文件 + 旁路新增 | Property 15 + 黄金样例 + mbti 守护 |
| R13 流水线集成 | `pipeline.mbt` | Property 16 + 单元 |
| R14 质量门禁 | 三后端/PBT/文档/SemVer/`release.mbt` | CI 聚合门禁 |
