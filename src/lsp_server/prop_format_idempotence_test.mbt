// prop_format_idempotence_test.mbt —— 格式化幂等属性测试（任务 11.3，Property 17）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 17「格式化幂等」：
//
//   *对任意* 由生成器产出的 DSL 文档 doc，令
//     e1   = formatting(doc)
//     t1   = apply_workspace_edit(doc.text, e1)   // 一次格式化后的文本
//     doc1 = { uri: doc.uri, text: t1 }
//     e2   = formatting(doc1)
//   则同时满足：
//     1. **e2 为空**：对已格式化文本再次 `formatting` 不再产生任何改变文本的编辑
//        （即 `format ∘ format == format`，规范形式是 `formatting` 的不动点）；
//     2. **再次应用 e2 不改变文本**：t2 = apply_workspace_edit(t1, e2) 满足
//        t2 == t1（与断言 1 互为佐证；e2 为空时拼接恒等）。
//
// **Validates: Requirements 5.5**
//
// ── 「随机 DSL 文档」生成策略（保证属性非平凡且可靠）─────────────────────
// 本文件为黑盒测试，仅依赖 format.mbt 的公开 API（`formatting`）、rename.mbt 的
// `apply_workspace_edit`（同包）与 types.mbt 的 `TextDocument`。
//
// 为让幂等测试**非平凡**（真正出现需规范化的行），生成器 `p17_gen_unformatted_doc`
// 主动在赋值行的 `key` 与 '='、'=' 与 `value` 之间、以及行首插入 0..3 个随机空白，
// 故大量行处于**非规范**状态（如 "key=value"、"key   =   value"、"  key =value"），
// 首次 `formatting` 会产出非空编辑；同时混入注释行 / 空行 / 已规范行，覆盖
// `formatting` 的「不动点 / 跳过」路径。
//
// 约束（与 format.mbt 语义对齐）：
//   * `formatting` 仅规范赋值行的等号周边空白；value **内部**空白保留。生成的
//     value 片段不含 '\n'（不改变行结构）、不含 '='（不引入第二个等号歧义）、
//     不以 '#' 起始（不误判为注释），并避免源码裸 `${`（本测试纯空白扰动，
//     value 不含引用）。
//   * 键取自合法标识符小集合，确保是 `formatting` 认可的赋值行。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增的 helper 均以 `p17_` 前缀命名，与同包既有测试 helper
// （`dsl_key_pool` / `gen_dsl_doc` / `find_diagnostic` 等）不重名。

// ---------------------------------------------------------------------------
// 随机（含不规范空白的）DSL 文档生成器
// ---------------------------------------------------------------------------

///|
/// 待选键集合（合法标识符；小集合便于在文档内反复出现）。
let p17_key_pool : Array[String] = ["k0", "k1", "key", "a", "name_1"]

///|
/// value 字面片段池：不含 '$' / '{' / '}' / '=' / '\n' / 行首 '#'，避免误构成
/// 引用 / 第二个等号 / 注释 / 换行，从而不破坏「赋值行」结构。
let p17_value_pool : Array[String] = ["x", "1", "val", "foo", "hello", ""]

///|
/// 生成 0..3 个空格组成的随机空白串（仅普通空格，确定性可重放）。
fn p17_spaces(rng : @infra_pbt.Rng) -> String {
  let n = rng.next_below(4) // 0..3
  let mut s = ""
  let mut i = 0
  while i < n {
    s = s + " "
    i = i + 1
  }
  s
}

///|
/// 生成一段 value 文本：1..3 段字面片段，段间以 0..2 个空格连接
/// （内部空白用于验证 `formatting` 保留 value 内部空白；首尾空白由扰动注入）。
fn p17_gen_value(rng : @infra_pbt.Rng) -> String {
  let segs = rng.next_range(1, 3) // 1..3 段
  let mut v = p17_value_pool[rng.next_below(p17_value_pool.length())]
  let mut i = 1
  while i < segs {
    // 段间 0..2 个空格（内部空白，formatting 应原样保留）。
    let gap = rng.next_below(3)
    let mut g = ""
    let mut j = 0
    while j < gap {
      g = g + " "
      j = j + 1
    }
    v = v + g + p17_value_pool[rng.next_below(p17_value_pool.length())]
    i = i + 1
  }
  v
}

///|
/// 生成一份**含不规范空白**的随机 DSL 文档：逐行随机产出
///   * 赋值行：`<行首空白><key><空白>=<空白><value>`，各空白段独立取 0..3 空格，
///     故大概率非规范，首次 formatting 会产出编辑；
///   * 注释行 `# ...` / 空行 / 已规范行 `key = value`：覆盖跳过 / 不动点路径。
fn p17_gen_unformatted_doc(rng : @infra_pbt.Rng) -> TextDocument {
  let n_lines = rng.next_range(2, 7) // 2..6 行
  let mut text = ""
  let mut li = 0
  while li < n_lines {
    let kind = rng.next_below(6)
    if kind == 0 {
      // 空行。
      text = text + "\n"
    } else if kind == 1 {
      // 注释行（首个非空白为 '#'，formatting 应跳过）。
      text = text + p17_spaces(rng) + "# comment\n"
    } else if kind == 2 {
      // 已规范赋值行（不动点路径）。
      let key = p17_key_pool[rng.next_below(p17_key_pool.length())]
      text = text + key + " = " + p17_gen_value(rng) + "\n"
    } else {
      // 不规范赋值行：行首 / key 与 '=' 之间 / '=' 与 value 之间随机空白。
      let lead = p17_spaces(rng)
      let key = p17_key_pool[rng.next_below(p17_key_pool.length())]
      let left = p17_spaces(rng)
      let right = p17_spaces(rng)
      let value = p17_gen_value(rng)
      text = text + lead + key + left + "=" + right + value + "\n"
    }
    li = li + 1
  }
  { uri: "file:///prop17.conf", text }
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn p17_gen_samples() -> @infra_pbt.Gen[TextDocument] {
  @infra_pbt.Gen::new(fn(rng) { p17_gen_unformatted_doc(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词（Property 17）
// ---------------------------------------------------------------------------

///|
/// 对文档 doc 判定「格式化幂等」是否成立：
///   1. e2 = formatting(format-once(doc)) 为空（不再产生改变文本的编辑）；
///   2. 再次应用 e2 得 t2 == t1（佐证幂等）。
fn p17_format_idempotent(doc : TextDocument) -> Bool {
  let e1 = formatting(doc)
  let t1 = apply_workspace_edit(doc.text, e1)
  let doc1 : TextDocument = { uri: doc.uri, text: t1 }
  let e2 = formatting(doc1)
  if e2.length() != 0 {
    return false
  }
  let t2 = apply_workspace_edit(t1, e2)
  t2 == t1
}

// ---------------------------------------------------------------------------
// 属性测试（Property 17）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 17: 格式化幂等
///
/// 对任意由生成器产出的（含不规范空白的）DSL 文档：对其规范化文本再次应用
/// `formatting` 不再产生改变文本的编辑（`format ∘ format == format`）。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 5.5**
test "Feature: lsp, Property 17: formatting is idempotent (format(format(x)) == format(x))" {
  let ok = @infra_pbt.holds_for_all(p17_gen_samples(), fn(doc) {
    p17_format_idempotent(doc)
  })
  assert_true(ok)
}
