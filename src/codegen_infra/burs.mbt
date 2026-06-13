// burs.mbt —— 指令选择升级：BURS 代价最优 tiling 与最大吞噬，旁路新增。
//
// paper-to-code：BURS（Bottom-Up Rewrite System，自底向上重写）带代价树模式
// 匹配，以动态规划求代价最优 tiling；最大吞噬（maximal munch）自顶向下贪心匹配
// 作为对照基线；Appel《Modern Compiler Implementation》指令选择章节。
//
// 设计落点（design.md §4.10，R11）：既有 `select(Array[IselRule], IrNode)` 的
// 后序遍历语义完全冻结，`select_burs` 与其互为旁路。模式语言为单节点模式
// （`Const` / `VarRef` / `BinOp` / `BinOp:<op>`），运算符特化规则优先于通用规则
// （R11.3）；覆盖完整——每个 IR 节点都被某规则覆盖（R11.1/11.5）；所选覆盖
// 总代价不大于任何其它合法覆盖（R11.6）。

// ---------------------------------------------------------------------------
// 带代价规则
// ---------------------------------------------------------------------------

///|
/// 带代价的指令选择规则。
///
/// `pattern` ∈ {`"Const"`, `"VarRef"`, `"BinOp"`, `"BinOp:<op>"`}；`template` 为
/// 目标操作码；`cost` 为该规则覆盖其匹配节点的代价（≥ 0）。
pub(all) struct CostRule {
  pattern : String
  template : String
  cost : Int
} derive(Eq, Show)

///|
/// 一个规则的 pattern 是否匹配给定节点种类与运算符。
fn rule_matches(r : CostRule, kind : String, op : String) -> Bool {
  if kind == "BinOp" {
    r.pattern == "BinOp:" + op || r.pattern == "BinOp"
  } else {
    r.pattern == kind
  }
}

///|
/// 收集匹配给定节点种类与运算符的全部规则。
fn match_rules(
  rules : Array[CostRule],
  kind : String,
  op : String,
) -> Array[CostRule] {
  let out : Array[CostRule] = []
  for r in rules {
    if rule_matches(r, kind, op) {
      out.push(r)
    }
  }
  out
}

///|
/// 在匹配规则集中挑选「最优」规则：代价最小者；代价相等时优先运算符特化规则
/// （`BinOp:<op>`），再退化为列表中靠前者。无匹配返回 `None`。
fn pick_best(matching : Array[CostRule], op : String) -> CostRule? {
  if matching.length() == 0 {
    return None
  }
  let specialized = "BinOp:" + op
  let mut best = matching[0]
  let mut i = 1
  while i < matching.length() {
    let r = matching[i]
    if r.cost < best.cost {
      best = r
    } else if r.cost == best.cost &&
      r.pattern == specialized &&
      best.pattern != specialized {
      best = r
    }
    i = i + 1
  }
  Some(best)
}

// ---------------------------------------------------------------------------
// BURS 动态规划：代价最优 tiling
// ---------------------------------------------------------------------------

///|
/// 计算覆盖整棵 IR 树的最优 tiling 总代价（自底向上 DP）。
///
/// 单节点模式下，每个节点独立选用其最小代价规则；子树代价相加即为最优覆盖代价。
/// 覆盖完整的规则集前提下每个节点恒有匹配规则；无匹配时退化以 0 计（占位）。
pub fn tiling_cost(rules : Array[CostRule], ir : IrNode) -> Int {
  match ir {
    Const(_) => node_cost(rules, "Const", "")
    VarRef(_) => node_cost(rules, "VarRef", "")
    BinOp(op, l, r) =>
      node_cost(rules, "BinOp", op) +
      tiling_cost(rules, l) +
      tiling_cost(rules, r)
  }
}

///|
/// 单节点的最优规则代价（无匹配规则退化为 0）。
fn node_cost(rules : Array[CostRule], kind : String, op : String) -> Int {
  match pick_best(match_rules(rules, kind, op), op) {
    Some(r) => r.cost
    None => 0
  }
}

///|
/// BURS 指令选择：自底向上 DP 为每子树选用代价最优规则，后序发射代价最优的
/// 目标指令序列。每个产出指令首操作数为目标虚拟寄存器 `t{n}`，其后为子树结果。
pub fn select_burs(rules : Array[CostRule], ir : IrNode) -> Array[TargetInstr] {
  let out : Array[TargetInstr] = []
  let counter = [0]
  select_burs_node(rules, ir, out, counter) |> ignore
  out
}

///|
/// `select_burs` 的后序递归发射，返回当前子树结果操作数记号。
fn select_burs_node(
  rules : Array[CostRule],
  ir : IrNode,
  out : Array[TargetInstr],
  counter : Array[Int],
) -> String {
  match ir {
    Const(n) => {
      let dst = fresh_temp(counter)
      let tmpl = match pick_best(match_rules(rules, "Const", ""), "") {
        Some(r) => r.template
        None => "li"
      }
      out.push({ op: tmpl, operands: [dst, n.to_string()] })
      dst
    }
    VarRef(v) => {
      let name = "v" + v.id.to_string()
      match pick_best(match_rules(rules, "VarRef", ""), "") {
        Some(r) => {
          let dst = fresh_temp(counter)
          out.push({ op: r.template, operands: [dst, name] })
          dst
        }
        None => name
      }
    }
    BinOp(op, l, r) => {
      let lo = select_burs_node(rules, l, out, counter)
      let ro = select_burs_node(rules, r, out, counter)
      let dst = fresh_temp(counter)
      let tmpl = match pick_best(match_rules(rules, "BinOp", op), op) {
        Some(rr) => rr.template
        None => op
      }
      out.push({ op: tmpl, operands: [dst, lo, ro] })
      dst
    }
  }
}

// ---------------------------------------------------------------------------
// 最大吞噬（maximal munch）—— 自顶向下贪心对照基线
// ---------------------------------------------------------------------------

///|
/// 最大吞噬指令选择：自顶向下贪心匹配（运算符特化优先），作为对照基线。
///
/// 在单节点模式语言下与 `select_burs` 的覆盖一致，但选规则按「特化优先 + 列表
/// 顺序」而非代价最优——用于在文档与基准中对照「贪心」与「代价最优」之别。
pub fn max_munch(rules : Array[CostRule], ir : IrNode) -> Array[TargetInstr] {
  let out : Array[TargetInstr] = []
  let counter = [0]
  mm_node(rules, ir, out, counter) |> ignore
  out
}

///|
/// `max_munch` 的后序递归发射。
fn mm_node(
  rules : Array[CostRule],
  ir : IrNode,
  out : Array[TargetInstr],
  counter : Array[Int],
) -> String {
  match ir {
    Const(n) => {
      let dst = fresh_temp(counter)
      let tmpl = first_template(rules, "Const", "").unwrap_or("li")
      out.push({ op: tmpl, operands: [dst, n.to_string()] })
      dst
    }
    VarRef(v) => {
      let name = "v" + v.id.to_string()
      match first_template(rules, "VarRef", "") {
        Some(t) => {
          let dst = fresh_temp(counter)
          out.push({ op: t, operands: [dst, name] })
          dst
        }
        None => name
      }
    }
    BinOp(op, l, r) => {
      let lo = mm_node(rules, l, out, counter)
      let ro = mm_node(rules, r, out, counter)
      let dst = fresh_temp(counter)
      let tmpl = first_template(rules, "BinOp", op).unwrap_or(op)
      out.push({ op: tmpl, operands: [dst, lo, ro] })
      dst
    }
  }
}

///|
/// 取首个匹配规则的模板：运算符特化（`BinOp:<op>`）优先于通用 `BinOp`。
fn first_template(
  rules : Array[CostRule],
  kind : String,
  op : String,
) -> String? {
  if kind == "BinOp" {
    for r in rules {
      if r.pattern == "BinOp:" + op {
        return Some(r.template)
      }
    }
    for r in rules {
      if r.pattern == "BinOp" {
        return Some(r.template)
      }
    }
    None
  } else {
    for r in rules {
      if r.pattern == kind {
        return Some(r.template)
      }
    }
    None
  }
}
