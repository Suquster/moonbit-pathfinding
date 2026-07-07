// config_test.mbt —— TOML/INI 黑盒测试。
//
// TOML 用例对照 toml.io v1.0.0 规范示例；INI 对照 configparser 语义。

///|
test "TOML：标量类型全覆盖（字符串/整数/浮点/布尔/日期时间）" {
  let doc =
    #|title = "TOML Example"
    #|literal = 'C:\Users\nodejs'
    #|int1 = +99
    #|int2 = -17
    #|big = 5_349_221
    #|hex = 0xDEADBEEF
    #|oct = 0o755
    #|bin = 0b11010110
    #|flt1 = 3.1415
    #|flt2 = -2E-2
    #|flt3 = 5e+22
    #|bool1 = true
    #|bool2 = false
    #|odt = 1979-05-27T07:32:00Z
    #|ld = 1979-05-27
    #|lt = 07:32:00
  guard @infra_config.toml_parse(doc) is Some(root)
  assert_true(
    @infra_config.toml_get(root, "title") ==
    Some(@infra_config.TomlString("TOML Example")),
  )
  assert_true(
    @infra_config.toml_get(root, "literal") ==
    Some(@infra_config.TomlString("C:\\Users\\nodejs")),
  )
  assert_true(
    @infra_config.toml_get(root, "int1") == Some(@infra_config.TomlInt(99L)),
  )
  assert_true(
    @infra_config.toml_get(root, "int2") == Some(@infra_config.TomlInt(-17L)),
  )
  assert_true(
    @infra_config.toml_get(root, "big") == Some(@infra_config.TomlInt(5349221L)),
  )
  assert_true(
    @infra_config.toml_get(root, "hex") ==
    Some(@infra_config.TomlInt(0xDEADBEEFL)),
  )
  assert_true(
    @infra_config.toml_get(root, "oct") == Some(@infra_config.TomlInt(493L)),
  )
  assert_true(
    @infra_config.toml_get(root, "bin") == Some(@infra_config.TomlInt(214L)),
  )
  assert_true(
    @infra_config.toml_get(root, "flt1") ==
    Some(@infra_config.TomlFloat(3.1415)),
  )
  assert_true(
    @infra_config.toml_get(root, "flt2") == Some(@infra_config.TomlFloat(-0.02)),
  )
  assert_true(
    @infra_config.toml_get(root, "flt3") ==
    Some(@infra_config.TomlFloat(5.0e22)),
  )
  assert_true(
    @infra_config.toml_get(root, "bool1") == Some(@infra_config.TomlBool(true)),
  )
  assert_true(
    @infra_config.toml_get(root, "bool2") == Some(@infra_config.TomlBool(false)),
  )
  assert_true(
    @infra_config.toml_get(root, "odt") ==
    Some(@infra_config.TomlDatetime("1979-05-27T07:32:00Z")),
  )
  assert_true(
    @infra_config.toml_get(root, "ld") ==
    Some(@infra_config.TomlDatetime("1979-05-27")),
  )
  assert_true(
    @infra_config.toml_get(root, "lt") ==
    Some(@infra_config.TomlDatetime("07:32:00")),
  )
}

///|
test "TOML：字符串转义与多行字符串" {
  let doc =
    #|esc = "tab\tnewline\nquote\"backslash\\u-esc\u00E9"
    #|ml = """
    #|Roses are red
    #|Violets are blue"""
    #|mll = '''line1
    #|line2'''
  guard @infra_config.toml_parse(doc) is Some(root)
  assert_true(
    @infra_config.toml_get(root, "esc") ==
    Some(@infra_config.TomlString("tab\tnewline\nquote\"backslash\\u-escé")),
  )
  assert_true(
    @infra_config.toml_get(root, "ml") ==
    Some(@infra_config.TomlString("Roses are red\nViolets are blue")),
  )
  assert_true(
    @infra_config.toml_get(root, "mll") ==
    Some(@infra_config.TomlString("line1\nline2")),
  )
}

///|
test "TOML：数组、内联表、点分键" {
  let doc =
    #|ints = [ 1, 2, 3 ]
    #|nested = [ [ 1, 2 ], ["a", "b"] ]
    #|trailing = [ 1, 2, ]
    #|point = { x = 1, y = 2 }
    #|physical.color = "orange"
    #|physical.shape = "round"
  guard @infra_config.toml_parse(doc) is Some(root)
  assert_true(
    @infra_config.toml_get(root, "ints") ==
    Some(
      @infra_config.TomlArray([
        @infra_config.TomlInt(1L),
        @infra_config.TomlInt(2L),
        @infra_config.TomlInt(3L),
      ]),
    ),
  )
  assert_true(
    @infra_config.toml_get(root, "trailing") ==
    Some(
      @infra_config.TomlArray([
        @infra_config.TomlInt(1L),
        @infra_config.TomlInt(2L),
      ]),
    ),
  )
  guard @infra_config.toml_get(root, "point")
    is Some(@infra_config.TomlTable(pt))
  assert_true(
    @infra_config.toml_get(pt, "x") == Some(@infra_config.TomlInt(1L)),
  )
  guard @infra_config.toml_get(root, "physical")
    is Some(@infra_config.TomlTable(phys))
  assert_true(
    @infra_config.toml_get(phys, "shape") ==
    Some(@infra_config.TomlString("round")),
  )
}

///|
test "TOML：[table] 与 [[array-of-tables]]" {
  let doc =
    #|[server]
    #|host = "example.com"
    #|
    #|[server.tls]
    #|enabled = true
    #|
    #|[[products]]
    #|name = "Hammer"
    #|sku = 738594937
    #|
    #|[[products]]
    #|name = "Nail"
  guard @infra_config.toml_parse(doc) is Some(root)
  guard @infra_config.toml_get(root, "server")
    is Some(@infra_config.TomlTable(server))
  assert_true(
    @infra_config.toml_get(server, "host") ==
    Some(@infra_config.TomlString("example.com")),
  )
  guard @infra_config.toml_get(server, "tls")
    is Some(@infra_config.TomlTable(tls))
  assert_true(
    @infra_config.toml_get(tls, "enabled") == Some(@infra_config.TomlBool(true)),
  )
  guard @infra_config.toml_get(root, "products")
    is Some(@infra_config.TomlArray(products))
  assert_true(products.length() == 2)
  guard products[0] is @infra_config.TomlTable(p0)
  assert_true(
    @infra_config.toml_get(p0, "sku") == Some(@infra_config.TomlInt(738594937L)),
  )
  guard products[1] is @infra_config.TomlTable(p1)
  assert_true(
    @infra_config.toml_get(p1, "name") == Some(@infra_config.TomlString("Nail")),
  )
}

///|
test "TOML：注释、空文档、引号键" {
  let doc =
    #|# 整行注释
    #|key = "value"  # 行尾注释
    #|"quoted key" = 1
    #|'literal key' = 2
  guard @infra_config.toml_parse(doc) is Some(root)
  assert_true(
    @infra_config.toml_get(root, "key") ==
    Some(@infra_config.TomlString("value")),
  )
  assert_true(
    @infra_config.toml_get(root, "quoted key") ==
    Some(@infra_config.TomlInt(1L)),
  )
  assert_true(@infra_config.toml_parse("") == Some([]))
}

///|
test "TOML：畸形输入拒绝（重复键/缺=/未闭合/坏转义/坏数字）" {
  assert_true(@infra_config.toml_parse("a = 1\na = 2") == None)
  assert_true(@infra_config.toml_parse("a 1") == None)
  assert_true(@infra_config.toml_parse("a = \"unterminated") == None)
  assert_true(@infra_config.toml_parse("[table") == None)
  assert_true(@infra_config.toml_parse("a = \"bad \\x escape\"") == None)
  assert_true(@infra_config.toml_parse("a = 0x") == None)
  assert_true(@infra_config.toml_parse("a = 1 trailing") == None)
  assert_true(@infra_config.toml_parse("a = [1, 2") == None)
  // [[t]] 与既有普通表冲突。
  assert_true(@infra_config.toml_parse("[t]\na=1\n[[t]]\nb=2") == None)
}

///|
test "INI：节/键值/注释/引号值/last-wins" {
  let doc =
    #|; 顶部注释
    #|global_key = top
    #|
    #|[server]
    #|host = example.com
    #|port: 8080
    #|greeting = " hello world "
    #|host = override.example.com
    #|
    #|[empty]
    #|
    #|[client]
    #|# 注释
    #|retries = 3
  guard @infra_config.ini_parse(doc) is Some(sections)
  assert_true(@infra_config.ini_get(sections, "", "global_key") == Some("top"))
  assert_true(
    @infra_config.ini_get(sections, "server", "host") ==
    Some("override.example.com"),
  )
  assert_true(@infra_config.ini_get(sections, "server", "port") == Some("8080"))
  assert_true(
    @infra_config.ini_get(sections, "server", "greeting") ==
    Some(" hello world "),
  )
  assert_true(@infra_config.ini_get(sections, "client", "retries") == Some("3"))
  assert_true(@infra_config.ini_get(sections, "missing", "key") == None)
  // 节保序：""、server、empty、client。
  assert_true(sections.length() == 4)
  assert_true(sections[1].0 == "server")
  assert_true(sections[2].0 == "empty")
}

///|
test "INI：畸形输入拒绝与边界" {
  assert_true(@infra_config.ini_parse("[unclosed") == None)
  assert_true(@infra_config.ini_parse("no_separator_line") == None)
  assert_true(@infra_config.ini_parse("= value_without_key") == None)
  assert_true(@infra_config.ini_parse("") == Some([]))
  // CRLF 行尾。
  guard @infra_config.ini_parse("[s]\r\nk = v\r\n") is Some(s)
  assert_true(@infra_config.ini_get(s, "s", "k") == Some("v"))
}
