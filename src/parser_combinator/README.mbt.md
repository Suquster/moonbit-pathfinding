# parser_combinator · 可执行文档

> **方向四（R4）解析器组合子库** — 可组合原语 · 三后端一致 · 文档即测试。
>
> 本文件既是 `parser_combinator` 子包的使用说明，**也是**一份可执行测试脚本：
> 每段 ` ```mbt check ` 代码块都会被 `moon test src/parser_combinator/README.mbt.md`
> 编译 + 运行 + 快照校验。文档与实现一旦漂移，构建立即失败。

---

## 为什么是这份文档？

[Markdown-Oriented Programming](https://www.moonbitlang.com/blog/moonbit-markdown)
是 MoonBit 独占特性：放进 `.mbt.md` 的代码块会被 `moon test` 当作 black-box 测试
编译执行。对应需求 **R4.7（≥3 个端到端解析样例）** 与 **R11.4（可执行文档门禁）**，
tasks.md **任务 5.5**。

本文件作为 `parser_combinator` 包的黑盒测试运行，因此可直接调用本包公开 API
（`pchar` / `satisfy` / `seq` / `alt` / `many` / `many1` / `optional` 等）而无需限定包名。
下面 4 段示例覆盖 **序列（seq）/ 择一（alt）/ 重复（many、many1）** 三类组合子的端到端解析。

> **关于代码围栏**：可执行代码块均以 ` ```mbt check ` 开头，这是 MoonBit toolchain
> 识别可运行代码块的标记；块首的 `///|` 是 top-level marker，用于声明该段为一个独立条目。

---

## 示例 1 · 序列组合 seq —— 按顺序消费输入前缀

`seq(a, b)` 先运行 `a`，成功后在其剩余输入上运行 `b`，两者皆成功时产出二元组
`(va, vb)` 并携带剩余未消费输入（满足 **R4.2**）。下例顺序匹配字符 `'a'`、`'b'`，
解析 `"abc"` 得到 `('a', 'b')`，剩余输入停在 `'c'`。

```mbt check
///|
test "README · seq 按顺序消费并配对结果" {
  let p = seq(pchar('a'), pchar('b'))
  let result = p.parse_string("abc")
  assert_true(result.is_ok())
  // 产出二元组 (va, vb)
  assert_true(result.value() == Some(('a', 'b')))
  // 剩余未消费输入停在 'c'（R4.2：返回解析结果与剩余输入）
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some('c'))
    None => fail("expected remaining input")
  }
}
```

---

## 示例 2 · 择一组合 alt —— 多分支择一并回溯

`alt(ps)` 按顺序尝试每个分支，返回首个成功结果；全部失败时在分支起始位置返回
失败、汇总各分支期望符号且**不消费输入**（满足 **R4.3 / R4.4**）。下例匹配三种运算符
字符之一，并演示全部分支失败时的含位置错误。

```mbt check
///|
test "README · alt 择一匹配并在全失败时报告位置" {
  let op = alt([pchar('+'), pchar('-'), pchar('*')])
  // 命中靠后分支
  assert_true(op.parse_string("-x").value() == Some('-'))
  assert_true(op.parse_string("*y").value() == Some('*'))
  // 全部分支失败：定位到分支起点 1:1，汇总期望符号，且不消费输入（R4.3）
  let miss = op.parse_string("/z")
  match miss {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      assert_true(expected == ["'+'", "'-'", "'*'"])
    }
    Ok(_, _) => fail("expected failure")
  }
}
```

---

## 示例 3 · 重复组合 many —— 零次或多次贪婪收集

`many(p)` 尽可能多地重复应用 `p` 并收集全部产出，遇首个失败即停止；零次匹配
也成功（返回空数组且不消费输入），故 `many` 永不失败。下例用 `satisfy` 构造数字
原语，连续收集 `"2026 osc"` 开头的数字序列。

```mbt check
///|
test "README · many 贪婪收集数字序列（含零次匹配）" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  let p = many(digit)
  // 收集前缀 "2026"，剩余停在空格
  let result = p.parse_string("2026 osc")
  assert_true(result.value() == Some(['2', '0', '2', '6']))
  match result.rest() {
    Some(rest) => assert_true(rest.peek() == Some(' '))
    None => fail("expected remaining input")
  }
  // 零次匹配：无数字时成功返回空数组且不消费输入
  let none_match = p.parse_string("osc")
  assert_true(none_match.is_ok())
  let empty : Array[Char] = []
  assert_true(none_match.value() == Some(empty))
}
```

---

## 示例 4 · 重复组合 many1 + seq —— 端到端解析带井号编号

`many1(p)` 与 `many` 类似但要求至少成功一次；首次即失败时返回含位置与期望符号
的错误（**R4.3**）。下例把 `seq` 与 `many1` 组合成一个端到端解析器，解析形如
`"#123"` 的带井号编号：`'#'` 后跟随至少一位数字；并演示 `'#'` 后缺失数字时的失败诊断。

```mbt check
///|
test "README · seq + many1 端到端解析带井号编号" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  // '#' 后跟随 1 个或多个数字
  let numbered = seq(pchar('#'), many1(digit))
  let ok = numbered.parse_string("#123;")
  assert_true(ok.is_ok())
  match ok.value() {
    Some((hash, digits)) => {
      assert_eq(hash, '#')
      assert_true(digits == ['1', '2', '3'])
    }
    None => fail("expected parsed value")
  }
  // 剩余输入停在分隔符 ';'
  match ok.rest() {
    Some(rest) => assert_true(rest.peek() == Some(';'))
    None => fail("expected remaining input")
  }
  // many1 至少一次：'#' 后无数字时失败，定位到第 2 列并报告期望"数字"（R4.3）
  let bad = numbered.parse_string("#x")
  match bad {
    Fail(pos, expected~) => {
      inspect(pos, content="1:2")
      assert_true(expected == ["数字"])
    }
    Ok(_, _) => fail("expected failure")
  }
}
```

---

## 验证方式

```bash
# native 后端测试前先导出库路径
export LIBRARY_PATH=/usr/lib64:/usr/lib

# 在项目根目录执行（默认 wasm-gc 后端）
moon test src/parser_combinator/README.mbt.md

# 三后端一致性（R11.1 / R4.8）：同一文档套件在三后端均须通过
moon test src/parser_combinator/README.mbt.md --target wasm-gc
moon test src/parser_combinator/README.mbt.md --target js
moon test src/parser_combinator/README.mbt.md --target native
```

预期看到：

```
Total tests: 4, passed: 4, failed: 0.
```

（示例 1~4 的 4 段可执行测试全部通过。）一旦修改组合子实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并以
最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
