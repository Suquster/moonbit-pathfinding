// error_model_prop_test.mbt —— L0 错误模型属性测试与桥接单元测试（tasks 4.4, 4.5）。
//
// 以全称量化形式实现 Property 16~20（失败结构完整性、label 位置敏感改写、期望
// 集合确定性顺序、最远失败 + 期望合并不变量、错误位置单调性），并补充
// `to_path_error` 桥接单元测试（R5.4）。
//
// 说明：`merge_farthest` / `normalize_expected` 为包内私有，对黑盒测试不可见，
// 故本文件以测试本地的 `dedup_preserve`（去重保序）独立复刻参照逻辑，从而对
// `alt` 的最远失败合并做差分校验。

///|
/// 测试本地参照：去重并保留首次出现顺序（与实现的 normalize_expected 同语义）。
fn dedup_preserve(xs : Array[String]) -> Array[String] {
  let out : Array[String] = []
  for x in xs {
    let mut found = false
    for y in out {
      if y == x {
        found = true
        break
      }
    }
    if !found {
      out.push(x)
    }
  }
  out
}

// ---------------------------------------------------------------------------
// Property 16：失败结构完整性
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 16: 失败结构完整性
///
/// 对任意在某输入上失败的（由生成器产生的）解析器，其结果为 `Fail(pos, expected~)`，
/// 其中 `pos` 的 `line`/`col`/`offset` 合法、`expected` 为非空集合。
///
/// **Validates: Requirements 5.1**
test "Feature: parser-combinator, Property 16: failure structure completeness" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    match p.parse_string(s) {
      Fail(pos, expected~) =>
        expected.length() > 0 &&
        pos.line >= 1 &&
        pos.col >= 1 &&
        pos.offset >= 0
      Ok(_, _) => true
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 17：label 位置敏感改写
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 17: label 位置敏感改写
///
/// 对任意输入：当解析器在其起始位置失败时，`label(p, name)` 的期望集合等于
/// `[name]`；当解析器已消费至少一个字符后失败时，`label(p, name)` 保留原始的
/// 失败位置与期望集合。
///
/// **Validates: Requirements 5.2, 5.3**
test "Feature: parser-combinator, Property 17: label position-sensitive rewrite" {
  let ok = @infra_pbt.holds_for_all(gen_input(), fn(s) {
    // 情形 A：在起始位置失败（pchar('z') 对 a/b/c 字母表恒在起点失败）。
    let pa = pchar('z')
    let cond_a = match pa.parse_string(s) {
      Fail(pos, ..) =>
        if pos.offset == 0 {
          match label(pa, "NAME").parse_string(s) {
            Fail(p2, expected=e2) => p2.offset == 0 && e2 == ["NAME"]
            Ok(_, _) => false
          }
        } else {
          true
        }
      Ok(_, _) => true
    }
    // 情形 B：消费 'a' 后再失败（seq(pchar('a'), pchar('z'))）。
    let pb = seq(pchar('a'), pchar('z'))
    let cond_b = match pb.parse_string(s) {
      Fail(pos, expected=e) =>
        if pos.offset > 0 {
          match label(pb, "NAME").parse_string(s) {
            Fail(p2, expected=e2) => p2.offset == pos.offset && e2 == e
            Ok(_, _) => false
          }
        } else {
          true
        }
      Ok(_, _) => true
    }
    cond_a && cond_b
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 18：期望集合确定性顺序
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 18: 期望集合确定性顺序
///
/// 对任意失败场景，对同一输入重复解析两次所得的期望集合序列逐元素一致。
///
/// **Validates: Requirements 5.5**
test "Feature: parser-combinator, Property 18: expected set deterministic order" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    match (p.parse_string(s), p.parse_string(s)) {
      (Fail(_, expected=e1), Fail(_, expected=e2)) => e1 == e2
      (Ok(_, _), Ok(_, _)) => true
      _ => false
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 19：最远失败位置与期望合并不变量
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 19: 最远失败位置与期望合并不变量
///
/// 对任意解析器列表与输入：`alt` 在全部分支失败时报告的失败位置等于各分支失败
/// 位置中的最大 `offset`（不早于任一分支），且期望集合等于落在该最远位置上的
/// 分支期望的去重保序并集（较早位置分支的期望被舍弃）。当存在成功分支时，`alt`
/// 返回首个成功分支的结果。
///
/// **Validates: Requirements 6.1, 6.2, 6.3, 6.4**
test "Feature: parser-combinator, Property 19: farthest failure position and expected merge" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (
      gen_parser_int_at(rng, 2),
      gen_parser_int_at(rng, 2),
      gen_parser_int_at(rng, 2),
      gen_input_str(rng),
    )
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(quad) {
    let (p1, p2, p3, s) = quad
    let branches = [p1, p2, p3]
    let actual = alt(branches).parse_string(s)
    let results = branches.map(fn(p) { p.parse_string(s) })
    // 参照：第一个成功分支。
    let mut succ : (Int, Int)? = None
    for r in results {
      if succ is None {
        match r {
          Ok(v, rest) => succ = Some((v, rest.pos.offset))
          Fail(_, ..) => ()
        }
      }
    }
    match succ {
      Some((sv, soff)) =>
        match actual {
          Ok(v, rest) => v == sv && rest.pos.offset == soff
          Fail(_, ..) => false
        }
      None => {
        // 全部失败：最远位置 + 该位置期望去重保序并集。
        let mut maxoff = -1
        for r in results {
          match r {
            Fail(pos, ..) => if pos.offset > maxoff { maxoff = pos.offset }
            Ok(_, _) => ()
          }
        }
        let merged : Array[String] = []
        for r in results {
          match r {
            Fail(pos, expected=e) =>
              if pos.offset == maxoff {
                for x in e {
                  merged.push(x)
                }
              }
            Ok(_, _) => ()
          }
        }
        let expected_ref = dedup_preserve(merged)
        match actual {
          Fail(pos, expected=ea) => pos.offset == maxoff && ea == expected_ref
          Ok(_, _) => false
        }
      }
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// Property 20：错误位置单调性
// ---------------------------------------------------------------------------

///|
/// Feature: parser-combinator, Property 20: 错误位置单调性
///
/// 对任意解析器 `p1`、`p2` 与输入：若 `p1` 成功消费前缀至偏移 `k`，则
/// `seq(p1, p2)` 若失败，其失败位置偏移不早于 `k`（失败位置随成功消费推进而
/// 不回退）。
///
/// **Validates: Requirements 6.5**
test "Feature: parser-combinator, Property 20: error position monotonicity" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(triple) {
    let (p1, p2, s) = triple
    match p1.parse_string(s) {
      Ok(_, r1) => {
        let k = r1.pos.offset
        match seq(p1, p2).parse_string(s) {
          Fail(pos, ..) => pos.offset >= k
          Ok(_, _) => true
        }
      }
      Fail(_, ..) => true
    }
  })
  assert_true(ok)
}

// ---------------------------------------------------------------------------
// to_path_error 桥接单元测试（task 4.5）
// ---------------------------------------------------------------------------

///|
/// to_path_error 把失败桥接为携带行列位置与期望文本的 @core.PathError::InvalidInput
/// （R5.4）；成功结果桥接为 None。
test "to_path_error bridges failure with position and expected text" {
  // 失败：pchar('x') 对 "abc" 在 1:1（offset 0）失败，期望 'x'。
  match pchar('x').parse_string("abc").to_path_error() {
    Some(InvalidInput(msg)) =>
      @test.assert_eq(msg, "解析失败于 1:1（offset 0），期望 'x'")
    _ => fail("expected InvalidInput bridge")
  }
  // 成功：桥接为 None。
  assert_true(pchar('a').parse_string("abc").to_path_error() is None)
}
