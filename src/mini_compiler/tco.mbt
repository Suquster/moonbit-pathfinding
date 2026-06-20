// tco.mbt —— MiniML 尾调用优化（TCO）（design.md §「Mini-compiler 特性与优化设
// 计」AC3，覆盖 Requirement 9.3 / 9.4）。
//
// 本文件**不修改**任何既有文件与签名，全部能力旁路新增（freeze + bypass）。
//
// ===========================================================================
// 设计策略（为何采用「字节码规范化 + 尾调用感知解释器」两件套）
// ===========================================================================
//   既有 `Instr` 枚举已**冻结**，不能新增专用的 `TailCall` 指令；既有
//   `VM::run(Bytecode, Env) -> Val` 在每次 `Call` 都压入新帧、`Ret` 才弹出，故深
//   度 N 的尾递归会线性堆积至 N 帧。为在不动既有签名的前提下实现 AC3「尾位置调用
//   复用帧、帧数不随 N 线性增长」，本文件提供：
//
//   (1) `tco_opt(Bytecode) -> Bytecode`：**等价的字节码规范化**。把每条「目标处
//       恰为 `Ret`」的无条件 `Jump(t)`（即 `instrs[t]` 为 `Ret`）就地改写为
//       `Ret`。正确性：无条件跳到一条 `Ret` 再执行该 `Ret`，与直接执行 `Ret` 完
//       全等价（同样弹出当前帧、把体结果留在调用处栈顶，且 `Jump` 无栈副作用）。
//       指令条数不变。该规范化把诸如 `... ; Call ; Jump(→Ret)` 的尾位置整理为
//       `... ; Call ; Ret`，使下游解释器能以「`Call` 紧邻 `Ret`」这一**局部窗口**
//       判定尾调用，从而识别更多尾调用（如尾调用位于 `if` 的 then 分支时，原本其
//       后是 `Jump(→Ret)` 而非直接 `Ret`）。对嵌套闭包体递归施加。
//
//   (2) `run_tco(Bytecode, Env) -> Val`：**尾调用感知解释器**（新增，bypass）。
//       与 `VM::run` 语义一致，唯一区别：执行 `Call` 时若**当前帧的下一条指令是
//       `Ret`**（即该调用处于尾位置），则不在调用者帧之上压入被调帧，而是先**弹出
//       （丢弃）当前调用者帧**再压入被调帧——复用帧位置。正确性：尾位置的调用者
//       在被调返回后只会立即执行 `Ret`（弹出自身、把结果留给上层），故提前丢弃调
//       用者帧不改变任何可观测行为；被调结果经共享操作数栈自然流向上层。如此尾递
//       归的活动帧数恒定，不随递归深度 N 线性增长（AC3）。
//
//   配套提供 `run_tco_with_depth(Bytecode, Env) -> (Val, Int)`：在执行同时统计**最
//   大活动帧深**，供属性/单元测试验证「帧数不随 N 线性增长」（对不同 N 测得的最大
//   帧深应为与 N 无关的小常数）。`run_tco` 即取其结果分量。
//
//   等价保证（AC4 / R9.4）：对任意可成功编译的程序，
//   `run_tco(tco_opt(bc), env) == VM::run(bc, env)`——`tco_opt` 等价改写、`run_tco`
//   仅对尾调用复用帧（语义等价），两者结果与既有非 TCO 路径逐位相等。
//
// 复用既有同包私有助手（vm.mbt / ml_eval.mbt）：`SVal` / `Frame` / `VM` /
// `senv_of_env` / `senv_lookup` / `pop_s` / `top_s` / `sval_int` / `sval_bool` /
// `sval_to_val` / `ml_apply_arith` / `ml_apply_cmp`。

// ---------------------------------------------------------------------------
// (1) 字节码规范化：Jump-to-Ret → Ret
// ---------------------------------------------------------------------------

///|
/// 尾调用相关的字节码规范化（AC3 / R9.3）：把每条「目标处恰为 `Ret`」的无条件
/// `Jump(t)` 改写为 `Ret`（等价且指令数不变），并对嵌套闭包体递归施加。规范化后
/// 由 `run_tco` 消费——它令尾位置（含位于分支内、原本以 `Jump(→Ret)` 收尾的尾调
/// 用）整理为「`Call` 紧邻 `Ret`」，从而被尾调用感知解释器识别并复用帧。
///
/// 正确性：执行 `Jump(t)`（`instrs[t]` 为 `Ret`）= 无条件转移到 `t` 再执行 `Ret`；
/// 与原地直接执行 `Ret` 完全等价（同样结束当前帧、结果留调用处栈顶，`Jump` 无栈副
/// 作用）。故求值结果不变（AC4）。
pub fn tco_opt(bc : Bytecode) -> Bytecode {
  let instrs = bc.instrs
  let n = instrs.length()
  let result : Array[Instr] = []
  for i in 0..<n {
    let ins = instrs[i]
    match ins {
      // 目标处恰为 Ret 的无条件跳转 → 直接内联为 Ret。
      Jump(t) =>
        if t >= 0 && t < n && instr_is_ret(instrs[t]) {
          result.push(Ret)
        } else {
          result.push(ins)
        }
      // 嵌套闭包体递归规范化。
      MkClosure(p, body) => result.push(MkClosure(p, tco_opt(body)))
      MkRecClosure(f, p, body) => result.push(MkRecClosure(f, p, tco_opt(body)))
      other => result.push(other)
    }
  }
  Bytecode::{ instrs: result }
}

///|
/// 判定一条指令是否为 `Ret`。
fn instr_is_ret(ins : Instr) -> Bool {
  match ins {
    Ret => true
    _ => false
  }
}

// ---------------------------------------------------------------------------
// (2) 尾调用感知解释器
// ---------------------------------------------------------------------------

///|
/// 尾调用感知执行（AC3 / R9.3）：语义与 `VM::run` 一致，但对处于**尾位置**（当前帧
/// 下一条为 `Ret`）的 `Call` 复用调用者帧（先弹调用者帧再压被调帧），使尾递归活动
/// 帧数不随递归深度线性增长。返回程序结束时栈顶 `Val`。
pub fn run_tco(bc : Bytecode, env : Env) -> Val {
  let (result, _) = run_tco_with_depth(bc, env)
  result
}

///|
/// 与 `run_tco` 同构，但额外返回**执行过程中达到的最大活动帧深**，供测试验证「帧
/// 数不随 N 线性增长」（不同 N 应测得与 N 无关的小常数最大帧深）。
pub fn run_tco_with_depth(bc : Bytecode, env : Env) -> (Val, Int) {
  let vm = VM::{ stack: [], frames: [] }
  vm.frames.push(Frame::{ bc, pc: 0, env: senv_of_env(env) })
  let mut max_depth = vm.frames.length()
  while vm.frames.length() > 0 {
    if vm.frames.length() > max_depth {
      max_depth = vm.frames.length()
    }
    let frame = vm.frames[vm.frames.length() - 1]
    // 当前帧字节码耗尽：顶层结束则退出；否则弹出该帧回到调用者。
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
        // 尾位置判定：当前帧紧邻下一条是否为 Ret（经 tco_opt 规范化后，分支内的
        // 尾调用亦呈现此形态）。
        let next_is_ret = frame.pc + 1 < frame.bc.instrs.length() &&
          instr_is_ret(frame.bc.instrs[frame.pc + 1])
        // 先把调用者 pc 推进到 Call 之后（非尾调用时使被调返回后自然续接）。
        frame.pc += 1
        match callee {
          SClosure(p, body, cenv) => {
            // 尾位置：复用调用者帧位置（先弹后压），活动帧深不增。
            if next_is_ret {
              vm.frames.pop() |> ignore
            }
            vm.frames.push(Frame::{
              bc: body,
              pc: 0,
              env: cenv.prepend((p, arg)),
            })
          }
          SRecClosure(f, p, body, cenv) => {
            let rec_env = cenv.prepend((f, callee)).prepend((p, arg))
            if next_is_ret {
              vm.frames.pop() |> ignore
            }
            vm.frames.push(Frame::{ bc: body, pc: 0, env: rec_env })
          }
          // 经类型检查的程序应用位必为闭包；回退保持全函数（不卡住、不复用帧）。
          _ => vm.stack.push(SInt(0))
        }
      }
      Ret =>
        // 结束当前帧：体结果此刻位于栈顶，弹出本帧后该值留给调用者。
        vm.frames.pop() |> ignore
      MkTuple(n) => {
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
  (sval_to_val(top_s(vm.stack)), max_depth)
}
