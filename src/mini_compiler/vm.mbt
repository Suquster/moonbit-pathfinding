// vm.mbt —— MiniML 栈式虚拟机（design.md §「组件与接口 → 9. 栈式虚拟机」，
// 覆盖 R6.3，并与 Property 10「编译—执行等价」R6.5 对齐）。
//
// 本文件**不修改**任何既有文件，全部能力旁路新增（R12.4）。它消费 `bytecode.mbt`
// 由 `compile_ml(TExpr) -> Bytecode` 产出的字节码，以一台**内存中的栈式抽象机**
// （操作数栈 + 调用帧）解释每条 `Instr`，程序结束时把栈顶值投影为公开 `Val`。
//
// ===========================================================================
// 与字节码契约（bytecode.mbt 顶部）的逐条对应
// ===========================================================================
//   * 跳转目标为**绝对索引**：`JumpIfFalse(t)` / `Jump(t)` 直接把当前帧 `pc`
//     置为 `t`。
//   * 二元节点「左先压、右后压」：`Arith` / `Cmp` / `Logic` 先弹右 `b`、再弹左
//     `a`，计算 `a op b`；除零=0（复用 `ml_apply_arith`，与 ml_eval 一致）。
//   * 调用约定：`Call` 弹「实参在栈顶、闭包在其下」，以闭包捕获环境扩展
//     `param -> arg`（递归闭包额外绑定自身名）建立新帧执行其体。
//   * 闭包体以 `Ret` 收尾：`Ret` 结束当前帧，体结果留在调用处栈顶。
//   * `MkClosure` 捕获**当前帧环境**；`MkRecClosure` 额外把自身名绑定到自己。
//
// ===========================================================================
// 值表示与「公开 Val」之间的阻抗匹配（重要设计说明）
// ===========================================================================
//   公开 `Val::VClosure(String, TExpr, Env)` 存的是**树形** `TExpr` 体，而 VM 在
//   字节码层面工作，闭包体是 **`Bytecode`**。为忠实执行字节码（尤其支持闭包与
//   递归），VM 内部采用一套**专用栈值** `SVal` 与**内部环境**
//   `@list.List[(String, SVal)]`：`SClosure` / `SRecClosure` 携带 `Bytecode` 体
//   与捕获的内部环境，故 `Call` 可直接跳入其体执行。
//
//   `VM::run` 的签名（design.md）为 `(Bytecode, Env) -> Val`：入口把种子公开
//   `env` 转为内部环境（顶层调用恒为空环境），执行后把最终 `SVal` 投影回公开
//   `Val`。投影规则：
//     * `SInt`  -> `VInt`、`SBool` -> `VBool`、`STuple` -> `VTuple`（递归）——
//       **完全忠实**。Property 10 的良类型生成器顶层结果恒为 `TyInt` / `TyBool`
//       （`ml_well_typed_expr_gen`），故 `VM::run` 与 `eval_ml` 在基值/元组结果
//       上逐位相等。
//     * `SClosure` / `SRecClosure` -> `Val::VClosure`：由于忠实的 `VClosure` 需
//       要 `TExpr` 体而 VM 仅持有 `Bytecode`，此处以**哨兵** `TExpr`（`TEInt(0,
//       TyInt, span0)`）与空环境构造一个形参正确、但体不可比的占位闭包。这是
//       已知且**有意**的保真度边界：顶层结果为闭包时两路闭包本就难以逐位相等，
//       而 Property 10 / 端到端两路一致针对的是基值/元组结果。

// ---------------------------------------------------------------------------
// 内部栈值与内部环境
// ---------------------------------------------------------------------------

///|
/// VM 内部操作数栈值（旁路私有，仅服务字节码执行）。与公开 `Val` 的关键区别：
/// 闭包携带 **`Bytecode`** 体（而非 `TExpr`）与内部环境，使 `Call` 能直接执行。
pub enum SVal {
  /// 整数值。
  SInt(Int)
  /// 布尔值。
  SBool(Bool)
  /// 普通闭包：形参、体字节码、捕获的内部环境。
  SClosure(String, Bytecode, @list.List[(String, SVal)])
  /// 递归闭包：自身名、形参、体字节码、捕获的内部环境（被调用时额外绑定自身名）。
  SRecClosure(String, String, Bytecode, @list.List[(String, SVal)])
  /// 元组值。
  STuple(Array[SVal])
}

///|
/// 内部求值环境：(名字, 内部值) 不可变序列，最近绑定在表头（遮蔽语义）。
type SEnv = @list.List[(String, SVal)]

// ---------------------------------------------------------------------------
// 调用帧与虚拟机（design.md §9 的命名符号：Frame / VM / VM::run）
// ---------------------------------------------------------------------------

///|
/// 调用帧：正在执行的体字节码、程序计数器 `pc` 与该帧的局部环境。
///
/// design.md 记述 `Frame { env; return_pc }`；本实现把「返回地址」语义落在
/// **调用者帧自身的 `pc`**（`Call` 前已将其推进到 `Call` 之后），故被调帧只需
/// 持有自己的 `bc` / `pc` / `env`，返回时弹出本帧即自然回到调用者续点——语义
/// 等价且更直观。
pub struct Frame {
  bc : Bytecode
  mut pc : Int
  env : SEnv
}

///|
/// 栈式虚拟机：以**操作数栈** `stack` 与**调用帧栈** `frames` 解释 `Bytecode`
/// （R6.3）。操作数栈在各帧间共享——每个（由 `compile_ml` 产出的）体字节码都是
/// 栈平衡的、恰好净产出一个结果值，故被调帧只在调用者留下的值之上增减，返回时
/// 体结果留在栈顶供调用者续用。
pub struct VM {
  stack : Array[SVal]
  frames : Array[Frame]
}

///|
/// 执行字节码，程序结束时产出栈顶 `Val`（R6.3）。
///
/// `env` 为种子公开环境（顶层调用恒为空）；入口将其转换为内部环境，逐条解释
/// 指令直到顶层帧的字节码耗尽，最后把栈顶 `SVal` 投影为公开 `Val`。
pub fn VM::run(bc : Bytecode, env : Env) -> Val {
  let vm = VM::{ stack: [], frames: [] }
  vm.frames.push(Frame::{ bc, pc: 0, env: senv_of_env(env) })
  while vm.frames.length() > 0 {
    let frame = vm.frames[vm.frames.length() - 1]
    // 当前帧字节码耗尽：顶层结束则退出；否则（理论上不应发生，因闭包体以 Ret
    // 收尾）弹出该帧回到调用者。
    if frame.pc >= frame.bc.instrs.length() {
      if vm.frames.length() == 1 {
        break
      }
      vm.frames.pop() |> ignore
      continue
    }
    let instr = frame.bc.instrs[frame.pc]
    match instr {
      PushInt(n) => {
        vm.stack.push(SInt(n))
        frame.pc += 1
      }
      PushBool(b) => {
        vm.stack.push(SBool(b))
        frame.pc += 1
      }
      LoadVar(x) => {
        vm.stack.push(senv_lookup(frame.env, x))
        frame.pc += 1
      }
      Arith(op) => {
        let b = sval_int(pop_s(vm.stack))
        let a = sval_int(pop_s(vm.stack))
        vm.stack.push(SInt(ml_apply_arith(op, a, b)))
        frame.pc += 1
      }
      Cmp(op) => {
        let b = sval_int(pop_s(vm.stack))
        let a = sval_int(pop_s(vm.stack))
        vm.stack.push(SBool(ml_apply_cmp(op, a, b)))
        frame.pc += 1
      }
      Logic(op) => {
        let b = sval_bool(pop_s(vm.stack))
        let a = sval_bool(pop_s(vm.stack))
        vm.stack.push(
          SBool(
            match op {
              And => a && b
              Or => a || b
            },
          ),
        )
        frame.pc += 1
      }
      JumpIfFalse(t) => {
        let c = sval_bool(pop_s(vm.stack))
        if c {
          frame.pc += 1
        } else {
          frame.pc = t
        }
      }
      Jump(t) => frame.pc = t
      MkClosure(p, body) => {
        vm.stack.push(SClosure(p, body, frame.env))
        frame.pc += 1
      }
      MkRecClosure(f, p, body) => {
        vm.stack.push(SRecClosure(f, p, body, frame.env))
        frame.pc += 1
      }
      Call => {
        let arg = pop_s(vm.stack)
        let callee = pop_s(vm.stack)
        // 先把调用者 pc 推进到 Call 之后，使被调帧返回时自然续接。
        frame.pc += 1
        match callee {
          SClosure(p, body, cenv) =>
            vm.frames.push(Frame::{
              bc: body,
              pc: 0,
              env: cenv.prepend((p, arg)),
            })
          SRecClosure(f, p, body, cenv) => {
            // 新帧环境：捕获环境上先绑形参、再绑自身名（表头优先，二者均可见）。
            let rec_env = cenv.prepend((f, callee)).prepend((p, arg))
            vm.frames.push(Frame::{ bc: body, pc: 0, env: rec_env })
          }
          // 经类型检查的程序应用位必为闭包；回退保持全函数（不卡住）。
          _ => vm.stack.push(SInt(0))
        }
      }
      Ret =>
        // 结束当前帧：体结果此刻位于栈顶，弹出本帧后该值留给调用者。
        vm.frames.pop() |> ignore
      MkTuple(n) => {
        // 各分量按 item[0..n-1] 次序压入，故 item[n-1] 在栈顶；逆序弹出后翻转
        // 还原为原始次序。
        let collected : Array[SVal] = []
        for _ in 0..<n {
          collected.push(pop_s(vm.stack))
        }
        let items : Array[SVal] = []
        for i = collected.length() - 1; i >= 0; i = i - 1 {
          items.push(collected[i])
        }
        vm.stack.push(STuple(items))
        frame.pc += 1
      }
    }
  }
  sval_to_val(top_s(vm.stack))
}

// ---------------------------------------------------------------------------
// 操作数栈与内部值助手
// ---------------------------------------------------------------------------

///|
/// 弹出栈顶；空栈回退 `SInt(0)`（经编译的栈平衡字节码不会触发，仅保证全函数）。
fn pop_s(stack : Array[SVal]) -> SVal {
  match stack.pop() {
    Some(v) => v
    None => SInt(0)
  }
}

///|
/// 读取栈顶（不弹出）；空栈回退 `SInt(0)`。用于程序结束取结果。
fn top_s(stack : Array[SVal]) -> SVal {
  if stack.length() == 0 {
    SInt(0)
  } else {
    stack[stack.length() - 1]
  }
}

///|
/// 取整数；非整数回退 `0`（经 infer 的程序不会触发，仅保证全函数）。
fn sval_int(v : SVal) -> Int {
  match v {
    SInt(n) => n
    _ => 0
  }
}

///|
/// 取布尔；非布尔回退 `false`（同上，仅保证全函数）。
fn sval_bool(v : SVal) -> Bool {
  match v {
    SBool(b) => b
    _ => false
  }
}

// ---------------------------------------------------------------------------
// 内部环境查找
// ---------------------------------------------------------------------------

///|
/// 自表头（最近）向表尾扫描查找 `name`，命中即返回（遮蔽语义）。未命中回退
/// `SInt(0)`（经作用域检查/infer 的程序变量必有绑定，仅保证全函数）。
fn senv_lookup(env : SEnv, name : String) -> SVal {
  for kv in env.iter() {
    let (k, v) = kv
    if k == name {
      return v
    }
  }
  SInt(0)
}

// ---------------------------------------------------------------------------
// 公开 Val ⇄ 内部 SVal 转换
// ---------------------------------------------------------------------------

///|
/// 把种子公开环境 `Env` 转为内部环境，保持表头优先次序（顶层调用恒为空环境）。
fn senv_of_env(env : Env) -> SEnv {
  let pairs : Array[(String, SVal)] = []
  for kv in env.bindings.iter() {
    let (k, v) = kv
    pairs.push((k, sval_of_val(v)))
  }
  let mut result : SEnv = @list.List::new()
  for i = pairs.length() - 1; i >= 0; i = i - 1 {
    result = result.prepend(pairs[i])
  }
  result
}

///|
/// 公开 `Val` -> 内部 `SVal`。基值/元组逐位转换；闭包体经 `compile_ml` 重新编译
/// 为字节码（末尾补 `Ret`，与 `compile_ml` 对闭包体的处理一致），捕获环境递归
/// 转换——从而种子环境中的闭包亦可被 `Call` 忠实执行。
fn sval_of_val(v : Val) -> SVal {
  match v {
    VInt(n) => SInt(n)
    VBool(b) => SBool(b)
    VTuple(items) => STuple(items.map(sval_of_val))
    VClosure(param, body, cap) => {
      let body_instrs = compile_ml(body).instrs
      let instrs : Array[Instr] = []
      for ins in body_instrs {
        instrs.push(ins)
      }
      instrs.push(Ret)
      SClosure(param, Bytecode::{ instrs, }, senv_of_env(cap))
    }
  }
}

///|
/// 内部 `SVal` -> 公开 `Val`。基值/元组**完全忠实**；闭包以哨兵 `TExpr` 与空
/// 环境构造形参正确的占位 `VClosure`（见文件头「阻抗匹配」说明：闭包结果的
/// 体不可逐位比较，非 Property 10 的目标）。
fn sval_to_val(v : SVal) -> Val {
  match v {
    SInt(n) => VInt(n)
    SBool(b) => VBool(b)
    STuple(items) => VTuple(items.map(sval_to_val))
    SClosure(param, _, _) =>
      VClosure(
        param,
        TEInt(0, TyInt, Span::{ line: 0, col: 0 }),
        ml_env_empty(),
      )
    SRecClosure(_, param, _, _) =>
      VClosure(
        param,
        TEInt(0, TyInt, Span::{ line: 0, col: 0 }),
        ml_env_empty(),
      )
  }
}
