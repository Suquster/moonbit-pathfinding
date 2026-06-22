// Feature: championship-v1-upgrade, Property OSM-1/OSM-2: OSM 路网子集解析往返一致 + 缺失安全降级
//
// 本文件以属性测试校验 osm.mbt 新增公开函数的两条核心不变量
// （Requirement 8.7 · 任务 19.2）：
//
//   * **OSM-1 解析往返一致**：对任意随机非负整权边表，将其渲染为 TSV 文本后再经
//     `CsrGraph::from_osm_edge_list` 解析，得到的 CSR 图所含有向边多重集合与原始
//     边集合**逐元素相等**，且推断节点数恰为「最大节点标识 + 1」（无边时为 0）；
//     产出的 CSR 结构自洽（`row_ptr` 长度为 n+1、单调不减、末项等于边数）。
//   * **OSM-2 缺失安全降级**：`load_osm_or_synthetic` 对「数据缺失 / 空白 / 解析
//     失败」一律不报错，降级为非空合成网格（`SyntheticFallback`）；对合法数据采用
//     真实图（`RealOsm`）。任一情形产出的图恒结构自洽、节点数与字段一致。
//
// 驱动框架：复用共享 PBT 包 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all`
// （`for "test"` 引入，不进入运行时产物）。每条属性迭代 128 次（≥100 基线）。

///|
/// 校验 `CsrGraph[Double]` 的结构自洽性（CSR 三数组对齐 + row_ptr 单调）。
fn osm_csr_well_formed(g : CsrGraph[Double]) -> Bool {
  if g.n < 0 {
    return false
  }
  if g.row_ptr.length() != g.n + 1 {
    return false
  }
  if g.col_idx.length() != g.weights.length() {
    return false
  }
  if g.row_ptr[0] != 0 {
    return false
  }
  if g.row_ptr[g.n] != g.col_idx.length() {
    return false
  }
  let mut i = 1
  while i <= g.n {
    if g.row_ptr[i] < g.row_ptr[i - 1] {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 从 CSR 图按 (src, dst, weight) 提取全部有向边（src 为所在行）。
fn osm_extract_edges(g : CsrGraph[Double]) -> Array[(Int, Int, Double)] {
  let out : Array[(Int, Int, Double)] = []
  for v in 0..<g.n {
    let start = g.row_ptr[v]
    let stop = g.row_ptr[v + 1]
    for k in start..<stop {
      out.push((v, g.col_idx[k], g.weights[k]))
    }
  }
  out
}

///|
/// 以三态比较器按 (src, dst, weight) 升序排序边三元组数组（用于多重集合比较）。
fn osm_sort_triples(items : Array[(Int, Int, Double)]) -> Unit {
  items.sort_by(fn(a, b) {
    let (sa, ta, wa) = a
    let (sb, tb, wb) = b
    if sa != sb {
      if sa < sb {
        -1
      } else {
        1
      }
    } else if ta != tb {
      if ta < tb {
        -1
      } else {
        1
      }
    } else if wa < wb {
      -1
    } else if wa > wb {
      1
    } else {
      0
    }
  })
}

///|
/// 判断两边三元组多重集合是否逐元素相等（调用方须已分别排序）。
fn osm_triples_equal(
  a : Array[(Int, Int, Double)],
  b : Array[(Int, Int, Double)],
) -> Bool {
  if a.length() != b.length() {
    return false
  }
  let mut i = 0
  while i < a.length() {
    let (sa, ta, wa) = a[i]
    let (sb, tb, wb) = b[i]
    if sa != sb || ta != tb || (wa - wb).abs() > 1.0e-9 {
      return false
    }
    i = i + 1
  }
  true
}

///|
/// 随机边表生成器：节点数 1..7、边数 0..14；每条边整数权 1..1000（以 Double 承载）。
///
/// 整数权保证渲染为 TSV 文本后解析往返为相等 Double（避免浮点格式化误差）。
/// 同时携带「渲染好的 TSV 文本」与「期望边集合 / 期望节点数」，供属性直接比对。
struct OsmCase {
  tsv : String
  expected : Array[(Int, Int, Double)]
  expected_n : Int
}

///|
/// 构造随机 `OsmCase`：先随机产边，再以 TextBuilder 渲染为无表头的 TSV 文本。
fn osm_case_gen() -> @infra_pbt.Gen[OsmCase] {
  @infra_pbt.Gen::new(fn(rng) {
    let n_nodes = rng.next_range(1, 7) // 1..7 个可用节点
    let m = rng.next_below(15) // 0..14 条边
    let expected : Array[(Int, Int, Double)] = []
    let tb = @infra_text.TextBuilder::new()
    let mut max_id = -1
    let mut k = 0
    while k < m {
      let src = rng.next_below(n_nodes)
      let dst = rng.next_below(n_nodes)
      let wi = rng.next_range(1, 1000) // 整数权 1..1000
      let w = wi.to_double()
      expected.push((src, dst, w))
      if src > max_id {
        max_id = src
      }
      if dst > max_id {
        max_id = dst
      }
      // 渲染一行：src \t dst \t weight \n（整数权直接以 Int 文本写出）。
      tb.push_str(src.to_string())
      tb.push_char('\t')
      tb.push_str(dst.to_string())
      tb.push_char('\t')
      tb.push_str(wi.to_string())
      tb.push_char('\n')
      k = k + 1
    }
    OsmCase::{ tsv: tb.build(), expected, expected_n: max_id + 1 }
  })
}

///|
/// Feature: championship-v1-upgrade, Property OSM-1: OSM 边表解析往返一致
///
/// 对任意随机非负整权边表：渲染为 TSV → `from_osm_edge_list` 解析，得到的 CSR
/// 图结构自洽、推断节点数等于「最大标识 + 1」、所含边多重集合与原始集合相等。
///
/// **Validates: Requirements 8.7**
test "Feature: championship-v1-upgrade, Property OSM-1: osm edge list parse roundtrip" {
  let ok = @infra_pbt.holds_for_all(
    osm_case_gen(),
    fn(c) {
      match CsrGraph::from_osm_edge_list(c.tsv) {
        Err(_) => false // 合法输入不应解析失败
        Ok(g) => {
          if !osm_csr_well_formed(g) {
            return false
          }
          if g.n != c.expected_n {
            return false
          }
          let got = osm_extract_edges(g)
          let want = c.expected
          osm_sort_triples(got)
          osm_sort_triples(want)
          osm_triples_equal(got, want)
        }
      }
    },
    iters=128,
  )
  assert_true(ok)
}

///|
/// 降级场景标签：精确枚举四类输入形态，驱动 OSM-2 属性。
enum OsmScenario {
  Missing // content == None
  Blank // content == Some(仅空白)
  Malformed // content == Some(含非法非首行)
  Valid // content == Some(合法边表)
}

///|
/// 降级场景生成器：随机选取四类输入与回退维度 fallback_dim ∈ 1..5。
struct OsmFbCase {
  scenario : OsmScenario
  content : String?
  fallback_dim : Int
  expected_valid_n : Int // 仅 Valid 场景有意义：期望真实图节点数
}

///|
/// 构造随机降级场景：四类等概率取样，Valid 场景内联渲染一张小图。
fn osm_fb_gen() -> @infra_pbt.Gen[OsmFbCase] {
  @infra_pbt.Gen::new(fn(rng) {
    let dim = rng.next_range(1, 5) // 回退网格边长 1..5
    let pick = rng.next_below(4)
    match pick {
      0 =>
        OsmFbCase::{
          scenario: Missing,
          content: None,
          fallback_dim: dim,
          expected_valid_n: 0,
        }
      1 =>
        OsmFbCase::{
          scenario: Blank,
          content: Some("   \n\t\n  "),
          fallback_dim: dim,
          expected_valid_n: 0,
        }
      2 =>
        // 首行合法、第二行非法（非首行）→ 触发结构化解析失败 → 降级。
        OsmFbCase::{
          scenario: Malformed,
          content: Some("0\t1\t5.0\nNOT_A_VALID_LINE"),
          fallback_dim: dim,
          expected_valid_n: 0,
        }
      _ => {
        // Valid：渲染一条 (0 -> k) 边，期望节点数为 k + 1。
        let k = rng.next_range(1, 6) // 目标节点 1..5
        let tb = @infra_text.TextBuilder::new()
        tb.push_str("0\t")
        tb.push_str(k.to_string())
        tb.push_str("\t100\n")
        OsmFbCase::{
          scenario: Valid,
          content: Some(tb.build()),
          fallback_dim: dim,
          expected_valid_n: k + 1,
        }
      }
    }
  })
}

///|
/// Feature: championship-v1-upgrade, Property OSM-2: OSM 数据缺失安全降级
///
/// 对任意降级场景：`load_osm_or_synthetic` 恒不崩溃、恒返回结构自洽图，且
///   * 缺失 / 空白 / 解析失败 → `SyntheticFallback` 且节点数 = dim×dim > 0；
///   * 合法数据 → `RealOsm` 且节点数 = 期望真实图节点数。
/// 任一情形 `node_count` 与 `graph.n` 一致、`edge_count` 与 CSR 边数一致。
///
/// **Validates: Requirements 8.7**
test "Feature: championship-v1-upgrade, Property OSM-2: missing data safe degradation" {
  let ok = @infra_pbt.holds_for_all(
    osm_fb_gen(),
    fn(c) {
      let outcome = load_osm_or_synthetic(c.content, c.fallback_dim)
      let g = outcome.graph
      // 公共不变量：图结构自洽，且报告字段与图一致。
      if !osm_csr_well_formed(g) {
        return false
      }
      if outcome.node_count != g.n {
        return false
      }
      let ec = if g.col_idx.length() < g.weights.length() {
        g.col_idx.length()
      } else {
        g.weights.length()
      }
      if outcome.edge_count != ec {
        return false
      }
      match c.scenario {
        Valid =>
          outcome.source == RealOsm && g.n == c.expected_valid_n && g.n > 0
        Missing | Blank | Malformed => {
          // 降级三场景：来源为合成、节点数 = dim×dim > 0。
          let dim = c.fallback_dim
          outcome.source == SyntheticFallback && g.n == dim * dim && g.n > 0
        }
      }
    },
    iters=128,
  )
  assert_true(ok)
}
