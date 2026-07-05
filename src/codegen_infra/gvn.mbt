// gvn.mbt —— 全局值编号（Global Value Numbering）与强化 DCE / 复制传播，
// 旗舰深化旁路新增。
//
// paper-to-code：值编号（value numbering）；Appel《Modern Compiler
// Implementation》。为「相同操作符 + 相同值编号操作数」的表达式赋同一值编号，
// 将后继冗余计算替换为对先前等价计算结果的引用（R9.1）。
//
// 设计落点（design.md §4.6，R9）：
//   * `gvn`：支配性约束下的全局值编号合并（仅当代表定义支配冗余定义时合并，
//     从而沿任意 entry-rooted 路径语义安全），再施加强化复制传播与 DCE；
//   * `dce_strong`：删除无活跃使用且无副作用的定义，迭代至不动点（R9.2）；
//   * `copy_prop_strong`：复制目标使用替换为源并删除复制，迭代至不动点（R9.3）。
// 三者仅删除/改写、不新增定义，保持 SSA 单赋值不变量（R9.4）。
// 复用既有私有 `pass_dead_code_elim`/`pass_copy_prop`/`tokenize`/`version_id`，
// 支配信息复用 `build_dom_tree`/`DomTree::dominates`、φ 落点复用
// `reconstruct_phi_sites`。

///|
/// 程序签名：拼接全部块标签 / 指令与 φ（目标 + 实参），用于不动点收敛判定。
fn program_signature(p : SsaProgram) -> String {
  let parts : Array[String] = []
  for b in p.blocks {
    parts.push("B:" + b.label)
    for instr in b.instrs {
      parts.push("I:" + instr)
    }
    for s in b.succs {
      parts.push("S:" + s)
    }
  }
  for phi in p.phis {
    let a = StringBuilder::new()
    a.write_string("PHI:")
    a.write_string(phi.dest.id.to_string())
    a.write_string("<-")
    for arg in phi.args {
      a.write_string(arg.id.to_string())
      a.write_char(',')
    }
    parts.push(a.to_string())
  }
  join_tokens(parts)
}

///|
/// 强化死代码消除：迭代施加既有 `pass_dead_code_elim` 直至不动点。
pub fn dce_strong(p : SsaProgram) -> SsaProgram {
  let mut cur = p
  let mut sig = program_signature(cur)
  let mut iter = 0
  let limit = total_instr_count(p) + p.phis.length() + 4
  while iter <= limit {
    let next = pass_dead_code_elim(cur)
    let nsig = program_signature(next)
    if nsig == sig {
      return next
    }
    cur = next
    sig = nsig
    iter = iter + 1
  }
  cur
}

///|
/// 强化复制传播：迭代施加既有 `pass_copy_prop` 直至不动点（消解复制链）。
pub fn copy_prop_strong(p : SsaProgram) -> SsaProgram {
  let mut cur = p
  let mut sig = program_signature(cur)
  let mut iter = 0
  let limit = total_instr_count(p) + p.phis.length() + 4
  while iter <= limit {
    let next = pass_copy_prop(cur)
    let nsig = program_signature(next)
    if nsig == sig {
      return next
    }
    cur = next
    sig = nsig
    iter = iter + 1
  }
  cur
}

///|
/// 程序内块级指令总数（迭代上界估算）。
fn total_instr_count(p : SsaProgram) -> Int {
  let mut n = 0
  for b in p.blocks {
    n = n + b.instrs.length()
  }
  n
}

///|
/// 操作数记号的值编号：字面量 → `L|n`；外部输入 → `E|tok`；已编号定义 → 其值
/// 编号；尚未编号（前向/回边引用）→ 唯一回退 `U|tok`（杜绝错误合并）。
fn operand_vn(
  tok : String,
  vn_of : Map[String, String],
  defset : Map[String, Bool],
) -> String {
  match parse_int(tok) {
    Some(n) => "L|" + n.to_string()
    None =>
      if defset.contains(tok) {
        match vn_of.get(tok) {
          Some(k) => k
          None => "U|" + tok
        }
      } else {
        "E|" + tok
      }
  }
}

///|
/// 一条定义指令右值的值编号（copy 取源值编号，binop 取「操作符 + 操作数值编号」，
/// 其它形式取唯一文本编号）。
fn def_value_number(
  toks : Array[String],
  vn_of : Map[String, String],
  defset : Map[String, Bool],
) -> String {
  if toks.length() == 3 {
    operand_vn(toks[2], vn_of, defset)
  } else if toks.length() == 5 {
    let a = operand_vn(toks[2], vn_of, defset)
    let b = operand_vn(toks[4], vn_of, defset)
    // 交换律规范化：+ / * 的操作数按值编号字典序定序，
    // 使 `a + b` 与 `b + a` 获同一值编号。
    let (x, y) = if (toks[3] == "+" || toks[3] == "*") && b < a {
      (b, a)
    } else {
      (a, b)
    }
    "B|" + toks[3] + "|" + x + "|" + y
  } else {
    "U|" + join_tokens(toks)
  }
}

///|
/// 最近公共支配者（nearest common dominator）：沿 idom 父链求 `a`、`b`
/// 的公共祖先中最深者。两块均可达时必存在（至少为入口）。
fn dom_ncd(dom : DomTree, a : String, b : String) -> String {
  let anc : Map[String, Bool] = Map([])
  let mut x = a
  let limit = dom.reachable.length() + 1
  let mut steps = 0
  while steps <= limit {
    anc[x] = true
    match dom.idom.get(x) {
      Some(p) => x = p
      None => break
    }
    steps = steps + 1
  }
  let mut y = b
  steps = 0
  while steps <= limit {
    if anc.contains(y) {
      return y
    }
    match dom.idom.get(y) {
      Some(p) => y = p
      None => return y
    }
    steps = steps + 1
  }
  dom.root
}

///|
/// 沿冗余映射追溯到代表记号（消解链，bounded）。
fn resolve_rep(tok : String, redundant : Map[String, String]) -> String {
  let mut cur = tok
  let mut steps = 0
  while steps < 100000 {
    match redundant.get(cur) {
      Some(r) => cur = r
      None => return cur
    }
    steps = steps + 1
  }
  cur
}

///|
/// 全局值编号：支配性约束下合并计算等价表达式，并施加强化复制传播与 DCE。
pub fn gvn(p : SsaProgram) -> SsaProgram {
  if p.blocks.length() == 0 {
    return p
  }
  let entry = p.blocks[0].label
  let dom = build_dom_tree(p.blocks, entry~)
  let by_label : Map[String, BasicBlock] = Map([])
  for b in p.blocks {
    by_label[b.label] = b
  }
  // 定义记号集合 + 定义所在块 + id→记号 映射。
  let defset : Map[String, Bool] = Map([])
  let block_of : Map[String, String] = Map([])
  let id2token : Map[Int, String] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        defset[toks[0]] = true
        block_of[toks[0]] = b.label
        match version_id(toks[0]) {
          Some(v) => id2token[v] = toks[0]
          None => ()
        }
      }
    }
  }
  let sites = reconstruct_phi_sites(p)
  let sites_by_block : Map[String, Array[PhiSite]] = Map([])
  for s in sites {
    let dt = s.var_name + "#" + s.dest.to_string()
    defset[dt] = true
    block_of[dt] = s.block
    id2token[s.dest] = dt
    let lst = sites_by_block.get(s.block).unwrap_or([])
    lst.push(s)
    sites_by_block[s.block] = lst
  }
  // ---- 支配树前序值编号 ----
  let vn_of : Map[String, String] = Map([])
  let representative : Map[String, String] = Map([])
  let redundant : Map[String, String] = Map([])
  // 上提计划：代表定义记号 → 目标块标签（变换阶段从原块移除、
  // 插入目标块终结指令前；按支配树前序规划，依赖先于使用入列）。
  let hoist_to : Map[String, String] = Map([])
  for lbl in dom.reachable {
    // φ 目标：唯一值编号（不参与表达式合并）。
    match sites_by_block.get(lbl) {
      Some(plist) =>
        for site in plist {
          let dt = site.var_name + "#" + site.dest.to_string()
          vn_of[dt] = "P|" + dt
        }
      None => ()
    }
    match by_label.get(lbl) {
      Some(b) =>
        for instr in b.instrs {
          let toks = tokenize(instr)
          if toks.length() >= 2 && toks[1] == "=" {
            let d = toks[0]
            let key = def_value_number(toks, vn_of, defset)
            match representative.get(key) {
              Some(r) => {
                let rb = block_of.get(r).unwrap_or("")
                if dom.dominates(rb, lbl) {
                  redundant[d] = r
                } else if toks.length() == 5 &&
                  (toks[3] == "+" || toks[3] == "-" || toks[3] == "*") {
                  // PRE 式代码上提（code hoisting）：同一值编号在互不支配的
                  // 两块各算一次（典型菱形双臂冗余）时，若两操作数在最近
                  // 公共支配者处均可用（字面量/外部输入/定义块支配之），
                  // 将代表定义上提至该块终结指令前，另一臂改写为引用。
                  // 纯整数 + - * 无副作用无陷阱，推测执行语义安全。
                  let tgt = dom_ncd(dom, rb, lbl)
                  let mut ok = true
                  for j in [2, 4] {
                    let t = toks[j]
                    if parse_int(t) is Some(_) {
                      continue
                    }
                    if defset.contains(t) {
                      if !dom.dominates(block_of.get(t).unwrap_or(""), tgt) {
                        ok = false
                        break
                      }
                    }
                  }
                  if ok {
                    hoist_to[r] = tgt
                    block_of[r] = tgt
                    redundant[d] = r
                  }
                }
              }
              None => representative[key] = d
            }
            vn_of[d] = key
          }
        }
      None => ()
    }
  }
  // ---- 变换：删除冗余定义、使用替换为代表、落实上提计划 ----
  // 按规划顺序收集各目标块待插入的上提指令（使用已重写为代表）。
  let hoist_instrs : Map[String, Array[String]] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" && hoist_to.contains(toks[0]) {
        let out : Array[String] = [toks[0], "="]
        let mut j = 2
        while j < toks.length() {
          out.push(gvn_rewrite_use(toks[j], redundant))
          j = j + 1
        }
        let tgt = hoist_to.get(toks[0]).unwrap_or(b.label)
        let lst = hoist_instrs.get(tgt).unwrap_or([])
        lst.push(join_tokens(out))
        hoist_instrs[tgt] = lst
      }
    }
  }
  let new_blocks : Array[BasicBlock] = []
  for b in p.blocks {
    let new_instrs : Array[String] = []
    for instr in b.instrs {
      let toks = tokenize(instr)
      if toks.length() >= 2 && toks[1] == "=" {
        let d = toks[0]
        if redundant.contains(d) {
          continue // 删除冗余计算
        }
        if hoist_to.contains(d) {
          continue // 已上提至支配块，原址删除
        }
        let out : Array[String] = [toks[0], "="]
        let mut j = 2
        while j < toks.length() {
          out.push(gvn_rewrite_use(toks[j], redundant))
          j = j + 1
        }
        new_instrs.push(join_tokens(out))
      } else {
        let out : Array[String] = []
        for t in toks {
          out.push(gvn_rewrite_use(t, redundant))
        }
        new_instrs.push(join_tokens(out))
      }
    }
    // 落实上提：插入到终结指令（br/cbr/ret）之前；无终结指令则追加。
    match hoist_instrs.get(b.label) {
      Some(hs) => {
        let mut ins_at = new_instrs.length()
        if ins_at > 0 && is_terminator(new_instrs[ins_at - 1]) {
          ins_at = ins_at - 1
        }
        for h in hs {
          new_instrs.insert(ins_at, h)
          ins_at = ins_at + 1
        }
      }
      None => ()
    }
    new_blocks.push({ label: b.label, instrs: new_instrs, succs: b.succs })
  }
  // ---- φ 实参替换为代表版本 ----
  let new_phis : Array[Phi] = []
  for phi in p.phis {
    let new_args : Array[Var] = []
    for a in phi.args {
      match id2token.get(a.id) {
        Some(tok) =>
          if redundant.contains(tok) {
            let rep = resolve_rep(tok, redundant)
            match version_id(rep) {
              Some(v) => new_args.push({ id: v })
              None => new_args.push(a)
            }
          } else {
            new_args.push(a)
          }
        None => new_args.push(a)
      }
    }
    new_phis.push({ dest: phi.dest, args: new_args })
  }
  let merged : SsaProgram = { blocks: new_blocks, phis: new_phis }
  // ---- 强化复制传播 + DCE 清理 ----
  dce_strong(copy_prop_strong(merged))
}

///|
/// 若记号为冗余定义，替换为其代表记号，否则原样返回。
fn gvn_rewrite_use(tok : String, redundant : Map[String, String]) -> String {
  if redundant.contains(tok) {
    resolve_rep(tok, redundant)
  } else {
    tok
  }
}
