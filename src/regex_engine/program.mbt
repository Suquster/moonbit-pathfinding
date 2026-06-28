// program.mbt —— Pike VM 指令集 `Inst`、程序 `Program` 与编译器
// `compile_program`（旗舰深化）。
//
// 对应 design.md §4.3（R2）。本文件为**新增**。Pike VM 执行的是**线性指令
// 程序**（Thompson NFA 程序，Russ Cox 风格），而非邻接表 NFA。`compile_program`
// 把富语法树 `Ast` 发射为指令数组（绝对地址跳转）。
//
// paper-to-code：Thompson 1968 正则构造的程序化形式（Russ Cox《Regular
// Expression Matching: the Virtual Machine Approach》）。发射规则：
//   * `Lit`/`Set` → `IChar`/`ISet`；
//   * `Concat` → 顺序拼接；
//   * `Alt(a,b,..)` → 链式 `ISplit`（书写顺序定优先级）；
//   * `Group(Some(g))` → `ISave(2g)` … 子程序 … `ISave(2g+1)`；非捕获组不发 `ISave`；
//   * `Repeat`：贪婪 `*` 为 `Split(body,out)`，惰性 `*?` 为 `Split(out,body)`
//     （仅调换 Split 两臂优先级即统一贪婪 / 惰性）；`min` 份强制副本 + 上界处理；
//   * `Assert` → `IAssert`；`Look` → `ILook(positive, 子程序)`；
//   * 整个程序以 `ISave(0)` … `ISave(1)` 包裹整体匹配区间（第 0 组），末尾 `IMatch`。

///|
/// Pike VM 指令（instruction）。对外只读（`pub`），仅包内构造 / 匹配。
pub enum Inst {
  /// 消费匹配单字符。
  IChar(Char)
  /// 消费匹配字符集合（含 `.`、`\d` 等）。
  ISet(CharSet)
  /// 分叉：先尝试 a（高优先级）后 b。
  ISplit(Int, Int)
  /// 无条件跳转。
  IJmp(Int)
  /// 写捕获寄存器 slot（`2*group` / `2*group+1`）。
  ISave(Int)
  /// 零宽位置断言。
  IAssert(AssertKind)
  /// 前瞻：在当前位置锚定执行子程序（不消费输入）。
  ILook(positive~ : Bool, prog~ : Program)
  /// 匹配成功。
  IMatch
}

///|
/// Pike VM 程序（compiled program）。
///
///   * `insts`      —— 线性指令数组；
///   * `num_groups` —— 捕获组数（不含第 0 组整体匹配；slots 长度 `2*(num_groups+1)`）；
///   * `names`      —— 命名组「名称 → 编号」；
///   * `flags`      —— 编译标志集。
pub struct Program {
  insts : Array[Inst]
  num_groups : Int
  names : Map[String, Int]
  flags : Flags
  // 字面量预过滤策略（T2.1）：从 AST 推导的「匹配必经首字符集」，供 `exec_chars`
  // 在无在飞线程时快速跳过不可能起点。不影响匹配语义（见 `prefilter.mbt`）。
  prefilter : Prefilter
}

///|
/// 把富语法树编译为 Pike VM 程序（R2.1）。
pub fn compile_program(ast : Ast, flags? : Flags = Flags::default()) -> Program {
  let insts : Array[Inst] = []
  insts.push(ISave(0))
  emit_node(insts, ast, flags)
  insts.push(ISave(1))
  insts.push(IMatch)
  let names : Map[String, Int] = Map([])
  ast_collect_names(ast, names)
  let prefilter = compute_prefilter(ast, flags)
  { insts, num_groups: ast_max_group(ast), names, flags, prefilter }
}

///|
/// 返回禁用字面量预过滤的等价程序（`prefilter = PfNone`），其余完全不变。
///
/// 供差分属性测试与基准对照使用：「开启预过滤」与「禁用预过滤」必须在任意
/// 输入上产出逐位相等的匹配结果（T2.1 正确性不变量），而基准可量化两者时差。
pub fn Program::without_prefilter(self : Program) -> Program {
  { ..self, prefilter: PfNone }
}

///|
/// 递归发射一个 AST 节点的指令（落在 `insts` 末尾，自然顺序衔接后继）。
fn emit_node(insts : Array[Inst], ast : Ast, flags : Flags) -> Unit {
  match ast {
    Empty => ()
    Lit(c) =>
      if flags.ignore_case {
        insts.push(ISet(char_set_of_char(c).case_fold()))
      } else {
        insts.push(IChar(c))
      }
    Set(cs) =>
      if flags.ignore_case {
        insts.push(ISet(cs.case_fold()))
      } else {
        insts.push(ISet(cs))
      }
    Concat(parts) =>
      for p in parts {
        emit_node(insts, p, flags)
      }
    Alt(branches) => emit_alt(insts, branches, flags)
    Repeat(node~, min~, max~, greedy~) =>
      emit_repeat(insts, node, min, max, greedy, flags)
    Group(body~, index~, name~) => {
      ignore(name)
      match index {
        Some(g) => {
          insts.push(ISave(2 * g))
          emit_node(insts, body, flags)
          insts.push(ISave(2 * g + 1))
        }
        None => emit_node(insts, body, flags)
      }
    }
    Assert(kind) => insts.push(IAssert(kind))
    Look(positive~, body~) => {
      let sub = compile_program(body, flags~)
      insts.push(ILook(positive~, prog=sub))
    }
  }
}

///|
/// 发射择一：链式 `ISplit`，各分支末尾 `IJmp` 汇合至结尾（书写顺序定优先级）。
fn emit_alt(insts : Array[Inst], branches : Array[Ast], flags : Flags) -> Unit {
  if branches.length() == 0 {
    return
  }
  if branches.length() == 1 {
    emit_node(insts, branches[0], flags)
    return
  }
  let jmp_idxs : Array[Int] = []
  let last = branches.length() - 1
  for i in 0..<branches.length() {
    if i < last {
      let split_idx = insts.length()
      insts.push(ISplit(0, 0))
      let body_start = insts.length()
      emit_node(insts, branches[i], flags)
      let jmp_idx = insts.length()
      insts.push(IJmp(0))
      jmp_idxs.push(jmp_idx)
      let next = insts.length()
      insts[split_idx] = ISplit(body_start, next)
    } else {
      emit_node(insts, branches[i], flags)
    }
  }
  let end = insts.length()
  for j in jmp_idxs {
    insts[j] = IJmp(end)
  }
}

///|
/// 发射重复：`min` 份强制副本，随后按上界附加星闭包（无上界）或 `(max-min)`
/// 份可选副本（有上界）。
fn emit_repeat(
  insts : Array[Inst],
  node : Ast,
  min : Int,
  max : Int?,
  greedy : Bool,
  flags : Flags,
) -> Unit {
  for _i in 0..<min {
    emit_node(insts, node, flags)
  }
  match max {
    None => emit_star(insts, node, greedy, flags)
    Some(n) =>
      if n > min {
        for _i in 0..<(n - min) {
          emit_optional(insts, node, greedy, flags)
        }
      }
  }
}

///|
/// 发射星闭包 `*`：`L: Split(body,out); body; Jmp(L); out:`（惰性调换臂序）。
fn emit_star(
  insts : Array[Inst],
  node : Ast,
  greedy : Bool,
  flags : Flags,
) -> Unit {
  let split_idx = insts.length()
  insts.push(ISplit(0, 0))
  let body_start = insts.length()
  emit_node(insts, node, flags)
  insts.push(IJmp(split_idx))
  let out = insts.length()
  if greedy {
    insts[split_idx] = ISplit(body_start, out)
  } else {
    insts[split_idx] = ISplit(out, body_start)
  }
}

///|
/// 发射可选 `?`：`Split(body,out); body; out:`（惰性调换臂序）。
fn emit_optional(
  insts : Array[Inst],
  node : Ast,
  greedy : Bool,
  flags : Flags,
) -> Unit {
  let split_idx = insts.length()
  insts.push(ISplit(0, 0))
  let body_start = insts.length()
  emit_node(insts, node, flags)
  let out = insts.length()
  if greedy {
    insts[split_idx] = ISplit(body_start, out)
  } else {
    insts[split_idx] = ISplit(out, body_start)
  }
}

///|
/// 计算 AST 中最大捕获组编号（即捕获组数；无捕获组返回 0）。含前瞻内部的组，
/// 使外层 slots 数组覆盖按源顺序编号的全部组。
fn ast_max_group(ast : Ast) -> Int {
  match ast {
    Group(body~, index~, ..) => {
      let here = match index {
        Some(g) => g
        None => 0
      }
      let inner = ast_max_group(body)
      if here > inner {
        here
      } else {
        inner
      }
    }
    Concat(parts) => {
      let mut m = 0
      for p in parts {
        let x = ast_max_group(p)
        if x > m {
          m = x
        }
      }
      m
    }
    Alt(branches) => {
      let mut m = 0
      for b in branches {
        let x = ast_max_group(b)
        if x > m {
          m = x
        }
      }
      m
    }
    Repeat(node~, ..) => ast_max_group(node)
    Look(body~, ..) => ast_max_group(body)
    _ => 0
  }
}

///|
/// 收集 AST 中全部命名组「名称 → 编号」到 `names`。
fn ast_collect_names(ast : Ast, names : Map[String, Int]) -> Unit {
  match ast {
    Group(body~, index~, name~) => {
      match (name, index) {
        (Some(nm), Some(g)) => names[nm] = g
        _ => ()
      }
      ast_collect_names(body, names)
    }
    Concat(parts) =>
      for p in parts {
        ast_collect_names(p, names)
      }
    Alt(branches) =>
      for b in branches {
        ast_collect_names(b, names)
      }
    Repeat(node~, ..) => ast_collect_names(node, names)
    Look(body~, ..) => ast_collect_names(body, names)
    _ => ()
  }
}
