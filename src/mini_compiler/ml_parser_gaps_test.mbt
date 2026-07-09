// ml_parser_gaps_test.mbt —— ML 解析器语法错误分支覆盖收口
// （INFRA 第十七批）：let/if/lambda/元组/括号各产生式缺件的确定性反例。

///|
fn mg_err(src : String) -> Bool {
  match lex_ml(src) {
    Ok(toks) => parse_ml(toks) is Err(_)
    Err(_) => true
  }
}

///|
fn mg_ok(src : String) -> Bool {
  match lex_ml(src) {
    Ok(toks) => parse_ml(toks) is Ok(_)
    Err(_) => false
  }
}

///|
test "ml 解析：let / let rec 缺件拒绝" {
  assert_true(mg_err("let"))
  assert_true(mg_err("let 1 = 2 in x"))
  assert_true(mg_err("let x 2 in x"))
  assert_true(mg_err("let x = ) in x"))
  assert_true(mg_err("let x = 1 x"))
  assert_true(mg_err("let x = 1 in )"))
  assert_true(mg_ok("let rec f = lambda n -> n in f 1"))
  assert_true(mg_err("let rec = 1 in 2"))
}

///|
test "ml 解析：if / lambda 缺件拒绝" {
  assert_true(mg_err("if ) then 1 else 2"))
  assert_true(mg_err("if true 1 else 2"))
  assert_true(mg_err("if true then ) else 2"))
  assert_true(mg_err("if true then 1 2"))
  assert_true(mg_err("if true then 1 else )"))
  assert_true(mg_err("lambda"))
  assert_true(mg_err("lambda 1 -> x"))
  assert_true(mg_err("lambda x x"))
  assert_true(mg_err("lambda x -> )"))
  assert_true(mg_ok("fun x -> x 1"))
}

///|
test "ml 解析：二元层与原子错误传播" {
  // 各优先级层右操作数缺失。
  assert_true(mg_err("1 || )"))
  assert_true(mg_err("1 && )"))
  assert_true(mg_err("1 < )"))
  assert_true(mg_err("1 + )"))
  assert_true(mg_err("1 * )"))
  assert_true(mg_err("f )"))
  // 原子层：空输入 / 括号未闭合 / 括号内错误。
  assert_true(mg_err(""))
  assert_true(mg_err("(1"))
  assert_true(mg_err("()"))
  assert_true(mg_err("(1 2"))
}

///|
test "ml 解析：元组分支" {
  assert_true(mg_ok("(1, 2, 3)"))
  assert_true(mg_err("(1, )"))
  assert_true(mg_err("(1, 2"))
  // 分组沿用内层 span；应用左结合吞原子。
  assert_true(mg_ok("(1 + 2) * (true, false)"))
}
