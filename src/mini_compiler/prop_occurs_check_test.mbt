// prop_occurs_check_test.mbt —— occurs-check 正确性属性测试（task 4.3，覆盖 R3.6）。
//
// 本文件为同包黑盒测试文件（`_test.mbt`），以属性（全称量化）形式实现
// design.md「正确性属性」章节的 Property 4「occurs-check 正确性」：
//
//   对任意类型变量 `v` 与「包含 `v` 且不等于 `v`」的类型项 `t`，
//   `unify(TyVar(v), t)` 必须失败并返回 `kind == TypeError` 的诊断。
//
// 这是 unify.mbt 中 occurs-check 的可执行见证：把一个类型变量与一个真正包含
// 该变量的更大类型项合一，会构造出无限类型（如 `v ~ v -> a`），故合一必须
// 拒绝并报 `TypeError`（R3.2 / R3.6）。
//
// 生成器设计（本文件自带，独立于 ml_gen_test.mbt 的可合一类型对生成器）：
//   * 先采样一个变量 id `v ∈ [0, 5)`；再采样一段「其它」随机子结构 `other`；
//   * 把 `TyVar(v)` 嵌入 `TyFun` 或 `TyTuple` 的某个位置，与 `other` 组合，
//     得到 `t`。由于外层包裹的是 `TyFun` / `TyTuple` 构造子，`t` 在结构上
//     必然**大于** `TyVar(v)`（故 `t != TyVar(v)`），同时**必然包含** `TyVar(v)`。
//   * 两项条件（包含 v、不等于 v）均由构造方式静态保证，无需运行期过滤。
//
// 复用共享 PBT 包 @infra_pbt 的 `holds_for_all` 不变量模板，显式迭代 100 次
// （满足「每条属性测试 ≥100 迭代」基线）。
//
// 注：在三后端（wasm-gc / js / native）运行；运行 native 后端前需先执行
//     `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

// ---------------------------------------------------------------------------
// 本文件自带生成器：产出 (v, t)，t 包含 TyVar(v) 且 t != TyVar(v)
// ---------------------------------------------------------------------------

///|
/// 采样一段与变量 `v` 无关的「其它」随机子结构（基类型 / 函数 / 元组 / 另一个
/// 变量），用作把 `TyVar(v)` 包裹起来时的填充部件。深度受限以约束规模。
fn occurs_other_ty(rng : @infra_pbt.Rng, depth : Int) -> Ty {
  if depth <= 0 {
    match rng.next_below(3) {
      0 => TyInt
      1 => TyBool
      // 取一个较大的变量 id 区间，与目标 v ∈ [0,5) 区分；即便偶有重合也不影响
      // 属性（t 仍包含 v 且结构大于 TyVar(v)）。
      _ => TyVar(100 + rng.next_below(20))
    }
  } else {
    match rng.next_below(4) {
      0 => TyInt
      1 => TyBool
      2 =>
        TyFun(occurs_other_ty(rng, depth - 1), occurs_other_ty(rng, depth - 1))
      _ => {
        let n = 2 + rng.next_below(2)
        let arr : Array[Ty] = []
        for _ in 0..<n {
          arr.push(occurs_other_ty(rng, depth - 1))
        }
        TyTuple(arr)
      }
    }
  }
}

///|
/// occurs-check 用例生成器：产出 `(v, t)`，其中 `t` 把 `TyVar(v)` 嵌入一个
/// `TyFun` 或 `TyTuple` 包裹结构。外层构造子保证 `t` 结构上大于 `TyVar(v)`
/// （`t != TyVar(v)`），嵌入的 `TyVar(v)` 保证 `t` 包含 `v`。
pub fn occurs_pair_gen() -> @infra_pbt.Gen[(Int, Ty)] {
  @infra_pbt.Gen::new(fn(rng) {
    let v = rng.next_below(5)
    let other = occurs_other_ty(rng, 2)
    let t : Ty = match rng.next_below(4) {
      // 函数类型：把 TyVar(v) 放在参数或结果位置。
      0 => TyFun(TyVar(v), other)
      1 => TyFun(other, TyVar(v))
      // 元组类型：把 TyVar(v) 放在元组的某个分量。
      2 => TyTuple([other, TyVar(v)])
      _ => TyTuple([TyVar(v), other, other])
    }
    (v, t)
  })
}

// ---------------------------------------------------------------------------
// Property 4：occurs-check 正确性
// ---------------------------------------------------------------------------

///|
/// **Feature: mini-compiler, Property 4: occurs-check 正确性**
///
/// 对任意类型变量 `v` 与包含 `v` 且不等于 `v` 的类型项 `t`，`unify(TyVar(v), t)`
/// 失败并返回 `kind == TypeError` 的诊断。生成器 `occurs_pair_gen` 通过把
/// `TyVar(v)` 嵌入 `TyFun` / `TyTuple` 包裹结构，静态保证 `t` 包含 `v` 且
/// `t != TyVar(v)`。复用 @infra_pbt 的 `holds_for_all`，迭代 100 次。
///
/// **Validates: Requirements 3.6**
test "Feature: mini-compiler, Property 4: occurs-check 正确性" {
  let ok = @infra_pbt.holds_for_all(
    occurs_pair_gen(),
    fn(pair) {
      let (v, t) = pair
      match unify(TyVar(v), t) {
        Err(d) => d.kind == TypeError
        Ok(_) => false
      }
    },
    iters=100,
  )
  assert_true(ok)
}
