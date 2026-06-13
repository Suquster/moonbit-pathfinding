// algebra_prop_test.mbt —— L0 核心代数定律属性测试（tasks 1.2~1.5）。
//
// 以全称量化（property）形式实现 design.md「正确性属性」章节的 Property 1~10：
// functor / monad / applicative / alternative 定律与基础不变量。全部复用
// @infra_pbt 的 `holds_for_all`（默认 ≥100 迭代）与本包共享生成器
// （generators_test.mbt）。
//
// 约定：测试注释统一标注 `Feature: parser-combinator, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

///|
/// Feature: parser-combinator, Property 1: pure 恒成功零消费
///
/// 对任意值 `v` 与任意输入，`pure(v).parse(input)` 恒为 `Ok(v, input)`：恒成功、
/// 产出 `v`、且剩余输入位置与进入位置相同（零消费）。
///
/// **Validates: Requirements 1.1**
test "Feature: parser-combinator, Property 1: pure succeeds with value and zero consumption" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (rng.next_range(0, 99), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (v, s) = pair
    match pure(v).parse_string(s) {
      Ok(out, rest) => out == v && rest.pos.offset == 0
      Fail(_, ..) => false
    }
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 2: map 保持消费量
///
/// 对任意解析器 `p`、函数 `f` 与输入：若 `p` 成功，则 `map(p, f)` 产出
/// `f(p 的产出值)` 且其剩余输入偏移与 `p` 的剩余输入偏移相同（消费量不变）。
///
/// **Validates: Requirements 1.2**
test "Feature: parser-combinator, Property 2: map preserves consumption" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_fun_int(rng), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(triple) {
    let (p, f, s) = triple
    match (p.parse_string(s), map(p, f).parse_string(s)) {
      (Ok(v, r1), Ok(mv, r2)) => mv == f(v) && r1.pos.offset == r2.pos.offset
      (Fail(_, ..), _) => true // p 失败不属于本子句（由 Property 3 覆盖）
      _ => false
    }
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 3: map / bind 失败透传且不调用续延
///
/// 对任意在某输入上失败的解析器 `p`、函数 `f`：`map(p, f)` 与 `bind(p, g)` 均
/// 返回与 `p` 逐字段一致的失败（相同失败位置与期望集合）。`f` / `g` 不被调用
/// 由实现结构保证（失败分支不进入续延）。
///
/// **Validates: Requirements 1.3, 1.5**
test "Feature: parser-combinator, Property 3: map/bind propagate failure verbatim" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    match p.parse_string(s) {
      Ok(_, _) => true // 成功不属于本子句
      Fail(_, ..) => {
        let base = p.parse_string(s)
        let mapped = map(p, fn(n) { n + 1000 }).parse_string(s)
        let bound = bind(p, fn(n) { pure(n + 1000) }).parse_string(s)
        presult_eq(mapped, base) && presult_eq(bound, base)
      }
    }
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 4: Functor 恒等律
///
/// 对任意解析器 `p` 与输入，`map(p, fn(x){x})` 与 `p` 产生逐字段一致的结果。
///
/// **Validates: Requirements 2.1**
test "Feature: parser-combinator, Property 4: functor identity law" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser().generate(rng), gen_input().generate(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    presult_eq(map(p, fn(x) { x }).parse_string(s), p.parse_string(s))
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 5: Functor 复合律
///
/// 对任意解析器 `p`、函数 `f`、`g` 与输入，
/// `map(p, fn(x){g(f(x))})` 与 `map(map(p, f), g)` 产生逐字段一致的结果。
///
/// **Validates: Requirements 2.2**
test "Feature: parser-combinator, Property 5: functor composition law" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_fun_int(rng), gen_fun_int(rng), gen_input_str(
      rng,
    ))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(quad) {
    let (p, f, g, s) = quad
    let lhs = map(p, fn(x) { g(f(x)) }).parse_string(s)
    let rhs = map(map(p, f), g).parse_string(s)
    presult_eq(lhs, rhs)
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 6: Monad 左单位元律
///
/// 对任意值 `a`、函数 `f`（`Int -> Parser[Int]`）与输入，
/// `bind(pure(a), f)` 与 `f(a)` 产生逐字段一致的结果。
///
/// **Validates: Requirements 2.3, 1.4**
test "Feature: parser-combinator, Property 6: monad left identity law" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (rng.next_range(0, 20), gen_fun_parser(rng), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(triple) {
    let (a, f, s) = triple
    presult_eq(bind(pure(a), f).parse_string(s), f(a).parse_string(s))
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 7: Monad 右单位元律
///
/// 对任意解析器 `p` 与输入，`bind(p, pure)` 与 `p` 产生逐字段一致的结果。
///
/// **Validates: Requirements 2.4**
test "Feature: parser-combinator, Property 7: monad right identity law" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser().generate(rng), gen_input().generate(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    presult_eq(bind(p, fn(x) { pure(x) }).parse_string(s), p.parse_string(s))
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 8: Monad 结合律
///
/// 对任意解析器 `p`、函数 `f`、`g`（`Int -> Parser[Int]`）与输入，
/// `bind(bind(p, f), g)` 与 `bind(p, fn(x){bind(f(x), g)})` 产生逐字段一致的结果。
///
/// **Validates: Requirements 2.5**
test "Feature: parser-combinator, Property 8: monad associativity law" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_fun_parser(rng), gen_fun_parser(rng), gen_input_str(
      rng,
    ))
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(quad) {
    let (p, f, g, s) = quad
    let lhs = bind(bind(p, f), g).parse_string(s)
    let rhs = bind(p, fn(x) { bind(f(x), g) }).parse_string(s)
    presult_eq(lhs, rhs)
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 9: Alternative 左单位元律
///
/// 对任意解析器 `p` 与输入，`alt([pfail, p])`（`pfail` 为恒失败、不消费输入、
/// **期望集合为空**的零元）与 `p` 产生逐字段一致的结果。空期望使最远失败合并
/// 在两者同位置失败时不引入额外期望符号，从而退化为 `p` 自身的诊断。
///
/// **Validates: Requirements 2.6**
test "Feature: parser-combinator, Property 9: alternative left identity law" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    let zero : Parser[Int] = pfail(expected=[])
    presult_eq(alt([zero, p]).parse_string(s), p.parse_string(s))
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 10: Alternative 结合律（PEG 有序选择）
///
/// 对任意解析器三元组 `p`、`q`、`r` 与输入，
/// `alt([alt([p, q]), r])` 与 `alt([p, alt([q, r])])` 产生逐字段一致的结果。
/// 在 PEG 有序选择 + 最远失败合并语义下，两种结合方式均按 p→q→r 的左到右顺序
/// 归约，故成功值、剩余偏移与（去重保序的）期望集合均一致。
///
/// **Validates: Requirements 2.7**
test "Feature: parser-combinator, Property 10: alternative associativity law" {
  let gen = @infra_pbt.Gen::new(fn(rng) {
    (
      gen_parser_int_at(rng, 2),
      gen_parser_int_at(rng, 2),
      gen_parser_int_at(rng, 2),
      gen_input_str(rng),
    )
  })
  let ok = @infra_pbt.holds_for_all(gen, fn(quad) {
    let (p, q, r, s) = quad
    let lhs = alt([alt([p, q]), r]).parse_string(s)
    let rhs = alt([p, alt([q, r])]).parse_string(s)
    presult_eq(lhs, rhs)
  })
  assert_true(ok)
}
