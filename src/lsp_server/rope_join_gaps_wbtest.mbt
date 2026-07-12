// 白盒测试：覆盖率审计收口（INFRA 第七十四批）——
// rope_join 高度差组合矩阵：穷举左右子树规模拼接并校验内容序与
// 元数据一致，覆盖 join 回溯中的单/双旋修复路径。

///|
fn rjg_build(n : Int, base : Int) -> Rope {
  let cps : Array[Int] = []
  for i in 0..<n {
    cps.push(97 + (base + i) % 26)
  }
  rope_build(cps, 0, n)
}

///|
fn rjg_content(t : Rope) -> Array[Int] {
  let out : Array[Int] = []
  t.collect_range(0, t.cp_len(), out)
  out
}

///|
test "rope_join：规模矩阵拼接内容与元数据一致" {
  let sizes = [1, 2, 3, 5, 8, 13, 33, 100, 257, 1000]
  for a in sizes {
    for b in sizes {
      let l = rjg_build(a, 0)
      let r = rjg_build(b, a)
      let j = rope_join(l, r)
      assert_eq(j.cp_len(), a + b)
      let expect : Array[Int] = []
      for x in rjg_content(l) {
        expect.push(x)
      }
      for x in rjg_content(r) {
        expect.push(x)
      }
      assert_true(rjg_content(j) == expect)
    }
  }
}

///|
test "rope_join：深度倾斜链上逐次拼接保持平衡高度" {
  let mut t = rjg_build(1, 0)
  for i in 1..<400 {
    t = rope_join(t, rjg_build(1, i))
  }
  assert_eq(t.cp_len(), 400)
  // 平衡 join 下高度应为 O(log N)（400 码位 ≪ 2^30）。
  assert_true(t.height() <= 30)
  let mut u = rjg_build(1, 0)
  for i in 1..<400 {
    u = rope_join(rjg_build(1, i), u)
  }
  assert_eq(u.cp_len(), 400)
  assert_true(u.height() <= 30)
}
