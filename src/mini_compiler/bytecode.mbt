// bytecode.mbt —— MiniML 字节码模型与编译器（design.md §「组件与接口 →
// 8. 字节码编译后端」，覆盖 R6.1 / R6.2 与 R12.4）。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增；MiniML 编译路径以**新函数**
// `compile_ml(TExpr) -> Bytecode` 提供，**绝不触碰**既有 `compile(TypedAst,
// Backend) -> Bytes` 桩（R12.2 / R12.4）。
//
// ===========================================================================
// 字节码契约（Bytecode Contract）—— 任务 8.2 的栈式虚拟机 `VM::run` 必须与此
// 处逐条匹配。以下约定为编译器与 VM 之间的唯一接口规范。
// ===========================================================================
//
// 【执行模型】
//   VM 维护一个**操作数栈**与一组**调用帧**。每条指令在「当前帧环境」下对操作
//   数栈做就地变换。程序结束（顶层字节码执行到末尾）时，栈顶 `Val` 即为结果。
//
// 【跳转语义 —— 绝对索引】
//   `JumpIfFalse(target)` 与 `Jump(target)` 的 `target` 是**绝对索引**，即直接
//   指向**当前 `Bytecode.instrs` 数组**中的下标（而非相对偏移）。
//     * `JumpIfFalse(t)`：弹出栈顶布尔，若为 `false` 则把程序计数器置为 `t`，
//       否则顺序执行下一条。
//     * `Jump(t)`：无条件把程序计数器置为 `t`。
//   选择绝对索引是因为 `compile_ml` 在单个扁平数组上以「回填（backpatch）」技术
//   生成跳转，绝对索引最直观、最少出错。
//
// 【操作数栈求值次序 —— 左操作数先压、右操作数后压】
//   对二元节点 `l op r`，先 `emit(l)` 再 `emit(r)`，故运行时**右操作数在栈顶、
//   左操作数在其下**。VM 执行 `Arith` / `Cmp` 时：先弹出得右操作数 `b`，再弹出
//   得左操作数 `a`，计算 `a op b`，压回结果。`Logic` 同理（`a op b`）。
//     * `Arith(op)`：弹 b、弹 a，压 `VInt(a op b)`；**除零定义为 0**（与
//       ml_eval.mbt 的 `ml_apply_arith` 一致，R5.4）。
//     * `Cmp(op)`：弹 b、弹 a，压 `VBool(a op b)`。
//     * `Logic(op)`：弹 b、弹 a，压 `VBool(a op b)`（`&&` / `||`，不短路，与
//       ml_eval 一致——MiniML 无副作用故无可观察差异）。
//
// 【调用约定 —— Call 弹「实参在栈顶、闭包在其下」】
//   对应用 `f a`：先 `emit(f)`（压入闭包，位置较深）再 `emit(a)`（压入实参，位
//   于栈顶），最后 `Call`。VM 执行 `Call` 时：
//     1. 弹出栈顶得**实参** `arg`；
//     2. 弹出次顶得**闭包** `clo`；
//     3. 以 `clo` 捕获的环境扩展 `param -> arg`（对递归闭包还需绑定自身名，见
//        下）建立新帧，跳入闭包体字节码执行；
//     4. 闭包体以 `Ret` 结束，把体的结果留在调用者栈顶、弹出该帧。
//
// 【闭包体 Ret 约定】
//   `compile_ml` 为**每个**闭包体（`MkClosure` / `MkRecClosure` 携带的
//   `Bytecode`）在末尾追加一条 `Ret`。VM 见 `Ret` 即结束当前帧：体求值结果（此
//   时位于体的操作数栈顶）成为调用处的栈顶值。
//
// 【闭包构造 —— MkClosure 捕获「当前帧环境」】
//   `MkClosure(param, body)`：在**当前帧环境**快照下构造一个闭包值压栈。闭包被
//   `Call` 时在该捕获环境上扩展 `param -> arg` 求值 `body`（词法作用域，与
//   ml_eval 的 `VClosure` 语义一致，R5.2 / R5.3）。
//
// 【递归闭包 —— MkRecClosure 自指绑定】
//   `MkRecClosure(recName, param, body)`：构造一个**递归闭包**压栈。它与
//   `MkClosure` 的唯一区别是：被 `Call` 时，新帧环境除 `param -> arg` 外，还把
//   `recName` 绑定到**该递归闭包自身**，使 `body` 内对 `recName` 的引用解析回
//   自己，从而支持任意深度递归。这与 ml_eval.mbt 中 `let rec` 的「延迟按名查找
//   重建闭包」语义等价（见 `ml_env_lookup` / `bind_rec`），但以一条专用指令承载
//   自指，保持 VM 实现简单、三后端一致、无物理回边。
//
//   说明：指令集任务给定为「至少覆盖」一组指令，允许为正确性追加指令。本实现
//   追加 `MkRecClosure` 以让 `let rec` 在仅有给定指令时也能干净、正确地表达
//   （单纯 `MkClosure` 无法让闭包在其体内引用到自身）。任务 8.2 的 VM 必须实现
//   此指令。
//
// 【降低（lowering）规则总览】
//   `compile_ml` 以一个递归 `emit(te, out)` 把 `TExpr` 线性化进单个
//   `Array[Instr]`，按**求值次序**追加指令，覆盖**全部**子表达式、不留未编译
//   节点（R6.2）。各节点降低规则见下方 `emit` 实现的逐条注释。其中：
//     * `let x = e1 in e2` 降低为「立即应用的闭包」`(fun x -> e2) e1`，复用
//       `Call` 语义而无需新增 Let 指令。
//     * `let rec f = (fun x -> body) in e2` 降低为
//       `(fun f -> e2) (MkRecClosure f x body)`；若 `e1` 非函数抽象则退化为
//       普通 let 降低（与 ml_eval 的 `bind_rec` 行为对应）。

// ---------------------------------------------------------------------------
// 字节码模型（R6.1）
// ---------------------------------------------------------------------------

///|
/// 栈式虚拟机指令集（旁路新增，R6.1）。
///
/// `Instr` 与 `Bytecode` 相互递归（`MkClosure` / `MkRecClosure` 内含
/// `Bytecode`，而 `Bytecode` 含 `Array[Instr]`）——MoonBit 支持此类相互递归
/// 的代数数据类型。二者均 `derive(Eq)` 以支撑字节码的结构相等断言与属性测试。
pub(all) enum Instr {
  /// 压入整型常量。
  PushInt(Int)
  /// 压入布尔常量。
  PushBool(Bool)
  /// 从当前帧环境按名取值压栈。
  LoadVar(String)
  /// 弹右、弹左做算术，压回结果（除零=0）。
  Arith(BinOp)
  /// 弹右、弹左做比较，压回布尔。
  Cmp(CmpOp)
  /// 弹右、弹左做逻辑，压回布尔。
  Logic(LogicOp)
  /// 弹栈顶布尔，为 `false` 时跳到绝对索引 `target`。
  JumpIfFalse(Int)
  /// 无条件跳到绝对索引 `target`。
  Jump(Int)
  /// 以当前帧环境构造闭包（形参、体字节码）压栈。
  MkClosure(String, Bytecode)
  /// 构造递归闭包（自身名、形参、体字节码）压栈：被调用时额外把自身名绑定到自己。
  MkRecClosure(String, String, Bytecode)
  /// 调用：弹实参（栈顶）与闭包（次顶），建新帧执行其体。
  Call
  /// 返回：结束当前帧，体结果留调用处栈顶。
  Ret
  /// 弹出栈顶 `n` 个值，构造 `n` 元组压栈（可选特性 R1.5）。
  MkTuple(Int)
} derive(Eq)

///|
/// 线性字节码序列：`instrs` 为按求值次序排列的指令数组；跳转目标为其绝对下标。
pub(all) struct Bytecode {
  instrs : Array[Instr]
} derive(Eq)

// ---------------------------------------------------------------------------
// 编译器：TExpr -> Bytecode（R6.2）
// ---------------------------------------------------------------------------

///|
/// 把单个 `TExpr` 线性化进 `out`，按求值次序追加指令（覆盖全部子表达式，R6.2）。
fn emit(te : TExpr, out : Array[Instr]) -> Unit {
  match te {
    // 常量：直接压栈。
    TEInt(n, _, _) => out.push(PushInt(n))
    TEBool(b, _, _) => out.push(PushBool(b))
    // 变量：从当前帧环境取值。
    TEVar(x, _, _) => out.push(LoadVar(x))
    // 二元算术 / 比较 / 逻辑：先左后右，再运算（右在栈顶）。
    TEArith(op, l, r, _, _) => {
      emit(l, out)
      emit(r, out)
      out.push(Arith(op))
    }
    TECmp(op, l, r, _, _) => {
      emit(l, out)
      emit(r, out)
      out.push(Cmp(op))
    }
    TELogic(op, l, r, _, _) => {
      emit(l, out)
      emit(r, out)
      out.push(Logic(op))
    }
    // 条件：绝对索引回填。
    //   emit(c); JumpIfFalse(else_start); emit(then); Jump(end); <else_start> emit(else); <end>
    TEIf(c, a, b, _, _) => {
      emit(c, out)
      let jf = out.length()
      out.push(JumpIfFalse(0)) // 占位，稍后回填为 else 分支起点
      emit(a, out)
      let j = out.length()
      out.push(Jump(0)) // 占位，稍后回填为 if 整体之后位置
      let else_start = out.length()
      emit(b, out)
      let end_pos = out.length()
      // 回填（数组可变，绝对索引语义）。
      out[jf] = JumpIfFalse(else_start)
      out[j] = Jump(end_pos)
    }
    // 函数抽象：编译体为独立 Bytecode（末尾追加 Ret），压 MkClosure。
    TELam(x, body, _, _) => {
      let bb : Array[Instr] = []
      emit(body, bb)
      bb.push(Ret)
      out.push(MkClosure(x, Bytecode::{ instrs: bb }))
    }
    // 应用：先压闭包（深）、再压实参（顶），Call。
    TEApp(f, a, _, _) => {
      emit(f, out)
      emit(a, out)
      out.push(Call)
    }
    // let x = e1 in e2  ≡  (fun x -> e2) e1（复用 Call 语义）。
    TELet(x, e1, e2, _, _) => {
      let bb : Array[Instr] = []
      emit(e2, bb)
      bb.push(Ret)
      out.push(MkClosure(x, Bytecode::{ instrs: bb }))
      emit(e1, out)
      out.push(Call)
    }
    // let rec f = e1 in e2：
    //   * e1 为函数抽象 → (fun f -> e2) (MkRecClosure f x body)；
    //   * e1 非函数抽象 → 退化为普通 let 降低（与 ml_eval 的 bind_rec 对应）。
    TELetRec(f, e1, e2, _, _) => {
      let e2bb : Array[Instr] = []
      emit(e2, e2bb)
      e2bb.push(Ret)
      out.push(MkClosure(f, Bytecode::{ instrs: e2bb }))
      match e1 {
        TELam(px, pbody, _, _) => {
          let pbb : Array[Instr] = []
          emit(pbody, pbb)
          pbb.push(Ret)
          out.push(MkRecClosure(f, px, Bytecode::{ instrs: pbb }))
        }
        _ => emit(e1, out)
      }
      out.push(Call)
    }
    // 元组：依次压入各分量，再构造 n 元组。
    TETuple(items, _, _) => {
      for it in items {
        emit(it, out)
      }
      out.push(MkTuple(items.length()))
    }
  }
}

///|
/// 编译入口（R6.2）：把整棵带类型标注语法树 `TExpr` 编译为覆盖其全部子表达式的
/// 线性 `Bytecode`，不留未编译节点。以**新函数** `compile_ml` 提供，绝不触碰既
/// 有 `compile(TypedAst, Backend) -> Bytes` 桩（R12.2 / R12.4）。
///
/// 产出的字节码遵循本文件顶部声明的契约（绝对索引跳转、Call 弹实参在栈顶、闭包
/// 体以 Ret 收尾、MkRecClosure 自指绑定）；任务 8.2 的 `VM::run` 据此执行并应与
/// `eval_ml` 语义等价（Property 10 / 任务 8.4）。
pub fn compile_ml(te : TExpr) -> Bytecode {
  let out : Array[Instr] = []
  emit(te, out)
  Bytecode::{ instrs: out }
}
