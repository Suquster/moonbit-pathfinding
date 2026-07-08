// 白盒测试：lsp_server 内部未覆盖分支（rope 旋转/拼接叶子路径、demo JSON
// 辅助函数各分支、FrameError Show 渲染）。

///|
fn cgw_leaf(s : String) -> Rope {
  let cps : Array[Int] = []
  for ch in s {
    cps.push(ch.to_int())
  }
  RLeaf(cps)
}

///|
fn cgw_str(r : Rope) -> String {
  let mut n = 0
  n = r.cp_len()
  n.to_string()
}

///|
test "rope：旋转与拼接的叶子退化路径保持码位总数" {
  let a = cgw_leaf("ab")
  let b = cgw_leaf("cd")
  // 右子为叶子：左旋退化为普通构造。
  assert_eq(rope_rotate_left(a, b).cp_len(), 4)
  // 左子为叶子：右旋退化为普通构造。
  assert_eq(rope_rotate_right(a, b).cp_len(), 4)
  // join_right 左侧为叶子。
  assert_eq(rope_join_right(a, b).cp_len(), 4)
  // join_left 右侧为叶子 / 分支两条路径。
  assert_eq(rope_join_left(a, b).cp_len(), 4)
  let tall = rope_mk(rope_mk(a, b), rope_mk(cgw_leaf("e"), cgw_leaf("f")))
  let taller = rope_mk(tall, cgw_leaf("g"))
  // join_left：右侧为高分支，左侧为叶子 → 走递归下沉分支。
  let joined = rope_join_left(cgw_leaf("x"), rope_mk(taller, cgw_leaf("y")))
  assert_eq(joined.cp_len(), 9)
  // join_right：左侧为高分支，右侧为叶子。
  let joined2 = rope_join_right(rope_mk(cgw_leaf("x"), taller), cgw_leaf("z"))
  assert_eq(joined2.cp_len(), 9)
  assert_true(cgw_str(joined2) == "9")
}

///|
test "demo 辅助：completion kind / hover JSON / result 提取各分支" {
  assert_eq(demo_kind_str(Keyword), "keyword")
  assert_eq(demo_kind_str(Value), "value")
  // hover 为 None → JNull；有值无 range → 不含 range 字段。
  assert_true(demo_hover_to_json(None) is @lsp_binding.JNull)
  let h : Hover = { contents: "c", range: None }
  guard demo_hover_to_json(Some(h)) is @lsp_binding.JObj(fields)
  assert_eq(fields.length(), 1)
  // 回复缺失 → JNull；错误回复 → error 对象。
  assert_true(demo_result_of(None) is @lsp_binding.JNull)
  let err_reply = @lsp_binding.Response(
    id=@lsp_binding.IdNum(1),
    result=None,
    error=Some({ code: -1, message: "bad", data: None }),
  )
  guard demo_result_of(Some(err_reply)) is @lsp_binding.JObj(efields)
  assert_true(efields.length() == 1)
  // demo_str_field：值非字符串 / 整体非对象。
  assert_eq(
    demo_str_field(@lsp_binding.JObj([("k", @lsp_binding.JNum("1"))]), "k"),
    "",
  )
  assert_eq(demo_str_field(@lsp_binding.JNull, "k"), "")
}

///|
test "jsonrpc_frame：FrameError 三分支 Show 渲染与解码错误路径" {
  guard decode_frame("\r\n\r\nabc") is Err(e1)
  assert_true("\{e1}".contains("MissingContentLength"))
  guard decode_frame("Content-Length: xyz\r\n\r\n") is Err(e2)
  assert_true("\{e2}".contains("InvalidContentLength"))
  guard decode_frame("Content-Length: 10\r\n\r\nab") is Err(e3)
  assert_true("\{e3}".contains("IncompleteBody") && "\{e3}".contains("need=10"))
}
