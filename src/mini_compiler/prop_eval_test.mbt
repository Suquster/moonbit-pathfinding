// prop_eval_test.mbt —— Mini_Compiler 求值确定性与作用域不变量属性测试（task 15.5）。
//
// 本文件以属性（property，全称量化形式）实现 design.md「正确性属性」章节的
// Property 3：「Mini_Compiler 求值确定性与作用域不变量」——对任意*通过类型
// 检查的程序*，重复求值应产生相同结果（求值确定性），且作用域绑定一致性恒
// 成立（不存在自由变量）：
//
//   * 作用域不变量：生成器只产出**闭合 AST**（closed AST，所有变量引用都被
//     外层 `let` 绑定，无自由变量），故 `check` 必返回 `Ok(_)`——这正是
//     R1.9「作用域绑定一致性」在编译器层面的可执行见证；
//   * 求值确定性：对通过检查得到的 `TypedAst t`，重复求值结果恒等，即
//     `eval(t) == eval(t)`（R1.9「求值结果确定性」）。
//
// 与 design.md 的对应：Property 3 的「作用域绑定一致性证明谓词」在 proofs 包
// 以 `scope_binding_consistent(bound, used)` 落地（纯、全 Bool 谓词，见
// `src/proofs/mini_compiler_proof.mbt`），其正反例由 `src/proofs` 的运行期
// 测试校验（proofs 与 mini_compiler 为不同包，谓词为方向无关的纯函数）。本
// 文件则在 mini_compiler 包内以真实 `check` / `eval` 流水线验证同一性质。
//
// 复用共享 PBT 包 @infra_pbt 的种子驱动随机源 `Rng`、生成器 `Gen` 与不变量
// 断言模板 `holds_for_all`（默认迭代 100 次，满足 Requirement 11.3 的 ≥100
// 迭代基线），并保证 wasm-gc / js / native 三后端逐位一致与可重放。
//
// 注：合法标识符池 `ident_pool` 与 `gen_ident` / `gen_binop` 复用同包
// prop_roundtrip_test.mbt 中已定义的采样基元，避免重复定义。
//
// 约定：测试注释统一标注 `Feature: moonbit-infra-suite, Property {n}: {text}`，
// 并以 `**Validates: Requirements X.Y**` 链接验收标准。

// ---------------------------------------------------------------------------
// 闭合 AST 生成器（closed-AST generator）—— 保证所有变量都被 let 绑定
// ---------------------------------------------------------------------------

///|
/// 采样一个**闭合**叶子节点：当作用域非空时可取作用域内的变量引用，否则取
/// 非负整数字面量。由此保证产出的 `Var` 必引用一个已绑定（in-scope）名字。
fn gen_closed_leaf(rng : @infra_pbt.Rng, scope : Array[String]) -> Ast {
  if scope.length() > 0 && rng.next_bool() {
    Var(scope[rng.next_below(scope.length())])
  } else {
    Int(rng.next_range(0, 9999))
  }
}

///|
/// 返回在末尾追加 `name` 后的**新**作用域（不可变更新，便于子树独立采样）。
fn scope_with(scope : Array[String], name : String) -> Array[String] {
  let out : Array[String] = []
  for n in scope {
    out.push(n)
  }
  out.push(name)
  out
}

///|
/// 在给定剩余深度与可见作用域 `scope` 下采样一个**闭合**表达式。
///
///   * 叶子：整数或作用域内变量（绝不产生自由变量）；
///   * `Bin`：左右子表达式均在**当前**作用域内采样；
///   * `Let`：bound 在当前（外层）作用域采样，body 在引入绑定名后的**扩展**
///     作用域采样——非递归 let，`name` 不在 bound 自身作用域内，与 `check`
///     的作用域规则一致。
///
/// 由构造可知：任意节点处的 `Var` 都引用其某个外层 `let` 绑定，故整棵树闭合，
/// `check` 必成功。
fn gen_closed_expr_at(
  rng : @infra_pbt.Rng,
  scope : Array[String],
  depth : Int,
) -> Ast {
  if depth <= 0 {
    gen_closed_leaf(rng, scope)
  } else {
    match rng.next_below(4) {
      0 => gen_closed_leaf(rng, scope)
      1 =>
        Bin(
          gen_binop(rng),
          gen_closed_expr_at(rng, scope, depth - 1),
          gen_closed_expr_at(rng, scope, depth - 1),
        )
      _ => {
        let name = gen_ident(rng)
        let bound = gen_closed_expr_at(rng, scope, depth - 1)
        let body = gen_closed_expr_at(rng, scope_with(scope, name), depth - 1)
        Let(name, bound, body)
      }
    }
  }
}

///|
/// 闭合 AST 生成器：深度受限、保证无自由变量的随机 MiniLet 表达式。
fn gen_closed_ast() -> @infra_pbt.Gen[Ast] {
  @infra_pbt.Gen::new(fn(rng) { gen_closed_expr_at(rng, [], 4) })
}

// ---------------------------------------------------------------------------
// 单元测试（示例 / 边界）—— 锁定作用域不变量与求值确定性的具体见证
// ---------------------------------------------------------------------------

///|
/// 闭合程序通过类型检查并可确定性求值的具体见证。
test "closed programs type-check and evaluate deterministically" {
  let samples : Array[Ast] = [
    Let("x", Int(1), Bin(Add, Var("x"), Int(2))),
    Let(
      "x",
      Int(10),
      Let("y", Bin(Mul, Var("x"), Int(2)), Bin(Sub, Var("y"), Var("x"))),
    ),
    Bin(Div, Int(7), Int(0)),
    Let("a", Int(3), Let("a", Int(5), Var("a"))),
  ]
  for a in samples {
    match check(a) {
      Ok(t) => assert_true(eval(t) == eval(t))
      Err(_) => fail("闭合程序应通过类型检查: \{print_ast(a)}")
    }
  }
}

///|
/// 自由变量（未绑定引用）破坏作用域一致性，`check` 返回 `TypeError` 且无
/// `TypedAst` —— 与 Property 3 闭合输入空间互补的反例见证。
test "free variables break scope consistency and fail check" {
  let samples : Array[Ast] = [
    Var("undefined"),
    Bin(Add, Int(1), Var("y")),
    // 非递归 let：被绑定表达式在外层作用域检查，此处 z 自由。
    Let("x", Var("z"), Var("x")),
  ]
  for a in samples {
    match check(a) {
      Err(d) => assert_true(d.kind == TypeError)
      Ok(_) =>
        fail(
          "含自由变量的程序不应通过类型检查: \{print_ast(a)}",
        )
    }
  }
}

///|
/// 内层同名绑定遮蔽外层，求值取最近绑定且结果确定（作用域语义见证）。
test "shadowing resolves to the innermost binding deterministically" {
  let a : Ast = Let("a", Int(3), Let("a", Int(5), Var("a")))
  match check(a) {
    Ok(t) => {
      assert_true(eval(t) == IntV(5))
      assert_true(eval(t) == eval(t))
    }
    Err(_) => fail("遮蔽程序应通过类型检查")
  }
}

// ---------------------------------------------------------------------------
// Property 3：Mini_Compiler 求值确定性与作用域不变量
// ---------------------------------------------------------------------------

///|
/// Feature: moonbit-infra-suite, Property 3: Mini_Compiler 作用域绑定一致性
///
/// 对任意由生成器产出的**闭合** AST `a`（所有变量都被外层 `let` 绑定），类型
/// 检查 `check(a)` 必返回 `Ok(_)`——即作用域绑定一致、不存在自由变量。这是
/// R1.9「作用域绑定一致性」在编译器层面的可执行见证。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次（满足 ≥100 迭代基线）。
///
/// **Validates: Requirements 1.9**
test "Feature: moonbit-infra-suite, Property 3: closed asts satisfy scope binding consistency (check succeeds)" {
  let ok = @infra_pbt.holds_for_all(gen_closed_ast(), fn(a) {
    match check(a) {
      Ok(_) => true
      Err(_) => false
    }
  })
  assert_true(ok)
}

///|
/// Feature: moonbit-infra-suite, Property 3: Mini_Compiler 求值确定性
///
/// 对任意*通过类型检查*的程序，重复求值应产生相同结果：先对生成的闭合 AST
/// 做 `check` 得到 `TypedAst t`，再断言 `eval(t) == eval(t)`（R1.9「求值结果
/// 确定性」）。`eval` 为纯、全函数，故确定性恒成立。复用 @infra_pbt 的
/// `holds_for_all` 不变量模板，默认迭代 100 次。
///
/// **Validates: Requirements 1.9**
test "Feature: moonbit-infra-suite, Property 3: eval(t) == eval(t) for every type-checked program" {
  let ok = @infra_pbt.holds_for_all(gen_closed_ast(), fn(a) {
    match check(a) {
      Ok(t) => eval(t) == eval(t)
      Err(_) => false
    }
  })
  assert_true(ok)
}
