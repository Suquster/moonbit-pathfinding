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
      @test.assert_eq(what, "(")
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

## 旗舰深化能力（捕获 · 惰性 · 断言 · 标志 · 搜索 · demo）

> 以下示例使用旗舰深化新增的高层 API，与既有 `parse_regex`/`find` **并行存在、
> 严格向后兼容**（既有签名与语义冻结，新能力旁路扩展）。核心入口：
>
> * `parse_pattern(pattern, flags~) -> Result[Ast, ParseError]` —— 支持捕获 / 命名 /
>   非捕获组、惰性后缀、`\b`/`\B`、前瞻、预定义类 `\d\w\s`、标志的新解析器；
> * `Pattern::compile(pattern, flags~, kind~) -> Result[Pattern, ParseError]` —— 编译
>   句柄，宿主 `is_match`/`find`/`captures`/`find_all`/`replace`/`replace_all`/`split`；
> * `MatchKind`（`LeftmostLongest` 默认 / `LeftmostFirst`）、`Flags`（`i`/`m`/`s`）、
>   `Captures`（`group`/`name`/`group_count`）。

---

## 示例 5 · 捕获组 —— 编号 / 命名 / 非捕获

`Pattern::captures` 返回整体匹配（第 0 组）与各捕获组区间。捕获组按左括号源
顺序从 1 编号；`(?:...)` 非捕获组**不占编号**；`(?<name>...)` 既分配编号又登记
名称，可经 `Captures::name` 检索（**R1.1/1.2/1.3/1.4**）。

```mbt check
///|
test "README · 捕获组：编号 / 命名 / 非捕获" {
  let p = match
    Pattern::compile("(?<user>[a-z]+)@(?:[a-z]+)\\.(?<tld>[a-z]+)") {
    Ok(v) => v
    Err(_) => fail("expected successful compile")
  }
  match p.captures("bob@example.com") {
    Some(caps) => {
      // 第 0 组：整体匹配 [0,15)
      assert_true(caps.group(0) == Some({ start: 0, end: 15 }))
      // 第 1 组 = 命名 user = "bob" [0,3)，编号与命名检索一致
      assert_true(caps.group(1) == Some({ start: 0, end: 3 }))
      assert_true(caps.name("user") == caps.group(1))
      // (?:...) 非捕获组不占编号；第 2 组 = 命名 tld = "com" [12,15)
      assert_true(caps.group(2) == Some({ start: 12, end: 15 }))
      assert_true(caps.name("tld") == caps.group(2))
      // 含第 0 组共 3 组（非捕获组未计入）
      @test.assert_eq(caps.group_count(), 3)
    }
    None => fail("expected captures")
  }
}
```

---

## 示例 6 · 惰性量词 —— 贪婪 vs 惰性（LeftmostFirst）

惰性量词 `*?`/`+?`/`??`/`{m,n}?` 在不破坏整体匹配的前提下尽可能**少**匹配，与
贪婪量词共存。两者差异在 `LeftmostFirst`（PCRE/Perl）策略下最显著（**R3.1/3.2/3.3**）。

```mbt check
///|
test "README · 惰性量词：a+ 取最长、a+? 取最短" {
  let greedy = match Pattern::compile("a+", kind=LeftmostFirst) {
    Ok(v) => v
    Err(_) => fail("compile a+ failed")
  }
  let lazy_pat = match Pattern::compile("a+?", kind=LeftmostFirst) {
    Ok(v) => v
    Err(_) => fail("compile a+? failed")
  }
  // 贪婪取最长 [0,3)
  assert_true(greedy.find("aaa") == Some({ start: 0, end: 3 }))
  // 惰性取最短 [0,1)
  assert_true(lazy_pat.find("aaa") == Some({ start: 0, end: 1 }))
}
```

---

## 示例 7 · 零宽断言 —— 词边界与前瞻

`\b`/`\B` 与前瞻 `(?=p)`/`(?!p)` 均**不消费字符**（零宽）。词边界在词 / 非词
过渡处成立（串首前 / 串尾后视为非词）；前瞻只在当前位置锚定校验后续而不并入
匹配区间（**R5.1/5.2/5.4/5.5**）。

```mbt check
///|
test "README · 零宽断言：词边界 \\b 与正向前瞻 (?=...)" {
  // 词边界：串首前视为非词，故 "a" 命中、"ba" 不命中
  let wb = match Pattern::compile("\\ba") {
    Ok(v) => v
    Err(_) => fail("compile \\ba failed")
  }
  assert_true(wb.find("a") == Some({ start: 0, end: 1 }))
  assert_true(wb.find("ba") == None)
  // 正向前瞻：'a' 后须为 'b'，但 'b' 不并入匹配 → [0,1)
  let la = match Pattern::compile("a(?=b)") {
    Ok(v) => v
    Err(_) => fail("compile a(?=b) failed")
  }
  assert_true(la.find("ab") == Some({ start: 0, end: 1 }))
  assert_true(la.find("ac") == None)
}
```

---

## 示例 8 · 字符类与编译标志 —— `\d` / `i` / `s`

预定义类 `\d\w\s` 与标志 `i`（大小写不敏感）、`s`（dotall，点号含换行）、`m`
（多行锚点）均统一规约为 `CharSet` 区间运算（**R6.1/6.2/6.3/6.4**）。

```mbt check
///|
test "README · 字符类与标志：\\d / i / s" {
  // 预定义类 \d：在 "ab123cd" 中匹配 "123" → [2,5)
  let digits = match Pattern::compile("\\d+") {
    Ok(v) => v
    Err(_) => fail("compile \\d+ failed")
  }
  assert_true(digits.find("ab123cd") == Some({ start: 2, end: 5 }))
  // i 标志：大小写不敏感
  let ci = match Pattern::compile("abc", flags=Flags::parse("i")) {
    Ok(v) => v
    Err(_) => fail("compile abc/i failed")
  }
  assert_true(ci.is_match("ABC"))
  // s 标志：点号匹配换行；未启用时不匹配换行
  let dot_s = match Pattern::compile(".", flags=Flags::parse("s")) {
    Ok(v) => v
    Err(_) => fail("compile ./s failed")
  }
  assert_true(dot_s.is_match("\n"))
  let dot = match Pattern::compile(".") {
    Ok(v) => v
    Err(_) => fail("compile . failed")
  }
  assert_true(!dot.is_match("\n"))
}
```

---

## 示例 9 · 高层搜索 API —— find_all / split / replace_all

高层 API 直接完成扫描、抽取、切分与替换；替换文本可引用 `$1..$9`、`${name}`、
`$$`（字面 `$`）（**R8.1/8.5/8.6/8.7**）。

```mbt check
///|
test "README · 高层搜索：find_all / split / replace_all 引用捕获" {
  let comma = match Pattern::compile(",") {
    Ok(v) => v
    Err(_) => fail("compile , failed")
  }
  // find_all 不重叠枚举（"a,b,c" 有 2 个逗号）
  @test.assert_eq(comma.find_all("a,b,c").length(), 2)
  // split 以匹配为分隔切分
  let parts = comma.split("a,b,c")
  @test.assert_eq(parts.length(), 3)
  @test.assert_eq(parts[1], "b")
  // replace_all 引用编号组：交换 (a)(b)
  let pair = match Pattern::compile("(a)(b)") {
    Ok(v) => v
    Err(_) => fail("compile (a)(b) failed")
  }
  @test.assert_eq(pair.replace_all("abab", "$2$1"), "baba")
  // replace_all 引用命名组
  let named = match Pattern::compile("(?<x>a)(?<y>b)") {
    Ok(v) => v
    Err(_) => fail("compile named failed")
  }
  @test.assert_eq(named.replace_all("ab", "${y}${x}"), "ba")
}
```

---

## 示例 10 · 实战 demo —— ISO 日期捕获与重排替换

`demo_*` 实战正则集贯穿文档与基准。下例以 `demo_iso_date()` 演示命名捕获与
`replace_all` 引用命名组重排（**R11.2/11.3**）。

```mbt check
///|
test "README · 实战 demo：ISO 日期命名捕获与重排" {
  let p = match Pattern::compile(demo_iso_date()) {
    Ok(v) => v
    Err(_) => fail("compile demo_iso_date failed")
  }
  match p.captures("2026-06-12") {
    Some(caps) => {
      assert_true(caps.name("year") == Some({ start: 0, end: 4 }))
      assert_true(caps.name("month") == Some({ start: 5, end: 7 }))
      assert_true(caps.name("day") == Some({ start: 8, end: 10 }))
    }
    None => fail("expected captures for iso date")
  }
  // 命名引用重排为 day/month/year
  @test.assert_eq(
    p.replace_all("2026-06-12", "${day}/${month}/${year}"),
    "12/06/2026",
  )
}
```

---

## 实现边界与开源对标（RE2 / Rust `regex` / PCRE）

本库与 **Google RE2**、**Rust `regex`** 同侧：以放弃反向引用换取**最坏
情形线性时间**保证，**无回溯指数爆炸**。显式声明的实现边界（**R5.6/R10.5/R10.6**）：

* **环视 `(?=...)`/`(?!...)`/`(?<=...)`/`(?<!...)`** 仅在 **Pike VM 执行路径**
  可用；纯 DFA / 惰性 DFA 快路径**不支持环视**（无法折叠进有限状态转移表），
  故含环视的模式不参与「五路差分一致」，仅由 Pike VM 求值。后顾以翻转
  子程序自锚点向左反向扫描（支持变长体），保持线性时间。
* **捕获不跨环视边界导出**：环视内的捕获组不写回外层 `Captures`（与 RE2 对
  lookaround 的保守策略一致）。
* **不支持反向引用（backreference）**：需要回溯、破坏线性保证；
  解析期对明确不支持的构造报含位置的 `ParseError`，而非静默接受。
* **Unicode 折叠**：以 ASCII 大小写折叠为主，Unicode 简单折叠为声明边界。

| 维度 | 本库 | RE2 | Rust `regex` | PCRE |
|---|---|---|---|---|
| 匹配复杂度 | 线性（Pike VM / DFA） | 线性 | 线性 | 可指数（回溯） |
| 匹配策略 | LL 默认 + LF 可选 | LL / LF | LF | LF |
| 捕获子匹配 | 支持（Pike VM 寄存器） | 支持 | 支持 | 支持 |
| 前瞻 | Pike VM 支持，捕获不跨界 | 不支持 | 不支持 | 支持 |
| 后顾 | Pike VM 支持（含变长体，反向扫描） | 不支持 | 不支持 | 支持 |
| 反向引用 | 不支持（显式报错） | 不支持 | 不支持 | 支持 |

算法 paper-to-code 可追溯：NFA 构造（Thompson 1968）、子集构造、DFA 最小化
（Hopcroft 1971）、线性时间匹配 + 捕获（Russ Cox / Pike VM）、最左最长（POSIX）。

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
Total tests: 10, passed: 10, failed: 0.
```

（示例 1~10 的 10 段可执行测试全部通过。）一旦修改解析/匹配实现使其输出与本文档的
`inspect(..., content="...")` 快照或 `assert_*` 断言不符，`moon test` 会立即报错并以
最小化差异提示同步更新文档——这正是 MoonBit 独占的**文档即测试**体验。

---

## License

Apache-2.0 © 2026 Suquster. See [LICENSE](../../LICENSE).
