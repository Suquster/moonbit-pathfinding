// prop_minimal_compat_test.mbt —— Property 2：最小文法向后兼容。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_minimal_text（随机最小文法文本）。

///|
/// Feature: build-tool, Property 2: 最小文法向后兼容
///
/// 对任意由生成器产出的合法最小文法规则文本（仅 `target: dep*`、注释与空行），
/// 完整文法解析的图投影与既有最小文法解析在节点序列与依赖边集合上逐字段一致：
/// `RuleSet::to_graph(parse_rules_full(src))` 与 `parse_rules(src)` 相等。
///
/// **Validates: Requirements 2.4, 2.5**
test "Feature: build-tool, Property 2: minimal-grammar backward compatibility" {
  let ok = @infra_pbt.holds_for_all(gen_minimal_text(), fn(src) {
    match (parse_rules_full(src), parse_rules(src)) {
      (Ok(rs), Ok(g)) => {
        let g2 = rs.to_graph()
        targets_eq(g2.nodes, g.nodes) && edges_eq(g2.edges, g.edges)
      }
      // 最小文法对两解析器均合法，故只接受双 Ok。
      _ => false
    }
  })
  assert_true(ok)
}
