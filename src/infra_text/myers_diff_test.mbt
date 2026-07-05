// myers_diff_test.mbt —— Myers diff 黑盒测试：定向（空/全等/全异/交错）+
// round-trip PBT（apply==b、source==a）+ 与 O(N·M) DP 的最小性差分 PBT。

///|
test "myers directed: empty / identical / disjoint" {
  assert_eq(@infra_text.myers_diff("", "").length(), 0)
  let ins = @infra_text.myers_diff("", "abc")
  assert_true(ins == [@infra_text.DiffOp::Insert("abc")])
  let del = @infra_text.myers_diff("abc", "")
  assert_true(del == [@infra_text.DiffOp::Delete("abc")])
  let same = @infra_text.myers_diff("hello", "hello")
  assert_true(same == [@infra_text.DiffOp::Equal("hello")])
  // 全异：代价 = |a| + |b|。
  let dis = @infra_text.myers_diff("aaa", "bbb")
  assert_eq(@infra_text.diff_edit_cost(dis), 6)
  assert_eq(@infra_text.diff_apply(dis), "bbb")
  assert_eq(@infra_text.diff_source(dis), "aaa")
}

///|
test "myers directed: classic ABCABBA -> CBABAC (Myers 1986 running example)" {
  // 论文运行示例：最短编辑距离 D = 5。
  let ops = @infra_text.myers_diff("ABCABBA", "CBABAC")
  assert_eq(@infra_text.diff_edit_cost(ops), 5)
  assert_eq(@infra_text.diff_apply(ops), "CBABAC")
  assert_eq(@infra_text.diff_source(ops), "ABCABBA")
}

///|
test "myers directed: interleaved edits & CJK" {
  let a = "fn main() { println(\"你好\") }"
  let b = "fn main() { println(\"世界!\") }"
  let ops = @infra_text.myers_diff(a, b)
  assert_eq(@infra_text.diff_apply(ops), b)
  assert_eq(@infra_text.diff_source(ops), a)
  assert_eq(@infra_text.diff_edit_cost(ops), @infra_text.lcs_dp_cost(a, b))
}

///|
/// 确定性随机小串（小字母表放大公共段概率，使属性非平凡）。
fn gen_small(rng : @infra_pbt.Rng, max_len : Int) -> String {
  let sb = StringBuilder::new()
  for _ in 0..<rng.next_below(max_len + 1) {
    sb.write_char((97 + rng.next_below(4)).unsafe_to_char())
  }
  sb.to_string()
}

///|
test "myers PBT: round-trip apply==b and source==a (200 iterations)" {
  let rng = @infra_pbt.rng_new(0xD1FF_2026UL)
  for _ in 0..<200 {
    let a = gen_small(rng, 40)
    let b = gen_small(rng, 40)
    let ops = @infra_text.myers_diff(a, b)
    assert_eq(@infra_text.diff_apply(ops), b)
    assert_eq(@infra_text.diff_source(ops), a)
  }
}

///|
test "myers PBT: minimality vs O(NM) DP reference (120 iterations)" {
  let rng = @infra_pbt.rng_new(0x1986_0705UL)
  for _ in 0..<120 {
    let a = gen_small(rng, 24)
    let b = gen_small(rng, 24)
    let ops = @infra_text.myers_diff(a, b)
    assert_eq(@infra_text.diff_edit_cost(ops), @infra_text.lcs_dp_cost(a, b))
  }
}

///|
test "myers PBT: mutated-similar inputs keep D small (edit-bounded, 60 iterations)" {
  // 相似输入（b 由 a 经 k 次单码元变异得到）：D ≤ 2k——这是
  // O((N+M)·D) 相对 DP 的优势前提，用性质锁定。
  let rng = @infra_pbt.rng_new(0x5EED_D1FFUL)
  for _ in 0..<60 {
    let sb = StringBuilder::new()
    for _ in 0..<(50 + rng.next_below(150)) {
      sb.write_char((97 + rng.next_below(26)).unsafe_to_char())
    }
    let a = sb.to_string()
    let mut b = a
    let k = 1 + rng.next_below(6)
    for _ in 0..<k {
      let n = b.length()
      let p = rng.next_below(n)
      match rng.next_below(3) {
        0 =>
          // 替换。
          b = b[0:p].to_owned() + "Z" + b[p + 1:].to_owned()
        1 =>
          // 插入。
          b = b[0:p].to_owned() + "Q" + b[p:].to_owned()
        _ =>
          // 删除。
          b = b[0:p].to_owned() + b[p + 1:].to_owned()
      }
    }
    let ops = @infra_text.myers_diff(a, b)
    assert_eq(@infra_text.diff_apply(ops), b)
    assert_eq(@infra_text.diff_source(ops), a)
    assert_true(@infra_text.diff_edit_cost(ops) <= 2 * k)
  }
}
