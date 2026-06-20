// text_builder_prop_test.mbt —— `TextBuilder` 的属性测试（任务 1.2）。
//
// 覆盖 design.md §「正确性属性 · Property 1: R1 文本构建等价与线性」：
//
//   Property 1: `TextBuilder.build()` 与等价顺序 `+` 拼接逐字符相等；
//               `build` 后再追加仍按序包含全部片段。
//   **Validates: Requirements 1.2, 1.3, 1.4**
//
// 本文件以全称量化（property）形式校验三条子性质，全部复用共享 PBT 包
// @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（每条属性显式 `iters`
// ≥ 100，满足质量门禁 ≥100 迭代基线），并在 wasm-gc / js / native 三后端运行：
//
//   1. 等价性：随机「字符 / 字符串片段混合追加序列」，`build()` 与等价顺序
//      拼接的参照值逐字符相等。
//   2. 再追加保持（AC4）：随机序列，在中途 `build` 一次后继续追加，最终
//      `build()` 含全部历史片段且顺序正确，并等于一次性追加（无中途 build）
//      的结果。
//   3. len 一致：`len()` 在每一步均等于累计字符数，且最终等于 `build().length()`。
//
// 实现约束（遵循 quality-enforcement / anti-patterns 约定）：
//   * 参照值（「等价顺序拼接」）一律以 `Array[String]` + `join("")` 物化，
//     绝不在循环内使用 `out = out + ...`，避免引入 O(n²) 反模式；
//   * 生成的字符均取自「单个 UTF-16 码元」的字母表（BMP 且非代理对），
//     从而 `push_char` 计 1 与该字符在物化串中占 1 个码元一致，保证
//     `len()`（`total_len`）与 `build().length()`（UTF-16 码元数）严格相等。

///|
/// 追加操作的类型化表示：要么追加单个字符，要么追加一个字符串片段。
///
/// 用类型化枚举（而非用字符串模拟操作种类）区分 `push_char` 与 `push_str`，
/// 以便属性测试同时覆盖两类追加路径及其交错。
enum TbOp {
  OChar(Char)
  OStr(String)
}

///|
/// 字母表：全部为「单个 UTF-16 码元」的字符（BMP、非代理对）。
///
/// 含 ASCII 字母 / 数字 / 空白 / 标点，以及若干非 ASCII BMP 字符（拉丁补充、
/// 希腊、货币符号、CJK），用于增强输入多样性。刻意排除需代理对表示的字符
/// （如 emoji），以保证 `push_char`（计 1）与物化串 UTF-16 长度（占 1）一致。
let tb_alphabet : Array[Char] = [
  'a', 'b', 'c', 'z', 'A', 'Z', '0', '9', ' ', '\t', '\n', '!', '+', '/', '_', 'é',
  'Ω', '€', '中', '文', '字',
]

///|
/// 生成一个随机字符串片段：长度 `0..=5`，逐字符取自 `tb_alphabet`。
///
/// 以 `Array[String]` 收集单字符串片段后 `join("")` 物化，避免循环内 `+`。
fn tb_gen_str(rng : @infra_pbt.Rng) -> String {
  let n = rng.next_range(0, 5)
  let parts : Array[String] = []
  let mut i = 0
  while i < n {
    parts.push(tb_alphabet[rng.next_below(tb_alphabet.length())].to_string())
    i = i + 1
  }
  parts.join("")
}

///|
/// 生成一个随机的追加操作序列：长度 `0..=max_len`，每个操作等概率为
/// `push_char` 或 `push_str`，从而覆盖两类追加路径的任意交错。
fn tb_gen_ops_with(rng : @infra_pbt.Rng, max_len : Int) -> Array[TbOp] {
  let n = rng.next_range(0, max_len)
  let ops : Array[TbOp] = []
  let mut i = 0
  while i < n {
    if rng.next_bool() {
      ops.push(OChar(tb_alphabet[rng.next_below(tb_alphabet.length())]))
    } else {
      ops.push(OStr(tb_gen_str(rng)))
    }
    i = i + 1
  }
  ops
}

///|
/// 操作序列生成器（单段，最长 20 个操作）。
fn tb_gen_ops() -> @infra_pbt.Gen[Array[TbOp]] {
  @infra_pbt.Gen::new(fn(rng) { tb_gen_ops_with(rng, 20) })
}

///|
/// 操作序列对生成器（前缀段 + 后缀段，各最长 12 个操作），用于 AC4 再追加性质。
fn tb_gen_two_ops() -> @infra_pbt.Gen[(Array[TbOp], Array[TbOp])] {
  @infra_pbt.Gen::new(fn(rng) {
    (tb_gen_ops_with(rng, 12), tb_gen_ops_with(rng, 12))
  })
}

///|
/// 将操作序列依序施加到给定 `TextBuilder` 上。
fn tb_apply(tb : TextBuilder, ops : Array[TbOp]) -> Unit {
  for op in ops {
    match op {
      OChar(c) => tb.push_char(c)
      OStr(s) => tb.push_str(s)
    }
  }
}

///|
/// 参照实现：把操作序列折叠为「等价顺序拼接」的期望字符串。
///
/// 以 `Array[String]` 收集每个操作贡献的片段后一次性 `join("")`，与
/// `TextBuilder` 的增量追加相互独立，可作为等价性判定的对照。
fn tb_expected(ops : Array[TbOp]) -> String {
  let parts : Array[String] = []
  for op in ops {
    match op {
      OChar(c) => parts.push(c.to_string())
      OStr(s) => parts.push(s)
    }
  }
  parts.join("")
}

///|
/// 将字符串展开为字符数组，供逐字符比较使用。
fn tb_chars(s : String) -> Array[Char] {
  let arr : Array[Char] = []
  for c in s {
    arr.push(c)
  }
  arr
}

///|
/// 逐字符判等：长度相同且对应字符相等。
fn tb_chars_eq(a : String, b : String) -> Bool {
  let xs = tb_chars(a)
  let ys = tb_chars(b)
  if xs.length() != ys.length() {
    return false
  }
  for i in 0..<xs.length() {
    if xs[i] != ys[i] {
      return false
    }
  }
  true
}

///|
/// 判断 `whole` 是否以 `prefix` 为前缀（逐字符比较）。
fn tb_starts_with(whole : String, prefix : String) -> Bool {
  let ws = tb_chars(whole)
  let ps = tb_chars(prefix)
  if ws.length() < ps.length() {
    return false
  }
  for i in 0..<ps.length() {
    if ws[i] != ps[i] {
      return false
    }
  }
  true
}

///|
/// Feature: production-hardening, Property 1: TextBuilder.build() 与等价顺序拼接逐字符相等
///
/// 对任意「字符 / 字符串片段混合追加序列」，`TextBuilder.build()` 的结果与
/// 用参照实现得到的等价顺序拼接逐字符相等。
///
/// **Validates: Requirements 1.2, 1.3, 1.4**
test "Feature: production-hardening, Property 1: build equals sequential concatenation" {
  let ok = @infra_pbt.holds_for_all(
    tb_gen_ops(),
    fn(ops) {
      let tb = TextBuilder::new()
      tb_apply(tb, ops)
      let built = tb.build()
      let expected = tb_expected(ops)
      // 字符串相等（按码元逐位）+ 显式逐字符比较，双重确认「逐字符相等」。
      built == expected && tb_chars_eq(built, expected)
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 1 (AC4): build 后再追加保持全部历史片段且顺序正确
///
/// 对任意「前缀段 + 后缀段」操作序列：先施加前缀并 `build` 一次（记为
/// `first`），再施加后缀并再次 `build`（记为 `final_built`）。则：
///   * `final_built` 等于前缀+后缀的等价顺序拼接；
///   * `final_built` 以 `first` 为前缀（中途 `build` 未清空历史片段）；
///   * `final_built` 等于「一次性追加（无中途 build）」的结果，即中途
///     物化不改变最终结果；
///   * 长度 = `first` 长度 + 后缀片段长度。
///
/// **Validates: Requirements 1.2, 1.4**
test "Feature: production-hardening, Property 1 (AC4): rebuild after build preserves history" {
  let ok = @infra_pbt.holds_for_all(
    tb_gen_two_ops(),
    fn(pair) {
      let (prefix, suffix) = pair
      // 中途 build 一次再继续追加。
      let tb = TextBuilder::new()
      tb_apply(tb, prefix)
      let first = tb.build()
      tb_apply(tb, suffix)
      let final_built = tb.build()
      // 一次性追加（无中途 build）作为对照。
      let oneshot = TextBuilder::new()
      tb_apply(oneshot, prefix)
      tb_apply(oneshot, suffix)
      let oneshot_built = oneshot.build()
      // 前缀+后缀的等价顺序拼接期望值（合并为单一序列后参照物化）。
      let combined : Array[TbOp] = []
      for op in prefix {
        combined.push(op)
      }
      for op in suffix {
        combined.push(op)
      }
      let expected = tb_expected(combined)
      let suffix_expected = tb_expected(suffix)
      final_built == expected &&
      tb_chars_eq(final_built, oneshot_built) &&
      tb_starts_with(final_built, first) &&
      final_built.length() == first.length() + suffix_expected.length()
    },
    iters=200,
  )
  assert_true(ok)
}

///|
/// Feature: production-hardening, Property 1 (len consistency): len 始终等于字符总数与物化串长度
///
/// 对任意操作序列，`len()` 在每一步追加后均等于累计字符数（`push_char` 计 1、
/// `push_str` 计该片段长度）；最终 `len()` 等于 `build().length()`。由于字母表
/// 限定为单 UTF-16 码元字符，`total_len` 与 UTF-16 码元数严格一致。
///
/// **Validates: Requirements 1.2, 1.3**
test "Feature: production-hardening, Property 1 (len): len equals char total and built length" {
  let ok = @infra_pbt.holds_for_all(
    tb_gen_ops(),
    fn(ops) {
      let tb = TextBuilder::new()
      let mut expected_len = 0
      // 逐步追加并在每步校验 len 与累计期望长度一致。
      for op in ops {
        match op {
          OChar(c) => {
            tb.push_char(c)
            expected_len = expected_len + 1
          }
          OStr(s) => {
            tb.push_str(s)
            expected_len = expected_len + s.length()
          }
        }
        if tb.len() != expected_len {
          return false
        }
      }
      let built = tb.build()
      tb.len() == built.length() && tb.len() == expected_len
    },
    iters=150,
  )
  assert_true(ok)
}
