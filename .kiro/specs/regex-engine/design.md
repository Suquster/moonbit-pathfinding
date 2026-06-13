# 技术设计文档（Design Document）

## 概述（Overview）

本设计在已发布的 `regex_engine 0.1.0` 骨架之上，做**增量式、严格向后兼容**的旗舰级深化，目标对标 Google RE2、Rust `regex` crate 与 PCRE。核心原则一句话：**既有公开类型与函数（`Regex`/`CharClass`/`ClassItem`/`AnchorKind`/`CharSet`/`Match`/`ParseError`/`Nfa`/`Dfa` 与 `parse_regex`/`print_regex`/`build_nfa`/`to_dfa`/`Nfa::find`/`Dfa::find`/`find`/`is_match`）签名与语义冻结，所有新能力以旁路扩展（新增类型、新增文件、新增方法）的方式提供，绝不改写既有节点语义。**

既有流水线保持不变：

```
syntax(Regex) → parser(parse_regex) → nfa(build_nfa) → dfa(to_dfa) → matcher(find / is_match)
```

旗舰深化在其旁侧新增一条**功能完备流水线**，二者通过「子集投影」桥接以支撑差分一致性验证：

```
pattern(String) ─ parse_pattern ─▶ Ast(富语法树) ─ compile_program ─▶ Program(Pike VM 程序)
                                       │                                    │
                                       │ Ast::of_regex（提升既有 Regex）      ▼
                                       │                                Pike VM 执行（捕获 / 策略 / 断言）
                                       ▼                                    │
                              既有 Regex 子集 ─ build_nfa ─▶ Nfa ─ to_dfa ─▶ Dfa ─ minimize ─▶ 最小化 DFA
                                                              │                         │
                                                              └─ LazyDfa（按需子集构造）  └─（五路差分一致：P2）
```

旗舰能力分八条主线落地：捕获与子匹配、Pike VM 执行引擎、量词贪婪/惰性与匹配策略、零宽断言与字符类增强、DFA 最小化与惰性 DFA、高层搜索 API、可解释性与开源对标、质量门禁。本文档为每条主线给出模块划分、MoonBit 签名级接口、算法说明（paper-to-code）、三后端一致性策略、错误处理与正确性属性。

---

## 架构（Architecture）

### 设计原则与向后兼容契约

1. **冻结即契约**：`types.mbt`/`parser.mbt`/`printer.mbt`/`nfa.mbt`/`dfa.mbt`/`matcher.mbt`/`release.mbt` 中现有的 `pub` 声明，其签名、字段、变体与运行时行为一律不改。`pkg.generated.mbti` 现有条目保持稳定，新增条目仅追加。
2. **旁路扩展**：富语法树 `Ast`、程序 `Program`、`Pike VM`、`Captures`、`Flags`、`MatchKind`、`Pattern`、`LazyDfa`、`Dfa::minimize` 等全部为新增。新增方法挂在既有类型上（如 `Dfa::minimize`）只增不改。
3. **既有解析语义不变**：既有 `parse_regex` 中 `(...)` 仍解析为 **`Group`（仅分组、不捕获）**——因为旧 API 无捕获概念。捕获语义只存在于新解析器 `parse_pattern` 产出的 `Ast` 中。这是「同一括号、两套解析器、互不干扰」的关键。
4. **错误枚举不扩容**：`ParseError` 是 `pub(all) enum`，新增变体会改变其形态，故**不新增变体**；新解析器把「重复组名」「不支持的构造」等映射到既有变体（主要是 `Unexpected(pos~, expected~)`，以 `expected` 负载携带语义提示）。此为刻意取舍（见「设计权衡」）。
5. **infra 复用**：全部新增属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`（每条属性 ≥100 迭代）；发布元数据复用 `@release_meta`，`release_info`/`release_info_with_gates` 语义不变。

### 模块 / 文件划分

下表为 `src/regex_engine/` 下的文件规划。**既有文件**保持冻结，仅可追加新方法所需的 import；**新增文件**承载旗舰能力。

| 文件 | 状态 | 职责 | 主要需求 |
|---|---|---|---|
| `types.mbt` | 冻结 | 既有 `Regex`/`CharClass`/`ClassItem`/`AnchorKind`/`ParseError` | R12.1 |
| `parser.mbt` | 冻结 | 既有 `parse_regex`（`(...)`→`Group`） | R12.2 |
| `printer.mbt` | 冻结 | 既有 `print_regex` | R12.2 |
| `nfa.mbt` | 冻结 | 既有 `CharSet`/`Nfa`/`build_nfa`/`Nfa::find` | R12.1/12.2 |
| `dfa.mbt` | 冻结 | 既有 `Dfa`/`to_dfa`/`Dfa::find` | R12.1/12.2 |
| `matcher.mbt` | 冻结 | 既有 `Match`/`find`/`is_match` | R12.2 |
| `release.mbt` | 冻结 | 既有发布元数据登记 | R12.5 |
| `ast.mbt` | 新增 | 富语法树 `Ast`/`AssertKind`，`Ast::of_regex` 子集提升桥，`print_ast` | R1/R3/R5 |
| `flags.mbt` | 新增 | `Flags`（i/m/s），预定义类→`CharSet` 构造，大小写折叠，点号集合 | R6 |
| `charset_ext.mbt` | 新增 | `CharSet` 集合运算扩展（并/补/大小写闭包），不改既有 `CharSet` 字段 | R6.7 |
| `pattern_parser.mbt` | 新增 | 新解析器 `parse_pattern`：捕获/命名/非捕获组、惰性后缀、`\b\B`、前瞻、预定义类、内联标志 | R1/R3/R5/R6 |
| `program.mbt` | 新增 | Pike VM 指令集 `Inst`、`Program`、`compile_program`（Thompson 程序发射） | R2 |
| `pikevm.mbt` | 新增 | `Program::exec`：线程列表 + 捕获寄存器 + 去重 + 优先级 + 断言求值 | R2/R3/R4/R5 |
| `captures.mbt` | 新增 | `Captures`（slots + 名称映射 + 未设置语义），`group`/`name`/`group_count` | R1/R8.4 |
| `match_kind.mbt` | 新增 | `MatchKind`（LeftmostFirst/LeftmostLongest） | R4 |
| `minimize.mbt` | 新增 | `Dfa::minimize`（Hopcroft 1971 划分细化） | R7.1/7.2/7.5 |
| `lazy_dfa.mbt` | 新增 | `LazyDfa` 惰性按需子集构造 + 状态缓存 | R7.3/7.4 |
| `search.mbt` | 新增 | `Pattern` 编译句柄与高层 API：`find`/`find_all`/`find_iter`/`captures`/`replace`/`replace_all`/`split` | R8 |
| `demo.mbt` | 新增 | 实战正则集（email/IPv4/ISO 日期/数字）与替换演示数据 | R11 |
| `README.mbt.md` | 扩充 | 可执行文档覆盖新能力 | R11.4/R13.3 |
| `CHANGELOG.md` | 扩充 | SemVer 推进记录 | R13.5 |
| `prop_*_test.mbt` | 新增/既有 | 属性测试（见「测试策略」「正确性属性」） | R13.2 |

`benches/` 下新增基准包 `benches/regex_bench/`（`regex_bench.mbt` + `moon.pkg` + `pkg.generated.mbti`），结构对齐既有 `benches/astar_bench` 等，产出 `benches/results/` 工件并接入 guard（R9）。

---

## 组件与接口（Components and Interfaces）

> 下文签名均为 MoonBit 签名级，遵循既有 `.mbt`/`.mbti` 风格（`pub(all)` 暴露可构造数据，`pub` 暴露只读结构与函数）。

### 4.1 富语法树 `Ast` 与解析器扩展（R1/R3/R5/R6）

既有 `Regex` 不足以表达捕获编号、惰性标志、零宽断言与已 lowering 的字符集合，故新增**富语法树** `Ast`。设计取舍：预定义类 `\d\w\s` 在**解析期**即 lowering 为 `CharSet`（满足 R6.7「统一规约为 CharSet 区间运算」），AST 不保留 `\d` 之类符号节点。

```moonbit
// ast.mbt
pub enum AssertKind {
  TextStart        // \A 或非多行下的 ^
  TextEnd          // \z 或非多行下的 $
  LineStart        // 多行下的 ^（行首）
  LineEnd          // 多行下的 $（行尾）
  WordBoundary     // \b
  NotWordBoundary  // \B
} derive(Eq)

pub enum Ast {
  Empty                                                   // 空表达式
  Lit(Char)                                               // 字面字符（标志相关折叠在编译期处理）
  Set(CharSet)                                            // [...]、\d\w\s、. 等统一 lowering 结果
  Concat(Array[Ast])
  Alt(Array[Ast])
  Repeat(node~ : Ast, min~ : Int, max~ : Int?, greedy~ : Bool)  // *,+,?,{m,n} 及其惰性变体
  Group(body~ : Ast, index~ : Int?, name~ : String?)      // index=None → 非捕获组 (?:...)
  Assert(AssertKind)                                      // 零宽位置断言
  Look(positive~ : Bool, body~ : Ast)                     // (?=...) / (?!...) 前瞻
} derive(Eq)
```

`Ast::of_regex` 把既有 `Regex` 提升为 `Ast`（用于多引擎差分一致性，把生成的受支持子集正则喂给 Pike VM）。映射保持语义：既有 `Group` → 非捕获 `Group(index=None)`；`Star/Plus/Opt/Repeat` → `Repeat(greedy=true)`；`Anchor(Start/End)` → `Assert(TextStart/TextEnd)`（非多行默认）；`Class` → `Set(char_set_of_class(..))`。

```moonbit
pub fn Ast::of_regex(r : Regex) -> Ast            // 子集提升桥（保持语义）
pub fn print_ast(a : Ast) -> String               // 富语法树打印（命名/非捕获/惰性/断言可往返，供调试与扩展往返）
```

**新解析器** `parse_pattern` 在既有递归下降文法之上扩展（复用 `@pc.Input` 不可变游标，分支失败丢弃推进游标天然回溯）：

```
alt     := concat ('|' concat)*
concat  := piece*
piece   := atom quantifier?
quantifier := ('*'|'+'|'?'|'{' m (',' n?)? '}') '?'?     // 末尾可选 '?' 标记惰性
atom    := group | class | predef | anchor | wordb | look | escaped | char
group   := '(' ( '?:' | '?<' name '>' | '?P<' name '>' )? alt ')'
look    := '(' ('?=' | '?!') alt ')'
wordb   := '\b' | '\B'
predef  := '\d'|'\D'|'\w'|'\W'|'\s'|'\S'
anchor  := '^' | '$'
class   := '[' '^'? classitem+ ']'                       // classitem 支持 \d\w\s 内嵌
```

```moonbit
// pattern_parser.mbt
pub fn parse_pattern(pattern : String, flags~ : Flags = Flags::default()) -> Result[Ast, ParseError]
```

解析期职责：① 按左括号源位置顺序为捕获组分配 `1..n`（DFS 前序），`(?:...)` 不占号，`(?<name>...)` 既分配编号又登记名称（R1.1/1.2/1.3）；② 维护 `name → index` 映射，重复名报 `Unexpected(pos=该左括号位置, expected=["unique group name"])`，且**不构造任何程序/自动机**（R1.7）；③ 量词后缀末尾的 `?` 置 `greedy=false`（R3.1）；④ `\d\w\s` 等经 `flags.predef_*` lowering 为 `CharSet`（R6.1）；⑤ `.` lowering 为 `flags.dot_set()`（按 dotall 含/不含 `\n`，R6.2/6.3）；⑥ 内联标志组 `(?ims)` 可调整后续 `Flags`（可选增强）。

### 4.2 标志 `Flags` 与字符类增强（R6）

```moonbit
// flags.mbt
pub(all) struct Flags {
  ignore_case : Bool   // i
  multiline : Bool     // m
  dotall : Bool        // s
} derive(Eq)

pub fn Flags::default() -> Flags                        // 全 false，保持既有语义
pub fn Flags::parse(spec : String) -> Flags             // 由 "ims" 子集构造

// 预定义类 → CharSet（区间化），\D/\W/\S 为对应正向类在 [0,MAX_CODE] 上的补集
pub fn predef_digit() -> CharSet                        // \d ↔ [0-9]
pub fn predef_word() -> CharSet                         // \w ↔ [0-9A-Za-z_]
pub fn predef_space() -> CharSet                        // \s ↔ [ \t\n\r\f\v]
pub fn CharSet::complement(self : CharSet) -> CharSet    // [0,MAX_CODE] 上补集（复用既有补集逻辑）
pub fn CharSet::union(self : CharSet, other : CharSet) -> CharSet
pub fn Flags::dot_set(self : Flags) -> CharSet          // dotall → 全集；否则全集去 '\n'
pub fn CharSet::case_fold(self : CharSet) -> CharSet    // i 标志：ASCII 大小写闭包（含 Unicode 简单折叠的可声明边界）
```

设计要点：**所有字符集合语义统一经 `CharSet` 区间运算实现**（R6.7），与既有否定字符类补集、DFA 字母表原子区间划分完全同源，故新字符集合天然兼容既有 NFA/DFA 路径。`i` 标志在编译期把 `Lit(c)` 展开为 `Set(case_fold({c}))`、把 `Set(s)` 替换为 `Set(s.case_fold())`，从而把大小写不敏感规约为纯字符集合问题（避免在执行引擎里特判）。

### 4.3 程序编译 `Program` 与指令集（R2）

Pike VM 执行的是**线性指令程序**（Thompson NFA 程序，Russ Cox 风格），而非邻接表 NFA。`compile_program` 把 `Ast` 发射为指令数组：

```moonbit
// program.mbt
priv enum Inst {
  IChar(Char)                                   // 消费匹配单字符
  ISet(CharSet)                                 // 消费匹配字符集合（含 ., \d 等）
  ISplit(Int, Int)                              // 分叉：先尝试 a（高优先级）后 b
  IJmp(Int)
  ISave(Int)                                    // 写捕获寄存器 slot（2*group, 2*group+1）
  IAssert(AssertKind)                           // 零宽位置断言
  ILook(positive~ : Bool, prog~ : Program)      // 前瞻：在当前位置锚定执行子程序（不消费）
  IMatch
}

pub struct Program {
  insts : Array[Inst]
  num_groups : Int                              // 捕获组数（不含第 0 组的“整体”自身计入 slots）
  names : Map[String, Int]                      // 命名组 → 编号
  flags : Flags
}

pub fn compile_program(ast : Ast, flags~ : Flags = Flags::default()) -> Program
```

发射规则（Thompson 1968 的程序化形式）：
- `Lit/Set` → 单条 `IChar/ISet`；
- `Concat` → 顺序拼接；
- `Alt(a,b)` → `ISplit(a, b)`（分支按书写顺序排优先级）；
- `Group(index=Some(g))` → `ISave(2g)` … 子程序 … `ISave(2g+1)`；非捕获组不发 `ISave`；
- `Repeat`：贪婪 `*` 为 `L: ISplit(body, out)`，惰性 `*?` 为 `L: ISplit(out, body)`（**仅调换 Split 两臂优先级**，即可在同一引擎统一贪婪/惰性，R3.1）；`+`/`?`/`{m,n}` 按既有 `compile_repeat` 同构展开（m 份强制副本 + 上界处理），惰性同样靠 Split 臂序区分；
- `Assert` → `IAssert`；`Look` → `ILook(positive, compile_program(body))`；
- 整个程序末尾置 `IMatch`，并以 `ISave(0)`/`ISave(1)` 包裹整体匹配区间（第 0 组）。

### 4.4 Pike VM 执行引擎（R2/R3/R4/R5）

Pike VM 以「线程（thread = (pc, 捕获寄存器快照)）列表」沿输入逐字符推进，在每一步对当前线程集做 ε 闭包式展开（处理 `ISplit/IJmp/ISave/IAssert/ILook`），并以**每个 pc 至多一条线程**去重，从而把运行步数压到 `O(程序规模 × 输入长度)`（R2.2，避免回溯指数爆炸）。

```moonbit
// pikevm.mbt
pub fn Program::exec(self : Program, input : String,
                     start~ : Int = 0, kind~ : MatchKind = LeftmostLongest) -> Captures?
pub fn Program::is_match(self : Program, input : String) -> Bool
```

关键机制：
- **去重**：每步用 `seen : Array[Bool]`（长度 = 指令数）保证同一 pc 只入列一次；先入列者优先级更高（R2.3）。
- **优先级与策略**：线程入列顺序即优先级。`LeftmostFirst`（PCRE/Perl）下，首个到达 `IMatch` 的线程即结果，其后同位置低优先级线程被丢弃，自然实现「按书写顺序与量词贪婪/惰性优先级」（R4.4）。`LeftmostLongest`（POSIX）下，到达 `IMatch` 时不立即收敛，而是按 POSIX 规则在候选间取「最左且最长」（比较整体区间 end 取最大），与 `Nfa::find` 语义一致（R4.3、R2.6）。
- **捕获寄存器**：`ISave(slot)` 写当前位置到线程寄存器副本；汇合时保留高优先级线程的寄存器（R2.3/2.4）。
- **断言求值**：`IAssert` 在当前位置按 `AssertKind` 判定（见 4.7），成立则线程继续、否则丢弃，零宽（R5）。
- **无匹配**：无线程到达 `IMatch` 返回 `None`，不抛异常（R2.5）。

### 4.5 捕获与子匹配模型 `Captures`（R1/R8.4）

```moonbit
// captures.mbt
pub struct Captures {
  slots : Array[Int]          // 长度 2*(num_groups+1)；-1 表示未设置
  names : Map[String, Int]    // 名称 → 组编号
} derive(Eq)

pub fn Captures::group(self : Captures, i : Int) -> Match?   // i=0 整体匹配；越界/未设置 → None
pub fn Captures::name(self : Captures, n : String) -> Match? // 经 names 解析编号后委托 group
pub fn Captures::group_count(self : Captures) -> Int         // 含第 0 组
```

语义：第 `0` 组为整体匹配 `[slots[0], slots[1])`（R1.4）；第 `g` 组为 `[slots[2g], slots[2g+1])`，二者任一为 `-1` 即「未设置」（R1.5 未走通分支 / R1.6 名称未匹配 → 返回 `None` 而非整体失败）。各组区间恒为第 0 组的子区间，且 `input[group(g)] == 该组实际匹配子串`（捕获正确性，P3）。

### 4.6 匹配策略 `MatchKind`（R4）

```moonbit
// match_kind.mbt
pub enum MatchKind {
  LeftmostFirst     // PCRE/Perl：最左 + 按优先级首个成功
  LeftmostLongest   // POSIX：最左 + 最长（默认）
} derive(Eq)
```

默认 `LeftmostLongest` 以兼容既有 `find`/`is_match`（R4.2）。`Pattern` 与 `Program::exec` 均接受可选 `kind`。策略只改变 Pike VM 在「同起点多候选」时的取舍，不改变可匹配性。序关系不变量（P5）：同输入下 `start_LL ≤ start_LF` 且 `len_LL ≥ len_LF`（R4.5）。

### 4.7 零宽断言实现与边界声明（R5）

- **锚点 `^`/`$`**：编译期按 `flags.multiline` 选择 `LineStart/LineEnd`（多行，按 `\n` 切分行首尾，R6.5）或 `TextStart/TextEnd`（非多行，仅整串首尾，R6.6）。判定纯位置相关，零宽。
- **词边界 `\b`/`\B`**：以参考谓词 `is_word_boundary(input, pos)` 实现——「pos 左字符是否词字符」与「pos 右字符是否词字符」异或；串首前/串尾后视为非词字符（R5.2）。`\B` 取其逻辑非（R5.3）。词字符集合即 `\w`（复用 `predef_word()`）。零宽，不消费（R5.1）。
- **前瞻 `(?=p)`/`(?!p)`**：`ILook(positive, sub)` 在当前位置**锚定执行子程序** `sub`（一次独立、不消费外层输入的 Pike VM 子运行，仅判 bool）；`positive` 时子程序成功则断言成立，`!positive` 时子程序失败则成立（R5.4/5.5）。零宽（P6）。
- **实现边界声明（R5.6）**：前瞻仅在 **Pike VM 执行路径**可用；纯 DFA / 惰性 DFA 快路径**不支持前瞻**（前瞻一般无法折叠进有限状态转移表），故含前瞻的模式不参与「五路差分一致」，仅由 Pike VM 求值。**捕获不跨前瞻边界导出**（前瞻内的捕获组不写回外层 `Captures`，与 RE2 对待 lookaround 的保守策略一致）。**不支持变长后瞻与反向引用（backreference）**——与 RE2/Rust `regex` 一致，反向引用需要回溯、破坏线性保证。这些边界在 README 与本文档「设计权衡」显式声明，而非隐式留白。

### 4.8 DFA 最小化（Hopcroft 1971）（R7.1/7.2/7.5）

在既有 `Dfa` 上新增方法（不改 `Dfa` 字段）：

```moonbit
// minimize.mbt
pub fn Dfa::minimize(self : Dfa) -> Dfa
```

算法：Hopcroft 1971 划分细化。初始按 `(accept[state][flags])` 接受签名把状态分为可区分类（注意既有 `Dfa` 的接受性依赖锚点标志 `flags ∈ 0..3`，故签名为四元接受向量），随后对每个「字符类 × 锚点标志」反向细化划分至不动点，合并不可区分等价态，重建 `trans`/`accept`/`bounds`，得到状态数最小且语言等价的 DFA（R7.1/7.2）。最小化前后对任意输入整体区间一致（R7.5，P2）。

### 4.9 惰性 DFA（on-the-fly 子集构造）（R7.3/7.4）

```moonbit
// lazy_dfa.mbt
pub struct LazyDfa {
  nfa : Nfa
  cache : Map[String, Int]            // 已物化的 DFA 状态（NFA 核编码 → id）
  cores : Array[Array[Int]]           // id → NFA 状态核
}
pub fn LazyDfa::new(nfa : Nfa) -> LazyDfa
pub fn LazyDfa::find(self : LazyDfa, input : String) -> Match?
```

执行时按需对遇到的 `(状态, 锚点标志, 字符类)` 增量计算后继核并缓存（复用既有 `Nfa::closure`/`move_on`），不预先物化整张转移表。对同一 `(正则, 输入)` 与完整 `to_dfa` 给出一致判定（R7.4，P2）。

### 4.10 高层搜索 API（`Pattern`）（R8/R11）

```moonbit
// search.mbt
pub struct Pattern {
  prog : Program
  kind : MatchKind
}
pub fn Pattern::compile(pattern : String, flags~ : Flags = Flags::default(),
                        kind~ : MatchKind = LeftmostLongest) -> Result[Pattern, ParseError]

pub fn Pattern::is_match(self : Pattern, input : String) -> Bool
pub fn Pattern::find(self : Pattern, input : String) -> Match?
pub fn Pattern::captures(self : Pattern, input : String) -> Captures?
pub fn Pattern::find_all(self : Pattern, input : String) -> Array[Match]
pub fn Pattern::captures_all(self : Pattern, input : String) -> Array[Captures]
pub fn Pattern::replace(self : Pattern, input : String, repl : String) -> String      // 替换首个
pub fn Pattern::replace_all(self : Pattern, input : String, repl : String) -> String  // 替换全部
pub fn Pattern::split(self : Pattern, input : String) -> Array[String]
```

不重叠枚举（R8.1/8.2/8.8）：自 `pos=0` 反复在 `[pos, n]` 上锚定搜索，每命中一个匹配 `[s,e)` 后令 `pos = e` 继续；**空匹配** `s==e` 时令 `pos = e+1`（至少前进一字符）以保证终止（R8.3）。`find_iter` 作为 `find_all` 的别名/惰性形态提供。

替换引用（R8.6）：`replace*` 解析 `repl` 中的 `$0..$9`、`${name}` 与 `$$`（字面 `$`），以对应 `Captures` 组切片替换，未设置组替换为空串。`split`（R8.7/8.9）以全部不重叠匹配为分隔切分；`interleave(pieces, 分隔符匹配子串) == input`（P8）。

### 4.11 实战 demo 正则集（R11）

`demo.mbt` 提供贯穿文档与基准的实战模式与样例：

```moonbit
// demo.mbt
pub fn demo_email() -> String     // 含命名/编号组的 email 模式
pub fn demo_ipv4() -> String      // IPv4，四个八位组捕获
pub fn demo_iso_date() -> String  // (?<year>...)-(?<month>...)-(?<day>...)
pub fn demo_number() -> String    // 整数/小数/指数数字字面量
pub fn demo_cases() -> Array[(String, String)]   // (模式, 样例输入)
```

README 与基准复用同一组模式，演示匹配、捕获与 `replace_all`（含 `$1`/`${name}` 引用）的端到端用法（R11.2/11.3/11.4）。

### 4.12 性能基准设计（R9）

`benches/regex_bench/` 对三路执行（NFA `Nfa::find`、DFA `Dfa::find`、Pike VM `Program::exec`）在两类工作负载计时：① **病态输入**——形如 `a?{n}a{n}` 应用于 `a^n`，专门暴露回溯型实现的指数爆炸（Pike VM 应保持线性）；② **真实负载**——email/IPv4/数字字面量等 demo 模式 × 规模化输入。输出含机器标识、后端目标、输入规模与计时统计的 JSON/Markdown 工件（R9.3），写入 `benches/results/`；新运行与基线中位数比较，超声明容差时给出可审计失败报告（R9.4，复用既有 guard 模式）。文档记录运行命令，并要求 native 后端先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R9.5）。

---

## 数据模型（Data Models）

新增类型一览（既有 `Regex`/`CharSet`/`Match`/`ParseError`/`Nfa`/`Dfa` 不变）：

| 类型 | 文件 | 说明 |
|---|---|---|
| `Ast` / `AssertKind` | `ast.mbt` | 富语法树与零宽断言种类 |
| `Flags` | `flags.mbt` | i/m/s 标志集 |
| `Inst`（priv）/ `Program` | `program.mbt` | Pike VM 指令与程序 |
| `Captures` | `captures.mbt` | 捕获结果（slots + 名称映射） |
| `MatchKind` | `match_kind.mbt` | 匹配策略 |
| `LazyDfa` | `lazy_dfa.mbt` | 惰性 DFA |
| `Pattern` | `search.mbt` | 编译句柄与高层 API 宿主 |

**捕获寄存器布局**：`slots[2g]`/`slots[2g+1]` 为第 `g` 组起止，`-1` = 未设置；第 0 组为整体匹配。**发布元数据**：版本自 `0.1.0` 起按旗舰深化做次/主版本推进（R13.5），`release_info`/`release_info_with_gates` 语义不变，仅版本号字符串与 CHANGELOG 更新（R12.5）。

---

## 错误处理（Error Handling）

- **解析错误**：新解析器 `parse_pattern` 复用既有 `ParseError`（不扩容枚举）。映射约定：未闭合组/类 → `Unbalanced`；悬空量词 → `DanglingQuantifier`；非法 `{...}` → `InvalidRepeat`；残余输入 → `TrailingInput`；**重复组名 / 不支持的构造（如反向引用、变长后瞻）→ `Unexpected(pos, expected=[...])`**，`expected` 负载携带人类可读提示。所有错误携带字符偏移（`ParseError::pos`），且**解析失败不构造任何程序/自动机**（R1.7、与既有 P10 一致）。
- **执行无匹配**：返回 `None`（`Match?`/`Captures?`），绝不抛运行期异常（R2.5）。
- **前瞻越界能力**：在文档显式声明并在解析期对明确不支持的构造（反向引用 `\1`、后瞻 `(?<=...)`）报 `Unexpected`，而非静默接受（R5.6/R10.6）。
- **越界查询**：`Captures::group(i)` 越界或未设置返回 `None`；`Captures::name` 未知名返回 `None`。

---

## 算法说明与 paper-to-code 可追溯（R10）

| 算法 | 论文 / 规范 | 本库落点 |
|---|---|---|
| NFA 构造 | Thompson 1968《Regular Expression Search Algorithm》（对照 Glushkov 构造） | 既有 `build_nfa`（邻接表）+ 新 `compile_program`（指令程序，同构发射） |
| NFA→DFA | 子集构造（subset construction）+ 字母表原子区间划分 | 既有 `to_dfa` |
| DFA 最小化 | Hopcroft 1971 划分细化 | 新 `Dfa::minimize` |
| 惰性 DFA | on-the-fly 子集构造 | 新 `LazyDfa` |
| 线性时间匹配 + 捕获 | Russ Cox《Regular Expression Matching Can Be Simple And Fast》/ Pike VM | 新 `Program` + `Program::exec`（线程列表 + 捕获寄存器 + pc 去重） |
| 最左最长语义 | POSIX 正则规范 | `MatchKind::LeftmostLongest`（既有 `find`/`Nfa::find`/`Dfa::find` 默认） |

每个新增文件头部以注释标注其对应论文与本设计章节（沿用既有 `nfa.mbt`/`dfa.mbt` 的注释风格），实现 paper-to-code 可追溯（R10.1–10.4）。

---

## 三后端一致性与可移植性（R13.1/13.4）

- **确定性随机源**：全部属性测试复用 `@infra_pbt` 种子驱动 `Rng`，保证 `wasm-gc`/`js`/`native` 三后端逐位一致、可重放，任一后端输出分歧即判构建失败（R13.1）。
- **可移植实现约束**：算法仅依赖整数、数组、`Map` 与 `String::iter()`（Unicode 标量序列），不使用后端特定 API；`CharSet` 以码点区间表示，避免依赖平台字符表示差异。
- **native 前置**：文档与脚本要求 native 后端运行前 `export LIBRARY_PATH=/usr/lib64:/usr/lib`（R9.5/R13.4）。
- **门禁聚合**：三后端测试、属性测试、可执行文档任一未过，`release_info_with_gates` 经 `@release_meta` 聚合阻止本方向进入 release-ready（R13.6）。

---

## 设计权衡与开源对标（R10.5/R10.6）

| 维度 | 本库 | Google RE2 | Rust `regex` | PCRE |
|---|---|---|---|---|
| 匹配复杂度 | 线性（Pike VM / DFA），无回溯爆炸 | 线性（自动机） | 线性（自动机） | 可指数（回溯） |
| 匹配策略 | LL（默认）+ LF 可选 | LL / LF 可选 | LF（POSIX 变体可选） | LF |
| 捕获子匹配 | 支持（Pike VM 寄存器） | 支持 | 支持 | 支持 |
| 前瞻 lookahead | Pike VM 路径有限支持，DFA 不支持，捕获不跨界 | 不支持 lookaround | 不支持 lookaround | 支持 |
| 后瞻 / 反向引用 | 不支持（显式报错） | 不支持 | 不支持 | 支持（牺牲线性） |
| Unicode 折叠 | ASCII 折叠为主，Unicode 简单折叠声明边界 | 完整 | 完整 | 完整 |

**核心取舍**：与 RE2/Rust `regex` 同侧——**以放弃反向引用与变长后瞻换取最坏情形线性时间保证**。前瞻作为有限增强仅在 Pike VM 路径提供并显式声明边界。这些差异在 README 与本文档显式声明，而非隐式留白（R10.6）。

---

## 需求可追溯映射（Requirements Traceability）

| 需求 | 设计落点 |
|---|---|
| R1 捕获/命名/非捕获组 | 4.1 `Ast.Group`、`parse_pattern` 编号；4.5 `Captures` |
| R2 Pike VM | 4.3 `Program`/`compile_program`；4.4 `Program::exec` |
| R3 贪婪/惰性量词 | 4.1 `Repeat.greedy`；4.3 Split 臂序；4.4 优先级 |
| R4 匹配策略 | 4.6 `MatchKind`；4.4 策略求值 |
| R5 零宽断言 | 4.7 `Assert`/`Look` 与边界声明 |
| R6 字符类/标志 | 4.2 `Flags`/`CharSet` 扩展；4.1 lowering |
| R7 最小化/惰性 DFA | 4.8 `Dfa::minimize`；4.9 `LazyDfa` |
| R8 高层搜索 API | 4.10 `Pattern` 全套 |
| R9 基准 | 4.12 `benches/regex_bench` |
| R10 可解释性 | 「算法说明」「设计权衡与对标」 |
| R11 实战 demo | 4.11 `demo.mbt` + README |
| R12 向后兼容 | 「设计原则与兼容契约」「模块划分」冻结列 |
| R13 质量门禁 | 「三后端一致性」+ 测试策略 + 正确性属性 |

---

## 测试策略（Testing Strategy）

**双轨测试**：单元测试锁定具体见证与边界/错误条件；属性测试以 `@infra_pbt` 覆盖通用不变量（每条 ≥100 迭代，R13.2）。

- **单元测试**：Pike VM 入口存在性（R2.1）、最小化/惰性 DFA 入口（R7.1/7.3）、replace/split 代表样例（R8.5）、demo 模式匹配/替换（R11.2/11.3）、未设置组（R1.5）、惰性最小满足（R3.4）、无匹配不抛异常（R2.5）、既有 API 回归（R12.1/12.2/12.5）。
- **属性测试**：见下「正确性属性」P1–P10。生成器复用既有 `gen_regex_at`/`gen_input_str` 风格（小交叠字母表、深度受限），新增富正则生成器（含组/惰性/断言/标志）。
- **可执行文档**：`README.mbt.md` 覆盖捕获、惰性量词、零宽断言、字符类标志、高层 API 与实战 demo，全部经 `moon test *.mbt.md` 验证（R13.3）。
- **属性测试标注**：统一 `Feature: regex-engine, Property {n}: {text}`，并以 `**Validates: Requirements X.Y**` 链接验收标准；既有以 `moonbit-infra-suite` 标注的 Property 4/5/6 视为本套件 P1/P2/P10 的已发布种子，将扩展覆盖面。

---

## 正确性属性（Correctness Properties）

*属性（property）是对系统在所有合法执行下应恒成立行为的形式化陈述，是人类可读规格与机器可验证保证之间的桥梁。下列属性均以全称量化表述，并复用 `@infra_pbt` 的 `holds_for_all`/`round_trip`（每条 ≥100 迭代）。*

### Property 1：语法树往返（round-trip）

*对任意*由生成器产出的规范正则语法树 `r`，先打印再解析应得到等价语法树，即 `parse_regex(print_regex(r)) == Ok(r)`。

**Validates: Requirements 2.2, 2.7, 12.6**

### Property 2：多引擎差分一致性

*对任意*由生成器产出的受支持子集正则与任意输入字符串，五条执行路径——`Nfa::find`、`to_dfa` 后的 `Dfa::find`、`Dfa::minimize` 后的 DFA、`LazyDfa::find`、以及 `Ast::of_regex` 喂入的 Pike VM（`LeftmostLongest`）——应给出逐字段相等的整体匹配区间（`Match?`）。该属性综合验证确定化、最小化、惰性构造与 Pike VM 在最左最长策略下保持匹配语义一致。

**Validates: Requirements 2.6, 7.4, 7.5, 7.6, 4.2**

### Property 3：捕获正确性

*对任意*由生成器产出的含捕获/命名/非捕获组的模式与任意能成功匹配的输入：第 0 组等于整体匹配区间；每个已设置的第 `g` 组区间都是第 0 组的子区间，且 `input` 在该区间上的切片等于该组实际匹配的子串；非捕获组不占用编号（编号严格按左括号源顺序）；命名组经 `Captures::name` 检索得到与其编号 `Captures::group` 一致的结果；未参与匹配的组返回未设置（`None`）而非导致整体失败。

**Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.4, 8.4, 11.2**

### Property 4：贪婪 / 惰性单调性

*对任意*由生成器产出的含量词正则与任意输入，将其顶层量词取贪婪与取惰性两个变体分别匹配，贪婪变体所得整体匹配区间长度恒不小于同位置惰性变体所得整体匹配区间长度。

**Validates: Requirements 3.2, 3.3, 3.5**

### Property 5：匹配策略序关系不变量

*对任意*由生成器产出的正则与任意输入，`LeftmostLongest` 策略所得整体匹配区间的起点不晚于 `LeftmostFirst` 策略所得起点，且长度不小于后者长度。

**Validates: Requirements 2.3, 4.3, 4.4, 4.5**

### Property 6：零宽不变量与断言位置判定

*对任意*由生成器产出的输入与位置 `pos`：词边界断言 `\b` 的判定等于参考谓词「`pos` 左右词字符性相异」（串首前/串尾后视为非词字符），且 `\B` 在每个位置恰为 `\b` 之逻辑非；将任一满足的零宽断言（`\b`/`\B`/锚点/前瞻）插入正则任意位置，其对整体匹配消费长度的贡献恒为 0（不改变由非断言部分消费的字符边界）。多行下 `^`/`$` 的行首尾判定、非多行下仅整串首尾判定，复用同一位置判定逻辑。

**Validates: Requirements 5.2, 5.3, 5.7, 6.5, 6.6**

### Property 7：find_all 不重叠、穷尽且终止

*对任意*由生成器产出的模式与任意输入，`find_all` 产出的相邻匹配区间满足后一匹配 `start` 不小于前一匹配 `end`（互不共享字符）；遇空匹配时扫描位置至少前进一字符使枚举有限终止；扫描覆盖整个输入（在不重叠约束下每个可匹配起点均被产出）。

**Validates: Requirements 8.1, 8.2, 8.3, 8.8**

### Property 8：split / replace 重建一致性

*对任意*由生成器产出的模式与任意输入，将 `split` 所得子串与各分隔符匹配子串按序交错拼接应逐字符重建原输入；且 `replace_all` 以恒等引用 `$0` 替换时还原原输入，以 `$1`/`${name}` 引用替换时该处替换文本等于对应捕获组的匹配子串。

**Validates: Requirements 8.6, 8.7, 8.9**

### Property 9：预定义字符类与标志的 CharSet 语义

*对任意*由生成器产出的码点 `c`：`\d`/`\w`/`\s` lowering 所得 `CharSet` 对 `c` 的成员判定等于其参考谓词，且 `\D`/`\W`/`\S` 恒为对应正向类在 `[0, MAX_CODE]` 上的精确补集；点号 `.` 在未启用 dotall 时不含 `\n`、启用时含 `\n`；大小写不敏感（`i`）下字面字符的折叠集合同时匹配其大小写两种形态。所有字符集合均经统一的 `CharSet` 区间运算路径产生（归一化、不相交、升序不变量成立）。

**Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.7**

### Property 10：非法表达式错误条件

*对任意*语法非法的模式字符串（含重复捕获组名、不支持的构造如反向引用），`parse_pattern` 应返回携带合法字符偏移位置的解析错误（而非成功），且不构造任何程序或自动机。

**Validates: Requirements 1.7, 2.3**
