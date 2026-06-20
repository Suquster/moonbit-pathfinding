// prop_references_test.mbt —— 引用—定义自洽属性测试（任务 9.2，Property 8）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 8「引用—定义自洽」：
//
//   *对任意* 由生成器产出的（DSL 文档 doc, 其中某已定义键 k），令
//     a    = analyze(doc)
//     refs = references(a, k)
//   则同时满足：
//     1. **定义位置 ∈ refs**：a.symbols 中 name == k 的符号其定义范围所对应的
//        Location { uri: a.uri, range } 必出现在 refs 中；
//     2. **refs 中每个位置都落在 k 的某次出现上**：refs 的每个 Location 其 uri
//        等于 a.uri，且其 range 要么等于 k 的定义范围，要么等于 a.references 中
//        某个 name == k 的引用范围（即「定义或引用」之一）。
//
// **Validates: Requirements 5.1, 5.3, 5.8, 5.9**
//
// ── 「随机 DSL 文档 + 其中某已定义键」生成策略（保证属性非平凡且可靠）──────
// 本文件为黑盒测试，仅依赖 dsl.mbt 的公开 API（`analyze` / `TextDocument` /
// `Analysis` / `Symbol` / `Reference`）与 references.mbt 的 `references`、以及
// types.mbt 的 `Location` / `Range`（均 `derive(Eq)`，谓词以 `==` 比较）。
//
// 生成器自建一份**合法的 key = value 文档**（文法见 dsl.mbt / moon.pkg）：
//   1. 从一个小键集合 `dsl_key_pool`（k0/k1/k2/a/b）中随机取键，逐行写出
//      `key = value` 赋值；首次出现的键即被 `analyze` 记为已定义符号。
//   2. value 以一定概率插入 `${someKey}` 引用：`someKey` 优先取自**已声明键集**
//      （确保是「已定义键」的引用，使 k 的引用集非空、属性非平凡），并以较小
//      概率引用一个**未定义键**（`undef_pool`，如 zzz）以覆盖未定义引用情形，
//      但绝不会被选作待验证键 k。
//   3. 同时随机穿插空行与 `#` 注释行，覆盖分析器的忽略路径。
//   4. 返回 (TextDocument, String)：String 是文档中某个**已定义**键 k（从已声明
//      键集中随机选取，保证 analyze 后 a.symbols 必含该名）。
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（默认
// `iters=100`，满足每条属性 ≥100 次迭代基线）。纯函数、无 IO，三后端一致。
//
// 命名约定：本文件新增的 helper（`dsl_key_pool` / `undef_pool` /
// `dsl_literal_pool` / `gen_dsl_value` / `gen_dsl_doc` / `gen_dsl_samples` /
// `prop8_reference_definition_consistent`）均与同包既有测试 helper 不重名。

// ---------------------------------------------------------------------------
// 随机 DSL 文档生成器
// ---------------------------------------------------------------------------

///|
/// 待选键集合（小集合，便于在同一文档内反复出现，制造定义 + 多处引用）。
let dsl_key_pool : Array[String] = ["k0", "k1", "k2", "a", "b"]

///|
/// 未定义键池：以小概率被引用，覆盖「引用未定义键」路径；绝不被选作待验证键 k。
let undef_pool : Array[String] = ["zzz", "und"]

///|
/// 值中的字面文本片段池（不含 '$' / '{' / '}' / '\n' / 行首 '#'，避免误构成引用
/// 或注释/换行，从而不破坏既定的「已声明键 → 已定义符号」结构）。
let dsl_literal_pool : Array[String] = ["x", "1", "val", "foo", "", "hi"]

///|
/// 生成一段 value 文本：若干「字面片段」与「`${ref}` 引用」交替拼接。
///
/// 引用名优先取自 `declared`（已声明键，确保是已定义键的引用）；以小概率取自
/// `undef_pool`（未定义键）。`declared` 为空时只产出字面片段。
fn gen_dsl_value(rng : @infra_pbt.Rng, declared : Array[String]) -> String {
  let mut v = ""
  let segs = rng.next_range(1, 3) // 1..3 段
  let mut i = 0
  while i < segs {
    // 先接一段字面文本。
    v = v + dsl_literal_pool[rng.next_below(dsl_literal_pool.length())]
    // 以约 1/2 概率插入一处引用。
    if rng.next_bool() {
      let name = if declared.length() > 0 && rng.next_below(5) != 0 {
        // 多数情况下引用一个已声明键。
        declared[rng.next_below(declared.length())]
      } else {
        // 小概率引用一个未定义键。
        undef_pool[rng.next_below(undef_pool.length())]
      }
      // 注：经 `Char::from_int` 在**运行期**构造 `$` / `{` / `}`，避免源码中出现
      // 被常量折叠成字面 `${` 的片段（JS 后端会把悬空的 `${` 当作模板字符串插值
      // 起始，导致生成代码语法错误）；运行期仍得到 `${name}`。
      let dollar = Char::from_int(0x24).to_string() // '$'
      let lbrace = Char::from_int(0x7B).to_string() // '{'
      let rbrace = Char::from_int(0x7D).to_string() // '}'
      v = v + dollar + lbrace + name + rbrace
    }
    i = i + 1
  }
  v
}

///|
/// 某名字是否已在 `declared` 中（线性查找，避免依赖标准库子串/集合）。
fn declared_has(declared : Array[String], name : String) -> Bool {
  for n in declared {
    if n == name {
      return true
    }
  }
  false
}

///|
/// 生成一个样本：（DSL 文档, 文档中某已定义键 k）。
///
/// 逐行构造 `key = value`，随机穿插空行 / 注释行；维护已声明键集 `declared`，
/// 最终从中随机选取一个键作为待验证的「已定义键」k（必非空，因首条赋值行必声明
/// 一个键）。
fn gen_dsl_doc(rng : @infra_pbt.Rng) -> (TextDocument, String) {
  let n_lines = rng.next_range(2, 7) // 2..6 行
  let declared : Array[String] = []
  let mut text = ""
  let mut emitted = 0
  let mut li = 0
  while li < n_lines {
    // 约 1/5 概率产出空行或注释行（仅当已至少有一条赋值行时才穿插，确保首行是
    // 赋值行，从而 declared 非空）。
    let r = rng.next_below(5)
    if emitted > 0 && r == 0 {
      // 空行。
      text = text + "\n"
      li = li + 1
      continue
    }
    if emitted > 0 && r == 1 {
      // 注释行。
      text = text + "# comment line\n"
      li = li + 1
      continue
    }
    // 赋值行：随机键 + 随机值。
    let key = dsl_key_pool[rng.next_below(dsl_key_pool.length())]
    let value = gen_dsl_value(rng, declared)
    text = text + key + " = " + value + "\n"
    if not(declared_has(declared, key)) {
      declared.push(key)
    }
    emitted = emitted + 1
    li = li + 1
  }
  // 从已声明键集中随机选一个作为待验证的已定义键 k。
  let k = declared[rng.next_below(declared.length())]
  ({ uri: "file:///prop8.dsl", text }, k)
}

///|
/// 样本生成器（封装为 @infra_pbt.Gen）。
fn gen_dsl_samples() -> @infra_pbt.Gen[(TextDocument, String)] {
  @infra_pbt.Gen::new(fn(rng) { gen_dsl_doc(rng) })
}

// ---------------------------------------------------------------------------
// 属性谓词（Property 8）
// ---------------------------------------------------------------------------

///|
/// 对样本 (doc, k) 判定「引用—定义自洽」是否成立。
///
///   1. 定义位置 ∈ refs；
///   2. refs 每个 Location 的 uri == a.uri 且 range 落在 k 的某次出现上
///      （定义范围 或 a.references 中 name == k 的某引用范围）。
///
/// 期望出现范围集合（定义 + 全部同名引用范围）由 `a.symbols` / `a.references`
/// **独立**计算，再与 `references(a, k)` 的输出比对，使断言非平凡。
fn prop8_reference_definition_consistent(
  doc : TextDocument,
  k : String,
) -> Bool {
  let a = analyze(doc)
  let refs = references(a, k)
  // 独立求出 k 的定义范围（生成器保证 k 已定义，故必存在）。
  let mut def_range : Range? = None
  for s in a.symbols {
    if s.name == k {
      def_range = Some(s.range)
    }
  }
  match def_range {
    // k 必为已定义键；若分析后无此符号则属性失败（暴露生成器/实现不一致）。
    None => false
    Some(dr) => {
      let def_loc : Location = { uri: a.uri, range: dr }
      // 断言 1：定义位置 ∈ refs。
      let mut has_def = false
      for loc in refs {
        if loc == def_loc {
          has_def = true
        }
      }
      if not(has_def) {
        return false
      }
      // 断言 2：refs 每个位置都落在 k 的某次出现上。
      for loc in refs {
        if loc.uri != a.uri {
          return false
        }
        let mut on_occurrence = loc.range == dr
        for r in a.references {
          if r.name == k && r.range == loc.range {
            on_occurrence = true
          }
        }
        if not(on_occurrence) {
          return false
        }
      }
      true
    }
  }
}

// ---------------------------------------------------------------------------
// 属性测试（Property 8）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 8: 引用—定义自洽
///
/// 对任意由生成器产出的（DSL 文档, 其中某已定义键 k）：
///   * 键 k 的定义位置 Location 必出现在 `references(a, k)` 中；
///   * `references(a, k)` 中每个 Location 都落在 k 的某次出现（定义或引用）上。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次（≥100 基线）。
///
/// **Validates: Requirements 5.1, 5.3, 5.8, 5.9**
test "Feature: lsp, Property 8: references are consistent with the definition of a defined key" {
  let ok = @infra_pbt.holds_for_all(gen_dsl_samples(), fn(sample) {
    let (doc, k) = sample
    prop8_reference_definition_consistent(doc, k)
  })
  assert_true(ok)
}
