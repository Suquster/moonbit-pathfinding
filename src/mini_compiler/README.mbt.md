# mini_compiler · 可执行文档

> **方向一（R1）小语言编译器 / 解释器** — 词法 · 语法 · 类型检查 · 求值，三后端一致 · 文档即测试。
>
> 本文件既是 `mini_compiler` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/mini_compiler/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box
测试编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 15.6**：
展示「源码 → AST → 求值」的端到端流程。

本文件作为 `mini_compiler` 包的黑盒测试运行，因此可直接调用本包公开 API
（`lex` / `parse` / `check` / `eval` / `print_ast`）而无需限定包名。

> **黑盒构造约定**：示例统一通过流水线函数获得 `Token` / `Ast` / `TypedAst` /
> `Value`，再用 `match` 解构 `Result` 与 `Value`；需要写出枚举构造子时采用
> 限定形式（如 `Value::IntV`、`DiagKind::LexError`），避免黑盒环境下的名字歧义。

---

## MiniLet 文法（target language grammar）

示例围绕子包声明的目标语言 **MiniLet**（完整文法见 `moon.pkg` 的文法声明，
此处摘录），即「极简整数算术 + `let` 绑定 + 变量」的表达式语言：

```text
词法：
  INT     ::= DIGIT+                          // 非负整数字面量
  IDENT   ::= ALPHA (ALPHA | DIGIT | '_')*    // 标识符；关键字 let/in 除外
  符号    ::= '+' | '-' | '*' | '/' | '(' | ')' | '='

语法（优先级自低到高）：
  expr ::= "let" IDENT "=" expr "in" expr     // let 绑定（作用域最外）
         | add
  add  ::= mul (("+" | "-") mul)*             // 加减，左结合
  mul  ::= atom (("*" | "/") atom)*           // 乘除，左结合，优先级更高
  atom ::= INT | IDENT | "(" expr ")"
```

流水线：`lex`（源串 → 词法单元）→ `parse`（词法单元 → `Ast`）→ `check`
（`Ast` → `TypedAst`，含作用域检查）→ `eval`（`TypedAst` → `Value`）；
`print_ast` 为 `parse` 的逆向打印器，支撑「打印再解析」往返。

---

## 示例 1 · 端到端流程：源码 → 词法 → AST → 类型检查 → 求值

下例完整走通四个阶段。`1 + 2 * 3` 中乘除优先级高于加减，因此 `parse` 产出的
`Ast` 等价于 `1 + (2 * 3)`（用 `print_ast` 渲染查看树形），最终求值为 `7`。

```mbt check
///|
test "README · 端到端 源码→lex→parse→check→eval" {
  let src = "1 + 2 * 3"
  // 1) 词法分析：源串 → 词法单元序列
  let tokens = match lex(src) {
    Ok(ts) => ts
    Err(d) => fail("lex 失败：\{d.msg}")
  }
  // 5 个词法单元：1 + 2 * 3
  @test.assert_eq(tokens.length(), 5)
  // 2) 语法分析：词法单元 → AST；以 print_ast 渲染查看树形（乘除优先级更高）
  let ast = match parse(tokens) {
    Ok(a) => a
    Err(d) => fail("parse 失败：\{d.msg}")
  }
  inspect(print_ast(ast), content="(1 + (2 * 3))")
  // 3) 类型检查：AST → TypedAst（MiniLet 骨架统一标注 IntT）
  let typed = match check(ast) {
    Ok(t) => t
    Err(d) => fail("check 失败：\{d.msg}")
  }
  // 4) 求值：TypedAst → Value
  match eval(typed) {
    Value::IntV(n) => @test.assert_eq(n, 7)
  }
}
```

---

## 示例 2 · let 绑定求值与词法作用域遮蔽

`let x = e1 in e2` 在 `e1` 的求值结果上将 `x` 绑定，并在该绑定可见的作用域内
求值 `e2`；内层同名绑定遮蔽外层。下例演示绑定查找、被绑定表达式可见外层作用域，
以及内层 `let` 遮蔽。

```mbt check
///|
test "README · let 绑定求值与遮蔽" {
  // 求值助手：源串 → lex → parse → check → eval，返回整数结果。
  fn run(src : String) -> Int {
    let tokens = match lex(src) {
      Ok(ts) => ts
      Err(d) => abort("lex 失败：\{d.msg}")
    }
    let ast = match parse(tokens) {
      Ok(a) => a
      Err(d) => abort("parse 失败：\{d.msg}")
    }
    let typed = match check(ast) {
      Ok(t) => t
      Err(d) => abort("check 失败：\{d.msg}")
    }
    match eval(typed) {
      Value::IntV(n) => n
    }
  }

  // 基础绑定与变量查找：x 绑定为 2，x * x = 4
  @test.assert_eq(run("let x = 2 in x * x"), 4)
  // 被绑定表达式可见外层作用域：y = x + 1 = 4，x * y = 12
  @test.assert_eq(run("let x = 3 in let y = x + 1 in x * y"), 12)
  // 内层 let 遮蔽外层同名绑定：内层 x = 10，x + 1 = 11
  @test.assert_eq(run("let x = 1 in let x = 10 in x + 1"), 11)
}
```

---

## 示例 3 · print_ast 往返：parse ∘ print 还原同一 AST

`print_ast` 将 `Ast` 打印回 MiniLet 源串（二元运算完全括号化，与优先级无关），
对其重新 `lex` + `parse` 必然还原**同一**语法树。这正是任务 15.3「Property 1：
AST 往返」所依赖的互逆性质。

```mbt check
///|
test "README · print_ast 往返还原同一 AST" {
  let src = "let x = 1 in x + 2 * 3"
  // 首次解析得到 AST
  let ast1 = match
    parse(
      match lex(src) {
        Ok(ts) => ts
        Err(d) => fail("lex 失败：\{d.msg}")
      },
    ) {
    Ok(a) => a
    Err(d) => fail("parse 失败：\{d.msg}")
  }
  // 打印为规范源串：二元运算完全括号化，let 按文法形态打印
  let printed = print_ast(ast1)
  inspect(printed, content="let x = 1 in (x + (2 * 3))")
  // 对打印结果重新 lex + parse，应还原等价 AST
  let ast2 = match
    parse(
      match lex(printed) {
        Ok(ts) => ts
        Err(d) => fail("lex 失败：\{d.msg}")
      },
    ) {
    Ok(a) => a
    Err(d) => fail("parse 失败：\{d.msg}")
  }
  // 派生 Eq 比较：往返前后结构相等（无需构造枚举）
  assert_true(ast1 == ast2)
}
```

---

## 示例 4 · 含位置的诊断：词法 / 语法 / 类型错误

流水线各阶段在出错时返回 `Diagnostic`（携带类别 `kind` 与行列 `line` / `col`），
且**不**产生后续产物（R1.3 / R1.5）。下例分别触发三类错误并校验其类别与位置 /
消息。

```mbt check
///|
test "README · 词法/语法/类型错误的含位置诊断" {
  // (a) 词法错误：非法字符 '@' 定位到行 1 列 3，且不产生词法单元
  match lex("a @ b") {
    Ok(_) => fail("期望词法错误")
    Err(d) => {
      assert_true(d.kind == DiagKind::LexError)
      @test.assert_eq(d.line, 1)
      @test.assert_eq(d.col, 3)
    }
  }

  // (b) 语法错误：未闭合括号 → SyntaxError，消息提示期望 ')'
  let unbalanced = match lex("(1 + 2") {
    Ok(ts) => ts
    Err(d) => fail("lex 失败：\{d.msg}")
  }
  match parse(unbalanced) {
    Ok(_) => fail("期望语法错误")
    Err(d) => {
      assert_true(d.kind == DiagKind::SyntaxError)
      inspect(d.msg, content="期望 ')'")
    }
  }

  // (c) 类型错误：自由变量（未绑定）→ TypeError，消息标注出错变量名
  let free_var = match
    parse(
      match lex("1 + x") {
        Ok(ts) => ts
        Err(d) => fail("lex 失败：\{d.msg}")
      },
    ) {
    Ok(a) => a
    Err(d) => fail("parse 失败：\{d.msg}")
  }
  match check(free_var) {
    Ok(_) => fail("期望类型错误（自由变量 x）")
    Err(d) => {
      assert_true(d.kind == DiagKind::TypeError)
      assert_true(d.msg.contains("x"))
    }
  }
}
```

---

# MiniML 旗舰前端 · 可执行文档（任务 15.1）

> 上文示例 1~4 覆盖既有 **MiniLet** 骨架（整数算术 + `let`）。本章在其之上**追加**
> 旗舰级 **MiniML** 语言的可执行文档：词法 / 语法、Hindley-Milner 类型推断、
> 树遍历解释器、AST 优化、字节码编译与栈式 VM 执行，以及贯穿全链路的端到端
> 旗舰示例（对应 design.md §「paper-to-code 可追溯与开源对标」与 R9.5 / R11.1~
> R11.5 / R14.3 / R10.4）。
>
> 每段 ` ```mbt check ` 代码块同样被 `moon test` 编译 + 运行，直接调用本包公开
> API（`lex_ml` / `parse_ml` / `print_expr` / `erase_span` / `infer` / `type_of` /
> `eval_ml` / `optimize` / `const_fold` / `dead_let_elim` / `compile_ml` /
> `VM::run` / `run_interp` / `run_compiled` / `run_demo` / `of_minilet` …）。
>
> **断言风格约定**：`Ty` 派生 `Show + Eq`，故主类型既可 `inspect(..., content=...)`
> 也可 `== TyInt` 比较；`Val` 仅派生 `Eq`（无 `Show`），故运行期值统一以
> `assert_true(... == ...)` 比较。多字符算符、span、闭包捕获等细节与同目录
> `*_test.mbt` 黑盒单测一致。

---

## 示例 5 · MiniML 词法 / 语法：`lex_ml` + `parse_ml` + `print_expr` 往返

MiniML 在 MiniLet 基础上扩出布尔、比较 / 逻辑算符、`if`、一等函数（`fun`）、
函数应用与 `let rec`。`lex_ml` 产出携带 `span` 的 `MlToken` 序列，`parse_ml`
递归下降为携带 `span` 的 `Expr`，`print_expr` 完全括号化打印回源串。对打印结果
重新 `lex_ml` + `parse_ml`、去 `span` 后必还原**同一** AST（往返不变式 R2.5）。

```mbt check
///|
test "README · MiniML lex_ml/parse_ml/print_expr 往返" {
  let src = "let f = fun x -> x + 1 in f 10"
  // 1) 词法分析：12 个携带 span 的 MlToken
  let tokens = match lex_ml(src) {
    Ok(ts) => ts
    Err(d) => fail("lex_ml 失败：\{d.msg}")
  }
  @test.assert_eq(tokens.length(), 12)
  // 2) 语法分析：递归下降 + 优先级，得携带 span 的 Expr
  let e1 = match parse_ml(tokens) {
    Ok(e) => e
    Err(d) => fail("parse_ml 失败：\{d.msg}")
  }
  // 3) 完全括号化打印：let/fun/应用均显式括号
  inspect(print_expr(e1), content="(let f = (fun x -> (x + 1)) in (f 10))")
  // 4) 往返：重新 lex+parse 打印结果，去 span 后还原同一 AST（R2.5）
  let e2 = match
    parse_ml(
      match lex_ml(print_expr(e1)) {
        Ok(ts) => ts
        Err(d) => fail("lex_ml 失败：\{d.msg}")
      },
    ) {
    Ok(e) => e
    Err(d) => fail("parse_ml 失败：\{d.msg}")
  }
  assert_true(erase_span(e1) == erase_span(e2))
}
```

---

## 示例 6 · Hindley-Milner 类型推断：`infer` + `type_of`

`infer` 实现 Damas-Milner **Algorithm W**（合一 + let 多态），返回带类型标注的
`TExpr` 与推断出的**主类型**（principal type）。`type_of` 取 `TExpr` 根节点的
类型，必与主类型一致。`let id = fun x -> x in id 3` 把多态恒等函数在 `Int` 处
实例化得 `TyInt`；`1 < 2` 推断为 `TyBool`。

```mbt check
///|
test "README · HM 类型推断 infer/type_of 主类型" {
  // 解析 + 推断助手：失败即中止（样例均为良类型源串）
  fn infer_ml(src : String) -> (TExpr, Ty) {
    let toks = match lex_ml(src) {
      Ok(t) => t
      Err(d) => abort("lex_ml: \{d.msg}")
    }
    let e = match parse_ml(toks) {
      Ok(e) => e
      Err(d) => abort("parse_ml: \{d.msg}")
    }
    match infer(e) {
      Ok(pair) => pair
      Err(d) => abort("infer: \{d.msg}")
    }
  }

  // let 多态恒等函数在 Int 处实例化 => 主类型 TyInt
  let (te_int, ty_int) = infer_ml("let id = fun x -> x in id 3")
  inspect(ty_int, content="TyInt")
  assert_true(type_of(te_int) == ty_int) // type_of 取根节点类型，与主类型一致
  // 比较运算 => 主类型 TyBool
  let (_, ty_bool) = infer_ml("1 < 2")
  inspect(ty_bool, content="TyBool")
}
```

---

## 示例 7 · 树遍历解释器：`eval_ml`

`eval_ml` 在带类型标注的 `TExpr` 上做严格、左到右、确定性求值，产出 `Val`。
闭包捕获**定义处**词法环境，`let rec` 支持自指递归，除零定义为 `0`（全函数）。
下例演示高阶函数 `twice inc` 与递归阶乘。

```mbt check
///|
test "README · 树遍历解释器 eval_ml" {
  // 解析 → 推断 → 求值助手；失败即中止（样例均为良类型）
  fn run(src : String) -> Val {
    let toks = match lex_ml(src) {
      Ok(t) => t
      Err(d) => abort("lex_ml: \{d.msg}")
    }
    let e = match parse_ml(toks) {
      Ok(e) => e
      Err(d) => abort("parse_ml: \{d.msg}")
    }
    match infer(e) {
      Ok((te, _)) => eval_ml(te)
      Err(d) => abort("infer: \{d.msg}")
    }
  }

  // 高阶函数：twice 把 inc 作用两次，inc(inc(10)) = 12
  assert_true(
    run(
      "let twice = fun f -> fun x -> f (f x) in let inc = fun n -> n + 1 in twice inc 10",
    ) ==
    VInt(12),
  )
  // 递归阶乘：fact 5 = 120
  assert_true(
    run(
      "let rec fact = fun n -> if n <= 1 then 1 else n * fact (n - 1) in fact 5",
    ) ==
    VInt(120),
  )
}
```

---

## 示例 8 · AST 优化：`const_fold` / `dead_let_elim` / `optimize`

优化是一组**语义保持**的 `Expr → Expr` 变换：`const_fold` 自底向上折叠常量算术 /
比较 / 逻辑与常量 `if`；`dead_let_elim` 消除 body 中零引用的 `let`；`optimize`
为二者组合。以 `print_expr(erase_span(...))` 观察优化前后形态。

```mbt check
///|
test "README · AST 优化 const_fold/dead_let_elim/optimize" {
  // 解析助手：失败即中止
  fn p(src : String) -> Expr {
    let toks = match lex_ml(src) {
      Ok(t) => t
      Err(d) => abort("lex_ml: \{d.msg}")
    }
    match parse_ml(toks) {
      Ok(e) => e
      Err(d) => abort("parse_ml: \{d.msg}")
    }
  }

  // optimize 把 1 + 2 * 3 常量折叠为单一字面量 7
  @test.assert_eq(print_expr(erase_span(optimize(p("1 + 2 * 3")))), "7")
  // const_fold 折叠常量比较 + 逻辑：(1 < 2) && (3 > 4) => false
  @test.assert_eq(
    print_expr(erase_span(const_fold(p("(1 < 2) && (3 > 4)")))),
    "false",
  )
  // dead_let_elim 移除未使用的 let：let x = 5 in 42 => 42
  @test.assert_eq(
    print_expr(erase_span(dead_let_elim(p("let x = 5 in 42")))),
    "42",
  )
  // optimize 组合：先消除死 let（x 未用）再常量折叠 => 7
  @test.assert_eq(
    print_expr(erase_span(optimize(p("let x = 5 in 1 + 2 * 3")))),
    "7",
  )
}
```

---

## 示例 9 · 字节码编译与栈式 VM 执行：`compile_ml` + `VM::run`

`compile_ml` 把良类型 `TExpr` 降为栈式 `Bytecode`（操作数栈 + 调用帧；闭包以
`MkClosure` / 递归以 `MkRecClosure` 指令实现），`VM::run` 在内存栈式抽象机上
执行得 `Val`。编译—执行路径与树遍历解释器 `eval_ml` 在所有良类型输入上一致
（设计属性 10）。

```mbt check
///|
test "README · 字节码编译 compile_ml 与 VM::run 执行" {
  // 解析 → 推断助手，得良类型 TExpr
  fn te(src : String) -> TExpr {
    let toks = match lex_ml(src) {
      Ok(t) => t
      Err(d) => abort("lex_ml: \{d.msg}")
    }
    let e = match parse_ml(toks) {
      Ok(e) => e
      Err(d) => abort("parse_ml: \{d.msg}")
    }
    match infer(e) {
      Ok((t, _)) => t
      Err(d) => abort("infer: \{d.msg}")
    }
  }

  // 字节码结构：1 + 2 降为 [PushInt 1, PushInt 2, Arith Add]（右操作数在栈顶）
  assert_true(
    compile_ml(te("1 + 2")).instrs == [PushInt(1), PushInt(2), Arith(Add)],
  )
  // 递归阶乘：VM 执行与解释器一致，均为 VInt(120)
  let fact = te(
    "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5",
  )
  assert_true(VM::run(compile_ml(fact), ml_env_empty()) == VInt(120))
  assert_true(VM::run(compile_ml(fact), ml_env_empty()) == eval_ml(fact))
}
```

---

## 示例 10 · 旗舰端到端示例：`run_demo`（阶乘 / 斐波那契）

`run_demo` 跑通完整链路 `lex_ml → parse_ml → infer →(optimize)→ eval_ml` 与
`… → compile_ml → VM::run`，把推断主类型、优化后形态、解释结果与 VM 结果收敛进
`DemoTrace`。旗舰阶乘示例 `demo_factorial_src`（`fact 5`）三者一致：主类型
`TyInt`、解释结果与 VM 结果均为 `VInt(120)`；斐波那契 `demo_fib_src`（`fib 10`）
两路一致为 `VInt(55)`。

```mbt check
///|
test "README · 旗舰端到端 run_demo 三阶段一致" {
  // 阶乘：主类型 TyInt，解释 == VM == VInt(120)（R9.2/R9.3/R9.4）
  let t = run_demo(demo_factorial_src)
  assert_true(t.principal_type == TyInt)
  assert_true(t.interp_result == VInt(120))
  assert_true(t.vm_result == VInt(120))
  assert_true(t.interp_result == t.vm_result)
  // 斐波那契：两路一致为 VInt(55)
  let f = run_demo(demo_fib_src)
  assert_true(f.interp_result == f.vm_result)
  assert_true(f.interp_result == VInt(55))
  assert_true(f.principal_type == TyInt)
}
```

---

## 示例 11 · 统一流水线：`run_interp` 与 `run_compiled` 一致

`run_interp`（解释路径）与 `run_compiled`（编译—执行路径）共享前端
（`lex_ml → parse_ml →(可选)optimize→ infer`），仅尾部后端不同。对相同良类型
输入，两路产出彼此相等的 `PipelineResult`（端到端两路一致，R13.3）；`optimize`
旗标不改变语义。

```mbt check
///|
test "README · 统一流水线 run_interp/run_compiled 一致" {
  // 递归阶乘：两路一致，结果 Produced(VInt(120))
  let src = "let rec f = fun n -> if n <= 1 then 1 else n * f (n - 1) in f 5"
  let ri = run_interp(src)
  let rc = run_compiled(src)
  assert_true(ri == rc)
  assert_true(ri == Produced(VInt(120)))
  // 开启优化后两路仍一致且语义不变：未使用的 let x 不影响 1 + 2 = 3
  let oi = run_interp("let x = 99 in 1 + 2", optimize=true)
  let oc = run_compiled("let x = 99 in 1 + 2", optimize=true)
  assert_true(oi == oc)
  assert_true(oi == Produced(VInt(3)))
}
```

---

## 示例 12 · MiniLet → MiniML 桥：`of_minilet`

既有 MiniLet `Ast`（示例 1~4）通过 `of_minilet` 桥被**无损提升**为 MiniML
`Expr` 子集，从而复用 HM 推断、解释器与字节码后端。下例把 MiniLet 解析所得
`Ast` 提升后推断为 `TyInt` 并求值为 `VInt(7)`，印证两套前端语义贯通。

```mbt check
///|
test "README · MiniLet→MiniML 桥 of_minilet" {
  // 用既有 MiniLet 前端解析为 Ast
  let ast = match
    parse(
      match lex("1 + 2 * 3") {
        Ok(ts) => ts
        Err(d) => fail("lex 失败：\{d.msg}")
      },
    ) {
    Ok(a) => a
    Err(d) => fail("parse 失败：\{d.msg}")
  }
  // 提升为 MiniML Expr，再走 HM 推断与解释器
  let e = of_minilet(ast)
  match infer(e) {
    Ok((te, t)) => {
      assert_true(t == TyInt) // 提升后仍推断为基类型 TyInt
      assert_true(eval_ml(te) == VInt(7)) // 1 + 2 * 3 = 7
    }
    Err(d) => fail("infer 失败：\{d.msg}")
  }
}
```

---

## paper-to-code 可追溯（R11.1 / R11.2）

MiniML 各组件均可追溯至奠基论文与权威教材，实现风格对标《Write You a Haskell》：

| 组件 | 论文 / 教材来源 |
| --- | --- |
| HM 类型推断、Algorithm W | Hindley (1969)、Milner (1978)、Damas & Milner (1982) |
| 合一、occurs-check、幂等替换 | Robinson 合一；Damas-Milner Algorithm W |
| 类型系统与求值模型 | Pierce《Types and Programming Languages》(TAPL) |
| 树遍历解释器、闭包、字节码 VM | Nystrom《Crafting Interpreters》(jlox / clox) |
| 编译链路与栈式代码生成 | Appel《Modern Compiler Implementation》 |
| 整体工程组织与 HM 实现风格 | 《Write You a Haskell》(WYAH) |

## 开源对标（R11.3）

| 维度 | OCaml | Haskell（GHC / WYAH） | Rust 教学编译器 | 本方向 Mini_Compiler |
| --- | --- | --- | --- | --- |
| 类型推断 | HM + 行多态 / 模块 | HM + 类型类 + 约束求解 | 多为单态 / 无 HM | HM / Algorithm W + let 多态（无类型类） |
| 求值 | 编译为原生 / 字节码 | 惰性图归约 | 取决于实现 | 严格、树遍历 + 栈式字节码 VM |
| 编译目标 | 原生 / bytecode | 原生（STG） | 原生 / LLVM | 内存栈式 VM（不生成原生码） |
| 除零 | 异常 | 异常 | panic | 定义为 `0`（全函数、三后端一致） |
| 求值顺序 | 严格 | 惰性 | 严格 | 严格、左到右、确定性 |

## 实现边界声明（R11.4）

Mini_Compiler 是一门**玩具 / 教学语言**的编译器与解释器模型层，停留在
「词法 → 语法 → 类型推断 → 优化 → 求值 / 字节码编译 → 虚拟机执行」抽象层：

- 字节码虚拟机 `VM` 是一台**内存中的栈式抽象机**——以操作数栈与调用帧解释
  `Bytecode` 产出 `Val`。
- **不**生成原生可执行文件、**不**汇编或链接、**不**绑定任何具体指令集架构（ISA）。
- 可选的 wasm 文本（`emit_wat`）/ js 源（`emit_js`）输出仅作为**额外文本后端**，
  仅供展示，**不**保证可被外部工具链消费。

该边界使核心算法（合一、Algorithm W、求值、编译—执行等价）可被属性测试穷尽
校验，且在 `wasm-gc` / `js` / `native` 三后端上行为一致。

## 显式差异声明（R11.5）

- **除零 = 0**：与 OCaml / Haskell / Rust 的异常 / panic 不同，MiniML 定义
  `x / 0 = 0`（沿用 MiniLet `semantics.mbt` 既有约定），以保证 `eval_ml` 为
  **全函数**、求值确定、三后端一致，并使「良类型不卡住」可被属性测试穷尽验证
  （类型安全 / 求值确定性 PBT）。
- **可选特性取舍**：元组（`ETuple`）、beta 化简（`beta_reduce`）、错误恢复、
  文本后端（`emit_wat` / `emit_js`）均为可选能力，默认关闭 / 仅展示，以保持核心
  性质（往返、两路一致、优化保持语义）简单可测。

> **三后端一致性 / 文档校验前置（R10.4 / R14.3）**：在 `native` 后端运行测试或
> 校验本可执行文档前，须先导出库路径
> `export LIBRARY_PATH=/usr/lib64:/usr/lib`，否则 native 链接阶段会因找不到
> 系统库而失败。`wasm-gc` / `js` 后端无需此步。

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/mini_compiler/README.mbt.md

# 三后端一致性（R11.1 / R1.10）：同一文档套件在三后端均须通过
moon test src/mini_compiler/README.mbt.md --target wasm-gc
moon test src/mini_compiler/README.mbt.md --target js
moon test src/mini_compiler/README.mbt.md --target native
```

预期看到全部 12 段可执行测试通过（示例 1~4 覆盖 MiniLet 骨架，示例 5~12 覆盖
MiniML 旗舰前端 / 推断 / 解释器 / 优化 / 字节码 VM / 端到端 / 流水线 / 桥）：

```
Total tests: 12, passed: 12, failed: 0.
```

一旦修改流水线实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并
以最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
