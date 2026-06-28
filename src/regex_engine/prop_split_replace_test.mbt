// prop_split_replace_test.mbt —— Property 8：split / replace 重建一致性（任务 9.3）。
//
// Feature: regex-engine, Property 8: split / replace 重建一致性
//
// 对任意模式与任意输入：`split` 所得子串与各分隔符匹配子串按序交错拼接逐字符
// 重建原输入；`replace_all` 以恒等引用 `$0` 还原原输入，以 `$1` / `${name}`
// 引用整体捕获时替换文本等于对应捕获组子串（重建原输入）。
//
// **Validates: Requirements 8.6, 8.7, 8.9**
//
// 复用 prop_match_kind_test.mbt 的共享生成器 `gen_pat_input`（≥100 迭代）。
// `gen_valid_pattern` 不产命名组，故包裹为 `(P)` / `(?<g>P)` 不会重名。

///|
/// 字符数组 `[a,b)` 切片为字符串。
fn sr_slice(chars : Array[Char], a : Int, b : Int) -> String {
  let mut s = ""
  let lo = if a < 0 { 0 } else { a }
  let hi = if b > chars.length() { chars.length() } else { b }
  for k in lo..<hi {
    s = s + chars[k].to_string()
  }
  s
}

///|
/// 以 `split` 子串与 `find_all` 分隔符匹配子串交错重建：应逐字符等于原输入。
fn sr_reconstruct(p : Pattern, input : String) -> String {
  let chars = input.iter().to_array()
  let pieces = p.split(input)
  let ms = p.find_all(input)
  // pieces.length() == ms.length() + 1（split 以全部不重叠匹配为分隔）。
  let mut out = pieces[0]
  let mut i = 0
  while i < ms.length() {
    let m = ms[i]
    out = out + sr_slice(chars, m.start, m.end)
    out = out + pieces[i + 1]
    i = i + 1
  }
  out
}

///|
/// Feature: regex-engine, Property 8: split / replace 重建一致性
///
/// **Validates: Requirements 8.6, 8.7, 8.9**
test "Feature: regex-engine, Property 8: split and replace reconstruct input" {
  let ok = @infra_pbt.holds_for_all(gen_pat_input(), fn(pair) {
    let (pat, input) = pair
    match Pattern::compile(pat) {
      Err(_) => false
      Ok(p) => {
        // 1. split 交错重建。
        let r1 = sr_reconstruct(p, input) == input
        // 2. replace_all 以 $0 恒等引用还原原输入。
        let r2 = p.replace_all(input, "$0") == input
        // 3. 整体包裹捕获组：$1 引用整体匹配 ⇒ 还原原输入。
        let r3 = match Pattern::compile("(" + pat + ")") {
          Ok(pg) => pg.replace_all(input, "$1") == input
          Err(_) => false
        }
        // 4. 整体包裹命名组：${g} 引用整体匹配 ⇒ 还原原输入。
        let r4 = match Pattern::compile("(?<g>" + pat + ")") {
          Ok(pn) => pn.replace_all(input, "${g}") == input
          Err(_) => false
        }
        r1 && r2 && r3 && r4
      }
    }
  })
  assert_true(ok)
}

///|
/// 代表性见证：split 切分、replace_all 引用捕获组（编号 / 命名）。
test "split and replace representative witnesses" {
  // split 以 ',' 切分。
  match Pattern::compile(",") {
    Ok(p) => {
      let parts = p.split("a,b,c")
      @test.assert_eq(parts.length(), 3)
      assert_true(parts[0] == "a")
      assert_true(parts[1] == "b")
      assert_true(parts[2] == "c")
    }
    Err(_) => fail("compile failed for ,")
  }
  // 编号引用：交换两组。
  match Pattern::compile("(a)(b)") {
    Ok(p) => assert_true(p.replace_all("ab", "$2$1") == "ba")
    Err(_) => fail("compile failed for (a)(b)")
  }
  // 命名引用：交换命名组。
  match Pattern::compile("(?<x>a)(?<y>b)") {
    Ok(p) => assert_true(p.replace_all("ab", "${y}${x}") == "ba")
    Err(_) => fail("compile failed for named groups")
  }
  // $$ 转义为字面 '$'。
  match Pattern::compile("a") {
    Ok(p) => assert_true(p.replace("a", "$$") == "$")
    Err(_) => fail("compile failed for a")
  }
}
