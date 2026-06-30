// typed_passes.mbt —— 类型化 IR 优化遍 + 可验证 pass 流水线（旗舰深化，旁路新增 / bypass）。
//
// 纲领落点（docs/PRODUCTION_FRONTIER_ROADMAP.md 方向三 Codegen）：
//   * T3.1「Pass 流水线管理器 + IR 验证器」—— 在 8.1 类型化 IR
//     （`Operand` / `TypedInstr` / `TypedBlock` / `TypedFunction`）、8.2 验证器
//     `validate_ir`、8.3 解释器 `interp_ir` 之上，新增一个**可组合**的 pass
//     流水线，并提供「每遍前后断言 SSA 良构性」的验证型驱动
//     `run_typed_pipeline_validated`：输入须先通过 `validate_ir`，此后每施加
//     一遍优化即重新 `validate_ir`，任一时刻失去良构性即返回结构化错误。
//   * T3.2「优化 pass 扩充」—— 新增五个经典优化遍，均为**纯函数**、**保持
//     可观察求值等价**（见 prop_typed_passes_wbtest.mbt 的 ≥100 迭代等价 PBT）：
//       - `const_fold_typed`      常量折叠（块内常量传播 + 二元立即数折叠）
//       - `algebraic_simplify_typed` 代数化简（x*0=0 / x*1=x / x-0=x / x-x=0 等恒等式）
//       - `strength_reduce_typed` 强度削减（x*2 → x+x）
//       - `dce_typed`             死代码消除（无用且无副作用的定义指令）
//       - `cse_typed`             公共子表达式消除（块内值编号 + 全局改名）
//
// 冻结复用原则（只增不减 / freeze + bypass）：本文件**不修改、不删除**任何
// 既有公开签名；既有字符串 IR 上的 `run_passes` / `run_pipeline` /
// `run_to_fixpoint`（作用于 `SsaProgram`）全部冻结保留，类型化 IR 的优化遍
// 与流水线作为独立平行通道新增，命名一律带 `_typed` 后缀以与之区分。
//
// 正确性契约（与 `interp_ir` 对齐，见 §「可观察等价」）：
//   每个优化遍 `opt` 满足——对任意入参 `args`，`interp_ir(opt(f), args)` 与
//   `interp_ir(f, args)` **可观察等价**：返回值 `returned` 相等，且优化后仍存
//   在的每个寄存器其终值与优化前一致（保值遍 const_fold / algebraic /
//   strength 不丢寄存器，dce / cse 仅删除「不可观察」的寄存器）。`cse_typed`
//   依赖输入为良构 SSA（定义支配使用，由 `validate_ir` 通过 + 标准 SSA 构造
//   保证），其等价性在该前提下成立。
//
// 反模式禁令（遵循 quality-enforcement / anti-patterns 约束）：
//   * 无 `abort()` / `todo!()` / `panic` 占位 —— 所有遍对任意输入均返回结构化结果；
//   * 无 magic number —— 不动点上限以命名常量 `typed_fixpoint_max_iters` 表达，
//     强度削减的「乘 2」阈值以命名常量 `strength_double_factor` 表达；
//   * 无字符串模拟结构化数据 —— IR 以枚举/结构体表达；CSE 的值编号 key 是
//     **测试可复现的内部规范串**，仅用作 `Map` 键，不承载结构语义；
//   * `Show` 手写（`derive(Eq)` + `pub impl Show`）以规避 `derive(Debug)`
//     弃用告警，与 typed_ir.mbt / ir_validator.mbt / ir_interp.mbt 保持一致。

// ───────────────────────────── 命名常量 ─────────────────────────────

///|
/// 类型化不动点驱动 `run_typed_to_fixpoint` 的默认安全迭代上限。
///
/// 反复施加 pass 直到一轮内程序不再变化（收敛）或达此上限；取一个足够大的常量，
/// 使一切合理规模的程序都能收敛，仅在病态构造上触顶。命名常量化以杜绝 magic
/// number。
let typed_fixpoint_max_iters : Int = 32

///|
/// 强度削减识别的「乘以二」因子：`x * 2` 等价于 `x + x`（一次乘法→一次加法）。
///
/// 仅对该因子做单指令改写（更高次幂的 `x * 2^k` 需引入临时寄存器与多条加法，
/// 不在单指令改写范围内）。命名常量化以杜绝 magic number。
let strength_double_factor : Int = 2

// ───────────────────────────── 优化遍枚举 ─────────────────────────────

///|
/// 类型化 IR 优化遍标签（供可组合流水线 `run_typed_pipeline` 等按序选择）。
///
/// 五个变体一一对应本文件的五个纯函数优化遍；以 `pub(all)` 暴露构造子，便于
/// 宿主与属性测试直接构造与模式匹配（与本包 `OptPass` / `Pass` 的可见性一致）。
/// 派生 `Eq` 支撑流水线声明的相等比较与测试断言。
pub(all) enum TypedPass {
  ConstFold
  AlgebraicSimplify
  StrengthReduce
  Dce
  Cse
} derive(Eq)

///|
/// 以可读形式展示优化遍标签（手写 `Show`，规避 `derive(Debug)` 弃用告警）。
pub impl Show for TypedPass with fn output(self : TypedPass, logger : &Logger) -> Unit {
  let name = match self {
    ConstFold => "ConstFold"
    AlgebraicSimplify => "AlgebraicSimplify"
    StrengthReduce => "StrengthReduce"
    Dce => "Dce"
    Cse => "Cse"
  }
  logger.write_string("TypedPass::")
  logger.write_string(name)
}

// ───────────────────────────── 操作数 / 指令工具 ─────────────────────────────

///|
/// 操作数若为 `Imm(v)` 则返回 `Some(v)`，否则 `None`（常量折叠 / 化简判定用）。
fn operand_imm(op : Operand) -> Int? {
  match op {
    Imm(v) => Some(v)
    Reg(_) | Mem(_) => None
  }
}

///|
/// 操作数若为寄存器 `Reg(r)` 则返回 `Some(r)`，否则 `None`（使用集合收集 /
/// 改名解析用）。
fn operand_reg(op : Operand) -> Int? {
  match op {
    Reg(r) => Some(r)
    Imm(_) | Mem(_) => None
  }
}

///|
/// 「物化常量」的规范指令形态：`dst := v`，以 `Add(dst, Imm v, Imm 0)` 表达
/// （类型化 IR 无独立 `Mov` / `Const` 指令，故以「加零」承载一个编译期常量，
/// 既保持 `dst` 单赋值，又使该值对验证器 / 解释器与既有语义完全一致）。
fn materialize_const(dst : Int, v : Int) -> TypedInstr {
  Add(dst~, lhs=Imm(v), rhs=Imm(0))
}

// ───────────────────────────── 常量折叠（T3.2） ─────────────────────────────

///|
/// 用块内常量环境 `env`（寄存器 → 已知常量）替换一条指令的**值位置**操作数，
/// 把 `Reg(r)`（当 `r` 已知为常量）替换为 `Imm(env[r])`。
///
/// 仅替换值位置（算术 `lhs` / `rhs`、`Store.value`、`Call.args`、`Ret` 值、
/// `CondBr.cond`）；**不**替换地址位置（`Load.addr` / `Store.addr`，替换为
/// 立即数会破坏地址类型约束）与 `Phi`（其取值来自前驱块，块内常量不可代入）。
fn cf_subst(env : Map[Int, Int], ins : TypedInstr) -> TypedInstr {
  let v = fn(op : Operand) -> Operand {
    match operand_reg(op) {
      Some(r) =>
        match env.get(r) {
          Some(c) => Imm(c)
          None => op
        }
      None => op
    }
  }
  match ins {
    Add(dst~, lhs~, rhs~) => Add(dst~, lhs=v(lhs), rhs=v(rhs))
    Sub(dst~, lhs~, rhs~) => Sub(dst~, lhs=v(lhs), rhs=v(rhs))
    Mul(dst~, lhs~, rhs~) => Mul(dst~, lhs=v(lhs), rhs=v(rhs))
    Load(dst~, addr~) => Load(dst~, addr~)
    Store(addr~, value~) => Store(addr~, value=v(value))
    Call(dst~, callee~, args~) => Call(dst~, callee~, args=args.map(v))
    Ret(value~) =>
      Ret(
        value=match value {
          Some(x) => Some(v(x))
          None => None
        },
      )
    Br(target~) => Br(target~)
    CondBr(cond~, then_~, else_~) => CondBr(cond=v(cond), then_~, else_~)
    Phi(dst~, args~) => Phi(dst~, args~)
  }
}

///|
/// 折叠一条「两操作数均为立即数」的二元算术指令为物化常量；其余指令原样返回。
///
/// 返回 `(指令, 该指令是否定义了一个新的已知常量及其值)`：折叠成功时第二项为
/// `Some((dst, 折叠值))`，调用方据此更新块内常量环境，实现常量在块内级联传播。
/// 折叠使用与 `interp_ir` **完全相同**的整型 `+` / `-` / `*`（含相同溢出语义），
/// 保证求值等价。
fn cf_fold(ins : TypedInstr) -> (TypedInstr, (Int, Int)?) {
  match ins {
    Add(dst~, lhs~, rhs~) =>
      match (operand_imm(lhs), operand_imm(rhs)) {
        (Some(a), Some(b)) =>
          (materialize_const(dst, a + b), Some((dst, a + b)))
        _ => (ins, None)
      }
    Sub(dst~, lhs~, rhs~) =>
      match (operand_imm(lhs), operand_imm(rhs)) {
        (Some(a), Some(b)) =>
          (materialize_const(dst, a - b), Some((dst, a - b)))
        _ => (ins, None)
      }
    Mul(dst~, lhs~, rhs~) =>
      match (operand_imm(lhs), operand_imm(rhs)) {
        (Some(a), Some(b)) =>
          (materialize_const(dst, a * b), Some((dst, a * b)))
        _ => (ins, None)
      }
    _ => (ins, None)
  }
}

///|
/// 常量折叠（含块内常量传播）。对每个基本块独立处理：维护一个块内常量环境
/// `env`（寄存器 → 编译期常量），按指令顺序——
///
///   1. 先以 `env` 替换当前指令的值位置操作数（`cf_subst`）；
///   2. 再尝试把「两操作数均为立即数」的二元算术折叠为物化常量（`cf_fold`），
///      折叠成功则把 `dst → 值` 记入 `env`，使后续指令可级联折叠。
///
/// 终结指令的值位置（`Ret` 值 / `CondBr` 条件）亦按 `env` 替换。块内传播在
/// 顺序执行语义下恒成立（定义先于使用），故求值**完全保值**（寄存器全集与
/// 返回值均不变），不依赖跨块支配关系。
pub fn const_fold_typed(func : TypedFunction) -> TypedFunction {
  let new_blocks : Array[TypedBlock] = []
  for b in func.blocks {
    let env : Map[Int, Int] = Map([])
    let new_instrs : Array[TypedInstr] = []
    for ins in b.instrs {
      let substituted = cf_subst(env, ins)
      let (folded, maybe_const) = cf_fold(substituted)
      match maybe_const {
        Some((d, c)) => env[d] = c
        None => ()
      }
      new_instrs.push(folded)
    }
    let new_term : TypedInstr? = match b.terminator {
      Some(t) => Some(cf_subst(env, t))
      None => None
    }
    new_blocks.push(TypedBlock::{
      label: b.label,
      instrs: new_instrs,
      terminator: new_term,
    })
  }
  TypedFunction::{ entry: func.entry, blocks: new_blocks }
}

// ───────────────────────────── 代数化简（T3.2） ─────────────────────────────

///|
/// 代数化简：对单条指令施加保值的代数恒等式改写（与上下文无关，逐指令独立）。
///
/// 识别的恒等式（均保持求值结果不变，且改写后类型合法——结果仍为值位置的
/// `Reg` / `Imm` 二元算术）：
///
///   * `x * 0` / `0 * x`  → `0`        （以 `Add(dst, Imm 0, Imm 0)` 物化）
///   * `x * 1` / `1 * x`  → `x`        （以 `Add(dst, x, Imm 0)` 物化）
///   * `x - 0`            → `x`        （`Add(dst, x, Imm 0)`）
///   * `x - x`（同一寄存器/同一立即数）→ `0`
///   * `0 + x`            → `x + 0`    （规范化，保值）
///
/// `x` 为「值」操作数（合法 IR 的二元算术操作数恒为 `Reg` / `Imm`），故所有
/// 改写结果均通过 `validate_ir`。
pub fn algebraic_simplify_typed(func : TypedFunction) -> TypedFunction {
  fn simp(ins : TypedInstr) -> TypedInstr {
    match ins {
      Mul(dst~, lhs~, rhs~) =>
        if operand_imm(lhs) == Some(0) || operand_imm(rhs) == Some(0) {
          materialize_const(dst, 0)
        } else if operand_imm(rhs) == Some(1) {
          Add(dst~, lhs~, rhs=Imm(0))
        } else if operand_imm(lhs) == Some(1) {
          Add(dst~, lhs=rhs, rhs=Imm(0))
        } else {
          ins
        }
      Sub(dst~, lhs~, rhs~) =>
        if operand_imm(rhs) == Some(0) {
          Add(dst~, lhs~, rhs=Imm(0))
        } else if lhs == rhs {
          materialize_const(dst, 0)
        } else {
          ins
        }
      Add(dst~, lhs~, rhs~) =>
        if operand_imm(rhs) == Some(0) {
          ins
        } else if operand_imm(lhs) == Some(0) {
          Add(dst~, lhs=rhs, rhs=Imm(0))
        } else {
          ins
        }
      _ => ins
    }
  }

  map_block_instrs(func, simp)
}

// ───────────────────────────── 强度削减（T3.2） ─────────────────────────────

///|
/// 强度削减：把较昂贵的运算替换为等价的较廉价运算（逐指令独立，保值）。
///
/// 识别 `x * 2` / `2 * x` → `x + x`（一次乘法替换为一次加法）。`x` 为值操作数
/// （`Reg` / `Imm`），`Add(dst, x, x)` 类型合法且求值与 `x * 2` 完全一致
/// （含相同整型溢出语义）。更高次幂的 `x * 2^k` 需临时寄存器与多条加法，不在
/// 单指令改写范围内，原样保留。
pub fn strength_reduce_typed(func : TypedFunction) -> TypedFunction {
  fn reduce(ins : TypedInstr) -> TypedInstr {
    match ins {
      Mul(dst~, lhs~, rhs~) =>
        if operand_imm(rhs) == Some(strength_double_factor) {
          Add(dst~, lhs~, rhs=lhs)
        } else if operand_imm(lhs) == Some(strength_double_factor) {
          Add(dst~, lhs=rhs, rhs~)
        } else {
          ins
        }
      _ => ins
    }
  }

  map_block_instrs(func, reduce)
}

///|
/// 对函数内每个基本块的**普通指令**逐条施加映射 `f`（终结指令不变），重建
/// 函数。代数化简 / 强度削减等「逐指令、上下文无关」的遍共享此骨架。
fn map_block_instrs(
  func : TypedFunction,
  f : (TypedInstr) -> TypedInstr,
) -> TypedFunction {
  let new_blocks : Array[TypedBlock] = []
  for b in func.blocks {
    let new_instrs : Array[TypedInstr] = []
    for ins in b.instrs {
      new_instrs.push(f(ins))
    }
    new_blocks.push(TypedBlock::{
      label: b.label,
      instrs: new_instrs,
      terminator: b.terminator,
    })
  }
  TypedFunction::{ entry: func.entry, blocks: new_blocks }
}

// ───────────────────────────── 死代码消除（T3.2） ─────────────────────────────

///|
/// 收集一条指令**使用**（读取）的全部寄存器，追加到 `used`。
///
/// 覆盖所有操作数位置：二元算术 `lhs` / `rhs`、`Load` / `Store` 地址、`Store`
/// 值、`Call` 实参、`Ret` 值、`CondBr` 条件、`Phi` 各来路取值。被「定义」的
/// `dst` 不计入使用。
fn collect_uses(ins : TypedInstr, used : Map[Int, Bool]) -> Unit {
  let mark = fn(op : Operand) -> Unit {
    match operand_reg(op) {
      Some(r) => used[r] = true
      None => ()
    }
  }
  match ins {
    Add(lhs~, rhs~, ..) | Sub(lhs~, rhs~, ..) | Mul(lhs~, rhs~, ..) => {
      mark(lhs)
      mark(rhs)
    }
    Load(addr~, ..) => mark(addr)
    Store(addr~, value~) => {
      mark(addr)
      mark(value)
    }
    Call(args~, ..) =>
      for a in args {
        mark(a)
      }
    Ret(value~) =>
      match value {
        Some(x) => mark(x)
        None => ()
      }
    CondBr(cond~, ..) => mark(cond)
    Phi(args~, ..) =>
      for pair in args {
        let (_, op) = pair
        mark(op)
      }
    Br(..) => ()
  }
}

///|
/// 指令是否带副作用而必须保留（即便其结果未被使用）。
///
/// `Store`（写内存）与 `Call`（可能有外部副作用）保守保留；其余定义类指令
/// （`Add` / `Sub` / `Mul` / `Load` / `Phi`）为纯计算，可在结果不被使用时删除。
/// 终结指令（`Ret` / `Br` / `CondBr`）由控制流保留，不经此函数判定。
fn has_side_effect(ins : TypedInstr) -> Bool {
  match ins {
    Store(..) | Call(..) => true
    _ => false
  }
}

///|
/// 死代码消除（不动点）。反复执行：收集全函数的寄存器使用集合，删除「定义了
/// 一个从未被使用的寄存器、且无副作用」的普通指令；删除会缩小使用集合，可能
/// 令更早的定义变为死代码，故迭代至不再有删除为止（最多 `typed_fixpoint_max_iters`
/// 轮，防御性上界）。
///
/// 删除的指令其结果**不可观察**（既未被任何指令读取，也无副作用），故返回值
/// 与所有存活寄存器的终值均不变（可观察等价）；优化后寄存器全集是优化前的子集。
pub fn dce_typed(func : TypedFunction) -> TypedFunction {
  let mut cur = func
  let mut iter = 0
  let mut changed = true
  while changed && iter < typed_fixpoint_max_iters {
    changed = false
    iter = iter + 1
    let used : Map[Int, Bool] = Map([])
    for b in cur.blocks {
      for ins in b.instrs {
        collect_uses(ins, used)
      }
      match b.terminator {
        Some(t) => collect_uses(t, used)
        None => ()
      }
    }
    let new_blocks : Array[TypedBlock] = []
    for b in cur.blocks {
      let kept : Array[TypedInstr] = []
      for ins in b.instrs {
        let drop = !has_side_effect(ins) &&
          (match ins.defined_reg() {
            Some(d) => !used.contains(d)
            None => false
          })
        if drop {
          changed = true
        } else {
          kept.push(ins)
        }
      }
      new_blocks.push(TypedBlock::{
        label: b.label,
        instrs: kept,
        terminator: b.terminator,
      })
    }
    cur = TypedFunction::{ entry: cur.entry, blocks: new_blocks }
  }
  cur
}

// ───────────────────────────── 公共子表达式消除（T3.2） ─────────────────────────────

///|
/// 沿改名表 `rw` 解析一个寄存器到其规范代表（追随 `rw` 链至终点）。
///
/// CSE 把冗余表达式的目标寄存器改名到首次出现的规范寄存器；解析时追随链条
/// （带步数上界防御自指环，正常 SSA 下链长 ≤ 1）。
fn resolve_reg(rw : Map[Int, Int], r : Int) -> Int {
  let mut cur = r
  let mut steps = 0
  while steps < typed_fixpoint_max_iters {
    match rw.get(cur) {
      Some(next) => {
        cur = next
        steps = steps + 1
      }
      None => break
    }
  }
  cur
}

///|
/// 按改名表 `rw` 替换一条指令**所有位置**的寄存器操作数（`Reg(r)` →
/// `Reg(resolve(r))`）。`Reg` 在值位置与地址位置均合法，故全位置替换保持类型
/// 良构（含 `Load` / `Store` 地址、`Phi` 取值）。
fn cse_rename(rw : Map[Int, Int], ins : TypedInstr) -> TypedInstr {
  let m = fn(op : Operand) -> Operand {
    match operand_reg(op) {
      Some(r) => Reg(resolve_reg(rw, r))
      None => op
    }
  }
  match ins {
    Add(dst~, lhs~, rhs~) => Add(dst~, lhs=m(lhs), rhs=m(rhs))
    Sub(dst~, lhs~, rhs~) => Sub(dst~, lhs=m(lhs), rhs=m(rhs))
    Mul(dst~, lhs~, rhs~) => Mul(dst~, lhs=m(lhs), rhs=m(rhs))
    Load(dst~, addr~) => Load(dst~, addr=m(addr))
    Store(addr~, value~) => Store(addr=m(addr), value=m(value))
    Call(dst~, callee~, args~) => Call(dst~, callee~, args=args.map(m))
    Ret(value~) =>
      Ret(
        value=match value {
          Some(x) => Some(m(x))
          None => None
        },
      )
    Br(target~) => Br(target~)
    CondBr(cond~, then_~, else_~) => CondBr(cond=m(cond), then_~, else_~)
    Phi(dst~, args~) =>
      Phi(dst~, args=args.map(fn(pair) { (pair.0, m(pair.1)) }))
  }
}

///|
/// 把单个操作数渲染为 CSE 值编号 key 的片段（`R<n>` / `I<n>` / `M<n>`）。
fn cse_operand_token(op : Operand) -> String {
  match op {
    Reg(r) => "R" + r.to_string()
    Imm(v) => "I" + v.to_string()
    Mem(m) => "M" + m.to_string()
  }
}

///|
/// 为一条**纯二元算术**指令计算值编号 key（其余指令返回 `None`，不参与 CSE）。
///
/// 加法 / 乘法可交换，故对其两操作数 token 做字典序排序后拼接，使 `a+b` 与
/// `b+a` 得到同一 key；减法不可交换，保留 `lhs` / `rhs` 顺序。key 仅作 `Map`
/// 键用，是测试可复现的内部规范串，不承载结构语义。
fn cse_key(ins : TypedInstr) -> String? {
  match ins {
    Add(lhs~, rhs~, ..) => {
      let a = cse_operand_token(lhs)
      let b = cse_operand_token(rhs)
      let (x, y) = if a <= b { (a, b) } else { (b, a) }
      Some("Add|" + x + "|" + y)
    }
    Mul(lhs~, rhs~, ..) => {
      let a = cse_operand_token(lhs)
      let b = cse_operand_token(rhs)
      let (x, y) = if a <= b { (a, b) } else { (b, a) }
      Some("Mul|" + x + "|" + y)
    }
    Sub(lhs~, rhs~, ..) =>
      Some("Sub|" + cse_operand_token(lhs) + "|" + cse_operand_token(rhs))
    _ => None
  }
}

///|
/// 公共子表达式消除（块内识别 + 全局改名）。逐块顺序处理：
///
///   1. 先按全局改名表 `rw` 替换当前指令的寄存器操作数（`cse_rename`）；
///   2. 若为纯二元算术且其值编号 key 在**本块**已出现过，则该指令冗余——把其
///      `dst` 记入 `rw`（改名到首次出现的规范寄存器）并删除该指令；否则登记
///      key→dst 并保留。
///
/// 值编号 `seen` 每块清空（仅做块内识别）；改名表 `rw` 全局累积并施加于其后
/// 所有块，从而冗余定义被删除时其跨块使用一并改名到规范寄存器。正确性前提：
/// 输入为良构 SSA（定义支配使用），此时规范寄存器支配冗余出现处的全部使用，
/// 且二者表达式相同（操作数为单赋值的 `Reg` / 立即数）故取值恒等。
pub fn cse_typed(func : TypedFunction) -> TypedFunction {
  let rw : Map[Int, Int] = Map([])
  let new_blocks : Array[TypedBlock] = []
  for b in func.blocks {
    let seen : Map[String, Int] = Map([])
    let kept : Array[TypedInstr] = []
    for raw in b.instrs {
      let ins = cse_rename(rw, raw)
      match (cse_key(ins), ins.defined_reg()) {
        (Some(key), Some(dst)) =>
          match seen.get(key) {
            Some(canon) => rw[dst] = canon
            None => {
              seen[key] = dst
              kept.push(ins)
            }
          }
        _ => kept.push(ins)
      }
    }
    let new_term : TypedInstr? = match b.terminator {
      Some(t) => Some(cse_rename(rw, t))
      None => None
    }
    new_blocks.push(TypedBlock::{
      label: b.label,
      instrs: kept,
      terminator: new_term,
    })
  }
  TypedFunction::{ entry: func.entry, blocks: new_blocks }
}

// ───────────────────────────── 可组合流水线（T3.1） ─────────────────────────────

///|
/// 按标签施加单个优化遍（流水线的基本步进）。
pub fn apply_typed_pass(
  func : TypedFunction,
  pass : TypedPass,
) -> TypedFunction {
  match pass {
    ConstFold => const_fold_typed(func)
    AlgebraicSimplify => algebraic_simplify_typed(func)
    StrengthReduce => strength_reduce_typed(func)
    Dce => dce_typed(func)
    Cse => cse_typed(func)
  }
}

///|
/// 按声明顺序对函数施加一遍各 `TypedPass`（可组合流水线，R10.1 的类型化对应）。
///
/// 不做验证（性能路径）；如需「每遍前后断言良构性」请用
/// `run_typed_pipeline_validated`。
pub fn run_typed_pipeline(
  func : TypedFunction,
  passes : Array[TypedPass],
) -> TypedFunction {
  let mut cur = func
  for p in passes {
    cur = apply_typed_pass(cur, p)
  }
  cur
}

///|
/// **验证型**流水线（T3.1 核心）：每遍前后断言 IR 良构性。
///
/// 流程：先 `validate_ir(func)`；若输入即非良构，立即返回 `Err`（携带全部诊断）。
/// 此后按序施加每个 pass，**每遍施加后重新 `validate_ir`**；任一遍产出非良构
/// IR（理论上不应发生，此处即「每 pass 后 SSA/类型/控制流良构性断言」）则返回
/// 该遍的 `Err`。全程良构则返回 `Ok(最终函数)`。
pub fn run_typed_pipeline_validated(
  func : TypedFunction,
  passes : Array[TypedPass],
) -> Result[TypedFunction, Array[IrError]] {
  match validate_ir(func) {
    Err(e) => return Err(e)
    Ok(_) => ()
  }
  let mut cur = func
  for p in passes {
    cur = apply_typed_pass(cur, p)
    match validate_ir(cur) {
      Err(e) => return Err(e)
      Ok(_) => ()
    }
  }
  Ok(cur)
}

///|
/// 反复施加 `passes` 直到函数在一轮内不再变化（收敛）或达上界 `max_iters`
/// （R10.2 的类型化对应）。收敛判定走 `TypedFunction` 的派生 `Eq`（结构相等）。
pub fn run_typed_to_fixpoint(
  func : TypedFunction,
  passes : Array[TypedPass],
  max_iters? : Int = typed_fixpoint_max_iters,
) -> TypedFunction {
  let mut cur = func
  let mut i = 0
  while i < max_iters {
    let next = run_typed_pipeline(cur, passes)
    if next == cur {
      return next
    }
    cur = next
    i = i + 1
  }
  cur
}
