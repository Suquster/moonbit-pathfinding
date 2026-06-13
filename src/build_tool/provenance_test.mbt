// provenance_test.mbt —— 溯源单元测试（任务 7.2）。
//
// 覆盖相同输入与动作产逐字段一致记录、输入哈希乱序经规范升序后一致、任一
// 分量变异记录不同（R9.2 / R9.3）。

///|
/// 相同输入与动作 → 逐字段一致记录（R9.2）。
test "record_provenance is deterministic for identical inputs" {
  let recipe : Recipe = { lines: ["gcc -c x.c"] }
  let p1 = record_provenance("x.o", ["h1", "h2"], recipe)
  let p2 = record_provenance("x.o", ["h1", "h2"], recipe)
  assert_true(p1 == p2)
}

///|
/// 输入哈希乱序经规范升序后记录一致（R9.2）。
test "record_provenance canonicalizes input hash order" {
  let recipe : Recipe = { lines: ["cmd"] }
  let p1 = record_provenance("x.o", ["h1", "h2"], recipe)
  let p2 = record_provenance("x.o", ["h2", "h1"], recipe)
  assert_true(p1 == p2)
}

///|
/// 任一分量变异 → 记录不同（R9.3）。
test "record_provenance distinguishes different inputs and actions" {
  let recipe : Recipe = { lines: ["cmd"] }
  let p1 = record_provenance("x.o", ["h1"], recipe)
  assert_true(p1 != record_provenance("x.o", ["h2"], recipe))
  assert_true(p1 != record_provenance("y.o", ["h1"], recipe))
  assert_true(p1 != record_provenance("x.o", ["h1"], { lines: ["other"] }))
}

///|
/// 输出哈希对各分量单射（R9.4，构造性）。
test "derive_output_hash is injective on components" {
  assert_true(
    derive_output_hash(["h1"], "a") != derive_output_hash(["h2"], "a"),
  )
  assert_true(
    derive_output_hash(["h1"], "a") != derive_output_hash(["h1"], "b"),
  )
  assert_true(
    derive_output_hash(["h1"], "a") == derive_output_hash(["h1"], "a"),
  )
}
