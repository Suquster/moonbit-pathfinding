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
  assert_eq(tokens.length(), 5)
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
    Value::IntV(n) => assert_eq(n, 7)
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
  assert_eq(run("let x = 2 in x * x"), 4)
  // 被绑定表达式可见外层作用域：y = x + 1 = 4，x * y = 12
  assert_eq(run("let x = 3 in let y = x + 1 in x * y"), 12)
  // 内层 let 遮蔽外层同名绑定：内层 x = 10，x + 1 = 11
  assert_eq(run("let x = 1 in let x = 10 in x + 1"), 11)
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
      assert_eq(d.line, 1)
      assert_eq(d.col, 3)
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

预期看到：

```
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改流水线实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并
以最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
