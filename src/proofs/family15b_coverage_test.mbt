// family15b_coverage_test.mbt —— proof_report JSON 解析器与 yen_post 残余
// 拒绝分支的覆盖收口（第十五批补遗）。

///|
test "yen post rejects decreasing cost across two valid entries" {
  // 图：0→1 权 5（直达），0→2 权 1、2→1 权 1（合计 2）。两条路径各自
  // 合法（后置条件成立），但按 [5, 2] 降序枚举 ⇒ prev_cost 比较分支拒绝。
  let succ = fn(n : Int) -> Array[(Int, Int)] {
    if n == 0 {
      [(1, 5), (2, 1)]
    } else if n == 2 {
      [(1, 1)]
    } else {
      ([] : Array[(Int, Int)])
    }
  }
  let ew = fn(u : Int, v : Int) -> Int? {
    if u == 0 && v == 1 {
      Some(5)
    } else if u == 0 && v == 2 {
      Some(1)
    } else if u == 2 && v == 1 {
      Some(1)
    } else {
      None
    }
  }
  let goal = fn(n : Int) -> Bool { n == 1 }
  assert_false(
    yen_post([([0, 1], 5), ([0, 2, 1], 2)], 0, goal, succ, ew, [0, 1, 2]),
  )
  // 升序枚举同两条路径 ⇒ 接受（prev_cost 比较分支的正例）。
  assert_true(
    yen_post([([0, 2, 1], 2), ([0, 1], 5)], 0, goal, succ, ew, [0, 1, 2]),
  )
}

///|
test "proof report from_json covers remaining field error branches" {
  // parse_proof_report 成功分支。
  let ok_doc = "{\"moon_version\":\"m\",\"generated_at\":\"t\",\"backends\":[\"native\"],\"entries\":[]}"
  assert_true(parse_proof_report(ok_doc) is Some(_))
  // 缺 generated_at。
  assert_true(
    ProofReport::from_json(
      "{\"moon_version\":\"m\",\"backends\":[],\"entries\":[]}",
    )
    is Err(_),
  )
  let head = "{\"moon_version\":\"m\",\"generated_at\":\"t\",\"backends\":[],\"entries\":["
  // entry 缺 property。
  assert_true(
    ProofReport::from_json(
      head + "{\"algorithm\":\"a\",\"passed\":true,\"evidence\":\"e\"}]}",
    )
    is Err(_),
  )
  // entry 缺 evidence。
  assert_true(
    ProofReport::from_json(
      head + "{\"algorithm\":\"a\",\"property\":\"p\",\"passed\":true}]}",
    )
    is Err(_),
  )
}

///|
test "proof report json parser rejects structural breakage" {
  // \uXX 截断（parse_hex4 内 peek() = None 分支）。
  assert_true(ProofReport::from_json("{\"a\":\"b\\u12") is Err(_))
  // 对象键后缺冒号。
  assert_true(ProofReport::from_json("{\"a\" 1}") is Err(_))
  // 对象成员后既非逗号也非闭括号。
  assert_true(ProofReport::from_json("{\"a\":1 \"b\":2}") is Err(_))
  // 数组成员后既非逗号也非闭括号。
  assert_true(ProofReport::from_json("{\"a\":[1 2]}") is Err(_))
  // 空对象：解析成功但缺必需字段（覆盖 parse_object 空对象分支）。
  assert_true(ProofReport::from_json("{}") is Err(_))
}
