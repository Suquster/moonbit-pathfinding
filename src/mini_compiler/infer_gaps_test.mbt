// infer_gaps_test.mbt —— Algorithm W 错误传播分支收口
// （INFRA 第二十三批）：各复合表达式子位置的类型错误向上冒泡。

///|
/// 词法 + 语法分析源串并推断，期望类型错误。
fn ig_err(src : String) -> Unit raise {
  let tokens = match lex_ml(src) {
    Ok(ts) => ts
    Err(d) => abort("词法分析意外失败：\{d.msg}")
  }
  let e = match parse_ml(tokens) {
    Ok(e) => e
    Err(d) => abort("语法分析意外失败：\{d.msg}")
  }
  assert_true(infer(e) is Err(_))
}

///|
test "infer：二元运算右操作数错误冒泡" {
  ig_err("1 + (2 + true)")
  ig_err("1 < (2 + true)")
}

///|
test "infer：if 各子位置错误冒泡" {
  ig_err("if 1 + true then 1 else 2") // 条件内部错误
  ig_err("if true then 1 + true else 2") // then 内部错误
  ig_err("if true then 1 else 2 + true") // else 内部错误
  ig_err("if true then 1 else false") // 分支类型不合一
}

///|
test "infer：lambda 体与应用两侧错误冒泡" {
  ig_err("fun x -> 1 + true") // 函数体内部错误
  ig_err("(1 + true) 2") // 函数位错误
  ig_err("(fun x -> x) (1 + true)") // 实参位错误
}
