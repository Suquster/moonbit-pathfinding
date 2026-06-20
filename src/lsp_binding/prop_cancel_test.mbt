// prop_cancel_test.mbt —— 请求取消产生取消响应属性测试（任务 3.3，Property 13）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 13「取消产生取消响应」：
//
//   *对任意* 由生成器产出的请求 `id` 集合与一个待取消 `id`，将其经
//   `CancelRegistry::cancel` 标记后：
//     (a) 该 `id` 经 `is_cancelled` 查询为 `true`；
//     (b) 对该 `id` 对应的进行中请求合成的 `cancelled_response` 是一条 `Response`，
//         其 `error` 携带 `request_cancelled_code`，且其 `id` 与请求 `id` 相等；
//     (c) 集合中与待取消 `id` 不同的 `id` 不受影响（`is_cancelled` 为 `false`）。
//
// **Validates: Requirements 2.5**
//
// 复用共享 PBT 包 @infra_pbt 的 `Gen` / `Rng` / `holds_for_all` 模板（每条属性
// ≥100 次迭代，由模板默认 `iters=100` 保证）。
//
// 生成器复用：`gen_id` / `gen_ascii_string` 已在同包文件 `prop_roundtrip_test.mbt`
// 定义，本文件直接复用，不重复定义（同包重名会冲突）。

// ---------------------------------------------------------------------------
// 随机生成器（id 集合 + 待取消 id）
// ---------------------------------------------------------------------------

///|
/// 生成一个随机长度（0..6）的请求 `id` 数组，元素复用同包 `gen_id`
/// （覆盖 IdNum / IdStr / IdNull 三种形态）。
fn gen_id_list(rng : @infra_pbt.Rng) -> Array[Id] {
  let n = rng.next_below(7)
  let ids : Array[Id] = []
  let mut i = 0
  while i < n {
    ids.push(gen_id(rng))
    i = i + 1
  }
  ids
}

///|
/// 生成一个「(id 集合, 待取消 id)」对。待取消 id 以一半概率取自集合中某个已存在
/// 元素（覆盖「取消集合内 id」场景），否则取一个独立随机 id（覆盖「取消集合外
/// id」场景）。
fn gen_cancel_case(rng : @infra_pbt.Rng) -> (Array[Id], Id) {
  let ids = gen_id_list(rng)
  let target = if ids.length() > 0 && rng.next_bool() {
    ids[rng.next_below(ids.length())]
  } else {
    gen_id(rng)
  }
  (ids, target)
}

///|
/// 「(id 集合, 待取消 id)」对生成器（封装为 @infra_pbt.Gen）。
fn gen_cancel_cases() -> @infra_pbt.Gen[(Array[Id], Id)] {
  @infra_pbt.Gen::new(fn(rng) { gen_cancel_case(rng) })
}

// ---------------------------------------------------------------------------
// 属性测试（Property 13）
// ---------------------------------------------------------------------------

///|
/// Feature: lsp, Property 13: 取消产生取消响应
///
/// 对任意由生成器产出的 (id 集合, 待取消 id)，将待取消 id 经
/// `CancelRegistry::cancel` 标记后应同时满足：
///   (a) `is_cancelled(target)` 为 `true`；
///   (b) `cancelled_response(target)` 是 `Response`，`error.code ==
///       request_cancelled_code`，且响应 `id` 与 `target` 相等；
///   (c) 集合中与 `target` 不相等的每个 id `is_cancelled` 仍为 `false`。
/// 复用 @infra_pbt 的 `holds_for_all` 不变量模板，默认迭代 100 次
/// （满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 2.5**
test "Feature: lsp, Property 13: cancel marks id and synthesizes cancelled response" {
  let ok = @infra_pbt.holds_for_all(gen_cancel_cases(), fn(case) {
    let (ids, target) = case
    let registry = CancelRegistry::new().cancel(target)

    // (a) 被标记的 id 查询为已取消。
    let marked = registry.is_cancelled(target)

    // (b) 合成的取消响应：Response + request_cancelled_code + id 一致。
    let resp = cancelled_response(target)
    let response_ok = match resp {
      Response(id~, result~, error~) =>
        id == target &&
        result == None &&
        (match error {
          Some(e) => e.code == request_cancelled_code
          None => false
        })
      _ => false
    }

    // (c) 与 target 不同的 id 不受影响。
    let mut others_unaffected = true
    for id in ids {
      if id != target && registry.is_cancelled(id) {
        others_unaffected = false
      }
    }
    marked && response_ok && others_unaffected
  })
  assert_true(ok)
}
