// parser_gaps_test.mbt —— 递归下降 let 语法各错误位置收口
// （INFRA 第二十四批）。

///|
fn pg_err(toks : Array[Token]) -> Unit raise {
  assert_true(parse(toks) is Err(_))
}

///|
test "parse：空输入拒绝" {
  pg_err([])
}

///|
test "parse：let 头部各错误位置拒绝" {
  pg_err([KwLet, IntLit(1)]) // 绑定名非标识符
  pg_err([KwLet]) // 绑定名缺失（EOF）
  pg_err([KwLet, KwIn, Assign, IntLit(1)]) // 关键字作绑定名
  pg_err([KwLet, KwLet, Assign, IntLit(1)]) // 关键字 let 作绑定名
}

///|
test "parse：let 绑定与 in/body 各错误位置拒绝" {
  pg_err([KwLet, Ident("x"), Assign, KwIn]) // 被绑定表达式错误
  pg_err([KwLet, Ident("x"), Assign, IntLit(1), Ident("foo")]) // 期望 in 见普通标识符
  pg_err([KwLet, Ident("x"), Assign, IntLit(1), LParen]) // 期望 in 见非字母
  pg_err([KwLet, Ident("x"), Assign, IntLit(1)]) // in 缺失（EOF）
  pg_err([KwLet, Ident("x"), Assign, IntLit(1), KwIn, KwIn]) // body 错误
}

///|
test "parse：原子位置意外关键字拒绝" {
  pg_err([KwIn])
  pg_err([IntLit(1), Plus, KwLet, Ident("y"), Assign, IntLit(2), KwIn, KwIn])
}
