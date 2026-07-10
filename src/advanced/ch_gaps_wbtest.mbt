// ch_gaps_wbtest.mbt —— CH 捷径展开不变量防御分支收口
// （INFRA 第三十二批）：退化捷径拒绝、层级不变量违例、层级缺失降级。

///|
fn chg_empty() -> CHGraph[Int, Int] {
  CHGraph::{
    nodes: [1, 2, 3],
    level: Map([]),
    up_adj: Map([]),
    dn_adj: Map([]),
    shortcut: Map([]),
  }
}

///|
test "ch_shortcut_mid：中点与端点重合的退化捷径拒绝" {
  let g = chg_empty()
  g.shortcut[(1, 2)] = 1
  assert_true(ch_shortcut_mid(g, 1, 2) is None)
  g.shortcut[(1, 2)] = 2
  assert_true(ch_shortcut_mid(g, 1, 2) is None)
}

///|
test "ch_shortcut_mid：层级不变量违例与缺失均降级" {
  let g = chg_empty()
  g.shortcut[(1, 2)] = 3
  // 层级缺失 → 无法证明不变量，降级为直接边。
  assert_true(ch_shortcut_mid(g, 1, 2) is None)
  // 中点层级不低于端点 → 违反收缩不变量，拒绝。
  g.level[1] = 0
  g.level[2] = 1
  g.level[3] = 5
  assert_true(ch_shortcut_mid(g, 1, 2) is None)
  // 合法情形：中点层级低于两端。
  g.level[3] = -1
  assert_true(ch_shortcut_mid(g, 1, 2) is Some(3))
}
