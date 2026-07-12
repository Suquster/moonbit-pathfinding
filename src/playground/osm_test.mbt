// OSM 图模式导出层（osm.mbt）黑盒测试：句柄协议、错误码、单向/双向
// Dijkstra 正确性与不可达语义。

///|
/// 构造一个 6 节点带权有向图（存在两条 0→5 路径，最短为 0→2→3→5 = 6），
/// 供多个测试复用。
fn osm_setup_diamond() -> Unit {
  assert_eq_int(@playground.pg_osm_reset(6), 0)
  // 长路：0→1→4→5 = 3 + 4 + 5 = 12
  assert_eq_int(@playground.pg_osm_add_edge(0, 1, 3), 0)
  assert_eq_int(@playground.pg_osm_add_edge(1, 4, 4), 0)
  assert_eq_int(@playground.pg_osm_add_edge(4, 5, 5), 0)
  // 短路：0→2→3→5 = 1 + 2 + 3 = 6
  assert_eq_int(@playground.pg_osm_add_edge(0, 2, 1), 0)
  assert_eq_int(@playground.pg_osm_add_edge(2, 3, 2), 0)
  assert_eq_int(@playground.pg_osm_add_edge(3, 5, 3), 0)
  assert_eq_int(@playground.pg_osm_build(), 0)
}

///|
/// Int 断言辅助（避免元组 Show 弃用告警）。
fn assert_eq_int(actual : Int, expected : Int) -> Unit {
  if actual != expected {
    abort("expected \{expected}, got \{actual}")
  }
}

///|
test "osm route dijkstra finds shortest path" {
  osm_setup_diamond()
  assert_eq(@playground.pg_osm_route(0, 0, 5), 0)
  assert_eq(@playground.pg_osm_last_error(), 0)
  assert_eq(@playground.pg_osm_cost(), 6)
  assert_eq(@playground.pg_osm_path_len(), 4)
  assert_eq(@playground.pg_osm_path_at(0), 0)
  assert_eq(@playground.pg_osm_path_at(1), 2)
  assert_eq(@playground.pg_osm_path_at(2), 3)
  assert_eq(@playground.pg_osm_path_at(3), 5)
  assert_true(@playground.pg_osm_settled() > 0)
}

///|
test "osm route bidirectional matches unidirectional cost and endpoints" {
  osm_setup_diamond()
  assert_eq(@playground.pg_osm_route(1, 0, 5), 0)
  assert_eq(@playground.pg_osm_cost(), 6)
  assert_eq(@playground.pg_osm_path_len(), 4)
  assert_eq(@playground.pg_osm_path_at(0), 0)
  assert_eq(@playground.pg_osm_path_at(3), 5)
}

///|
test "osm route unreachable returns -1 path length with err_ok" {
  osm_setup_diamond()
  // 节点 5 无出边，5→0 不可达
  assert_eq(@playground.pg_osm_route(0, 5, 0), 0)
  assert_eq(@playground.pg_osm_last_error(), 0)
  assert_eq(@playground.pg_osm_path_len(), -1)
  assert_eq(@playground.pg_osm_cost(), -1)
  assert_eq(@playground.pg_osm_route(1, 5, 0), 0)
  assert_eq(@playground.pg_osm_path_len(), -1)
}

///|
test "osm route same source and target has zero cost" {
  osm_setup_diamond()
  assert_eq(@playground.pg_osm_route(0, 2, 2), 0)
  assert_eq(@playground.pg_osm_cost(), 0)
  assert_eq(@playground.pg_osm_path_len(), 1)
  assert_eq(@playground.pg_osm_path_at(0), 2)
  assert_eq(@playground.pg_osm_route(1, 2, 2), 0)
  assert_eq(@playground.pg_osm_cost(), 0)
  assert_eq(@playground.pg_osm_path_len(), 1)
}

///|
test "osm protocol rejects invalid operations" {
  // 非法 reset
  assert_eq(@playground.pg_osm_reset(0), 5)
  assert_eq(@playground.pg_osm_reset(-3), 5)
  // 合法 reset 后：越界/负权边拒绝
  assert_eq(@playground.pg_osm_reset(3), 0)
  assert_eq(@playground.pg_osm_add_edge(-1, 0, 1), 5)
  assert_eq(@playground.pg_osm_add_edge(0, 3, 1), 5)
  assert_eq(@playground.pg_osm_add_edge(0, 1, -1), 5)
  assert_eq(@playground.pg_osm_last_error(), 5)
  // build 前 route 拒绝
  assert_eq(@playground.pg_osm_route(0, 0, 1), 5)
  // 正常 build；重复 build 拒绝；build 后添边拒绝
  assert_eq(@playground.pg_osm_add_edge(0, 1, 2), 0)
  assert_eq(@playground.pg_osm_build(), 0)
  assert_eq(@playground.pg_osm_build(), 5)
  assert_eq(@playground.pg_osm_add_edge(1, 2, 1), 5)
  // 非法算法码与越界端点拒绝
  assert_eq(@playground.pg_osm_route(2, 0, 1), 5)
  assert_eq(@playground.pg_osm_route(0, -1, 1), 5)
  assert_eq(@playground.pg_osm_route(0, 0, 3), 5)
  // 越界路径读取
  assert_eq(@playground.pg_osm_path_at(-1), -1)
  assert_eq(@playground.pg_osm_path_at(99), -1)
}

///|
test "osm bidirectional agrees with unidirectional on random graphs" {
  // 128 节点随机图（xorshift 简易生成），两算法逐对交叉验证代价一致
  let n = 128
  let mut state : UInt64 = 88172645463325252UL
  fn next() -> UInt64 {
    state = state ^ (state << 13)
    state = state ^ (state >> 7)
    state = state ^ (state << 17)
    state
  }

  assert_eq(@playground.pg_osm_reset(n), 0)
  // 环底座保证强连通 + 随机弦
  for i in 0..<n {
    let w = (next() % 9UL).to_int() + 1
    assert_eq(@playground.pg_osm_add_edge(i, (i + 1) % n, w), 0)
  }
  for _ in 0..<(n * 3) {
    let u = (next() % n.to_uint64()).to_int()
    let v = (next() % n.to_uint64()).to_int()
    let w = (next() % 99UL).to_int() + 1
    assert_eq(@playground.pg_osm_add_edge(u, v, w), 0)
  }
  assert_eq(@playground.pg_osm_build(), 0)
  for _ in 0..<50 {
    let s = (next() % n.to_uint64()).to_int()
    let t = (next() % n.to_uint64()).to_int()
    assert_eq(@playground.pg_osm_route(0, s, t), 0)
    let uni_cost = @playground.pg_osm_cost()
    let uni_settled = @playground.pg_osm_settled()
    assert_eq(@playground.pg_osm_route(1, s, t), 0)
    assert_eq(@playground.pg_osm_cost(), uni_cost)
    assert_true(uni_settled >= 0)
  }
}
