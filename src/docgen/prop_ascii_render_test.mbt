// Feature: championship-v1-upgrade, Property 32: ASCII 渲染字符集与图例约束
//
// 本文件实现 Property 32（design.md §「Property 32: ASCII 渲染字符集与图例
// 约束」/ Requirements 20.2, 20.3）的属性测试：
//   * render_ascii() 输出的「网格区域」（图例之前的部分）仅使用 5 个互异单
//     字符 S / G / # / * / .（外加换行 \n）；
//   * 输出附带图例段（以「图例：」开头）；
//   * 当 path 为空（无可行路径）时，整段输出不含 '*'，且图例标注「无可行路径」；
//   * 当 path 非空时，图例含「*=路径」。
//
// 复用共享 PBT 包 @infra_pbt 的 Gen / Rng / holds_for_all 模板，迭代次数 ≥100。

///|
/// 将字符串展开为字符数组（便于做精确的逐字符 / 子串检查）。
fn ar_to_chars(s : String) -> Array[Char] {
  let chars : Array[Char] = []
  for c in s {
    chars.push(c)
  }
  chars
}

///|
/// 在字符数组 hay 中查找子串 needle 的首个出现位置；找不到返回 -1。
///
/// 朴素 O(|hay|·|needle|) 匹配；本测试中字符串规模有限（≤20×20 网格 + 图例），
/// 性能充裕，且仅用于测试断言、不进入运行时产物。
fn ar_index_of(hay : Array[Char], needle : Array[Char]) -> Int {
  let hn = hay.length()
  let nn = needle.length()
  if nn == 0 {
    return 0
  }
  for i = 0; i + nn <= hn; i = i + 1 {
    let mut matched = true
    for j = 0; j < nn; j = j + 1 {
      if hay[i + j] != needle[j] {
        matched = false
        break
      }
    }
    if matched {
      return i
    }
  }
  -1
}

///|
/// 判断字符串 s 是否包含子串 sub。
fn ar_contains(s : String, sub : String) -> Bool {
  ar_index_of(ar_to_chars(s), ar_to_chars(sub)) >= 0
}

///|
/// 判断字符 c 是否属于网格区域允许的字符集合 {S, G, #, *, ., \n}。
fn ar_is_grid_char(c : Char) -> Bool {
  c == 'S' || c == 'G' || c == '#' || c == '*' || c == '.' || c == '\n'
}

///|
/// 随机生成一个 AsciiGrid：
///   * rows / cols ∈ [3, 19]（落在 3..20 示意规模区间内）；
///   * blocked 为长度 rows*cols 的随机障碍位图；
///   * start / goal 为 [0, rows*cols) 内的随机合法线性索引；
///   * path 以约 1/3 概率为空（无可行路径），否则为 [0, rows*cols) 内随机长度、
///     随机内容的索引序列（索引始终落在合法范围内）。
fn ar_gen_grid() -> @infra_pbt.Gen[AsciiGrid] {
  @infra_pbt.Gen::new(fn(rng) {
    let rows = rng.next_range(3, 19)
    let cols = rng.next_range(3, 19)
    let cell_count = rows * cols
    // 随机障碍位图。
    let blocked : Array[Bool] = []
    for i = 0; i < cell_count; i = i + 1 {
      blocked.push(rng.next_bool())
    }
    // 合法的起点 / 终点（允许相等，渲染时起点优先）。
    let start = rng.next_below(cell_count)
    let goal = rng.next_below(cell_count)
    // 约 1/3 概率生成空 path（无可行路径），否则随机长度的合法索引序列。
    let path : Array[Int] = []
    if rng.next_below(3) != 0 {
      let path_len = rng.next_below(cell_count + 1)
      for k = 0; k < path_len; k = k + 1 {
        path.push(rng.next_below(cell_count))
      }
    }
    AsciiGrid::{ rows, cols, blocked, start, goal, path }
  })
}

///|
/// 校验单个 AsciiGrid 渲染输出满足 Property 32 的全部约束。
fn ar_render_invariants_hold(grid : AsciiGrid) -> Bool {
  let out = render_ascii(grid)
  let chars = ar_to_chars(out)
  // (a) 必须附带图例段，且以「图例：」开头标识。
  let legend_at = ar_index_of(chars, ar_to_chars("图例："))
  if legend_at < 0 {
    return false
  }
  // (b) 网格区域（图例之前的部分）每个字符 ∈ {S, G, #, *, ., \n}。
  for i = 0; i < legend_at; i = i + 1 {
    if !ar_is_grid_char(chars[i]) {
      return false
    }
  }
  let has_path = grid.path.length() > 0
  if has_path {
    // (c) path 非空：图例含「*=路径」。
    ar_contains(out, "*=路径")
  } else {
    // (d) path 为空：整段输出不含 '*'，且图例含「无可行路径」。
    let no_star = ar_index_of(chars, ['*']) < 0
    no_star && ar_contains(out, "无可行路径")
  }
}

///|
/// Feature: championship-v1-upgrade, Property 32（属性·随机网格满足字符集与图例约束，≥100 迭代）
///
/// 对随机生成的 AsciiGrid（rows/cols∈[3,19]、随机障碍位图、随机合法起终点、
/// 随机 path 子集或空 path），校验：
///   * 网格区域仅使用 5 个互异单字符 S/G/#/*/. 外加换行；
///   * 输出附带以「图例：」开头的图例段；
///   * path 为空时整段输出不含 '*' 且图例标注「无可行路径」；
///   * path 非空时图例含「*=路径」。
/// 复用 @infra_pbt 的 holds_for_all 模板，显式迭代 100 次。
///
/// **Validates: Requirements 20.2, 20.3**
test "Feature: championship-v1-upgrade, Property 32: ascii render charset and legend constraints (holds_for_all template)" {
  let ok = @infra_pbt.holds_for_all(
    ar_gen_grid(),
    fn(grid) { ar_render_invariants_hold(grid) },
    iters=100,
  )
  assert_true(ok)
}

///|
/// Feature: championship-v1-upgrade, Property 32（确定性校验·有路径 / 无路径两个代表样例）
///
/// 以两个确定样例锚定关键行为，避免纯随机遗漏边界：
///   * 3×3、存在路径：网格区域字符合法、图例含「*=路径」、整段含「图例：」；
///   * 3×3、空 path：整段不含 '*'、图例含「无可行路径」。
///
/// **Validates: Requirements 20.2, 20.3**
test "Feature: championship-v1-upgrade, Property 32: ascii render charset and legend constraints (deterministic)" {
  // 样例一：3×3，存在可行路径。
  let with_path = AsciiGrid::{
    rows: 3,
    cols: 3,
    blocked: [false, false, true, false, false, false, true, false, false],
    start: 0,
    goal: 8,
    path: [0, 3, 4, 5, 8],
  }
  assert_true(ar_render_invariants_hold(with_path))
  let out1 = render_ascii(with_path)
  assert_true(ar_contains(out1, "图例："))
  assert_true(ar_contains(out1, "*=路径"))
  // 样例二：3×3，空 path（无可行路径）。
  let no_path = AsciiGrid::{
    rows: 3,
    cols: 3,
    blocked: [false, false, true, false, false, false, true, false, false],
    start: 0,
    goal: 8,
    path: [],
  }
  assert_true(ar_render_invariants_hold(no_path))
  let out2 = render_ascii(no_path)
  assert_true(ar_contains(out2, "无可行路径"))
  assert_true(!ar_contains(out2, "*"))
}
