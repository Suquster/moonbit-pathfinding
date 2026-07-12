// 黑盒测试：覆盖率审计收口（INFRA 第七十八批）——
// 文档高亮的引用命中、空白位置与无定义引用余臂。

///|
test "document_highlights：引用位置命中同名定义与全部引用" {
  let doc : TextDocument = {
    uri: "file:///h.conf",
    text: "name = app\ngreeting = hello ${name}",
  }
  let a = analyze(doc)
  // 位于第 2 行 `${name}` 引用内部。
  let hs = document_highlights(a, { line: 1, character: 20 })
  assert_true(hs.length() >= 2)
}

///|
test "document_highlights：空白位置与无定义引用" {
  let doc : TextDocument = { uri: "file:///h2.conf", text: "a = ${missing}\n" }
  let a = analyze(doc)
  // `=` 两侧空白：既非符号亦非引用 → 空结果。
  assert_eq(document_highlights(a, { line: 0, character: 2 }).length(), 0)
  // 未定义名字的引用：无定义范围，仅高亮引用本身。
  let hs = document_highlights(a, { line: 0, character: 8 })
  assert_eq(hs.length(), 1)
}
