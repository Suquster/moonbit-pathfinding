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
      @test.assert_eq(hash, '#')
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

## 示例 5 · 核心代数 map / bind / pure —— 单子风格组合

L0 代数核心层提供 `pure`（不消费输入恒成功）、`map`（变换产出值并保持消费量）、
`bind`（依赖式串联）。这是对标 Haskell `parsec` 单子接口的地基
（Hutton & Meijer 1998《Monadic Parser Combinators》）。

```mbt check
///|
test "README · 核心代数 map / bind / pure" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  // map：把数字字符变换为其数值
  let to_int = map(digit, fn(c) { c.to_int() - '0'.to_int() })
  assert_true(to_int.parse_string("7").value() == Some(7))
  // pure：不消费输入、恒成功、携带给定值
  assert_true(pure(42).parse_string("abc").value() == Some(42))
  // bind：读一个字符，要求其后紧随同一字符（依赖前驱产出值）
  let doubled = bind(any_char(), fn(c) { pchar(c) })
  assert_true(doubled.parse_string("aa").is_ok())
  assert_false(doubled.parse_string("ab").is_ok())
}
```

---

## 示例 6 · 衍生组合子 sep_by / between / chainl1 —— 高层结构

衍生组合子让列表、括号包裹与带优先级的运算符表达式可直接表达，无需手写递归。
`chainl1` 以左结合折叠操作数序列（Hutton & Meijer 1998 §chainl）。

```mbt check
///|
test "README · 衍生组合子 sep_by / between / chainl1" {
  let digit = satisfy(fn(c) { c >= '0' && c <= '9' }, label="数字")
  let number = map(many1(digit), fn(chars) {
    let mut n = 0
    for c in chars {
      n = n * 10 + (c.to_int() - '0'.to_int())
    }
    n
  })
  // sep_by：以逗号分隔收集数字
  assert_true(
    sep_by(number, pchar(',')).parse_string("1,2,3").value() == Some([1, 2, 3]),
  )
  // between：仅产出括号内主体
  assert_true(
    between(pchar('('), number, pchar(')')).parse_string("(42)").value() ==
    Some(42),
  )
  // chainl1：左结合减法 8-3-2 == (8-3)-2 == 3
  let sub = map(pchar('-'), fn(_c) { fn(a : Int, b : Int) -> Int { a - b } })
  assert_true(chainl1(number, sub).parse_string("8-3-2").value() == Some(3))
}
```

---

## 示例 7 · 错误处理 —— label 与最远失败（farthest-failure）

`label`（`<?>`）在起始位置失败时以友好名称替换期望符号；`alt` 在多分支失败时
报告推进得**最远**的失败点（对标 Parsec 的错误模型，Leijen & Meijer）。

```mbt check
///|
test "README · 错误处理 label 与最远失败" {
  // label：在起始位置失败时用名称替换期望
  match label(pchar('x'), "标识符").parse_string("abc") {
    Fail(pos, expected~) => {
      inspect(pos, content="1:1")
      assert_true(expected == ["标识符"])
    }
    Ok(_, _) => fail("expected failure")
  }
  // alt 最远失败：分支二在 offset 1 失败（推进更远），故报告 1:2
  let deep = map(seq(pchar('a'), pchar('b')), fn(_p) { '!' })
  match alt([pchar('z'), deep]).parse_string("ax") {
    Fail(pos, expected~) => {
      inspect(pos, content="1:2")
      assert_true(expected == ["'b'"])
    }
    Ok(_, _) => fail("expected failure")
  }
  // to_path_error：桥接为 @core.PathError
  assert_true(pchar('x').parse_string("y").to_path_error() is Some(_))
}
```

---

## 示例 8 · 旗舰示例 JSON —— 递归结构 / 转义 / 往返 / 恢复

`parse_json` 解析完整 JSON 文法（对象/数组/字符串/数值/布尔/null），解码全部
转义序列；`print_json` 与之互为逆（往返）；`parse_json_recover` 在数组元素语法
错误时同步到下一分隔符继续解析。

```mbt check
///|
test "README · 旗舰示例 JSON 解析 / 转义 / 往返 / 恢复" {
  // 解析嵌套结构
  match parse_json("{\"name\":\"kiro\",\"tags\":[1,2,3],\"ok\":true}") {
    Ok(JObject(pairs)) => @test.assert_eq(pairs.length(), 3)
    _ => fail("expected object")
  }
  // 转义解码：\n 解码为换行
  match parse_json("\"line1\\nline2\"") {
    Ok(JString(s)) => assert_true(s == "line1\nline2")
    _ => fail("expected string")
  }
  // 往返：parse → print → reparse，规范化打印形式稳定（parse(print(x)) ≡ x）
  match parse_json("[1,false,null]") {
    Ok(v) => {
      let printed = print_json(v)
      match parse_json(printed) {
        Ok(v2) => assert_true(print_json(v2) == printed)
        Err(_) => fail("re-parse failed")
      }
    }
    Err(_) => fail("parse failed")
  }
  // 错误恢复：跳过非法元素 @@@ 继续解析 1 与 3
  let (recovered, errors) = parse_json_recover("[1,@@@,3]")
  assert_true(recovered is Some(_))
  assert_true(errors.length() >= 1)
}
```

---

## 示例 9 · 旗舰示例 算术求值器 —— 优先级与左/右结合

`parse_and_eval` 按运算符优先级与结合性求值中缀算术表达式：`+ -`/`* /` 左结合
（`chainl1`）、`^` 右结合（`chainr1`）。

```mbt check
///|
test "README · 旗舰示例 算术优先级与结合性" {
  // 乘高于加
  assert_true(parse_and_eval("2+3*4") == Ok(14.0))
  // 左结合减法
  assert_true(parse_and_eval("8-3-2") == Ok(3.0))
  // 右结合幂：2^(3^2) == 2^9 == 512
  assert_true(parse_and_eval("2^3^2") == Ok(512.0))
  // 括号改变优先级
  assert_true(parse_and_eval("(2+3)*4") == Ok(20.0))
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
Total tests: 9, passed: 9, failed: 0.
```

（示例 1~9 的 9 段可执行测试全部通过。）一旦修改组合子实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并以
最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## 论文可追溯（paper-to-code）与开源对标

本库的关键算法均可追溯到经典文献，并相对主流开源库显式声明语义差异。

### Paper-to-code 对照

| 设计构造 | 论文出处 | 对应实现 |
|---|---|---|
| `pure` / `map` / `bind` / `ap`、`chainl1` / `chainr1` 单子风格折叠 | Hutton & Meijer 1998《Monadic Parser Combinators》 | `algebra.mbt`、`derived.mbt` |
| 消费提交语义（`commit` / `cut`）、最远失败 + 期望合并错误模型、`label`（`<?>`） | Leijen & Meijer 的 Parsec 设计 | `commit.mbt`、`error_model.mbt`、`combinators.mbt`（`alt`） |
| PEG 有序选择（首个成功即提交）、packrat 记忆化（位置 × 规则缓存 → 线性时间） | Ford 2002《Parsing Expression Grammars》 / packrat 论文 | `combinators.mbt`（`alt`）、`packrat.mbt` |
| 直接左递归 seed-growing（失败种子 + 迭代增长） | Warth et al. 2008《Packrat Parsers Can Support Left Recursion》 | `left_recursion.mbt` |

### 与 Haskell `parsec` / `megaparsec` 及 Rust `nom` 的对比

- **回溯默认行为**：`parsec` / `megaparsec` 默认**不**回溯已消费输入的分支（择一仅在
  前一分支未消费时回退），需以 `try` 显式开启回溯；`nom` 默认基于消费的可回溯组合子。
  本库的 L0 `alt` 默认**总是**从同一不可变游标重试每个分支（PEG 风格的完全回溯），
  更贴近 PEG / packrat 语义；当需要「一旦进入即不回退」的硬失败时，使用 L1 的
  `commit` + `choice`（对应 `parsec` 默认的不回溯 + `try` 反向开关的语义取舍）。
- **提交语义**：`megaparsec` 以是否消费输入 + `try` 表达提交；本库以显式 `commit` / `cut`
  把软失败提升为硬失败，`choice` 据此停止回溯（更接近 `nom` 的 `cut`/`Err::Failure`）。
- **错误模型**：`parsec` / `megaparsec` 采用最远失败位置 + 期望集合合并；本库的 `alt`
  同样报告最远失败点并合并该点期望（去重保序），`label`（`<?>`）在起始位置失败时替换
  期望符号。`nom` 的错误模型以错误种类链为主，本库则以「位置 + 期望集合」为中心。

### 显式差异声明（R13.6）

1. **仅支持直接左递归**：`left_recursive` 以 Warth 2008 seed-growing 支持形如
   `A := A op b | b` 的**直接**左递归；间接 / 相互左递归不在本库范围内（与 `parsec`
   一致地不支持左递归，但本库额外提供直接左递归入口）。
2. **`alt` 失败诊断精化**：相对 `0.1.0`，`alt` 在全分支失败时由「报告分支起点 + 拼接全部
   期望」精化为「报告最远失败点 + 仅合并该点期望（去重保序）」。这是唯一可观察的行为
   精化（严格信息增益：位置不早于原值、期望更聚焦），签名与成功路径行为不变，故版本
   推进为次版本 `0.2.0`。
3. **期望集合顺序**：采用**去重并保留首次出现顺序**的确定性归一，而非字典序重排——
   既满足确定性（同输入重复解析逐元素一致），又保持 `0.1.0` 既有的「按分支顺序汇总」
   可观察顺序（向后兼容）。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
