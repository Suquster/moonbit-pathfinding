// text_proof_test.mbt —— 文本引擎家族证明谓词的真实实现接地测试。
//
// 以 @infra_text 的真实包实现驱动 text_proof.mbt 中的谓词（跨包驱动只
// 发生在测试期）：
//   * myers_diff：diff_source 还原 a、diff_apply 还原 b、
//     diff_edit_cost 与 LCS 闭式最优（随机字符串对 PBT）；
//   * grapheme_clusters：簇拼接无损还原原串 + 簇计数一致；
//   * eq_fold：等价关系三律（自反/对称/传递，随机三元组 PBT）；
//   * PieceTable / Rope：随机编辑脚本与朴素 String 模型逐步一致。

///|
/// 随机短字符串生成器（字母表 {a, b, A, B}，长度 ∈ [0, 10]，覆盖大小写
/// 折叠等价类与高碰撞差分路径）。
fn tx_string_gen() -> @infra_pbt.Gen[String] {
  @infra_pbt.Gen::new(fn(rng) {
    let alphabet = ["a", "b", "A", "B"]
    let n = rng.next_range(0, 10)
    let mut s = ""
    for _i in 0..<n {
      s = s + alphabet[rng.next_range(0, 3)]
    }
    s
  })
}

///|
fn tx_pair_gen() -> @infra_pbt.Gen[(String, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let g = tx_string_gen()
    (g.generate(rng), g.generate(rng))
  })
}

///|
test "myers diff reconstructs both sides and is LCS-optimal" {
  let ok = @infra_pbt.holds_for_all(
    tx_pair_gen(),
    fn(pair : (String, String)) -> Bool {
      let (a, b) = pair
      let ops = @infra_text.myers_diff(a, b)
      @infra_text.diff_source(ops) == a &&
      @infra_text.diff_apply(ops) == b &&
      // lcs_dp_cost 返回的即为参照最小编辑距离 N+M−2·LCS，据此还原 LCS。
      diff_optimal_cost(
        @infra_text.diff_edit_cost(ops),
        a.length(),
        b.length(),
        (a.length() + b.length() - @infra_text.lcs_dp_cost(a, b)) / 2,
      )
    },
    iters=200,
  )
  assert_true(ok)
}

///|
test "diff_optimal_cost rejects a suboptimal cost" {
  assert_false(diff_optimal_cost(3, 2, 2, 1))
}

///|
test "grapheme clusters reassemble losslessly with consistent count" {
  for s in ["", "abc", "汉字与 ascii", "e\u{301}xam", "👍🏽ok"] {
    let parts = @infra_text.grapheme_clusters(s)
    assert_true(partition_reassembles(parts, s))
    assert_true(parts.length() == @infra_text.grapheme_count(s))
  }
}

///|
test "partition_reassembles rejects a lossy split" {
  assert_false(partition_reassembles(["ab"], "abc"))
}

///|
test "eq_fold satisfies equivalence laws over random triples" {
  let ok = @infra_pbt.holds_for_all(
    @infra_pbt.Gen::new(fn(rng) {
      let g = tx_string_gen()
      (g.generate(rng), g.generate(rng), g.generate(rng))
    }),
    fn(t : (String, String, String)) -> Bool {
      equivalence_laws(t.0, t.1, t.2, @infra_text.eq_fold)
    },
    iters=200,
  )
  assert_true(ok)
}

///|
test "equivalence_laws rejects a non-symmetric relation" {
  assert_false(equivalence_laws("a", "b", "c", fn(x, y) { x <= y }))
}

// --- PieceTable / Rope：模型等价 ---

///|
/// 随机编辑脚本：(位置比例 ∈ [0, 100], 是否插入, 载荷编号)。
fn tx_script_gen() -> @infra_pbt.Gen[Array[(Int, Bool, Int)]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(1, 24)
    let out : Array[(Int, Bool, Int)] = []
    for _i in 0..<n {
      out.push(
        (rng.next_range(0, 100), rng.next_range(0, 1) > 0, rng.next_range(0, 2)),
      )
    }
    out
  })
}

///|
fn tx_payload(k : Int) -> String {
  ["x", "yz", "文"][k]
}

///|
fn tx_model_insert(model : String, at : Int, payload : String) -> String {
  let mut left = ""
  let mut right = ""
  let mut i = 0
  for c in model.iter() {
    if i < at {
      left = left + c.to_string()
    } else {
      right = right + c.to_string()
    }
    i += 1
  }
  left + payload + right
}

///|
fn tx_model_delete(model : String, at : Int, count : Int) -> String {
  let mut acc = ""
  let mut i = 0
  for c in model.iter() {
    if i < at || i >= at + count {
      acc = acc + c.to_string()
    }
    i += 1
  }
  acc
}

///|
fn tx_prop_piece_table_model(script : Array[(Int, Bool, Int)]) -> Bool {
  let pt = @infra_text.PieceTable::from_string("seed")
  let rope = @infra_text.Rope::from_string("seed")
  let mut model = "seed"
  for step in script {
    let (posp, is_insert, k) = step
    let at = if model.length() == 0 { 0 } else { posp * model.length() / 100 }
    if is_insert {
      let payload = tx_payload(k)
      pt.insert(at, payload)
      rope.insert(at, payload)
      model = tx_model_insert(model, at, payload)
    } else if model.length() > at {
      pt.delete(at, 1)
      rope.delete(at, at + 1)
      model = tx_model_delete(model, at, 1)
    }
    if pt.to_string() != model || rope.to_string() != model {
      return false
    }
    if pt.len() != model.length() || rope.len() != model.length() {
      return false
    }
  }
  true
}

///|
test "PieceTable and Rope agree with the naive string model step by step" {
  let ok = @infra_pbt.holds_for_all(
    tx_script_gen(),
    tx_prop_piece_table_model,
    iters=128,
  )
  assert_true(ok)
}
