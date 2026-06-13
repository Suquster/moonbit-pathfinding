// prop_burs_optimal_test.mbt —— Property 17：指令选择代价最优（任务 16.4）。
//
// Feature: codegen-infra, Property 17: 指令选择代价最优
// **Validates: Requirements 11.2, 11.6**
//
// 性质：对任意随机 IR 树与覆盖完整的带代价规则集，`select_burs` 所选覆盖方案的
// 总代价（`tiling_cost`）不大于穷举所得的任何其它合法覆盖方案的总代价。oracle
// `brute_min_tiling` 显式枚举所有合法覆盖（每节点选任一匹配规则的笛卡尔积）的
// 总代价并取最小，独立于被测 DP 逻辑。IR 树深度限制为 2 以保证枚举有界。
// 复用 @infra_pbt.holds_for_all（100 次迭代）。

///|
/// 匹配给定节点种类 / 运算符的全部规则代价（独立于被测私有匹配逻辑）。
fn t_matching_costs(
  rules : Array[CostRule],
  kind : String,
  op : String,
) -> Array[Int] {
  let out : Array[Int] = []
  for r in rules {
    let m = if kind == "BinOp" {
      r.pattern == "BinOp:" + op || r.pattern == "BinOp"
    } else {
      r.pattern == kind
    }
    if m {
      out.push(r.cost)
    }
  }
  out
}

///|
/// 穷举所有合法覆盖的总代价列表（笛卡尔积）。
fn t_all_covering_costs(rules : Array[CostRule], ir : IrNode) -> Array[Int] {
  match ir {
    Const(_) => t_matching_costs(rules, "Const", "")
    VarRef(_) => t_matching_costs(rules, "VarRef", "")
    BinOp(op, l, r) => {
      let node = t_matching_costs(rules, "BinOp", op)
      let lc = t_all_covering_costs(rules, l)
      let rc = t_all_covering_costs(rules, r)
      let out : Array[Int] = []
      for nc in node {
        for a in lc {
          for b in rc {
            out.push(nc + a + b)
          }
        }
      }
      out
    }
  }
}

///|
/// 穷举 oracle：所有合法覆盖中的最小总代价。
fn t_brute_min_tiling(rules : Array[CostRule], ir : IrNode) -> Int {
  let costs = t_all_covering_costs(rules, ir)
  let mut m = costs[0]
  for c in costs {
    if c < m {
      m = c
    }
  }
  m
}

///|
/// Feature: codegen-infra, Property 17: 指令选择代价最优
/// **Validates: Requirements 11.2, 11.6**
test "Feature: codegen-infra, Property 17: instruction selection is cost-optimal" {
  let ok = @infra_pbt.holds_for_all(
    gen_ir_and_rules(2),
    fn(pair) {
      let (ir, rules) = pair
      tiling_cost(rules, ir) == t_brute_min_tiling(rules, ir)
    },
    iters=100,
  )
  assert_true(ok)
}
