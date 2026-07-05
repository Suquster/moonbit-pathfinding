// prop_adversarial_test.mbt —— 对抗性鲁棒性回归（T2.4）。
//
// Feature: regex-engine, Property: no exponential blowup on pathological regexes
//
// 回溯式引擎在病态正则（嵌套量词、歧义选择、灾难性回溯诱饵）上呈指数爆炸；
// Pike VM 的「每 pc 至多一条线程」去重把每个输入位置的工作量压到 O(程序规模)，
// 总步数满足**硬上界** `steps ≤ ninst × (n + 1)`（R2.2）。本文件以
// `Program::exec_steps` 的确定性步数对经典灾难性模式逐一断言该线性上界，并以
// 倍增输入验证增速为线性（步数比 ≤ 输入比 + 松弛），证明无指数行为。
//
// **Validates: Requirements 2.2, 7.4**

///|
/// 经典灾难性回溯诱饵（对回溯引擎为指数级；对 Pike VM 必须线性）。
let adversarial_patterns : Array[String] = [
  // 嵌套星闭包。
  "(a*)*b",
  // 嵌套加号（正则界最著名的 ReDoS 形态 (a+)+）。
   "(a+)+b",
  // 歧义选择 × 量词。
   "(a|a)*b", "(a|aa)+b",
  // 深嵌套分组。
   "((((a*)*)*)*)b",
  // 量词展开放大程序规模。
   "(a{2,8}){2,8}b",
  // 巨型字符类 × 量词。
   "[a-zA-Z0-9_]([a-zA-Z0-9_]*)*b",
]

///|
/// 构造长度 `n` 的诱饵输入：全 'a' 且**不含**收尾 'b'（迫使引擎穷尽所有
/// 歧义分解——回溯引擎的最坏情形）。
fn adv_input(n : Int) -> String {
  let tb = @infra_text.TextBuilder::new()
  for _i in 0..<n {
    tb.push_char('a')
  }
  tb.build()
}

///|
/// 硬上界：任意病态模式在诱饵输入上的线程步数 ≤ ninst × (n + 1)。
test "Feature: regex-engine, Property: pikevm steps bounded by ninst x (n+1) on ReDoS baits" {
  for p in adversarial_patterns {
    let pat = match Pattern::compile(p) {
      Ok(x) => x
      Err(_) => abort("unexpected parse error: " + p)
    }
    let ninst = pat.prog.insts.length()
    for n in [16, 64, 256] {
      let steps = pat.prog.exec_steps(adv_input(n))
      assert_true(steps <= ninst * (n + 1))
    }
  }
}

///|
/// 线性增速见证：输入倍增 4× 时步数增速 ≤ 5×（线性 + 松弛；指数行为在
/// n=64→256 时步数比将 >> 10⁹，与之天壤之别）。
test "adversarial step growth is linear under input doubling" {
  for p in adversarial_patterns {
    let pat = match Pattern::compile(p) {
      Ok(x) => x
      Err(_) => abort("unexpected parse error: " + p)
    }
    let s1 = pat.prog.exec_steps(adv_input(64))
    let s2 = pat.prog.exec_steps(adv_input(256))
    assert_true(s1 > 0)
    assert_true(s2 <= s1 * 5)
  }
}

///|
/// 语义健全性：诱饵（无 'b' 收尾）不匹配；补上 'b' 后全部命中。步数守护
/// 之外确认引擎在这些模式上行为正确。
test "adversarial patterns match correctly when bait is completed" {
  for p in adversarial_patterns {
    let pat = match Pattern::compile(p) {
      Ok(x) => x
      Err(_) => abort("unexpected parse error: " + p)
    }
    assert_true(!pat.is_match(adv_input(64)))
    assert_true(pat.is_match(adv_input(64) + "b"))
  }
}
