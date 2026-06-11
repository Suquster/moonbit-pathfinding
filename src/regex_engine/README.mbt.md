# regex_engine · 可执行文档

> **方向二（R2）正则表达式引擎** — 解析 · 匹配 · 区间返回 · 三后端一致 · 文档即测试。
>
> 本文件既是 `regex_engine` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/regex_engine/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R11.4（可执行文档门禁）**，tasks.md **任务 6.6**。

本文件作为 `regex_engine` 包的黑盒测试运行，因此可直接调用本包公开 API
（`parse_regex` / `print_regex` / `find` / `is_match` 等）而无需限定包名。
下面 4 段示例覆盖**解析正则、打印往返、匹配成功/失败、返回匹配区间**与
**非法表达式的含位置错误**，串起 `syntax → parser → nfa → dfa → matcher` 完整流水线。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。

---

## 数据模型速览

* `parse_regex(s : String) -> Result[Regex, ParseError]` —— 解析正则文本为语法树；
  非法表达式返回**含字符偏移位置**的 `ParseError`，且不构造自动机（**R2.3**）。
* `print_regex(r : Regex) -> String` —— 语法树打印器，与 `parse_regex` 互逆。
* `find(r : Regex, input : String) -> Match?` —— 最左最长匹配，命中时返回匹配区间
  `Match{ start, end }`（半开区间 `[start, end)`），无匹配返回 `None`（**R2.5**）。
* `is_match(r : Regex, input : String) -> Bool` —— 仅判定是否存在匹配的便捷入口。

---

## 示例 1 · 解析正则并打印 —— parse_regex + print_regex 往返

`parse_regex` 把正则文本解析为 `Regex` 语法树（**R2.2**）。下例解析 `"a(b|c)*"`：
顶层为 `a` 与分组 `(b|c)` 的 Kleene 星号的串接。`print_regex` 再把语法树打印回
等价文本，二者互逆（往返自洽，为 Property 4 奠基）。

```mbt check
///|
test "README · parse_regex 解析为语法树并 print_regex 往返" {
  match parse_regex("a(b|c)*") {
    Ok(r) => {
      // print_regex 把语法树打印回等价的规范文本
      inspect(print_regex(r), content="a(b|c)*")
      // print_regex 与 parse_regex 互逆：打印结果重新解析得到等价语法树
      assert_true(parse_regex(print_regex(r)) == Ok(r))
    }
    Err(_) => fail("expected successful parse")
  }
}
```

---

## 示例 2 · 匹配成功与失败 —— is_match 判定存在性

`is_match` 在输入中搜索是否存在正则的匹配，返回布尔值。下例用择一
`"cat|dog"` 演示命中（输入含 `dog`）与不命中（输入不含任何分支）两种情形。

```mbt check
///|
test "README · is_match 判定匹配成功与失败" {
  let r = match parse_regex("cat|dog") {
    Ok(v) => v
    Err(_) => fail("expected successful parse")
  }
  // 匹配成功：输入中存在分支 "dog"
  assert_true(is_match(r, "my dog barks"))
  // 匹配成功：另一分支 "cat"
  assert_true(is_match(r, "a cat sleeps"))
  // 匹配失败：两个分支均不出现
  assert_true(!is_match(r, "a bird flies"))
}
```

---

## 示例 3 · 返回匹配区间 —— find 的最左最长语义

`find` 命中时返回匹配区间 `Match{ start, end }`，为半开区间 `[start, end)`，
偏移基于输入的 Unicode 标量字符序列（**R2.5**）。下例用 `"[a-c]+"`（一个或多个
`a`/`b`/`c`）在 `"x bca y"` 上演示：跳过前缀直到最左起点，并贪婪取最长区间；
另演示无匹配时返回 `None`。

```mbt check
///|
test "README · find 返回最左最长匹配区间" {
  let r = match parse_regex("[a-c]+") {
    Ok(v) => v
    Err(_) => fail("expected successful parse")
  }
  // 在 "xbca y" 中最左命中起点为索引 1，贪婪吞尽 "bca"，区间 [1,4)
  match find(r, "xbca y") {
    Some(m) => {
      inspect(m.start, content="1")
      inspect(m.end, content="4")
      // 半开区间长度即匹配字符数
      inspect(m.end - m.start, content="3")
    }
    None => fail("expected a match")
  }
  // 无任何 a/b/c：返回 None
  assert_true(find(r, "xyz 123") == None)
}
```

---

## 示例 4 · 非法表达式的含位置错误 —— parse_regex 错误诊断

非法正则不会构造自动机，而是返回携带**字符偏移位置**的 `ParseError`（**R2.3**）。
下例演示未闭合分组 `"(a"`：解析器在缺失 `)` 处报告 `Unbalanced`，并通过
`ParseError::pos` 提取错误位置；另演示量词无作用对象 `"*"` 的 `DanglingQuantifier`。

```mbt check
///|
test "README · 非法表达式返回含位置的解析错误" {
  // 未闭合分组：在偏移 2（输入末尾，缺失 ')'）处报告 Unbalanced("(")
  match parse_regex("(a") {
    Err(Unbalanced(pos~, what~)) => {
      assert_eq(what, "(")
      inspect(pos, content="2")
    }
    _ => fail("expected Unbalanced error")
  }
  // 量词无可作用对象：在偏移 0 处报告 DanglingQuantifier
  match parse_regex("*") {
    Err(e) =>
      match e {
        DanglingQuantifier(pos~) => inspect(pos, content="0")
        _ => fail("expected DanglingQuantifier error")
      }
    Ok(_) => fail("expected parse error")
  }
}
```

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/regex_engine/README.mbt.md

# 三后端一致性（R11.1 / R2.9）：同一文档套件在三后端均须通过
moon test src/regex_engine/README.mbt.md --target wasm-gc
moon test src/regex_engine/README.mbt.md --target js
moon test src/regex_engine/README.mbt.md --target native
```

预期看到：

```
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改解析/匹配实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并以
最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
