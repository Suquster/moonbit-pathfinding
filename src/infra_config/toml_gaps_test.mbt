// toml_gaps_test.mbt —— TOML 解析器错误分支与标量分类覆盖收口
// （INFRA 第十七批）：字符串续行/多行、inf/nan、进制整数、浮点词法、
// 数组/内联表结构破坏、点分键冲突与数组表定位的确定性反例。

///|
fn tg_ok(src : String) -> Bool {
  toml_parse(src) is Some(_)
}

///|
fn tg_err(src : String) -> Bool {
  toml_parse(src) is None
}

///|
test "toml 字符串：转义、续行、多行与未闭合拒绝" {
  // 基本字符串小写 hex 转义 / 未闭合 / 换行截断 / 非法转义。
  match toml_parse("k = \"a\\u00e9b\"") {
    Some(t) => assert_true(toml_get(t, "k") == Some(TomlString("aéb")))
    None => assert_true(false)
  }
  assert_true(tg_err("k = \"abc"))
  assert_true(tg_err("k = \"abc\nd\""))
  assert_true(tg_err("k = \"\\q\""))
  // 续行反斜杠（多行基本字符串内，尾随空白 + 换行）。
  match toml_parse("k = \"\"\"a\\   \n   b\"\"\"") {
    Some(t) => assert_true(toml_get(t, "k") == Some(TomlString("ab")))
    None => assert_true(false)
  }
  // 多行基本字符串（内部单引号 / 双引号非终止）与未闭合。
  match toml_parse("k = \"\"\"a\"b\"\"\"") {
    Some(t) => assert_true(toml_get(t, "k") == Some(TomlString("a\"b")))
    None => assert_true(false)
  }
  assert_true(tg_err("k = \"\"\"abc"))
  // 字面量字符串：单行未闭合 / 换行截断；多行含单引号与未闭合。
  assert_true(tg_err("k = 'abc"))
  assert_true(tg_err("k = 'abc\nd'"))
  match toml_parse("k = '''a'b'''") {
    Some(t) => assert_true(toml_get(t, "k") == Some(TomlString("a'b")))
    None => assert_true(false)
  }
  assert_true(tg_err("k = '''abc"))
}

///|
test "toml 标量：inf/nan、日期时间、进制与浮点词法" {
  // inf / -inf / nan。
  assert_true(tg_ok("a = inf\nb = +inf\nc = -inf\nd = nan\ne = -nan"))
  // 日期时间（带空格分隔）与纯时刻。
  assert_true(tg_ok("t = 2026-07-09 14:00:00\nu = 08:30:00"))
  // 进制整数：0x 大小写 / 0o / 0b / 下划线 / 空位拒绝 / 负号拒绝 / 越基数拒绝。
  match toml_parse("h = 0xaB_c\no = 0o17\nb = 0b1_01") {
    Some(t) => {
      assert_true(toml_get(t, "h") == Some(TomlInt(0xABCL)))
      assert_true(toml_get(t, "o") == Some(TomlInt(15L)))
      assert_true(toml_get(t, "b") == Some(TomlInt(5L)))
    }
    None => assert_true(false)
  }
  assert_true(tg_err("k = 0x"))
  assert_true(tg_err("k = -0x1"))
  assert_true(tg_err("k = 0o9"))
  assert_true(tg_err("k = 0b2"))
  // 整数：纯符号 / 空词素 / 非法字符 / 仅下划线拒绝。
  assert_true(tg_err("k = +"))
  assert_true(tg_err("k = 1z2"))
  assert_true(tg_err("k = _"))
  // 浮点词法：缺整数位 / 缺小数位 / 缺指数位 / 尾随垃圾拒绝；合法指数通过。
  assert_true(tg_err("k = .5"))
  assert_true(tg_err("k = 1."))
  assert_true(tg_err("k = 1e"))
  assert_true(tg_err("k = 1e+"))
  assert_true(tg_ok("k = 1_000.5e-2"))
}

///|
test "toml 数组与内联表结构破坏" {
  // 数组：尾逗号允许 / 缺逗号拒绝 / 未闭合拒绝 / 元素非法拒绝。
  assert_true(tg_ok("a = [1, 2,]"))
  assert_true(tg_err("a = [1 2]"))
  assert_true(tg_err("a = [1,"))
  assert_true(tg_err("a = [+]"))
  // 内联表：空表 / 点分键 / 缺 '=' / 值非法 / 缺逗号或闭括号 / 重复键拒绝。
  assert_true(tg_ok("t = {}"))
  assert_true(tg_ok("t = { a.b = 1, c = 2 }"))
  assert_true(tg_err("t = { a 1 }"))
  assert_true(tg_err("t = { a = + }"))
  assert_true(tg_err("t = { a = 1 b = 2 }"))
  assert_true(tg_err("t = { a = 1, a = 2 }"))
  assert_true(tg_err("t = { a = 1, a.b = 2 }"))
}

///|
test "toml 表头定位与点分键冲突" {
  // [[t]] 数组表：追加元素 / 与普通表冲突 / 中段数组表进入末元素。
  assert_true(tg_ok("[[t]]\na = 1\n[[t]]\na = 2\n[t.sub]\nb = 3"))
  assert_true(tg_err("[t]\na = 1\n[[t]]\nb = 2"))
  // 中段键指向非表值 → 拒绝。
  assert_true(tg_err("a = 1\n[a.b]\nc = 2"))
  assert_true(tg_err("a = [1]\n[a.b]\nc = 2"))
  // 表头缺 ']' / [[ 缺第二个 ']' / 表头后有垃圾。
  assert_true(tg_err("[t\na = 1"))
  assert_true(tg_err("[[t]\na = 1"))
  assert_true(tg_err("[t] junk\na = 1"))
  // 顶层键值：缺 '=' / 值非法 / 行尾垃圾。
  assert_true(tg_err("k 1"))
  assert_true(tg_err("k = +"))
  assert_true(tg_err("k = 1 junk"))
}
