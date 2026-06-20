// prop_workspace_symbol_test.mbt —— 工作区符号可靠性属性测试（任务 9.3，Property 15）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 15「工作区符号可靠性」：
//
//   *对任意* 由生成器产出的（多文档内存工作区 docs, 查询字符串 query），令
//     result = workspace_symbols(docs, query)
//   则 result 中的**每一个** Location loc 都同时满足：
//     1. **来自工作区某文档的已定义符号**：存在某 doc ∈ docs，使
//        doc.uri == loc.uri，且 doc.symbols 中存在某 symbol，其 range == loc.range；
//     2. **该符号名包含查询子串**：上述命中的 symbol 其 name 包含 query 子串。
//
//   即：workspace/symbol 不会凭空捏造定位，也不会返回名称不含查询子串的符号。
//
// **Validates: Requirements 5.2**
//
// ── 「随机多文档工作区 + 查询字符串」生成策略（保证属性非平凡且可靠）─────────
// 本文件为黑盒测试，仅依赖同包公开 / 同包可见 API：
//   * dsl.mbt 的 `analyze` / `TextDocument` / `Analysis` / `Symbol`；
//   * references.mbt 的 `workspace_symbols`（5.2）与同包私有 `contains_substring`
//     （`fn contains_substring(haystack, needle) -> Bool`，同 package 可直接复用）；
//   * types.mbt 的 `Location` / `Range`（`derive(Eq)`，谓词以 `==` 比较）。
//
// 复用任务 9.2（prop_references_test.mbt）已在**同包**定义的随机 DSL 文档生成器
// `gen_dsl_doc(rng) -> (TextDocument, String)`（连同 `dsl_key_pool` /
// `gen_dsl_value` / `declared_has` 等），不重复定义。工作区由 1..N 个独立文档构成：
//   1. 文档数 N 随机取 1..4；每个文档调用 `gen_dsl_doc(rng)` 取其 `.0`
//      （TextDocument，忽略其携带的「某已定义键」分量），再 `analyze` 成 Analysis；
//      为避免多文档共用同一 uri 干扰「某 doc.uri == loc.uri」的判定，逐文档改写
//      为带序号的唯一 uri。
//   2. 查询字符串从一个小集合 `ws_query_pool` 中随机取：覆盖空串（匹配全部）、
//      常见命中键前缀（"k" / "a" / "k0"）、单字符、以及大概率不命中（"z" / "qq"），
//      使结果时而非空（属性非平凡）、时而为空（覆盖空结果路径）。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增的 helper（`ws_query_pool` / `ws_contains` /
// `gen_workspace` / `gen_workspace_samples` / `prop15_workspace_symbols_reliable`）
// 均与同包既有测试 helper 不重名。注：references.mbt 内的 `contains_substring`
// 为源文件私有 `fn`，对黑盒测试（`_test.mbt`，视本包为外部包）不可见，故此处自实现
// 等价的子串判定 `ws_contains`，与 workspace_symbols 内部判定语义一致（空 needle
// 视为被任意串包含）。

// ---------------------------------------------------------------------------
// 子串匹配辅助（与 workspace_symbols 内部判定语义一致）
// ---------------------------------------------------------------------------

///|
/// 朴素子串包含判定：`haystack` 是否包含 `needle`（按 Unicode 码位/字符滑窗）。
/// 空 `needle` 视为被任意串包含（与「空查询匹配全部符号」一致）。
fn ws_contains(haystack : String, needle : String) -> Bool {
  let hs : Array[Char] = []
  for c in haystack {
    hs.push(c)
  }
  let ns : Array[Char] = []
  for c in needle {
    ns.push(c)
  }
  let hn = hs.length()
  let nn = ns.length()
  if nn == 0 {
    return true
  }
  if nn > hn {
    return false
  }
  let mut i = 0
  while i + nn <= hn {
    let mut j = 0
    let mut matched = true
    while j < nn {
      if hs[i + j] != ns[j] {
        matched = false
        break
      }
      j = j + 1
    }
    if matched {
      return true
    }
    i = i + 1
  }
  false
}

// ---------------------------------------------------------------------------
// 随机多文档工作区 + 查询字符串生成器
// ---------------------------------------------------------------------------

///|
/// 查询字符串候选池：覆盖空串、命中前缀、单字符、以及大概率不命中的串。
///
///   * ""    —— 空查询，子串包含空串，匹配全部符号（覆盖「全量」路径）；
///   * "k"   —— 命中 dsl_key_pool 中的 k0/k1/k2（覆盖多命中路径）；
///   * "a"   —— 命中键 a（覆盖单字符命中路径）；
///   * "k0"  —— 命中具体键 k0（覆盖多字符命中路径）；
///   * "b"   —— 命中键 b；
///   * "z"   —— 不命中任何已定义键（覆盖空结果路径）；
///   * "qq"  —— 不命中（覆盖多字符空结果路径）。
let ws_query_pool : Array[String] = ["", "k", "a", "k0", "b", "z", "qq"]

///|
/// 生成一个样本：（多文档内存工作区 docs : Array[Analysis], 查询字符串 query）。
///
/// 文档数 N ∈ 1..4，每个文档复用同包 `gen_dsl_doc` 取其 TextDocument 分量，
/// 改写为带序号的唯一 uri 后 `analyze` 成 Analysis；query 取自 `ws_query_pool`。
fn gen_workspace(rng : @infra_pbt.Rng) -> (Array[Analysis], String) {
  let n_docs = rng.next_range(1, 4) // 1..4 个文档
  let docs : Array[Analysis] = []
  let mut di = 0
  while di < n_docs {
    // 复用任务 9.2 的随机 DSL 文档生成器，仅取 TextDocument 分量。
    let (td, _k) = gen_dsl_doc(rng)
    // 赋予唯一 uri，避免多文档共用同一 uri 干扰来源判定。
    let uri = "file:///ws/doc" + di.to_string() + ".dsl"
    let doc : TextDocument = { uri, text: td.text }
    docs.push(analyze(doc))
    di = di + 1
  }
  let query = ws_query_pool[rng.next_below(ws_query_pool.length())]
  (docs, query)
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn gen_workspace_samples() -> @infra_pbt.Gen[(Array[Analysis], String)] {
  @infra_pbt.Gen::new(fn(rng) { gen_workspace(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词（Property 15）
// ---------------------------------------------------------------------------

///|
/// 对样本 (docs, query) 判定「工作区符号可靠性」是否成立。
///
/// 对 `workspace_symbols(docs, query)` 的每个 Location loc：
///   1. 存在某 doc ∈ docs，doc.uri == loc.uri 且其某 symbol 的 range == loc.range；
///   2. 上述命中的 symbol 其 name 包含 query 子串。
///
/// 期望命中由 `docs` 的 `symbols` 投影**独立**重算，再与 `workspace_symbols`
/// 的输出比对，使断言非平凡。
fn prop15_workspace_symbols_reliable(
  docs : Array[Analysis],
  query : String,
) -> Bool {
  let result = workspace_symbols(docs, query)
  for loc in result {
    // 在工作区中寻找一个 (doc.uri == loc.uri && symbol.range == loc.range &&
    // symbol.name 含 query) 的见证。
    let mut witnessed = false
    for doc in docs {
      if doc.uri != loc.uri {
        continue
      }
      for s in doc.symbols {
        if s.range == loc.range && ws_contains(s.name, query) {
          witnessed = true
          break
        }
      }
      if witnessed {
        break
      }
    }
    if not(witnessed) {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// 属性测试（Property 15）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 15: 工作区符号可靠性
///
/// 对任意由生成器产出的（多文档工作区 docs, 查询字符串 query）：
///   `workspace_symbols(docs, query)` 返回的每个 Location 都对应工作区内某文档
///   的某已定义符号（uri 与 range 一致），且该符号名包含 query 子串。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 5.2**
test "Feature: lsp, Property 15: workspace symbols are reliable matches of defined symbols" {
  let ok = @infra_pbt.holds_for_all(gen_workspace_samples(), fn(sample) {
    let (docs, query) = sample
    prop15_workspace_symbols_reliable(docs, query)
  })
  assert_true(ok)
}
