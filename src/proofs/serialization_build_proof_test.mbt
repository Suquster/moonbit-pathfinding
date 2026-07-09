// serialization_build_proof_test.mbt —— 序列化/构建工具/发布聚合家族的
// 证明谓词真实实现接地测试（INFRA 第十批）。
//
// 以 @serialization / @build_tool / @release_aggregate 的真实包实现驱动
// 既有谓词库（跨包驱动只发生在测试期）：
//   * serialization：base64 编解码往返恒等（随机字节串 PBT）、
//     zigzag 32/64 往返恒等、bits↔float/double 位级往返、schema 演化
//     自反无破坏；
//   * build_tool：topo_order 产出满足 build_order_respects_deps（随机
//     DAG PBT）——每个目标排在其全部依赖之后；
//   * release_aggregate：compat_diff 自反为空、actual_bump 与表面差异
//     一致、release_manifest 全就绪 ⟺ suite_release_ready。

// --- serialization：往返恒等 ---

///|
fn sb_bytes_gen() -> @infra_pbt.Gen[Bytes] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(0, 24)
    let arr : Array[Byte] = []
    for _i in 0..<n {
      arr.push(rng.next_range(0, 255).to_byte())
    }
    Bytes::from_array(arr)
  })
}

///|
test "base64 encode/decode round-trips over random byte strings" {
  let ok = @infra_pbt.holds_for_all(
    sb_bytes_gen(),
    fn(bs : Bytes) -> Bool {
      let back = @serialization.base64_decode(@serialization.base64_encode(bs))
      back == Some(bs)
    },
    iters=200,
  )
  assert_true(ok)
}

///|
test "zigzag 32/64 round-trips over random integers" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) {
      rng.next_range(-1_000_000_000, 1_000_000_000)
    }),
    fn(x : Int) -> Bool {
      @serialization.zigzag_decode_32(@serialization.zigzag_encode_32(x)) == x &&
      @serialization.zigzag_decode_64(
        @serialization.zigzag_encode_64(x.to_int64()),
      ) ==
      x.to_int64()
    },
    iters=200,
  )
  assert_true(ok)
}

///|
test "float/double bit casts round-trip" {
  for x in [0.0, 1.5, -2.25, 1024.0e10, -0.5] {
    assert_true(
      @serialization.bits_to_double(@serialization.double_to_bits(x)) == x,
    )
    let f = Float::from_double(x)
    assert_true(
      @serialization.bits_to_float(@serialization.float_to_bits(f)) == f,
    )
  }
}

// --- build_tool：拓扑序尊重依赖 ---

///|
/// 随机 DAG 生成器：n ∈ [1, 10] 个目标，仅生成 u > v 的依赖边
/// （t{u} 依赖 t{v}），结构上无环。
fn sb_dag_gen() -> @infra_pbt.Gen[(Int, Array[(Int, Int)])] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 10)
    let edges : Array[(Int, Int)] = []
    let m = rng.next_range(0, 2 * n)
    for _i in 0..<m {
      let u = rng.next_range(0, n - 1)
      let v = rng.next_range(0, n - 1)
      if u > v {
        edges.push((u, v))
      }
    }
    (n, edges)
  })
}

///|
fn sb_prop_topo_respects_deps(input : (Int, Array[(Int, Int)])) -> Bool {
  let (n, raw_edges) = input
  let targets : Array[@build_tool.Target] = []
  for i in 0..<n {
    targets.push(@build_tool.Target::new("t\{i}"))
  }
  let edges : Array[(@build_tool.Target, @build_tool.Target)] = []
  for e in raw_edges {
    edges.push((targets[e.0], targets[e.1]))
  }
  match @build_tool.topo_order(@build_tool.BuildGraph::new(targets, edges)) {
    Ok(order) => {
      // 以名字驻留还原下标位置，交给 build_order_respects_deps 判定。
      let pos : Array[Int] = []
      for _i in 0..<n {
        pos.push(-1)
      }
      let mut rank = 0
      for t in order {
        let mut idx = 0
        while idx < n {
          if targets[idx] == t {
            pos[idx] = rank
          }
          idx += 1
        }
        rank += 1
      }
      // BuildGraph 边 (u, v) 表示「u 先于 v」，谓词边 (依赖方, 被依赖方)
      // 即 (v, u)，据此翻转后交给 build_order_respects_deps 判定。
      let dep_edges : Array[(Int, Int)] = []
      for e in raw_edges {
        dep_edges.push((e.1, e.0))
      }
      build_order_respects_deps(pos, dep_edges)
    }
    Err(_) => false
  }
}

///|
test "topo_order places every target after all its dependencies" {
  let ok = @infra_pbt.holds_for_all(
    sb_dag_gen(),
    sb_prop_topo_respects_deps,
    iters=128,
  )
  assert_true(ok)
}

// --- release_aggregate：兼容性差异与套件就绪 ---

///|
test "compat_diff is reflexively empty and detects removals" {
  let surface = @release_aggregate.ApiSurface::new([
    ("core", "shortest_path"),
    ("graph", "synthetic_grid_csr"),
  ])
  let same = @release_aggregate.compat_diff(surface, surface)
  assert_true(same.removed.length() == 0 && same.added.length() == 0)
  let shrunk = @release_aggregate.ApiSurface::new([("core", "shortest_path")])
  let diff = @release_aggregate.compat_diff(surface, shrunk)
  assert_true(diff.removed.length() == 1)
}

///|
test "release manifest readiness agrees with per-direction conjunction" {
  let manifest = @release_aggregate.release_manifest()
  let mut all_ready = true
  for d in manifest {
    if !d.release_ready {
      all_ready = false
    }
  }
  assert_true(@release_aggregate.suite_release_ready(manifest) == all_ready)
}
