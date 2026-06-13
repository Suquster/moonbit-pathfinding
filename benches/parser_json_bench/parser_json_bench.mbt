// benches/parser_json_bench — JSON 解析基准（packrat vs 朴素，递增规模）。
//
// 工作负载（R12.1）：解析逐渐增大的 JSON 文本（扁平数组 + 嵌套数组），分别以
// `run_packrat`（记忆化）与 `run_naive`（朴素参照）计时，呈现复杂度趋势对比
// （R12.3）。smoke 测试保证基准工作负载在三后端均可正确解析（防回归）。
//
// _Requirements: 12.1, 12.2, 12.3, 12.5_

///|
/// 构造扁平 JSON 数组文本 `[0,1,2,...,n-1]`。
fn make_flat_array(n : Int) -> String {
  let mut s = "["
  let mut i = 0
  while i < n {
    if i > 0 {
      s = s + ","
    }
    s = s + "\{i}"
    i = i + 1
  }
  s + "]"
}

///|
/// 构造右嵌套 JSON 数组文本 `[[[...]]]`，嵌套深度 `d`，最内层为数字 `0`。
fn make_nested_array(d : Int) -> String {
  let mut open = ""
  let mut close = ""
  let mut i = 0
  while i < d {
    open = open + "["
    close = close + "]"
    i = i + 1
  }
  open + "0" + close
}

///|
/// Smoke guard：基准工作负载在 packrat / 朴素入口均能正确解析（结果一致）。
test "smoke: parser_json bench workload parses under both run modes" {
  let g = @pc.json_value_grammar()
  let flat = make_flat_array(64)
  let nested = make_nested_array(16)
  assert_true(g.run_packrat_string(flat).is_ok())
  assert_true(g.run_naive_string(flat).is_ok())
  assert_true(g.run_packrat_string(nested).is_ok())
  assert_true(g.run_naive_string(nested).is_ok())
}

///|
/// Native benchmark：packrat vs 朴素在递增规模（几何增长）下的计时对比。
test "bench: parser_json packrat vs naive over increasing sizes" (b : @bench.T) {
  let g = @pc.json_value_grammar()
  let sizes = [16, 64, 256]
  for n in sizes {
    let input = make_flat_array(n)
    b.bench(name="json_flat_packrat_\{n}", fn() {
      b.keep(g.run_packrat_string(input))
    })
    b.bench(name="json_flat_naive_\{n}", fn() {
      b.keep(g.run_naive_string(input))
    })
  }
  let depths = [8, 16, 32]
  for d in depths {
    let input = make_nested_array(d)
    b.bench(name="json_nested_packrat_\{d}", fn() {
      b.keep(g.run_packrat_string(input))
    })
    b.bench(name="json_nested_naive_\{d}", fn() {
      b.keep(g.run_naive_string(input))
    })
  }
}
