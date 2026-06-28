// out_of_ssa.mbt —— SSA 析构（out-of-SSA），旗舰深化旁路新增。
//
// paper-to-code：Sreedhar et al. / Boissinot 等的 φ 消除与并行复制破环序列化。
//   * 将每个 φ `dest = φ(a_1..a_p)` 消除为：在第 i 个前驱→汇合块的边上插入复制
//     `dest ← a_i`（R7.1）；
//   * 同一边上的多个 φ 形成一组「并行复制」，以「就绪节点优先 + 环检测引入临时」
//     序列化为保持并行语义的串行复制序列（R7.2/7.3）；
//   * 析构后程序不含任何 φ（R7.4）。
//
// 设计落点（design.md §4.4，R7）。本模型为块结构 IR：边上复制落地为在前驱块
// 终结指令之前追加复制指令。沿任意 entry-rooted 路径解释执行时，到达汇合块前
// 最后执行的复制恰对应其直接前驱（更早前驱写入的同名目标被覆盖），故与 SSA 的
// φ 选择语义一致（语义等价见 prop_out_of_ssa_test.mbt，P12）。φ 落点复用
// `reconstruct_phi_sites`（evaluate.mbt）。

///|
/// 将一组并行复制 `[(dst, src)]` 序列化为保持并行语义的串行复制序列。
///
/// 算法：反复发射「目标不被任何待处理复制用作源」的复制（就绪优先）；当仅剩
/// 复制环时，引入临时变量保存环中某目标的旧值并将对其的源引用重定向到临时，
/// 从而打破环（经典 out-of-SSA 破环法）。临时变量以负号 `id`（`-1, -2, …`）
/// 标识，与非负版本号互不冲突。平凡复制（`dst == src`）被略去。
pub fn sequentialize_parallel_copy(
  copies : Array[(Var, Var)],
) -> Array[(Var, Var)] {
  let pending : Array[(Var, Var)] = []
  for c in copies {
    let (d, s) = c
    if d.id != s.id {
      pending.push((d, s))
    }
  }
  let result : Array[(Var, Var)] = []
  let mut tempctr = 0
  let mut steps = 0
  let limit = copies.length() * copies.length() + copies.length() + 4
  while pending.length() > 0 && steps <= limit {
    steps = steps + 1
    // 找一个目标不被任何待处理复制用作源的复制（就绪）。
    let mut idx = -1
    for i in 0..<pending.length() {
      let (d, _) = pending[i]
      let mut used = false
      for j in 0..<pending.length() {
        let (_, sj) = pending[j]
        if sj.id == d.id {
          used = true
          break
        }
      }
      if !(used) {
        idx = i
        break
      }
    }
    if idx >= 0 {
      result.push(pending[idx])
      pending.remove(idx) |> ignore
    } else {
      // 仅剩环：保存 pending[0] 的目标到临时并重定向源。
      let (d, _) = pending[0]
      tempctr = tempctr + 1
      let t : Var = { id: -tempctr }
      result.push((t, d))
      let newpending : Array[(Var, Var)] = []
      for c in pending {
        let (dj, sj) = c
        if sj.id == d.id {
          newpending.push((dj, t))
        } else {
          newpending.push((dj, sj))
        }
      }
      pending.clear()
      for c in newpending {
        pending.push(c)
      }
    }
  }
  result
}

///|
/// 一个记号是否为终结指令（`ret` / `br` / `cbr`）。
fn is_terminator(instr : String) -> Bool {
  let toks = tokenize(instr)
  if toks.length() == 0 {
    return false
  }
  toks[0] == "ret" || toks[0] == "br" || toks[0] == "cbr"
}

///|
/// 将复制指令插入到块的终结指令之前（无终结指令则追加到末尾）。
fn insert_before_terminator(
  instrs : Array[String],
  extra : Array[String],
) -> Array[String] {
  if extra.length() == 0 {
    return instrs
  }
  let n = instrs.length()
  if n > 0 && is_terminator(instrs[n - 1]) {
    let out : Array[String] = []
    for i in 0..<(n - 1) {
      out.push(instrs[i])
    }
    for e in extra {
      out.push(e)
    }
    out.push(instrs[n - 1])
    out
  } else {
    let out : Array[String] = []
    for i in instrs {
      out.push(i)
    }
    for e in extra {
      out.push(e)
    }
    out
  }
}

///|
/// SSA 析构：消除全部 φ，产出语义等价、不含 φ 的程序。
pub fn destruct_ssa(p : SsaProgram) -> SsaProgram {
  let sites = reconstruct_phi_sites(p)
  // id → 变量名（块内定义 + φ 目标），用于复制指令记号重建。
  let id2name : Map[Int, String] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        match split_versioned(toks[0]) {
          Some((nm, v)) => id2name[v] = nm
          None => ()
        }
      }
    }
  }
  for s in sites {
    id2name[s.dest] = s.var_name
    for a in s.args {
      // 实参变量名与 φ 同名（同一变量的不同版本）。
      id2name[a] = s.var_name
    }
  }
  // 按前驱块分组收集边上的并行复制。
  let copies_by_pred : Map[String, Array[(Var, Var)]] = Map([])
  for s in sites {
    for i in 0..<s.preds.length() {
      if i < s.args.length() {
        let pred = s.preds[i]
        let lst = copies_by_pred.get(pred).unwrap_or([])
        lst.push(({ id: s.dest }, { id: s.args[i] }))
        copies_by_pred[pred] = lst
      }
    }
  }
  let new_blocks : Array[BasicBlock] = []
  for b in p.blocks {
    let copies = copies_by_pred.get(b.label).unwrap_or([])
    if copies.length() == 0 {
      new_blocks.push({ label: b.label, instrs: b.instrs, succs: b.succs })
      continue
    }
    let seq = sequentialize_parallel_copy(copies)
    let copy_instrs : Array[String] = []
    for c in seq {
      let (d, s) = c
      copy_instrs.push(
        token_of(d.id, id2name) + " = " + token_of(s.id, id2name),
      )
    }
    let new_instrs = insert_before_terminator(b.instrs, copy_instrs)
    new_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  { blocks: new_blocks, phis: [] }
}

///|
/// 由 `Var.id` 重建复制指令记号：负 id 为临时（`tmp<n>`）；已知版本变量为
/// `name#id`；其余回退为 `v<id>`。
fn token_of(id : Int, id2name : Map[Int, String]) -> String {
  if id < 0 {
    "tmp" + (-id).to_string()
  } else {
    match id2name.get(id) {
      Some(name) => name + "#" + id.to_string()
      None => "v" + id.to_string()
    }
  }
}
