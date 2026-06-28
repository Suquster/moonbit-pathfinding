// ssa_min.mbt —— 最小 SSA 构造（Cytron 支配边界 φ 放置 + 支配树驱动重命名），
// 旗舰深化旁路新增。
//
// paper-to-code：Cytron, Ferrante, Rosen, Wegman, Zadeck 1991《Efficiently
// Computing Static Single Assignment Form and the Control Dependence Graph》。
//   ① 在变量定义块集合的「迭代支配边界」处放置 φ（最小 φ 放置，R6.1/6.5）；
//   ② φ 实参个数等于汇合块前驱数（R6.2）；
//   ③ 沿支配树前序遍历、以版本号栈重命名定义与使用（R6.3）。
//
// 设计落点（design.md §4.3，R6）：既有 `build_ssa` 行为完全冻结，本模块以旁路
// `build_ssa_minimal(blocks, entry~)` 提供。版本编号沿用 `build_ssa` 的全局扫描
// 序约定——先按块/指令扫描序为每个定义分配版本号，再为 φ 目标分配后续版本号，
// 从而在「直线代码 / 简单菱形」等最小文法输入上与冻结 `build_ssa` 的 φ 数量、
// 版本化文本与块结构逐字段一致（R6.4）；在一般 CFG 上则给出正确的 Cytron 最小
// SSA。复用同包私有辅助 `tokenize`/`join_tokens`/`versioned`/`version_id`、
// `instr_use_def`/`array_contains_str`（liveness.mbt）、`build_dom_tree`/
// `dominance_frontier`（dominator.mbt）与 `preds_in_order`（evaluate.mbt）。

///|
/// 构造最小 SSA 程序（Cytron 支配边界 φ 放置 + 支配树前序重命名）。
///
/// 步骤：
///   1) `build_dom_tree` + `dominance_frontier` 获取支配信息；
///   2) 扫描序预分配定义版本号、记录各变量定义块集合；
///   3) 对每个变量按迭代支配边界放置 φ（Cytron worklist），φ 目标版本号在全部
///      块内定义之后按「块数组序、块内变量名升序」分配；
///   4) 沿支配树前序、以版本号栈重命名定义/使用，并在前驱处回填后继 φ 实参。
///
/// 仅处理自 `entry` 可达的块（不可达块原样透传，且不参与支配/φ 计算，R5.4）。
pub fn build_ssa_minimal(
  blocks : Array[BasicBlock],
  entry~ : String,
) -> SsaProgram {
  let dom = build_dom_tree(blocks, entry~)
  let df = dominance_frontier(blocks, dom)
  let reachset : Map[String, Bool] = Map([])
  for r in dom.reachable {
    reachset[r] = true
  }
  let by_label : Map[String, BasicBlock] = Map([])
  for b in blocks {
    by_label[b.label] = b
  }
  let preds = preds_in_order(blocks)

  // ---- Phase A：扫描序预分配定义版本号 ----
  let mut next_id = 0
  let def_ids : Map[String, Array[Int]] = Map([]) // 块 → 每条指令的定义版本号（-1 非定义）
  let defsites : Map[String, Array[String]] = Map([]) // 变量名 → 定义块集合（去重、块序）
  let first_def : Map[String, Int] = Map([]) // 变量名 → 最小定义版本号
  for b in blocks {
    if !reachset.contains(b.label) {
      continue
    }
    let row : Array[Int] = []
    for instr in b.instrs {
      let (_, def) = instr_use_def(instr)
      match def {
        Some(name) => {
          let id = next_id
          next_id = next_id + 1
          row.push(id)
          let sites = defsites.get(name).unwrap_or([])
          if !array_contains_str(sites, b.label) {
            sites.push(b.label)
          }
          defsites[name] = sites
          match first_def.get(name) {
            Some(_) => ()
            None => first_def[name] = id
          }
        }
        None => row.push(-1)
      }
    }
    def_ids[b.label] = row
  }

  // 变量名升序（确定性）。
  let var_names : Array[String] = []
  for kv in defsites {
    let (nm, _) = kv
    var_names.push(nm)
  }
  var_names.sort()

  // ---- Phase B：Cytron 迭代支配边界 φ 放置 ----
  let phi_blocks : Map[String, Map[String, Bool]] = Map([]) // 变量名 → 需放 φ 的块集
  for v in var_names {
    let d = defsites.get(v).unwrap_or([])
    let has_phi : Map[String, Bool] = Map([])
    let on_work : Map[String, Bool] = Map([])
    let worklist : Array[String] = []
    for b in d {
      worklist.push(b)
      on_work[b] = true
    }
    while worklist.length() > 0 {
      let x = worklist.pop().unwrap()
      for y in df.get(x).unwrap_or([]) {
        if !has_phi.contains(y) {
          has_phi[y] = true
          if !on_work.contains(y) {
            on_work[y] = true
            worklist.push(y)
          }
        }
      }
    }
    phi_blocks[v] = has_phi
  }

  // ---- Phase C：分配 φ 目标版本号（块数组序、块内变量名升序）----
  let phi_at : Map[String, Array[(String, Int)]] = Map([]) // 块 → [(变量名, 目标版本号)]
  for b in blocks {
    if !reachset.contains(b.label) {
      continue
    }
    let row : Array[(String, Int)] = []
    for v in var_names {
      match phi_blocks.get(v) {
        Some(hp) =>
          if hp.contains(b.label) {
            let id = next_id
            next_id = next_id + 1
            row.push((v, id))
          }
        None => ()
      }
    }
    if row.length() > 0 {
      phi_at[b.label] = row
    }
  }

  // ---- 预创建 φ（args 数组按前驱数定长，重命名阶段回填）----
  let phis : Array[Phi] = []
  let phi_args : Map[(String, String), Array[Var]] = Map([])
  for b in blocks {
    if !reachset.contains(b.label) {
      continue
    }
    match phi_at.get(b.label) {
      Some(row) => {
        let pc = preds.get(b.label).unwrap_or([]).length()
        for pair in row {
          let (v, did) = pair
          let default_id = first_def.get(v).unwrap_or(did)
          let args : Array[Var] = Array::make(pc, { id: default_id })
          phis.push({ dest: { id: did }, args })
          phi_args[(b.label, v)] = args
        }
      }
      None => ()
    }
  }

  // ---- Phase D：支配树前序重命名（显式 enter/exit 栈，避免递归捕获）----
  let stacks : Map[String, Array[Int]] = Map([])
  let renamed : Map[String, Array[String]] = Map([])
  let pushed_at : Map[String, Array[String]] = Map([]) // 块 → 本块压栈的变量名（退出时弹出）
  let work : Array[(String, Bool)] = []
  if reachset.contains(dom.root) {
    work.push((dom.root, false))
  }
  while work.length() > 0 {
    let (label, is_exit) = work.pop().unwrap()
    if is_exit {
      for v in pushed_at.get(label).unwrap_or([]) {
        match stacks.get(v) {
          Some(st) => st.pop() |> ignore
          None => ()
        }
      }
      continue
    }
    let b = by_label.get(label).unwrap()
    let pushed : Array[String] = []
    // 1) 压入本块 φ 目标版本。
    match phi_at.get(label) {
      Some(row) =>
        for pair in row {
          let (v, did) = pair
          let st = stacks.get(v).unwrap_or([])
          st.push(did)
          stacks[v] = st
          pushed.push(v)
        }
      None => ()
    }
    // 2) 重命名块内指令。
    let row_ids = def_ids.get(label).unwrap_or([])
    let new_instrs : Array[String] = []
    for ii, instr in b.instrs {
      let toks = tokenize(instr)
      let id = if ii < row_ids.length() { row_ids[ii] } else { -1 }
      if id >= 0 {
        let (_, defname) = instr_use_def(instr)
        let name = defname.unwrap()
        let out : Array[String] = [versioned(name, id), "="]
        let mut j = 2
        while j < toks.length() {
          out.push(rewrite_use_stack(toks[j], stacks))
          j = j + 1
        }
        let st = stacks.get(name).unwrap_or([])
        st.push(id)
        stacks[name] = st
        pushed.push(name)
        new_instrs.push(join_tokens(out))
      } else {
        let out : Array[String] = []
        for t in toks {
          out.push(rewrite_use_stack(t, stacks))
        }
        new_instrs.push(join_tokens(out))
      }
    }
    renamed[label] = new_instrs
    pushed_at[label] = pushed
    // 3) 回填后继 φ 实参（本块作为前驱的每条边）。
    for s in b.succs {
      if !reachset.contains(s) {
        continue
      }
      match phi_at.get(s) {
        Some(row) => {
          let ps = preds.get(s).unwrap_or([])
          for pair in row {
            let (v, did) = pair
            let val = match stacks.get(v) {
              Some(st) =>
                if st.length() > 0 {
                  st[st.length() - 1]
                } else {
                  first_def.get(v).unwrap_or(did)
                }
              None => first_def.get(v).unwrap_or(did)
            }
            match phi_args.get((s, v)) {
              Some(args) =>
                for idx in 0..<ps.length() {
                  if ps[idx] == label {
                    args[idx] = { id: val }
                  }
                }
              None => ()
            }
          }
        }
        None => ()
      }
    }
    // 4) 先排退出标记，再排子节点（LIFO → 子节点先于退出处理，得到前序）。
    work.push((label, true))
    let children = dom.children.get(label).unwrap_or([])
    let mut ci = children.length() - 1
    while ci >= 0 {
      work.push((children[ci], false))
      ci = ci - 1
    }
  }

  // ---- 组装输出块（原数组序；可达块用重命名结果，不可达块原样透传）----
  let out_blocks : Array[BasicBlock] = []
  for b in blocks {
    let instrs = match renamed.get(b.label) {
      Some(ri) => ri
      None => b.instrs
    }
    out_blocks.push({ label: b.label, instrs, succs: b.succs })
  }
  { blocks: out_blocks, phis }
}

///|
/// 以版本号栈重写一个使用记号：若 `tok` 为当前有版本的变量名则替换为 `name#ver`，
/// 否则（运算符、字面量、未定义/前向引用）原样返回。
fn rewrite_use_stack(tok : String, stacks : Map[String, Array[Int]]) -> String {
  match stacks.get(tok) {
    Some(st) =>
      if st.length() > 0 {
        versioned(tok, st[st.length() - 1])
      } else {
        tok
      }
    None => tok
  }
}
