// road_service_test.mbt —— 端到端路网服务切片黑盒测试（G-C1）。
//
// 覆盖：边表解析（注释/空行/畸形行诊断）、CH 路由正确性（对照手工
// 最短路）、CLI 全链（route --from --to）、熔断器短路与恢复、
// 指标快照、PBT（随机网格路网 CH 结果与 Dijkstra 语义一致的度量：
// 路径成本 = 逐边权和且首尾正确）。

///|
fn sample_edges() -> Array[String] {
  [
    "# demo road network", "A B 4", "B C 3", "A C 9", "C D 2", "B D 7", "", "bad line",
    "A E xx",
  ]
}

///|
test "parse_road_network：解析与诊断" {
  let (net, diags) = @road_service.parse_road_network(sample_edges())
  assert_eq(net.nodes.length(), 4)
  assert_eq(diags.length(), 2)
  assert_true(diags[0].contains("expected 3 fields"))
  assert_true(diags[1].contains("bad weight"))
}

///|
test "RoadService：CH 路由正确性与指标快照" {
  let (net, _) = @road_service.parse_road_network(sample_edges())
  let svc = @road_service.RoadService::build(net)
  // A->D 最短：A-B-C-D = 4+3+2 = 9（优于 A-C-D=11、A-B-D=11）。
  match svc.route("A", "D", 0, 5) {
    @road_service.RouteFound(path, cost) => {
      assert_eq(cost, 9)
      assert_true(path == ["A", "B", "C", "D"])
    }
    _ => assert_true(false)
  }
  // 反向不可达（有向图）。
  assert_true(svc.route("D", "A", 10, 3) == @road_service.RouteNotFound)
  let (queries, rejected, p50, _p99) = svc.metrics_snapshot()
  assert_eq(queries, 2)
  assert_eq(rejected, 0)
  assert_true(p50 >= 3 && p50 <= 5)
}

///|
test "RoadService：熔断器短路与冷却恢复" {
  let (net, _) = @road_service.parse_road_network(["A B 1"])
  let svc = @road_service.RoadService::build(net)
  // 连续 3 次无路失败 → 熔断器打开。
  for k in 0..<3 {
    assert_true(
      svc.route("B", "A", k.to_int64(), 1) == @road_service.RouteNotFound,
    )
  }
  // 打开期内短路拒绝。
  assert_true(svc.route("A", "B", 10, 1) == @road_service.RouteRejected)
  let (_, rejected, _, _) = svc.metrics_snapshot()
  assert_eq(rejected, 1)
  // 冷却（1000ms）后半开，成功查询恢复闭合。
  match svc.route("A", "B", 2000, 1) {
    @road_service.RouteFound(_, cost) => assert_eq(cost, 1)
    _ => assert_true(false)
  }
  assert_true(svc.route("A", "B", 2001, 1) is @road_service.RouteFound(_, _))
}

///|
test "run_cli：route 子命令全链与错误诊断" {
  let (net, _) = @road_service.parse_road_network(sample_edges())
  let svc = @road_service.RoadService::build(net)
  assert_eq(
    @road_service.run_cli(svc, ["route", "--from", "A", "--to", "D"], 0, 2),
    "route: A B C D (cost 9)",
  )
  assert_eq(
    @road_service.run_cli(svc, ["route", "--from", "D", "--to", "A"], 1, 2),
    "no route: D -> A",
  )
  assert_eq(
    @road_service.run_cli(svc, ["route", "--from", "A"], 2, 1),
    "error: --from and --to are required",
  )
  assert_true(
    @road_service.run_cli(svc, ["route", "--bogus"], 3, 1).contains(
      "unknown flag",
    ),
  )
  // 无子命令 → 帮助文本。
  assert_true(@road_service.run_cli(svc, [], 4, 1).contains("roadd"))
}

///|
test "PBT：随机链式路网 CH 成本 = 逐边权和（100 迭代）" {
  let gen : @infra_pbt.Gen[Array[Int]] = @infra_pbt.Gen::new(fn(rng) {
    let n = 2 + rng.next_below(12)
    let weights : Array[Int] = []
    for _k in 0..<(n - 1) {
      weights.push(1 + rng.next_below(50))
    }
    weights
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(weights) {
    // 链 n0 -> n1 -> ... -> nk（另加随机「捷径」不短于链和，最短路必为整链）。
    let lines : Array[String] = []
    let mut total = 0
    for k in 0..<weights.length() {
      lines.push(
        "n" +
        k.to_string() +
        " n" +
        (k + 1).to_string() +
        " " +
        weights[k].to_string(),
      )
      total = total + weights[k]
    }
    // 直达捷径：权 = 链和 + 1（必不被选）。
    lines.push(
      "n0 n" + weights.length().to_string() + " " + (total + 1).to_string(),
    )
    let (net, diags) = @road_service.parse_road_network(lines)
    if diags.length() != 0 {
      return false
    }
    let svc = @road_service.RoadService::build(net)
    match svc.route("n0", "n" + weights.length().to_string(), 0, 1) {
      @road_service.RouteFound(path, cost) =>
        cost == total && path.length() == weights.length() + 1
      _ => false
    }
  })
  assert_true(ok)
}

///|
test "run_cli：熔断器打开期短路拒绝" {
  let (net, _) = @road_service.parse_road_network(["A B 1"])
  let svc = @road_service.RoadService::build(net)
  for k in 0..<3 {
    assert_true(
      svc.route("B", "A", k.to_int64(), 1) == @road_service.RouteNotFound,
    )
  }
  let out = @road_service.run_cli(
    svc,
    ["route", "--from", "A", "--to", "B"],
    10,
    1,
  )
  assert_eq(out, "rejected: circuit breaker open")
}
