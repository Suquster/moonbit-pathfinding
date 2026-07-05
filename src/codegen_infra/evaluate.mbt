// evaluate.mbt —— 参考解释器（reference interpreter），旗舰深化旁路新增。
//
// paper-to-code：参考解释器是语义保持类正确性属性的「oracle」。它给出 IR
// 模型的一个确定性、纯函数的执行语义，用于在属性测试中比较「变换前后」
// （SCCP、GVN）与「SSA 与析构后」（out-of-SSA）在相同初始赋值与控制流路径
// 下的输出与目标变量取值是否一致。
//
//   * R7.5：out-of-SSA 与 SSA 语义等价的 oracle；
//   * R8.5：SCCP 保持语义的 oracle；
//   * R9.5：GVN 保持语义的 oracle。
//
// 设计取舍（见 design.md §4.11、§「错误处理」）：解释器为全函数，算术沿用既有
// `fold_op` 的 `+ - *` 语义；未知运算符不抛异常而退回左操作数取值；未知记号
// 退回 0。φ 函数按「进入汇合块的前驱」选择对应实参版本求值。
//
// 由于既有 `Phi { dest, args }` 数据模型不携带「φ 所属块 / 变量名 / 前驱顺序」
// 信息（向后兼容冻结，见 R15.1），本文件提供包内私有的 `reconstruct_phi_sites`
// 由 `SsaProgram` 重建 φ 落点信息（block / 变量名 / 实参在前驱序中的对应），
// 供 `evaluate` / `destruct_ssa` / `sccp` / `gvn` 共享复用，保持单一数据表示。

// ---------------------------------------------------------------------------
// 参考解释器输出
// ---------------------------------------------------------------------------

///|
/// 参考解释器的执行结果：路径末端各（版本化）变量取值与可达输出序列。
pub(all) struct EvalResult {
  values : Map[String, Int] // 版本化变量记号（如 `x#2`）→ 取值
  output : Array[Int] // `ret` 记号沿路径产出的可达输出序列
} derive(Eq, Debug)

// ---------------------------------------------------------------------------
// φ 落点重建（reconstruct φ placement）—— 供解释器 / 析构 / 数据流优化共享
// ---------------------------------------------------------------------------

///|
/// 重建出的 φ 落点信息（包内私有）。
///
/// `block` 为 φ 所在汇合块标签；`var_name` 为 φ 的变量名；`dest` 为 φ 目标版本号；
/// `args` 为各前驱到达版本号，与 `preds`（前驱标签，块序）一一对应。
priv struct PhiSite {
  block : String
  var_name : String
  dest : Int
  args : Array[Int]
  preds : Array[String]
}

///|
/// 解析带版本记号 `name#ver`，返回 `(name, ver)`；非该形式返回 `None`。
fn split_versioned(tok : String) -> (String, Int)? {
  let cs = tok.iter().to_array()
  let mut hash = -1
  for i in 0..<cs.length() {
    if cs[i] == '#' {
      hash = i
    }
  }
  if hash <= 0 || hash + 1 >= cs.length() {
    return None
  }
  let mut n = 0
  let mut j = hash + 1
  while j < cs.length() {
    let c = cs[j]
    if c >= '0' && c <= '9' {
      n = n * 10 + (c.to_int() - '0'.to_int())
    } else {
      return None
    }
    j = j + 1
  }
  let name = StringBuilder::new()
  for i in 0..<hash {
    name.write_char(cs[i])
  }
  Some((name.to_string(), n))
}

///|
/// 计算各块前驱标签（按块数组顺序），仅在程序内出现的块之间建立。
fn preds_in_order(blocks : Array[BasicBlock]) -> Map[String, Array[String]] {
  let preds : Map[String, Array[String]] = Map([])
  for b in blocks {
    if !preds.contains(b.label) {
      preds[b.label] = []
    }
  }
  for b in blocks {
    for s in b.succs {
      let lst = preds.get(s).unwrap_or([])
      lst.push(b.label)
      preds[s] = lst
    }
  }
  preds
}

///|
/// 由 `SsaProgram` 重建 φ 落点信息。
///
/// 重建规则（对 `build_ssa` 风格输出与本方向生成器均稳健）：
///   1) 由块内全部带版本记号（定义与使用）建立「版本号 → 变量名」映射；
///   2) φ 的变量名优先取其目标版本号的使用记号，退而取首个实参版本号
///      对应的变量名（复制传播可能把实参改写为其它变量的版本，此时
///      仅目标使用记号能给出正确变量名）；
///   3) φ 所在块取「前驱数 ≥ 2 且其指令中引用了 φ 目标记号 `name#dest`」的块。
///
/// 目标记号未在任何块中被引用的「死 φ」无法定位其汇合块，此时跳过——其语义为
/// 无可观测效应，解释器 / 析构忽略之与「死代码」处理一致。
fn reconstruct_phi_sites(p : SsaProgram) -> Array[PhiSite] {
  let ver2name : Map[Int, String] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      for t in tokenize(instr) {
        match split_versioned(t) {
          Some((nm, v)) => if !ver2name.contains(v) { ver2name[v] = nm }
          None => ()
        }
      }
    }
  }
  let preds = preds_in_order(p.blocks)
  let sites : Array[PhiSite] = []
  for phi in p.phis {
    let args : Array[Int] = []
    for a in phi.args {
      args.push(a.id)
    }
    if args.length() == 0 {
      continue
    }
    let dest = phi.dest.id
    let name = match ver2name.get(dest) {
      Some(n) => n
      None =>
        match ver2name.get(args[0]) {
          Some(n) => n
          None => ""
        }
    }
    if name == "" {
      continue
    }
    let dest_tok = name + "#" + dest.to_string()
    let mut found = ""
    for b in p.blocks {
      let pcount = preds.get(b.label).unwrap_or([]).length()
      if pcount < 2 {
        continue
      }
      let mut uses = false
      for instr in b.instrs {
        for t in tokenize(instr) {
          if t == dest_tok {
            uses = true
            break
          }
        }
        if uses {
          break
        }
      }
      if uses {
        found = b.label
        break
      }
    }
    if found == "" {
      continue
    }
    sites.push({
      block: found,
      var_name: name,
      dest,
      args,
      preds: preds.get(found).unwrap_or([]),
    })
  }
  sites
}

// ---------------------------------------------------------------------------
// 解释执行（interpret along a control-flow path）
// ---------------------------------------------------------------------------

///|
/// 取记号 `tok` 的整数取值：整型字面量直接解析；否则查 `values`（已求值版本化
/// 变量），再查 `init`（初始赋值），都没有则退回 0。
fn eval_lookup(
  tok : String,
  values : Map[String, Int],
  init : Map[String, Int],
) -> Int {
  match parse_int(tok) {
    Some(n) => n
    None =>
      match values.get(tok) {
        Some(v) => v
        None => init.get(tok).unwrap_or(0)
      }
  }
}

///|
/// 沿给定块标签路径 `path` 解释执行程序 `p`，返回末端变量取值与输出序列。
///
/// 进入汇合块时按「来路前驱」为该块每个 φ 绑定对应实参版本的取值（R7 φ 语义）；
/// 块内 `name = a op b` 做整数算术、`name = a` 做复制、`ret x` 产出可达输出；
/// `br` / `cbr` 不参与求值（实走分支由 `path` 给定）。纯函数、三后端确定一致。
pub fn evaluate(
  p : SsaProgram,
  init : Map[String, Int],
  path : Array[String],
) -> EvalResult {
  let by_label : Map[String, BasicBlock] = Map([])
  for b in p.blocks {
    by_label[b.label] = b
  }
  let sites = reconstruct_phi_sites(p)
  let sites_by_block : Map[String, Array[PhiSite]] = Map([])
  for s in sites {
    let lst = sites_by_block.get(s.block).unwrap_or([])
    lst.push(s)
    sites_by_block[s.block] = lst
  }
  // 版本号 → 变量名（含定义与使用记号）：φ 实参经复制传播可能被改写为
  // 其它变量的版本，取实参取值时须按实参自身的变量名定位记号。
  let ver2name : Map[Int, String] = Map([])
  for b in p.blocks {
    for instr in b.instrs {
      for t in tokenize(instr) {
        match split_versioned(t) {
          Some((nm, v)) => if !ver2name.contains(v) { ver2name[v] = nm }
          None => ()
        }
      }
    }
  }
  let values : Map[String, Int] = Map([])
  let output : Array[Int] = []
  let mut prev = ""
  for cur_label in path {
    match by_label.get(cur_label) {
      None => ()
      Some(b) => {
        // φ：按来路前驱绑定目标版本取值。
        if prev != "" {
          match sites_by_block.get(cur_label) {
            Some(plist) =>
              for site in plist {
                let mut idx = -1
                for i in 0..<site.preds.length() {
                  if site.preds[i] == prev {
                    idx = i
                    break
                  }
                }
                if idx >= 0 && idx < site.args.length() {
                  let arg_id = site.args[idx]
                  let arg_name = ver2name.get(arg_id).unwrap_or(site.var_name)
                  let arg_tok = arg_name + "#" + arg_id.to_string()
                  let dest_tok = site.var_name + "#" + site.dest.to_string()
                  values[dest_tok] = eval_lookup(arg_tok, values, init)
                }
              }
            None => ()
          }
        }
        for instr in b.instrs {
          let toks = tokenize(instr)
          if toks.length() >= 2 && toks[1] == "=" {
            let lhs = toks[0]
            if toks.length() == 3 {
              values[lhs] = eval_lookup(toks[2], values, init)
            } else if toks.length() == 5 {
              let x = eval_lookup(toks[2], values, init)
              let y = eval_lookup(toks[4], values, init)
              match fold_op(toks[3], x, y) {
                Some(r) => values[lhs] = r
                None => values[lhs] = x
              }
            }
          } else if toks.length() >= 2 && toks[0] == "ret" {
            output.push(eval_lookup(toks[1], values, init))
          }
        }
      }
    }
    prev = cur_label
  }
  { values, output }
}
