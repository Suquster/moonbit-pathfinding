// commit_prop_test.mbt —— L1 提交语义属性测试与恢复单元测试（tasks 7.2, 7.3）。
//
// 实现 Property 21（提交感知择一语义）、Property 22（提交透明性）与 `recover`
// 同步恢复单元测试（R7.4，服务 R11.4）。

///|
/// Feature: parser-combinator, Property 21: 提交感知择一语义
///
/// 对含提交点的分支序列与输入：当某分支跨越提交点之后失败时，`choice` 停止尝试
/// 后续分支并向上传播硬失败（即便后续分支本可匹配也不再尝试）；当某分支在跨越
/// 提交点之前失败时，`choice` 回溯到分支起点继续尝试后续分支。
///
/// 见证文法：`b1 = 'a' 之后 commit('b')`，`b2 = 'a'`（后备分支）。
///   * `"ab…"` → b1 成功（值 1）。
///   * `"a" + 非 'b'` → b1 跨越提交点后硬失败 → choice 不再尝试 b2（值 2 不被
///     返回）→ 整体失败（提交语义的核心见证）。
///   * `非 'a'` → b1 在提交点前软失败 → 回溯尝试 b2 → b2 亦失败 → 整体失败。
/// 对照：无提交版本 `b1' = 'a' 之后 'b'` 在 `"a"+非'b'` 时软失败 → choice 回溯
/// 到 b2 → 返回值 2。
///
/// **Validates: Requirements 7.1, 7.2, 7.3**
test "Feature: parser-combinator, Property 21: commit-aware choice semantics" {
  let b1 = lift(pchar('a')).bind(fn(_) {
    commit(lift(pchar('b'))).map(fn(_) { 1 })
  })
  let b2 = lift(pchar('a')).map(fn(_) { 2 })
  let committed_choice = choice([b1, b2])
  // 对照：无提交。
  let b1_nc = lift(pchar('a')).bind(fn(_) { lift(pchar('b')).map(fn(_) { 1 }) })
  let soft_choice = choice([b1_nc, b2])
  let ok = @infra_pbt.holds_for_all(gen_input(), fn(s) {
    let chars = s.iter().to_array()
    let starts_a = chars.length() >= 1 && chars[0] == 'a'
    let second_b = chars.length() >= 2 && chars[1] == 'b'
    let committed_res = committed_choice.run_packrat_string(s)
    let soft_res = soft_choice.run_packrat_string(s)
    if starts_a && second_b {
      // 两种版本都经第一分支成功（值 1）。
      committed_res.value() == Some(1) && soft_res.value() == Some(1)
    } else if starts_a {
      // 提交版本：硬失败，不回退到 b2 → 失败；软版本：回退到 b2 → 值 2。
      !committed_res.is_ok() && soft_res.value() == Some(2)
    } else {
      // 非 'a'：两版本都在提交点前软失败 → 整体失败。
      !committed_res.is_ok() && !soft_res.is_ok()
    }
  })
  assert_true(ok)
}

///|
/// Feature: parser-combinator, Property 22: 提交透明性
///
/// 对不含任何提交点的富解析器 `g`（此处取 `lift(gen_parser)`，其失败永不被标记为
/// committed）与输入，`commit(g)` 与 `g` 产生逐字段一致的解析结果。
///
/// **Validates: Requirements 7.5**
test "Feature: parser-combinator, Property 22: commit transparency" {
  let g = @infra_pbt.Gen::new(fn(rng) {
    (gen_parser_int_at(rng, 3), gen_input_str(rng))
  })
  let ok = @infra_pbt.holds_for_all(g, fn(pair) {
    let (p, s) = pair
    let gram = lift(p)
    gresult_eq(commit(gram).run_naive_string(s), gram.run_naive_string(s))
  })
  assert_true(ok)
}

///|
/// recover：硬失败后扫描到 sync 同步点之后以 fallback 续解（R7.4，服务 R11.4）。
test "recover synchronizes past sync point after a committed failure" {
  let digit_g = lift(satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字"))
  // p：'(' 之后 commit(digit)。"(x" → '(' 成功、commit(digit) 硬失败。
  let p = lift(pchar('(')).bind(fn(_) { commit(digit_g) })
  let sync = lift(pchar(',')).map(fn(_c) { () })
  let r = recover(p, sync, '?')
  // "(x,abc"：硬失败后扫描到 ','（offset 2）之后，以 '?' 续解，剩余停在 'a'。
  match r.run_packrat_string("(x,abc") {
    Ok(v, rest) => {
      assert_eq(v, '?')
      assert_eq(rest.pos.offset, 3)
      assert_true(rest.peek() == Some('a'))
    }
    Fail(_, ..) => fail("expected recovery to succeed with fallback")
  }
  // 软失败（'(' 不匹配，未跨提交点）应原样透传为失败。
  match r.run_packrat_string("yyy") {
    Fail(_, ..) => assert_true(true)
    Ok(_, _) =>
      fail("soft failure before commit should pass through as failure")
  }
}
