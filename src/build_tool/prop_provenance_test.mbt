// prop_provenance_test.mbt —— Property 15：可复现性与溯源确定。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_prov_inputs（目标 / 输入哈希集合 /
// recipe）。校验记录确定（含输入哈希乱序后规范一致）与差异可区分。

///|
/// Feature: build-tool, Property 15: 可复现性与溯源确定
///
/// 对任意（目标, 输入内容哈希集合, 动作 recipe），`record_provenance` 产出逐
/// 字段一致的溯源记录（相同输入与动作恒得相同记录，且输入哈希乱序经规范升序
/// 后仍一致）；且对任一分量（目标 / 输入哈希 / 动作）变异，产出的记录不同。
///
/// **Validates: Requirements 9.1, 9.2, 9.3, 9.4**
test "Feature: build-tool, Property 15: reproducibility & provenance determinism" {
  let ok = @infra_pbt.holds_for_all(gen_prov_inputs(), fn(triple) {
    let (target, hs, recipe) = triple
    let p1 = record_provenance(target, hs, recipe)
    // 确定性：独立副本重算应得相同记录。
    let hs_copy : Array[String] = []
    for h in hs {
      hs_copy.push(h)
    }
    if !(p1 == record_provenance(target, hs_copy, recipe)) {
      return false
    }
    // 规范化：输入哈希乱序（逆序）经升序规范后记录一致。
    let rev : Array[String] = []
    let mut i = hs.length() - 1
    while i >= 0 {
      rev.push(hs[i])
      i = i - 1
    }
    if !(p1 == record_provenance(target, rev, recipe)) {
      return false
    }
    // 目标变化 → 记录不同。
    if p1 == record_provenance(target + "X", hs, recipe) {
      return false
    }
    // 动作（recipe）变化 → 动作指纹不同 → 记录不同。
    let lines2 : Array[String] = []
    for l in recipe.lines {
      lines2.push(l)
    }
    lines2.push("extra-cmd")
    if p1 == record_provenance(target, hs, { lines: lines2 }) {
      return false
    }
    // 任一输入哈希变化 → 记录不同。
    if hs.length() > 0 {
      let hs2 : Array[String] = []
      for h in hs {
        hs2.push(h)
      }
      hs2[0] = hs2[0] + "X"
      if p1 == record_provenance(target, hs2, recipe) {
        return false
      }
    }
    true
  })
  assert_true(ok)
}
