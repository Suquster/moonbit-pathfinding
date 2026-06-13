// prop_cache_key_test.mbt —— Property 3：缓存键确定且内容敏感。
//
// 复用 @infra_pbt 的 holds_for_all 与 gen_key_inputs（随机目标 / 输入哈希序列 /
// 动作指纹）。验证长度前缀单射编码的构造性：相同输入产相同键、任一分量改变
// 即产不同键。

///|
/// Feature: build-tool, Property 3: 缓存键确定且内容敏感
///
/// 对任意（目标, 输入内容哈希序列, 动作指纹），`cache_key` 计算确定（相同输入
/// 恒产相同键），且对任一分量（目标 / 任一输入哈希 / 动作指纹）改变敏感（产生
/// 不同键）。
///
/// **Validates: Requirements 3.1, 3.4, 3.6**
test "Feature: build-tool, Property 3: cache-key determinism & content sensitivity" {
  let ok = @infra_pbt.holds_for_all(gen_key_inputs(), fn(triple) {
    let (target, hs, afp) = triple
    let key = cache_key(target, hs, afp)
    // 确定性：以独立副本重算应得相同键。
    let hs_copy : Array[String] = []
    for h in hs {
      hs_copy.push(h)
    }
    if key != cache_key(target, hs_copy, afp) {
      return false
    }
    // 目标变化敏感。
    if key == cache_key(target + "X", hs, afp) {
      return false
    }
    // 动作指纹变化敏感。
    if key == cache_key(target, hs, afp + "X") {
      return false
    }
    // 任一输入哈希变化敏感。
    if hs.length() > 0 {
      let hs2 : Array[String] = []
      for h in hs {
        hs2.push(h)
      }
      hs2[0] = hs2[0] + "X"
      if key == cache_key(target, hs2, afp) {
        return false
      }
    }
    true
  })
  assert_true(ok)
}
