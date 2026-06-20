// prop_capabilities_test.mbt —— 能力协商子集属性测试（任务 5.5，Property 14）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 14「能力协商子集」：
//
//   *对任意* 由生成器产出的客户端能力声明（从 13 个规范能力名中随机选取的子集），
//   `negotiate(client)` 返回的 `ServerCapabilitiesExt` 满足：
//     (a) 子集性质：若某 provider 位为 `true`，则其对应的规范能力名必在客户端声明集中
//         （即「服务端声明能力集 ⊆ 客户端声明能力集」，限于已知规范能力名）；
//     (b) 未声明不予声明：对每个未在客户端声明集中的规范能力名，其对应 provider 位为
//         `false`。
//   二者合起来等价于：每个 provider 位 == （其能力名 ∈ 客户端声明集）。
//
// **Validates: Requirements 1.7**
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。

// ---------------------------------------------------------------------------
// 规范能力名 ↔ provider 位提取器
// ---------------------------------------------------------------------------

///|
/// 13 个规范能力名（与 capabilities_ext.mbt 中 `negotiate` 识别的名字一致）。
/// 客户端 `capabilities : Array[String]` 以这些名字声明其所支持的能力。
let cap_names : Array[String] = [
  "diagnostic", "completion", "definition", "hover", "documentSymbol", "references",
  "rename", "formatting", "codeAction", "signatureHelp", "semanticTokens", "foldingRange",
  "documentHighlight",
]

///|
/// 从协商结果中取出某规范能力名对应的 provider 位（与 `cap_names` 顺序一致）。
/// 用于逐位断言「provider 位 == 能力名 ∈ 客户端声明集」。
fn provider_bit(caps : ServerCapabilitiesExt, name : String) -> Bool {
  match name {
    "diagnostic" => caps.diagnostic_provider
    "completion" => caps.completion_provider
    "definition" => caps.definition_provider
    "hover" => caps.hover_provider
    "documentSymbol" => caps.document_symbol_provider
    "references" => caps.references_provider
    "rename" => caps.rename_provider
    "formatting" => caps.formatting_provider
    "codeAction" => caps.code_action_provider
    "signatureHelp" => caps.signature_help_provider
    "semanticTokens" => caps.semantic_tokens_provider
    "foldingRange" => caps.folding_range_provider
    _ => caps.document_highlight_provider
  }
}

///|
/// 某名字是否在能力名列表中（线性查找）。
fn contains_name(names : Array[String], name : String) -> Bool {
  for n in names {
    if n == name {
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// 随机生成器（客户端能力声明）
// ---------------------------------------------------------------------------

///|
/// 生成随机客户端能力声明：对 13 个规范能力名各以约 1/2 概率纳入，构造其子集。
/// 子集可能为空，也可能为全集，覆盖协商裁剪的各种规模。
fn gen_client_capabilities(rng : @infra_pbt.Rng) -> InitializeParamsExt {
  let selected : Array[String] = []
  for name in cap_names {
    if rng.next_bool() {
      selected.push(name)
    }
  }
  InitializeParamsExt::new(selected, [])
}

///|
/// 客户端能力声明生成器（封装为 @infra_pbt.Gen）。
fn gen_clients() -> @infra_pbt.Gen[InitializeParamsExt] {
  @infra_pbt.Gen::new(fn(rng) { gen_client_capabilities(rng) })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 14）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 14: 能力协商子集
///
/// 对任意由生成器产出的客户端能力声明，`negotiate` 后逐一检查 13 个规范能力位：
///   (a) 子集性质：provider 位为 true ⇒ 其能力名在客户端声明集中；
///   (b) 未声明不予声明：能力名不在客户端声明集中 ⇒ provider 位为 false。
/// 二者合并为逐位等价：`provider_bit(caps, name) == (name ∈ client.capabilities)`。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 1.7**
test "Feature: lsp, Property 14: capability negotiation yields a subset of client-declared capabilities" {
  let ok = @infra_pbt.holds_for_all(gen_clients(), fn(client) {
    let caps = negotiate(client)
    let mut holds = true
    for name in cap_names {
      let declared = contains_name(client.capabilities, name)
      let bit = provider_bit(caps, name)
      // 逐位等价：声明则置位、未声明则不置位（子集裁剪不变量）。
      if bit != declared {
        holds = false
      }
    }
    holds
  })
  assert_true(ok)
}
