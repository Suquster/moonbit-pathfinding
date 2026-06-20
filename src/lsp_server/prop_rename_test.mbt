// prop_rename_test.mbt —— 重命名完整性属性测试（任务 10.2，Property 9）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 9「重命名完整性」：
//
//   *对任意* 由生成器产出的（DSL 文档 doc, 其中某已定义键 k, 未被占用新名
//   new_name），令
//     a        = analyze(doc)
//     we       = rename(a, k, new_name)
//     edits    = we.changes 中 a.uri 对应的 TextEdit 序列
//     new_text = apply_workspace_edit(doc.text, edits)
//     a2       = analyze({ uri: doc.uri, text: new_text })
//   则同时满足：
//     1. **出现数守恒**：原名 k 在 a 中的出现数（name == k 的 symbol 数[0 或 1]
//        + name == k 的 reference 数）== 新名 new_name 在 a2 中的出现数
//        （name == new_name 的 symbol 数 + reference 数）。
//        即 rename 把 k 的全部「已解析出现」一致地迁移到 new_name 名下。
//     2. **原名消失**：原名 k 在 a2 中不再作为符号或引用出现。
//        该断言在 k 被**唯一定义**时成立——因 new_name 独特、k 的定义与全部
//        引用都被改名。若 k 被**重复定义**（DSL 语义错误，analyze 仅以首个定义
//        为权威、其余记 Warning 而不收入 symbols），rename 只迁移已解析的定义
//        与引用，重复定义行的裸 `k` 会在重分析后「浮现」为新的首个定义，故此
//        情形下不强制要求 k 消失（出现数守恒断言 1 仍恒成立）。
//
// **Validates: Requirements 5.4, 5.10**
//
// ── 生成策略（复用任务 9.2 的 DSL 文档生成器） ─────────────────────────
// 本文件为黑盒测试，复用**同包** prop_references_test.mbt 的
// `gen_dsl_doc(rng) -> (TextDocument, String)`（返回一份合法 key = value 文档与
// 其中某个**已定义**键 k）。仅依赖 dsl.mbt 公开 API（`analyze` / `TextDocument`
// / `Analysis` / `Symbol` / `Reference`）与 rename.mbt 的 `rename` /
// `apply_workspace_edit` / `WorkspaceEdit` / `TextEdit`。
//
// 新名 new_name 固定取独特名 "Q_renamed"：含大写字母与下划线，为合法 DSL 键名
// （`[A-Za-z_][A-Za-z0-9_]*`），且不在 `dsl_key_pool`（k0/k1/k2/a/b）/
// `undef_pool`（zzz/und）/ `dsl_literal_pool`（x/1/val/foo/""/hi）之中，亦不会
// 作为任何字面片段的子串出现，故保证「未被占用」：重命名前 new_name 在文档中
// 出现数恒为 0，重命名后其出现数应恰等于 k 原出现数。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `holds_for_all` 模板（默认 `iters=100`，
// 满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增 helper（`rename_new_name` / `count_name_occurrences` /
// `edits_for_uri` / `key_redefined` / `gen_rename_samples` /
// `prop9_rename_completeness`）均与同包既有测试 helper 不重名。

// ---------------------------------------------------------------------------
// 常量与辅助
// ---------------------------------------------------------------------------

///|
/// 独特的、未被生成文档占用的新名（合法 DSL 键名）。
let rename_new_name : String = "Q_renamed"

///|
/// 统计名字 `name` 在分析结果 `a` 中的出现数：
///   name == name 的 symbol 数（0 或 1，首个定义为权威）+ name == name 的
///   reference 数。以 `==` 比较 `Symbol.name` / `Reference.name`，不涉及 `${}`。
fn count_name_occurrences(a : Analysis, name : String) -> Int {
  let mut c = 0
  for s in a.symbols {
    if s.name == name {
      c = c + 1
    }
  }
  for r in a.references {
    if r.name == name {
      c = c + 1
    }
  }
  c
}

///|
/// 从 `WorkspaceEdit` 取出归属 `uri` 的 `TextEdit` 序列（无则空数组）。
fn edits_for_uri(we : WorkspaceEdit, uri : String) -> Array[TextEdit] {
  for change in we.changes {
    if change.0 == uri {
      return change.1
    }
  }
  []
}

///|
/// 判断键 `k` 是否在文档中被**重复定义**（analyze 对重复定义记一条
/// message == "重复定义键：" + k 的 Warning 诊断）。
fn key_redefined(a : Analysis, k : String) -> Bool {
  let dup_msg = "重复定义键：" + k
  for d in a.diagnostics {
    if d.message == dup_msg {
      return true
    }
  }
  false
}

// ---------------------------------------------------------------------------
// 样本生成器（复用 gen_dsl_doc）
// ---------------------------------------------------------------------------

///|
/// 样本生成器：复用同包 `gen_dsl_doc` 产出（DSL 文档, 某已定义键 k）。
fn gen_rename_samples() -> @infra_pbt.Gen[(TextDocument, String)] {
  @infra_pbt.Gen::new(fn(rng) { gen_dsl_doc(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词（Property 9）
// ---------------------------------------------------------------------------

///|
/// 对样本 (doc, k) 判定「重命名完整性」是否成立。
///
///   1. 出现数守恒：count(k in a) == count(new_name in a2)；
///   2. 原名消失：k 唯一定义时，count(k in a2) == 0。
fn prop9_rename_completeness(doc : TextDocument, k : String) -> Bool {
  let a = analyze(doc)
  let before_k = count_name_occurrences(a, k)
  // new_name 在原文档中应当未被占用（出现数为 0），属性方非平凡。
  if count_name_occurrences(a, rename_new_name) != 0 {
    return false
  }
  let we = rename(a, k, rename_new_name)
  let edits = edits_for_uri(we, a.uri)
  let new_text = apply_workspace_edit(doc.text, edits)
  let a2 = analyze({ uri: doc.uri, text: new_text })
  // 断言 1：出现数守恒（原名 k 原出现数 == 新名在重分析后的出现数）。
  let after_new = count_name_occurrences(a2, rename_new_name)
  if before_k != after_new {
    return false
  }
  // 断言 2：k 唯一定义时，原名 k 在重分析后不再出现。
  if not(key_redefined(a, k)) {
    if count_name_occurrences(a2, k) != 0 {
      return false
    }
  }
  true
}

// ---------------------------------------------------------------------------
// 属性测试（Property 9）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 9: 重命名完整性
///
/// 对任意由生成器产出的（DSL 文档 doc, 其中某已定义键 k）与独特新名
/// new_name = "Q_renamed"：应用 `rename` 产出的 `WorkspaceEdit` 后重分析，
///   * 新名 new_name 的出现数等于原名 k 的原出现数（出现数守恒）；
///   * 原名 k 不再出现（在 k 唯一定义时）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 5.4, 5.10**
test "Feature: lsp, Property 9: rename rewrites every occurrence of a key to a fresh name completely" {
  let ok = @infra_pbt.holds_for_all(gen_rename_samples(), fn(sample) {
    let (doc, k) = sample
    prop9_rename_completeness(doc, k)
  })
  assert_true(ok)
}
