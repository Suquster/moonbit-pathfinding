// Feature: championship-v1-upgrade, Property 30: 复杂度表内容由元数据决定
//
// 本文件实现 Property 30（设计文档 §「Property 30: 复杂度表内容由元数据决定」/
// Requirements 19.3）的属性测试：
//   * complexity_table 的输出内容完全由输入元数据决定——表格每条数据行的字段
//     值与对应 AlgoMeta 的五个字段值一致；
//   * 元数据变更 → 表格内容随之变更（不同元数据数组产生不同表格）。
//
// 复用共享 PBT 包 @infra_pbt 的 Gen / Rng / holds_for_all 模板，每条属性迭代
// 次数 ≥100（显式传入 iters=100，满足 Requirement 11.3 基线）。
//
// 设计要点：随机生成的字段均为「非空随机字符串」，字符取自 0-9 / A-Z / a-z
// 安全字母表（绝不含 Markdown 分隔符 '|' 或换行 '\n'），从而保证字段值不会
// 与表格的结构性分隔符混淆，使「字段值落入对应行」的判定稳健可靠。

///|
/// 生成单个安全字符：取自 0-9（48..57）/ A-Z（65..90）/ a-z（97..122）。
///
/// 该字母表共 62 个字符，刻意排除 '|' 与 '\n'，避免与 Markdown 表格的结构性
/// 分隔符混淆。
fn pc_random_char(rng : @infra_pbt.Rng) -> Char {
  let k = rng.next_below(62)
  if k < 10 {
    Int::unsafe_to_char(48 + k) // '0'..'9'
  } else if k < 36 {
    Int::unsafe_to_char(65 + (k - 10)) // 'A'..'Z'
  } else {
    Int::unsafe_to_char(97 + (k - 36)) // 'a'..'z'
  }
}

///|
/// 生成一个非空随机字段字符串（长度 1..8），全程经 TextBuilder 追加字符，
/// 不在循环内做字符串 '+' 拼接。
fn pc_random_field(rng : @infra_pbt.Rng) -> String {
  let len = rng.next_range(1, 9) // [1, 9) → 长度 1..8
  let tb = @infra_text.TextBuilder::new()
  for i = 0; i < len; i = i + 1 {
    tb.push_char(pc_random_char(rng))
  }
  tb.build()
}

///|
/// 生成一条随机元数据：五个必填字段均为非空随机字符串。
fn pc_random_meta(rng : @infra_pbt.Rng) -> AlgoMeta {
  {
    name: pc_random_field(rng),
    worst_time: pc_random_field(rng),
    avg_time: pc_random_field(rng),
    space: pc_random_field(rng),
    applicability: pc_random_field(rng),
  }
}

///|
/// 生成一个随机元数据数组（含 1..6 条），用于驱动 complexity_table。
fn pc_random_metas(rng : @infra_pbt.Rng) -> Array[AlgoMeta] {
  let n = rng.next_range(1, 7) // [1, 7) → 1..6 条
  let arr : Array[AlgoMeta] = []
  for i = 0; i < n; i = i + 1 {
    arr.push(pc_random_meta(rng))
  }
  arr
}

///|
/// 将表格文本按换行 '\n' 切分为「行」数组（丢弃尾随空段）。
///
/// complexity_table 的每一行都以 " |\n" 收尾，故最后一个换行后无残留内容，
/// 返回的行数恰为 2 行表头 + N 行数据。
fn pc_lines(s : String) -> Array[String] {
  let lines : Array[String] = []
  let tb = @infra_text.TextBuilder::new()
  for c in s {
    if c == '\n' {
      lines.push(tb.build())
      tb.reset()
    } else {
      tb.push_char(c)
    }
  }
  // 若末尾无尾随换行而仍有残留，也作为一行补入（稳健兜底）。
  if !tb.is_empty() {
    lines.push(tb.build())
  }
  lines
}

///|
/// 按 complexity_table 的行格式重建一条数据行的「期望文本」：
///   "| c1 | c2 | c3 | c4 | c5 |"
///
/// 用于以「精确相等」的方式见证：表格某行的内容完全由对应元数据决定。
fn pc_expected_row(m : AlgoMeta) -> String {
  let tb = @infra_text.TextBuilder::new()
  tb.push_str("| ")
  tb.push_str(m.name)
  tb.push_str(" | ")
  tb.push_str(m.worst_time)
  tb.push_str(" | ")
  tb.push_str(m.avg_time)
  tb.push_str(" | ")
  tb.push_str(m.space)
  tb.push_str(" | ")
  tb.push_str(m.applicability)
  tb.push_str(" |")
  tb.build()
}

///|
/// 校验「表格内容完全由元数据决定」：对一个元数据数组，complexity_table 必为
/// Ok，行数 = metas.length() + 2，且去掉两行表头后第 i 行：
///   * 与按 metas[i] 重建的期望行精确相等；
///   * 同时包含 metas[i] 的全部 5 个字段值（子串见证）。
fn pc_content_determined(metas : Array[AlgoMeta]) -> Bool {
  match complexity_table(metas) {
    Err(_) => false
    Ok(table) => {
      let lines = pc_lines(table)
      // 行数 = 数据条数 + 2 行表头。
      if lines.length() != metas.length() + 2 {
        return false
      }
      for i = 0; i < metas.length(); i = i + 1 {
        let row = lines[i + 2] // 跳过 2 行表头
        let m = metas[i]
        // (a) 精确相等：整行内容完全由该条元数据重建得到。
        if row != pc_expected_row(m) {
          return false
        }
        // (b) 子串见证：5 个字段值均出现在该行。
        if !row.contains(m.name) ||
          !row.contains(m.worst_time) ||
          !row.contains(m.avg_time) ||
          !row.contains(m.space) ||
          !row.contains(m.applicability) {
          return false
        }
      }
      true
    }
  }
}

///|
/// Feature: championship-v1-upgrade, Property 30（确定性示例）：内容由元数据决定
///
/// 以一个固定的 2 条元数据数组见证：表格恰 4 行（2 表头 + 2 数据），每条数据
/// 行与对应元数据重建的期望行精确相等。
///
/// **Validates: Requirements 19.3**
test "Feature: championship-v1-upgrade, Property 30: table content is determined by metadata (deterministic)" {
  let metas : Array[AlgoMeta] = [
    {
      name: "Foo",
      worst_time: "O(1)",
      avg_time: "O(1)",
      space: "O(1)",
      applicability: "示例甲",
    },
    {
      name: "Bar",
      worst_time: "O(n)",
      avg_time: "O(n)",
      space: "O(n)",
      applicability: "示例乙",
    },
  ]
  match complexity_table(metas) {
    Ok(table) => {
      let lines = pc_lines(table)
      @test.assert_eq(lines.length(), 4) // 2 表头 + 2 数据
      @test.assert_eq(lines[2], pc_expected_row(metas[0]))
      @test.assert_eq(lines[3], pc_expected_row(metas[1]))
    }
    Err(_) => abort("complexity_table 对合法元数据不应失败")
  }
  assert_true(pc_content_determined(metas))
}

///|
/// Feature: championship-v1-upgrade, Property 30（属性·内容由元数据决定，≥100 迭代）
///
/// 对任意随机生成的非空字段元数据数组：complexity_table 必为 Ok，行数 =
/// 条数 + 2，且去掉表头后第 i 行内容完全由 metas[i] 决定（精确相等 + 字段
/// 子串见证）。复用 @infra_pbt 的 holds_for_all 模板，显式迭代 100 次。
///
/// **Validates: Requirements 19.3**
test "Feature: championship-v1-upgrade, Property 30: each row content is determined by its metadata (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { pc_random_metas(rng) })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(metas) { pc_content_determined(metas) },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 30（属性·元数据变更则表格变更，≥100 迭代）
///
/// 对任意随机元数据数组，任取一条的 name 字段追加一个安全字符得到新数组：
/// 由于该字段值出现在对应数据行，两个不同元数据数组必产生不同表格文本。
/// 复用 @infra_pbt 的 holds_for_all 模板，显式迭代 100 次。
///
/// **Validates: Requirements 19.3**
test "Feature: championship-v1-upgrade, Property 30: changing metadata changes the table (holds_for_all template)" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    let metas = pc_random_metas(rng)
    let idx = rng.next_below(metas.length())
    (metas, idx)
  })
  let ok = @infra_pbt.holds_for_all(
    gen,
    fn(pair) {
      let (metas, idx) = pair
      // 构造内容变更后的元数据数组：仅改动第 idx 条的 name（追加 'Z'）。
      let mutated : Array[AlgoMeta] = []
      for i = 0; i < metas.length(); i = i + 1 {
        let m = metas[i]
        if i == idx {
          let nb = @infra_text.TextBuilder::new()
          nb.push_str(m.name)
          nb.push_char('Z')
          mutated.push({ ..m, name: nb.build() })
        } else {
          mutated.push(m)
        }
      }
      // 两份元数据本身不同 → 两张表格文本必不相同。
      match (complexity_table(metas), complexity_table(mutated)) {
        (Ok(t1), Ok(t2)) => t1 != t2
        _ => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
