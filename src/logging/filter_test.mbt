// filter_test.mbt —— 非法指令定位与路由匹配单元测试（任务 6.4）。
//
// 覆盖 Requirement 4.4（EnvFilter 非法指令携带偏移的错误、不登记任何阈值）与
// 4.5（路由匹配 / 无匹配交付）。

///|
/// 缺 '=' 的非法裸级别项返回携带偏移的错误，且不登记任何阈值。
test "parse_env_filter rejects unrecognized bare level with position" {
  match parse_env_filter("http=warn,notalevel") {
    Ok(_) => fail("非法级别标签应解析失败")
    Err(err) => {
      // "http=warn," 共 10 字符，第二段从偏移 10 起。
      assert_eq(err.pos, 10)
      assert_true(err.message.contains("notalevel"))
    }
  }
}

///|
/// `target=非法level` 返回指向级别 token 起点的偏移。
test "parse_env_filter rejects unrecognized directive level with position" {
  match parse_env_filter("db=nope") {
    Ok(_) => fail("非法级别应解析失败")
    Err(err) => {
      // "db=" 后级别从偏移 3 起。
      assert_eq(err.pos, 3)
      assert_true(err.message.contains("nope"))
    }
  }
}

///|
/// 空段（前导/尾随/连续逗号）非法。
test "parse_env_filter rejects empty segments" {
  assert_true(parse_env_filter("info,") is Err(_))
  assert_true(parse_env_filter(",info") is Err(_))
  assert_true(parse_env_filter("a=info,,b=warn") is Err(_))
}

///|
/// 空 spec 合法：无指令 + 默认兜底（Trace，最宽松）。
test "parse_env_filter accepts empty spec with default fallback" {
  match parse_env_filter("") {
    Ok(f) => {
      // 任意 target 走兜底 Trace：所有级别均保留。
      assert_true(f.threshold_for("anything") == Level::Trace)
      assert_true(f.allows(Event::new(0L, Level::Trace, {})))
    }
    Err(_) => fail("空 spec 应合法")
  }
}

///|
/// 大小写不敏感的级别标签（tracing 约定小写）。
test "parse_env_filter accepts case-insensitive levels" {
  match parse_env_filter("svc=ERROR,warn") {
    Ok(f) => {
      assert_true(f.threshold_for("svc") == Level::Error)
      assert_true(f.threshold_for("other") == Level::Warn)
    }
    Err(_) => fail("大小写级别应被识别")
  }
}

///|
/// 路由：匹配交付给条件 sink，无匹配返回空。
test "route delivers to matching sinks and none on no match" {
  let errors = Sink::new("errors", Formatter::Json, route=fn(e) {
    e.level.rank() >= Level::Error.rank()
  })
  let sinks = [errors]
  // Info 无匹配 → 空。
  assert_eq(route(sinks, Event::new(0L, Level::Info, {})).length(), 0)
  // Error 匹配 → [errors]。
  let m = route(sinks, Event::new(0L, Level::Error, {}))
  assert_eq(m.length(), 1)
  assert_eq(m[0], "errors")
}
