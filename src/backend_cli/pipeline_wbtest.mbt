// pipeline_wbtest.mbt —— 验证驱动语料的管线冒烟测试：
// 每条语料必须完整通过 lex → parse → infer → eval → JS/wat 发射，
// 保证 scripts/verify_backends.sh 依赖的驱动输出永不含 ERROR 分支。

///|
test "corpus passes full pipeline and emits nonempty backends" {
  assert_true(corpus.length() > 0)
  for src in corpus {
    match @mc.lex_ml(src) {
      Err(_) => abort("lex failed: " + src)
      Ok(toks) =>
        match @mc.parse_ml(toks) {
          Err(_) => abort("parse failed: " + src)
          Ok(e) =>
            match @mc.infer(e) {
              Err(_) => abort("infer failed: " + src)
              Ok((te, ty)) => {
                // 求值与形状描述均可用。
                let shown = @mc.js_show_val(@mc.eval_ml(te))
                assert_true(shown.length() > 0)
                assert_true(@mc.ty_shape(ty).length() > 0)
                // 两个后端发射非空程序。
                assert_true(@mc.emit_js_program(te).length() > 0)
                assert_true(@mc.emit_wat_module(te).length() > 0)
              }
            }
        }
    }
  }
}

///|
test "corpus covers key language features" {
  // 语料必须覆盖：递归 let rec、闭包 fun、元组、条件 if。
  let mut has_rec = false
  let mut has_fun = false
  let mut has_tuple = false
  let mut has_if = false
  for src in corpus {
    if src.contains("let rec") {
      has_rec = true
    }
    if src.contains("fun ") {
      has_fun = true
    }
    if src.contains("(") && src.contains(",") {
      has_tuple = true
    }
    if src.contains("if ") {
      has_if = true
    }
  }
  assert_true(has_rec)
  assert_true(has_fun)
  assert_true(has_tuple)
  assert_true(has_if)
}
