// sccp.mbt —— 稀疏条件常量传播（Sparse Conditional Constant Propagation），
// 旗舰深化旁路新增。
//
// paper-to-code：Wegman, Zadeck 1991《Constant Propagation with Conditional
// Branches》。联合维护两套信息至不动点：
//   * 每个 SSA 变量的格值（lattice value）：Top（未定）→ Const（常量）→
//     Bottom（不确定），单调下降；
//   * 每条 CFG 边的可达性：从入口出发，常量条件分支仅选定后继边可达。
//
// 设计落点（design.md §4.5，R8）：
//   * R8.1：格值 × 边可达性工作表迭代至不动点；
//   * R8.2：不动点处常量变量的全部使用替换为常量字面量；
//   * R8.3：常量条件分支仅选定后继边标记可达，另一边不可达；
//   * R8.4：仅折叠/替换、不新增定义，保持 SSA 单赋值不变量。
//
// φ 落点信息复用 evaluate.mbt 的 `reconstruct_phi_sites`（按前驱序对应实参）；
// 算术沿用既有 `fold_op` 的 `+ - *` 语义；非整型/外部输入变量取 Bottom。
// 输出对块结构无损（不删除不可达块），保证下游沿任意 entry-rooted 路径仍可解释。

///|
/// SCCP 格值：`Top`（未证明非常量）⊐ `Const(Int)`（已知常量）⊐ `Bottom`
/// （over-defined，随输入而变）。
pub(all) enum LatticeValue {
  Top
  Const(Int)
  Bottom
} derive(Eq, Show)

///|
/// 格的 meet（greatest lower bound）：Top 为单位元；同值常量相遇仍为该常量，
/// 异值常量相遇降为 Bottom；与 Bottom 相遇恒为 Bottom。
fn lat_meet(a : LatticeValue, b : LatticeValue) -> LatticeValue {
  match (a, b) {
    (Top, x) => x
    (x, Top) => x
    (Bottom, _) => Bottom
    (_, Bottom) => Bottom
    (Const(x), Const(y)) => if x == y { Const(x) } else { Bottom }
  }
}

///|
/// 取记号格值：整型字面量为 `Const`；已登记的定义记号查 `values`（缺省 `Top`）；
/// 其余（外部输入变量、未知记号）取 `Bottom`（随输入而变，不可折叠）。
fn token_lattice(
  tok : String,
  values : Map[String, LatticeValue],
  defset : Map[String, Bool],
) -> LatticeValue {
  match parse_int(tok) {
    Some(n) => Const(n)
    None =>
      if defset.contains(tok) {
        values.get(tok).unwrap_or(Top)
      } else {
        Bottom
      }
  }
}

///|
/// 计算一条定义指令右值的格值。
///   * 复制 `lhs = src`：取 `src` 的格值；
///   * 二元 `lhs = a op b`：任一为 Bottom → Bottom；任一为 Top → Top；
///     两者皆 Const → 折叠（不可折叠运算符 → Bottom）。
fn eval_def_lattice(
  toks : Array[String],
  values : Map[String, LatticeValue],
  defset : Map[String, Bool],
) -> LatticeValue {
  if toks.length() == 3 {
    token_lattice(toks[2], values, defset)
  } else if toks.length() == 5 {
    let x = token_lattice(toks[2], values, defset)
    let y = token_lattice(toks[4], values, defset)
    match (x, y) {
      (Bottom, _) => Bottom
      (_, Bottom) => Bottom
      (Top, _) => Top
      (_, Top) => Top
      (Const(cx), Const(cy)) =>
        match fold_op(toks[3], cx, cy) {
          Some(r) => Const(r)
          None => Bottom
        }
    }
  } else {
    Bottom
  }
}

///|
/// 计算块在当前格值下的可达后继标签集合。
///
/// 若块含条件分支 `cbr c L1 L2` 且 `c` 为常量：非零取 `L1`、零取 `L2`（仅选定边
/// 可达，R8.3）；否则全部 `succs` 可达。仅返回确实存在于 `succs` 中的标签。
fn reachable_succs(
  b : BasicBlock,
  values : Map[String, LatticeValue],
  defset : Map[String, Bool],
) -> Array[String] {
  for instr in b.instrs {
    let toks = tokenize(instr)
    if toks.length() >= 4 && toks[0] == "cbr" {
      match token_lattice(toks[1], values, defset) {
        Const(k) => {
          let chosen = if k != 0 { toks[2] } else { toks[3] }
          let out : Array[String] = []
          for s in b.succs {
            if s == chosen {
              out.push(s)
            }
          }
          // 若选定标签不在 succs（异常输入），回退为全部 succs 以保守可达。
          return if out.length() > 0 { out } else { b.succs }
        }
        _ => return b.succs
      }
    }
  }
  b.succs
}

///|
/// 稀疏条件常量传播：分析至不动点后折叠常量、替换常量变量的使用。
pub fn sccp(p : SsaProgram) -> SsaProgram {
  if p.blocks.length() == 0 {
    return p
  }
  let entry = p.blocks[0].label
  let by_label : Map[String, BasicBlock] = Map([])
  for b in p.blocks {
    by_label[b.label] = b
  }
  // 定义记号集合 + 初始格值（全部 Top）。
  let defset : Map[String, Bool] = Map([])
  let values : Map[String, LatticeValue] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        defset[toks[0]] = true
        values[toks[0]] = Top
      }
    }
  }
  let sites = reconstruct_phi_sites(p)
  for s in sites {
    let t = s.var_name + "#" + s.dest.to_string()
    defset[t] = true
    values[t] = Top
  }
  let sites_by_block : Map[String, Array[PhiSite]] = Map([])
  for s in sites {
    let lst = sites_by_block.get(s.block).unwrap_or([])
    lst.push(s)
    sites_by_block[s.block] = lst
  }
  // ---- 工作表不动点：交替更新可达性与格值，直至稳定 ----
  let limit = defset.size() * 2 + p.blocks.length() * 2 + 8
  let mut prev_reach_size = -1
  let mut iter = 0
  let mut reach_block : Map[String, Bool] = Map([])
  let mut reach_edge : Map[(String, String), Bool] = Map([])
  while iter <= limit {
    // 1) 重算可达块 / 可达边（BFS from entry）。
    let rb : Map[String, Bool] = Map([])
    let re : Map[(String, String), Bool] = Map([])
    let queue : Array[String] = []
    if by_label.contains(entry) {
      rb[entry] = true
      queue.push(entry)
    }
    let mut qi = 0
    while qi < queue.length() {
      let lbl = queue[qi]
      qi = qi + 1
      match by_label.get(lbl) {
        Some(b) =>
          for s in reachable_succs(b, values, defset) {
            re[(lbl, s)] = true
            if not(rb.contains(s)) {
              rb[s] = true
              queue.push(s)
            }
          }
        None => ()
      }
    }
    // 2) 重算可达块内定义的格值（含 φ）。
    let mut changed = false
    for b in p.blocks {
      if not(rb.contains(b.label)) {
        continue
      }
      for instr in b.instrs {
        let toks = tokenize(instr)
        if toks.length() >= 2 && toks[1] == "=" {
          let nv = eval_def_lattice(toks, values, defset)
          if values.get(toks[0]).unwrap_or(Top) != nv {
            values[toks[0]] = nv
            changed = true
          }
        }
      }
      match sites_by_block.get(b.label) {
        Some(plist) =>
          for site in plist {
            let mut acc : LatticeValue = Top
            for i in 0..<site.preds.length() {
              if i < site.args.length() &&
                re.contains((site.preds[i], site.block)) {
                let at = site.var_name + "#" + site.args[i].to_string()
                acc = lat_meet(acc, token_lattice(at, values, defset))
              }
            }
            let dt = site.var_name + "#" + site.dest.to_string()
            if values.get(dt).unwrap_or(Top) != acc {
              values[dt] = acc
              changed = true
            }
          }
        None => ()
      }
    }
    reach_block = rb
    reach_edge = re
    if not(changed) && rb.size() == prev_reach_size {
      break
    }
    prev_reach_size = rb.size()
    iter = iter + 1
  }
  let _ = reach_block
  let _ = reach_edge
  // ---- 变换：折叠常量、替换常量变量的使用（块结构无损）----
  let new_blocks : Array[BasicBlock] = []
  for b in p.blocks {
    let new_instrs : Array[String] = []
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        // 定义：保留 lhs，仅替换右值常量使用，必要时整表达式折叠。
        let out : Array[String] = [toks[0], "="]
        let mut j = 2
        while j < toks.length() {
          out.push(sccp_rewrite(toks[j], values, defset))
          j = j + 1
        }
        // 全常量二元表达式折叠为单字面量。
        if out.length() == 5 {
          match (parse_int(out[2]), parse_int(out[4])) {
            (Some(x), Some(y)) =>
              match fold_op(out[3], x, y) {
                Some(r) => {
                  new_instrs.push(join_tokens([out[0], "=", r.to_string()]))
                  continue
                }
                None => ()
              }
            _ => ()
          }
        }
        new_instrs.push(join_tokens(out))
      } else {
        // 非定义（ret / br / cbr）：替换其中常量变量使用（关键字/标签不受影响）。
        let out : Array[String] = []
        for t in toks {
          out.push(sccp_rewrite(t, values, defset))
        }
        new_instrs.push(join_tokens(out))
      }
    }
    new_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  { blocks: new_blocks, phis: p.phis }
}

///|
/// 若记号格值为常量则替换为其字面量，否则原样返回（运算符、标签、Bottom 变量
/// 不受影响）。
fn sccp_rewrite(
  tok : String,
  values : Map[String, LatticeValue],
  defset : Map[String, Bool],
) -> String {
  match token_lattice(tok, values, defset) {
    Const(c) =>
      // 已是字面量则保持；变量记号替换为常量。
      match parse_int(tok) {
        Some(_) => tok
        None => c.to_string()
      }
    _ => tok
  }
}
