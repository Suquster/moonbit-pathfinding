// prop_filter_test.mbt —— 过滤判定一致性属性测试（任务 6.3）。
//
//   Feature: logging, Property 9: 过滤判定一致性（filter-decision consistency）
//   --------------------------------------------------------------------
//   *对任意* EnvFilter 指令集与事件，事件被保留当且仅当其级别不低于其 target
//   的有效阈值：allows(f, e) ⟺ e.level.rank() >= threshold_for(target_of(e)).rank()；
//   且对任意字段谓词与事件，field_filter(pred, e) ⟺ pred(e.fields)。
//
// 复用 @infra_pbt 的 `holds_for_all`（默认 100 迭代）。

///|
/// 单次场景：随机构造 EnvFilter（各 target 阈值 + 兜底）与带 target 字段的事件，
/// 独立重算期望阈值并断言 allows 与之一致；并断言 field_filter 与谓词一致。
fn ft_consistency(rng : @infra_pbt.Rng) -> Bool {
  let targets = ["http", "db", "cache", "auth"]
  let directives : Map[String, Level] = Map([])
  for t in targets {
    if rng.next_bool() {
      directives[t] = sh_level(rng)
    }
  }
  let fallback = sh_level(rng)
  let f : EnvFilter = { directives, fallback }
  // 事件 target：一半取自指令集合内、一半取未登记 target（走兜底）。
  let target = if rng.next_bool() {
    targets[rng.next_below(targets.length())]
  } else {
    "unregistered"
  }
  let level = sh_level(rng)
  let e = Event::new(0L, level, { "target": VStr(target) })
  // 独立重算期望阈值（不经 allows）。
  let expected_threshold = match directives.get(target) {
    Some(lv) => lv
    None => fallback
  }
  let expected = level.rank() >= expected_threshold.rank()
  if f.allows(e) != expected {
    return false
  }
  // threshold_for 与独立计算一致。
  if f.threshold_for(target) != expected_threshold {
    return false
  }
  // field_filter 与谓词一致。
  let pred = fn(fields : Map[String, Value]) -> Bool {
    fields.get("target") is Some(_)
  }
  if field_filter(pred, e) != pred(e.fields) {
    return false
  }
  true
}

///|
/// Feature: logging, Property 9: 过滤判定一致性（holds_for_all 模板，≥100 迭代）
///
/// **Validates: Requirements 4.1, 4.2, 4.6**
test "Feature: logging, Property 9: filter-decision consistency (holds_for_all)" {
  let gen = @infra_pbt.Gen::new(fn(rng) { ft_consistency(rng) })
  assert_true(@infra_pbt.holds_for_all(gen, fn(ok) { ok }))
}

///|
/// 具体见证：EnvFilter 对登记 target 用其阈值、未登记走兜底。
test "env filter threshold and allows (witness)" {
  let f = match parse_env_filter("http=warn,db=debug,info") {
    Ok(f) => f
    Err(_) => {
      fail("合法指令不应解析失败")
      return
    }
  }
  // http 阈值 Warn：Info 事件被丢弃，Error 被保留。
  assert_false(
    f.allows(Event::new(0L, Level::Info, { "target": VStr("http") })),
  )
  assert_true(
    f.allows(Event::new(0L, Level::Error, { "target": VStr("http") })),
  )
  // db 阈值 Debug：Debug 被保留。
  assert_true(f.allows(Event::new(0L, Level::Debug, { "target": VStr("db") })))
  // 未登记 target 走兜底 Info：Debug 丢弃、Info 保留。
  assert_false(f.allows(Event::new(0L, Level::Debug, { "target": VStr("x") })))
  assert_true(f.allows(Event::new(0L, Level::Info, { "target": VStr("x") })))
}
