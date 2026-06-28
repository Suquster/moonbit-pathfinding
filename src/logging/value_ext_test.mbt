// value_ext_test.mbt —— 嵌套取值助手单元测试（任务 1.3）。
//
// 覆盖 `Value::is_scalar` / `is_nested` / `depth`（Requirement 1.2）。
// 黑盒测试中构造子以 `Value::` 限定（无类型上下文时必须限定）。

///|
/// is_scalar / is_nested 在各变体上的判定。
test "value is_scalar and is_nested classify scalar vs nested" {
  assert_true(Value::VStr("x").is_scalar())
  assert_true(Value::VInt(1L).is_scalar())
  assert_true(Value::VBool(true).is_scalar())
  assert_true(Value::VFloat(1.5).is_scalar())
  assert_false(Value::VStr("x").is_nested())
  let m : Map[String, Value] = { "a": Value::VInt(1L) }
  assert_true(Value::VMap(m).is_nested())
  assert_false(Value::VMap(m).is_scalar())
  assert_true(Value::VList([Value::VInt(1L)]).is_nested())
  assert_false(Value::VList([Value::VInt(1L)]).is_scalar())
}

///|
/// 标量取值深度为 0。
test "value depth of scalars is zero" {
  @test.assert_eq(Value::VStr("x").depth(), 0)
  @test.assert_eq(Value::VInt(7L).depth(), 0)
  @test.assert_eq(Value::VBool(false).depth(), 0)
  @test.assert_eq(Value::VFloat(3.25).depth(), 0)
}

///|
/// 空嵌套取值深度为 1；单层嵌套标量为 1。
test "value depth of empty and single-level nesting is one" {
  let empty_map : Map[String, Value] = {}
  @test.assert_eq(Value::VMap(empty_map).depth(), 1)
  let empty_list : Array[Value] = []
  @test.assert_eq(Value::VList(empty_list).depth(), 1)
  @test.assert_eq(
    Value::VMap({ "a": Value::VInt(1L), "b": Value::VStr("x") }).depth(),
    1,
  )
  @test.assert_eq(
    Value::VList([Value::VInt(1L), Value::VBool(true)]).depth(),
    1,
  )
}

///|
/// 多层嵌套深度为 1 + max(子取值深度)。
test "value depth of multi-level nesting takes one plus max child depth" {
  // { outer: [ {inner: 1} ] }  -> map(list(map(scalar))) = depth 3
  let inner : Map[String, Value] = { "inner": Value::VInt(1L) }
  let lst : Array[Value] = [Value::VMap(inner)]
  let outer : Map[String, Value] = { "outer": Value::VList(lst) }
  @test.assert_eq(Value::VMap(outer).depth(), 3)
  // mixed: list containing a scalar and a depth-2 map -> 1 + max(0, 2) = 3
  let deep_map : Map[String, Value] = { "k": Value::VList([Value::VInt(1L)]) } // depth 2
  let mixed : Array[Value] = [Value::VInt(9L), Value::VMap(deep_map)]
  @test.assert_eq(Value::VList(mixed).depth(), 3)
}
