// workspace_test.mbt —— 多包工作区模型黑盒测试（G-A1）。
//
// 覆盖：合法性校验、构建顺序拓扑性质、菱形依赖闭包去重、反向依赖、
// 增量重建计划（最小性 + 拓扑序 + 闭包性）、环检测、随机 DAG PBT。

///|
/// 夹具：菱形 + 尾包工作区。
///   app → {ui, net} → core；tool → net；leaf 无依赖无被依赖。
fn diamond_ws() -> @build_tool.Workspace {
  @build_tool.Workspace::new([
    @build_tool.WorkspacePackage::new("core", []),
    @build_tool.WorkspacePackage::new("ui", ["core"]),
    @build_tool.WorkspacePackage::new("net", ["core"]),
    @build_tool.WorkspacePackage::new("app", ["ui", "net"]),
    @build_tool.WorkspacePackage::new("tool", ["net"]),
    @build_tool.WorkspacePackage::new("leaf", []),
  ])
}

///|
/// order 中 a 是否先于 b。
fn precedes(order : Array[String], a : String, b : String) -> Bool {
  let mut ia = -1
  let mut ib = -1
  for k in 0..<order.length() {
    if order[k] == a {
      ia = k
    }
    if order[k] == b {
      ib = k
    }
  }
  ia >= 0 && ib >= 0 && ia < ib
}

///|
test "workspace 校验：重复包名与未知依赖被拒绝" {
  assert_true(diamond_ws().validate() is None)
  let dup = @build_tool.Workspace::new([
    @build_tool.WorkspacePackage::new("a", []),
    @build_tool.WorkspacePackage::new("a", []),
  ])
  assert_true(dup.validate() == Some("duplicate package: a"))
  let unknown = @build_tool.Workspace::new([
    @build_tool.WorkspacePackage::new("a", ["ghost"]),
  ])
  assert_true(unknown.validate() == Some("unknown dependency: a -> ghost"))
}

///|
test "workspace 构建顺序：被依赖包先行（拓扑性质）" {
  match diamond_ws().build_order() {
    Ok(order) => {
      assert_eq(order.length(), 6)
      assert_true(precedes(order, "core", "ui"))
      assert_true(precedes(order, "core", "net"))
      assert_true(precedes(order, "ui", "app"))
      assert_true(precedes(order, "net", "app"))
      assert_true(precedes(order, "net", "tool"))
    }
    Err(_) => assert_true(false)
  }
}

///|
test "workspace 菱形传递闭包去重与反向依赖" {
  let ws = diamond_ws()
  let deps = ws.transitive_deps("app")
  // ui / net / core 各出现一次（菱形不重复）。
  assert_eq(deps.length(), 3)
  assert_true(
    deps.contains("ui") && deps.contains("net") && deps.contains("core"),
  )
  let dependents = ws.dependents("core")
  assert_eq(dependents.length(), 4)
  assert_true(
    dependents.contains("ui") &&
    dependents.contains("net") &&
    dependents.contains("app") &&
    dependents.contains("tool"),
  )
  assert_eq(ws.dependents("leaf").length(), 0)
  assert_eq(ws.transitive_deps("ghost").length(), 0)
}

///|
test "workspace 增量重建计划：最小性 + 拓扑序" {
  let ws = diamond_ws()
  // 变更 net：重建 net → {app, tool}；core/ui/leaf 零重建。
  match ws.rebuild_plan(["net"]) {
    Ok(plan) => {
      assert_eq(plan.length(), 3)
      assert_true(
        plan.contains("net") && plan.contains("app") && plan.contains("tool"),
      )
      assert_true(
        !plan.contains("core") && !plan.contains("ui") && !plan.contains("leaf"),
      )
      assert_true(precedes(plan, "net", "app"))
      assert_true(precedes(plan, "net", "tool"))
    }
    Err(_) => assert_true(false)
  }
  // 空变更 → 空计划（零重建）。
  match ws.rebuild_plan([]) {
    Ok(plan) => assert_eq(plan.length(), 0)
    Err(_) => assert_true(false)
  }
}

///|
test "workspace 依赖环显式报错" {
  let cyc = @build_tool.Workspace::new([
    @build_tool.WorkspacePackage::new("a", ["b"]),
    @build_tool.WorkspacePackage::new("b", ["a"]),
  ])
  assert_true(cyc.build_order() is Err(_))
  assert_true(cyc.rebuild_plan(["a"]) is Err(_))
}

///|
test "PBT：随机 DAG 工作区的重建计划性质（100 迭代）" {
  let gen : @infra_pbt.Gen[(@build_tool.Workspace, Int)] = @infra_pbt.Gen::new(fn(
    rng,
  ) {
    // 分层随机 DAG：依赖只指向更小编号的包 → 必然无环。
    let n = 2 + rng.next_below(8)
    let pkgs : Array[@build_tool.WorkspacePackage] = []
    for i in 0..<n {
      let deps : Array[String] = []
      for j in 0..<i {
        if rng.next_below(3) == 0 {
          deps.push("p" + j.to_string())
        }
      }
      pkgs.push(@build_tool.WorkspacePackage::new("p" + i.to_string(), deps))
    }
    (@build_tool.Workspace::new(pkgs), rng.next_below(n))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(case) {
    let (ws, pick) = case
    if !(ws.validate() is None) {
      return false
    }
    let changed = "p" + pick.to_string()
    match (ws.build_order(), ws.rebuild_plan([changed])) {
      (Ok(order), Ok(plan)) => {
        // 1) 计划含变更包本身。
        if !plan.contains(changed) {
          return false
        }
        // 2) 计划 = 变更包 ∪ dependents（闭包性 + 最小性）。
        let expected : Array[String] = [changed]
        for d in ws.dependents(changed) {
          expected.push(d)
        }
        if plan.length() != expected.length() {
          return false
        }
        for e in expected {
          if !plan.contains(e) {
            return false
          }
        }
        // 3) 计划顺序与全量拓扑序中的相对顺序一致。
        for k in 0..<(plan.length() - 1) {
          if !precedes(order, plan[k], plan[k + 1]) {
            return false
          }
        }
        true
      }
      _ => false
    }
  })
  assert_true(ok)
}
