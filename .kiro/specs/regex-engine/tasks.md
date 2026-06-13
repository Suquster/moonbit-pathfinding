# 实现计划（Implementation Plan）：Regex_Engine 旗舰深化

## 概述（Overview）

本计划在已发布的 `regex_engine 0.1.0` 骨架之上做**严格向后兼容、旁路扩展**的旗舰级深化。既有文件 `types.mbt`/`parser.mbt`/`printer.mbt`/`nfa.mbt`/`dfa.mbt`/`matcher.mbt`/`release.mbt` 与既有公开 API（`parse_regex`/`print_regex`/`build_nfa`/`to_dfa`/`Nfa::find`/`Dfa::find`/`find`/`is_match`）**签名与语义冻结**，`ParseError` 枚举**不扩容**；所有新能力以新增文件、新增类型、在既有类型上追加只增方法的方式提供。

任务按依赖增量推进：基础类型/标志/AST/解析器 → 程序编译/Pike VM/捕获/策略 → 最小化/惰性 DFA/五路差分 → 高层搜索 API → demo/基准/文档/发布，期间设阶段检查点。所有新增文件均落在 `src/regex_engine/`（基准包除外），实现语言为 **MoonBit**（沿用既有 `.mbt`/`.mbti` 风格）。

所有属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`，每条属性 **≥100 次迭代**，统一标注 `Feature: regex-engine, Property {n}: {text}`。三后端（`wasm-gc`/`js`/`native`）一致；运行 **native 测试 / 基准 / 文档校验前必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

## 任务（Tasks）

- [x] 1. 基础类型与标志层（flags / charset_ext / match_kind）
  - [x] 1.1 实现 `flags.mbt`：标志集与预定义类构造
    - 定义 `pub(all) struct Flags { ignore_case; multiline; dotall }`，实现 `Flags::default()`（全 false，保持既有语义）与 `Flags::parse(spec)`（由 `"ims"` 子集构造）
    - 实现预定义类 → `CharSet`：`predef_digit()`（`[0-9]`）、`predef_word()`（`[0-9A-Za-z_]`）、`predef_space()`（`[ \t\n\r\f\v]`）
    - 实现 `Flags::dot_set()`：dotall 启用→全集，否则全集去 `\n`
    - 文件头注释标注对应设计 4.2 与 paper-to-code 出处
    - _Requirements: 6.1, 6.2, 6.3, 6.7_

  - [x] 1.2 实现 `charset_ext.mbt`：`CharSet` 集合运算扩展（不改既有 `CharSet` 字段）
    - 在既有 `CharSet` 上追加方法 `CharSet::union`、`CharSet::complement`（`[0,MAX_CODE]` 上补集，复用既有补集逻辑）、`CharSet::case_fold`（ASCII 大小写闭包，声明 Unicode 简单折叠边界）
    - 保证产出区间满足归一化、不相交、升序不变量，与既有否定字符类/DFA 字母表区间划分同源
    - _Requirements: 6.1, 6.4, 6.7_

  - [x] 1.3 实现 `match_kind.mbt`：匹配策略枚举
    - 定义 `pub enum MatchKind { LeftmostFirst; LeftmostLongest } derive(Eq)`，默认语义对齐既有 `find`/`is_match`（`LeftmostLongest`）
    - _Requirements: 4.1, 4.2_

  - [x]* 1.4 编写 Property 9 属性测试（预定义类与标志的 CharSet 语义）
    - **Property 9: 预定义字符类与标志的 CharSet 语义**
    - **Validates: Requirements 6.1, 6.2, 6.3, 6.4, 6.7**
    - 新建 `prop_charset_flags_test.mbt`，用 `@infra_pbt` 生成码点 `c`：校验 `\d`/`\w`/`\s` 成员判定等于参考谓词，`\D`/`\W`/`\S` 为对应正向类在 `[0,MAX_CODE]` 上精确补集；`.` 在 dotall 关/开时分别不含/含 `\n`；`i` 折叠集合同时含大小写两形态；区间归一化/不相交/升序不变量成立。≥100 迭代

  - [x]* 1.5 编写 `flags`/`charset_ext` 单元测试
    - 新建 `flags_charset_test.mbt`，覆盖 `Flags::parse` 边界、`union`/`complement`/`case_fold` 的代表样例与空集/全集边界
    - _Requirements: 6.1, 6.4, 6.7_

- [x] 2. 富语法树 Ast 与子集提升桥
  - [x] 2.1 实现 `ast.mbt`：`Ast`/`AssertKind` 定义、`print_ast` 与 `Ast::of_regex`
    - 定义 `pub enum AssertKind`（TextStart/TextEnd/LineStart/LineEnd/WordBoundary/NotWordBoundary）与 `pub enum Ast`（Empty/Lit/Set/Concat/Alt/Repeat{min,max,greedy}/Group{index,name}/Assert/Look{positive}），均 `derive(Eq)`
    - 实现 `Ast::of_regex(r)` 子集提升桥（保持语义：既有 `Group`→非捕获 `Group(index=None)`；`Star/Plus/Opt/Repeat`→`Repeat(greedy=true)`；`Anchor`→`Assert(TextStart/TextEnd)`；`Class`→`Set(..)`）
    - 实现 `print_ast(a)`（命名/非捕获/惰性/断言可往返打印，供调试与扩展）
    - 依赖 `charset_ext.mbt` 的 `CharSet`；文件头注释标注设计 4.1 与 Thompson 1968 出处
    - _Requirements: 1.1, 1.2, 1.3, 3.1, 5.1, 12.6_

  - [x]* 2.2 扩展 Property 1 属性测试（语法树往返）
    - **Property 1: 语法树往返（round-trip）**
    - **Validates: Requirements 2.2, 2.7, 12.6**
    - 在既有 `prop_roundtrip_test.mbt` 中扩展覆盖面：对生成器产出的规范语法树 `r` 校验 `parse_regex(print_regex(r)) == Ok(r)`，复用 `@infra_pbt::round_trip`。≥100 迭代

  - [x]* 2.3 编写 `ast` 单元测试
    - 新建 `ast_test.mbt`，覆盖 `Ast::of_regex` 对既有节点的语义映射见证、`print_ast` 对命名/非捕获/惰性/断言的可读输出
    - _Requirements: 1.2, 3.1, 5.1, 12.6_

- [x] 3. 新解析器 pattern_parser（捕获 / 命名 / 非捕获 / 惰性 / 断言 / 标志）
  - [x] 3.1 实现 `pattern_parser.mbt`：`parse_pattern`
    - 实现 `pub fn parse_pattern(pattern, flags~ : Flags = Flags::default()) -> Result[Ast, ParseError]`，复用 `@pc.Input` 不可变游标与既有递归下降文法分支回溯
    - 按左括号源顺序为捕获组分配 `1..n`（DFS 前序）；`(?:...)` 不占号；`(?<name>...)`/`(?P<name>...)` 既分配编号又登记名称，维护 `name→index` 映射
    - 量词后缀末尾 `?` 置 `greedy=false`；`\d\w\s` 经 `flags` lowering 为 `CharSet`；`.` lowering 为 `flags.dot_set()`；`^`/`$` 按 `multiline` 选断言；`\b`/`\B`、`(?=...)`/`(?!...)` 解析为 `Assert`/`Look`
    - 错误映射到既有 `ParseError`（不扩容枚举）：未闭合→`Unbalanced`、悬空量词→`DanglingQuantifier`、非法 `{...}`→`InvalidRepeat`、残余→`TrailingInput`、重复组名/不支持构造（反向引用、变长后瞻）→`Unexpected(pos, expected=[...])`；解析失败不构造任何程序/自动机
    - 依赖 `ast.mbt`、`flags.mbt`
    - _Requirements: 1.1, 1.2, 1.3, 1.7, 3.1, 5.1, 5.4, 5.5, 6.1, 6.2, 6.5, 6.6_

  - [x]* 3.2 扩展 Property 10 属性测试（非法表达式错误条件）
    - **Property 10: 非法表达式错误条件**
    - **Validates: Requirements 1.7, 2.3**
    - 在既有 `prop_error_test.mbt` 中扩展：对生成器产出的语法非法模式（含重复组名、反向引用等不支持构造）校验 `parse_pattern` 返回携带合法字符偏移的解析错误，且不构造任何程序/自动机。≥100 迭代

  - [x]* 3.3 编写 `pattern_parser` 单元测试
    - 新建 `pattern_parser_test.mbt`，覆盖编号顺序（嵌套/非捕获穿插）、命名组登记、惰性后缀、内联标志、各类错误位置见证
    - _Requirements: 1.1, 1.2, 1.3, 1.7, 3.1_

- [x] 4. 捕获与子匹配模型 captures
  - [x] 4.1 实现 `captures.mbt`：`Captures`
    - 定义 `pub struct Captures { slots : Array[Int]; names : Map[String, Int] } derive(Eq)`，`slots` 长度 `2*(num_groups+1)`，`-1` 表示未设置
    - 实现 `Captures::group(i)`（i=0 整体匹配，越界/未设置→`None`）、`Captures::name(n)`（经 `names` 解析编号后委托 `group`，未知名→`None`）、`Captures::group_count()`（含第 0 组）
    - 仅依赖既有 `Match` 类型
    - _Requirements: 1.4, 1.5, 1.6, 8.4_

  - [x]* 4.2 编写 `captures` 单元测试
    - 新建 `captures_test.mbt`，覆盖整体组/子组区间、未设置组返回 `None`、命名检索与编号检索一致、越界查询
    - _Requirements: 1.4, 1.5, 1.6, 8.4_

- [x] 5. 程序编译 program 与指令集
  - [x] 5.1 实现 `program.mbt`：`Inst`/`Program`/`compile_program`
    - 定义 `priv enum Inst`（IChar/ISet/ISplit/IJmp/ISave/IAssert/ILook{positive,prog}/IMatch）与 `pub struct Program { insts; num_groups; names; flags }`
    - 实现 `pub fn compile_program(ast, flags~ : Flags = Flags::default()) -> Program`，按 Thompson 程序化发射：`Lit/Set`→`IChar/ISet`；`Concat` 顺序拼接；`Alt`→`ISplit`（书写顺序定优先级）；`Group(Some(g))`→`ISave(2g)…ISave(2g+1)`；`Repeat` 贪婪 `ISplit(body,out)` / 惰性 `ISplit(out,body)`（仅调换 Split 臂序统一贪婪/惰性），`+`/`?`/`{m,n}` 按 m 份强制副本 + 上界处理同构展开
    - `i` 标志在编译期把 `Lit(c)` 展开为 `Set(case_fold({c}))`、`Set(s)` 替换为 `Set(s.case_fold())`；程序末尾置 `IMatch`，以 `ISave(0)`/`ISave(1)` 包裹整体匹配区间
    - 依赖 `ast.mbt`、`flags.mbt`、`charset_ext.mbt`
    - _Requirements: 2.1, 3.1, 3.2, 3.3, 5.1, 5.4, 5.5, 6.4_

  - [x]* 5.2 编写 `program` 单元测试
    - 新建 `program_test.mbt`，覆盖捕获组 `ISave` 槽位分配、贪婪/惰性 Split 臂序、`{m,n}` 展开、前瞻子程序发射的结构见证
    - _Requirements: 2.1, 3.1, 5.4, 5.5_

- [x] 6. Pike VM 执行引擎
  - [x] 6.1 实现 `pikevm.mbt`：`Program::exec` / `Program::is_match`
    - 实现 `pub fn Program::exec(self, input, start~ : Int = 0, kind~ : MatchKind = LeftmostLongest) -> Captures?` 与 `pub fn Program::is_match(self, input) -> Bool`
    - 线程列表（thread=(pc, 捕获寄存器快照））沿输入推进，每步对 `ISplit/IJmp/ISave/IAssert/ILook` 做 ε 闭包展开；以 `seen : Array[Bool]`（长度=指令数）保证每 pc 至多一条线程，先入列者优先级高
    - 策略求值：`LeftmostFirst` 取首达 `IMatch` 线程；`LeftmostLongest` 在候选间取最左最长（整体区间 end 取最大），与 `Nfa::find` 语义一致
    - 断言求值：`IAssert` 按 `AssertKind` 判位置（`\b` 用参考谓词 `is_word_boundary`，串首前/串尾后视为非词字符，`\B` 取逻辑非；`^`/`$` 按多行/非多行）；`ILook` 在当前位置锚定执行子程序（独立、不消费、仅判 bool），捕获不跨前瞻边界导出
    - 无线程到达 `IMatch` 返回 `None`，不抛异常
    - 依赖 `program.mbt`、`captures.mbt`、`match_kind.mbt`、`flags.mbt`
    - _Requirements: 2.1, 2.2, 2.3, 2.4, 2.5, 3.2, 3.3, 3.4, 4.3, 4.4, 5.1, 5.2, 5.3, 5.4, 5.5_

  - [x]* 6.2 编写 Property 3 属性测试（捕获正确性）
    - **Property 3: 捕获正确性**
    - **Validates: Requirements 1.1, 1.2, 1.3, 1.4, 1.5, 1.6, 2.4, 8.4, 11.2**
    - 新建 `prop_captures_test.mbt`：对含捕获/命名/非捕获组模式与成功匹配输入，校验第 0 组=整体区间、各已设置组为第 0 组子区间且切片等于实际匹配子串、非捕获组不占号、命名检索与编号检索一致、未参与组返回 `None`。≥100 迭代

  - [x]* 6.3 编写 Property 4 属性测试（贪婪/惰性单调性）
    - **Property 4: 贪婪 / 惰性单调性**
    - **Validates: Requirements 3.2, 3.3, 3.5**
    - 新建 `prop_greedy_lazy_test.mbt`：对含量词正则取贪婪/惰性两变体匹配同输入，校验贪婪整体区间长度恒不小于惰性。≥100 迭代

  - [x]* 6.4 编写 Property 5 属性测试（匹配策略序关系不变量）
    - **Property 5: 匹配策略序关系不变量**
    - **Validates: Requirements 2.3, 4.3, 4.4, 4.5**
    - 新建 `prop_match_kind_test.mbt`：校验 `LeftmostLongest` 起点不晚于 `LeftmostFirst` 起点且长度不小于后者。≥100 迭代

  - [x]* 6.5 编写 Property 6 属性测试（零宽不变量与断言位置判定）
    - **Property 6: 零宽不变量与断言位置判定**
    - **Validates: Requirements 5.2, 5.3, 5.7, 6.5, 6.6**
    - 新建 `prop_assert_test.mbt`：校验 `\b` 判定等于参考谓词「左右词字符性相异」、`\B` 为其逐位逻辑非；将任一满足的零宽断言（`\b`/`\B`/锚点/前瞻）插入正则任意位置，其对整体匹配消费长度贡献恒为 0；多行/非多行 `^`/`$` 行首尾与整串首尾判定复用同一位置逻辑。≥100 迭代

  - [x]* 6.6 编写 `pikevm` 单元测试
    - 新建 `pikevm_test.mbt`，覆盖入口存在性、病态输入线性见证、无匹配返回 `None` 不抛异常、前瞻成立/不成立、捕获不跨前瞻边界
    - _Requirements: 2.1, 2.5, 5.4, 5.5_

- [x] 7. 检查点 —— 执行引擎可用
  - 确保截至 Pike VM 的全部单元测试与属性测试通过（运行 native 后端前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`），如有疑问询问用户。

- [x] 8. DFA 最小化、惰性 DFA 与五路差分一致
  - [x] 8.1 实现 `minimize.mbt`：`Dfa::minimize`（Hopcroft 1971）
    - 在既有 `Dfa` 上追加方法 `pub fn Dfa::minimize(self) -> Dfa`（不改 `Dfa` 字段）
    - 初始按四元接受签名（接受性依赖锚点标志 `flags ∈ 0..3`）分可区分类，对「字符类 × 锚点标志」反向细化至不动点，合并不可区分态并重建 `trans`/`accept`/`bounds`
    - 文件头注释标注 Hopcroft 1971 与设计 4.8
    - _Requirements: 7.1, 7.2_

  - [x]* 8.2 编写 `minimize` 单元测试
    - 新建 `minimize_test.mbt`，覆盖最小化入口、等价态合并见证、最小化前后对代表输入判定一致
    - _Requirements: 7.1, 7.2, 7.5_

  - [x] 8.3 实现 `lazy_dfa.mbt`：`LazyDfa` 惰性按需子集构造
    - 定义 `pub struct LazyDfa { nfa; cache : Map[String, Int]; cores : Array[Array[Int]] }`，实现 `LazyDfa::new(nfa)` 与 `LazyDfa::find(input) -> Match?`
    - 执行时按需对 `(状态, 锚点标志, 字符类)` 增量计算后继核并缓存（复用既有 `Nfa::closure`/`move_on`），不预先物化整张转移表
    - 文件头注释标注 on-the-fly 子集构造与设计 4.9
    - _Requirements: 7.3, 7.4_

  - [x]* 8.4 编写 `lazy_dfa` 单元测试
    - 新建 `lazy_dfa_test.mbt`，覆盖入口、状态缓存命中、与完整 `to_dfa` 对代表输入判定一致
    - _Requirements: 7.3, 7.4_

  - [x]* 8.5 编写 Property 2 属性测试（多引擎差分一致性）
    - **Property 2: 多引擎差分一致性**
    - **Validates: Requirements 2.6, 7.4, 7.5, 7.6, 4.2**
    - 新建 `prop_diff_test.mbt`：对受支持子集正则与任意输入，校验五路——`Nfa::find`、`to_dfa` 后 `Dfa::find`、`Dfa::minimize` 后 DFA、`LazyDfa::find`、`Ast::of_regex` 喂入 Pike VM（`LeftmostLongest`）——给出逐字段相等的整体匹配区间。≥100 迭代

- [x] 9. 高层搜索 API（Pattern）
  - [x] 9.1 实现 `search.mbt`：`Pattern` 编译句柄与高层 API
    - 定义 `pub struct Pattern { prog : Program; kind : MatchKind }` 与 `Pattern::compile(pattern, flags~, kind~) -> Result[Pattern, ParseError]`（委托 `parse_pattern` + `compile_program`）
    - 实现 `is_match`/`find`/`captures`/`find_all`/`captures_all`/`replace`/`replace_all`/`split`
    - 不重叠枚举：自 `pos=0` 锚定搜索，命中 `[s,e)` 后 `pos=e`，空匹配 `s==e` 时 `pos=e+1` 保证终止；`find_iter` 作为 `find_all` 的别名/惰性形态
    - 替换引用解析 `repl` 中 `$0..$9`、`${name}`、`$$`，未设置组替换为空串；`split` 以全部不重叠匹配为分隔切分
    - 依赖 `pattern_parser.mbt`、`program.mbt`、`pikevm.mbt`、`captures.mbt`、`match_kind.mbt`
    - _Requirements: 8.1, 8.2, 8.3, 8.4, 8.5, 8.6, 8.7_

  - [x]* 9.2 编写 Property 7 属性测试（find_all 不重叠、穷尽且终止）
    - **Property 7: find_all 不重叠、穷尽且终止**
    - **Validates: Requirements 8.1, 8.2, 8.3, 8.8**
    - 新建 `prop_find_all_test.mbt`：校验相邻匹配后者 `start` 不小于前者 `end`、空匹配至少前进一字符使枚举有限终止、扫描覆盖整个输入。≥100 迭代

  - [x]* 9.3 编写 Property 8 属性测试（split / replace 重建一致性）
    - **Property 8: split / replace 重建一致性**
    - **Validates: Requirements 8.6, 8.7, 8.9**
    - 新建 `prop_split_replace_test.mbt`：校验 `split` 子串与分隔符匹配子串按序交错拼接逐字符重建原输入；`replace_all` 以 `$0` 恒等引用还原原输入，以 `$1`/`${name}` 引用时替换文本等于对应捕获组子串。≥100 迭代

  - [x]* 9.4 编写 `search` 单元测试
    - 新建 `search_test.mbt`，覆盖 `find_all`/`replace`/`replace_all`/`split`/`captures` 代表样例与空匹配前进、命名引用替换
    - _Requirements: 8.1, 8.5, 8.6, 8.7_

- [x] 10. 实战 demo 正则集
  - [x] 10.1 实现 `demo.mbt`：实战模式与样例
    - 实现 `demo_email()`（含命名/编号组）、`demo_ipv4()`（四个八位组捕获）、`demo_iso_date()`（`(?<year>..)-(?<month>..)-(?<day>..)`）、`demo_number()`（整数/小数/指数）与 `demo_cases() -> Array[(String, String)]`
    - 依赖 `search.mbt`（模式可经 `Pattern::compile` 验证）
    - _Requirements: 11.1, 11.2, 11.3_

  - [x]* 10.2 编写 `demo` 单元测试
    - 新建 `demo_test.mbt`，对每个 demo 模式与样例输入校验整体匹配、捕获组区间、`replace_all` 引用捕获组的预期结果
    - _Requirements: 11.2, 11.3_

- [x] 11. 检查点 —— 搜索 API 与 demo 可用
  - 确保高层搜索 API、demo 与全部属性/单元测试通过（运行 native 后端前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`），如有疑问询问用户。

- [x] 12. 性能基准（benches/regex_bench）
  - [x] 12.1 创建 `benches/regex_bench` 基准包并实现三路基准与工件输出
    - 新建 `benches/regex_bench/regex_bench.mbt`、`moon.pkg`、`pkg.generated.mbti`，结构对齐既有 `benches/astar_bench`
    - 对三路执行（`Nfa::find`、`Dfa::find`、`Program::exec`）在两类负载计时：病态输入（`a?{n}a{n}` 应用于 `a^n`）与真实负载（复用 `demo_*` 模式 × 规模化输入）
    - 输出含机器标识、后端目标、输入规模与计时统计的 JSON/Markdown 工件到 `benches/results/`
    - 文档记录运行命令，并要求 native 运行前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - 依赖 `pikevm.mbt`、`demo.mbt` 及既有 `nfa.mbt`/`dfa.mbt`
    - _Requirements: 9.1, 9.2, 9.3, 9.5_

  - [x] 12.2 实现基准回归基线 guard 比较
    - 在 `benches/regex_bench/regex_bench.mbt` 中追加：将新运行与已记入基线中位数比较，超声明容差时给出可审计失败报告（复用既有 guard 模式）
    - 运行 native 基准前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`
    - _Requirements: 9.3, 9.4_

- [x] 13. 可执行文档与发布推进
  - [x] 13.1 扩充 `README.mbt.md` 可执行文档
    - 扩充 `src/regex_engine/README.mbt.md`，覆盖捕获、惰性量词、零宽断言、字符类标志、高层搜索 API 与实战 demo（含 `$1`/`${name}` 替换）
    - 显式声明实现边界（前瞻仅 Pike VM 路径、DFA 不支持、捕获不跨前瞻、不支持后瞻/反向引用）与 RE2/Rust `regex`/PCRE 对标
    - 全部示例须通过 `moon test *.mbt.md`（运行 native 校验前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）
    - _Requirements: 5.6, 10.5, 10.6, 11.4, 13.3_

  - [x] 13.2 推进 `release.mbt` 版本与门禁聚合
    - 更新 `release.mbt` 中本方向版本号字符串（自 `0.1.0` 起按旗舰深化做次/主版本推进），保持 `release_info`/`release_info_with_gates` 既有语义
    - 经 `release_info_with_gates` 聚合三后端测试/属性测试/可执行文档门禁，任一未过即阻止进入 release-ready
    - _Requirements: 12.5, 13.5, 13.6_

  - [x] 13.3 更新 `CHANGELOG.md`
    - 在 `src/regex_engine/CHANGELOG.md` 记录本次旗舰深化的 SemVer 推进与新增能力条目
    - _Requirements: 13.5_

- [x] 14. 最终检查点 —— 全量门禁
  - 确保三后端（`wasm-gc`/`js`/`native`）下全部单元测试、属性测试（每条 ≥100 迭代）与 `README.mbt.md` 可执行文档全部通过，基准 guard 无回归（运行 native 前先 `export LIBRARY_PATH=/usr/lib64:/usr/lib`），如有疑问询问用户。

## 备注（Notes）

- 标注 `*` 的子任务为可选（属性/单元/集成测试），可为快速 MVP 跳过；非 `*` 任务为核心实现，必须完成。
- 每个任务引用具体需求子条款以保证可追溯；每条属性测试单独成任务并标注 `Property N` 与 `**Validates: Requirements X.Y**`。
- 严格向后兼容：既有 `types/parser/printer/nfa/dfa/matcher/release` 与既有公开 API 签名/语义冻结，`ParseError` 枚举不扩容；新能力以新增文件/类型与只增方法旁路扩展。
- 全部属性测试复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip`，每条 ≥100 迭代，统一标注 `Feature: regex-engine, Property {n}: {text}`。
- **native 测试 / 基准 / 文档校验前必须先执行** `export LIBRARY_PATH=/usr/lib64:/usr/lib`（见任务 7、11、12、13.1、14）。
- 检查点用于增量验证；属性测试覆盖通用不变量，单元测试覆盖具体见证与边界/错误条件。

## 任务依赖图（Task Dependency Graph）

```json
{
  "waves": [
    { "id": 0, "tasks": ["1.1", "1.2", "1.3", "4.1", "8.1", "8.3"] },
    { "id": 1, "tasks": ["2.1", "1.4", "1.5", "4.2", "8.2", "8.4"] },
    { "id": 2, "tasks": ["2.2", "2.3", "3.1", "5.1"] },
    { "id": 3, "tasks": ["3.2", "3.3", "5.2", "6.1"] },
    { "id": 4, "tasks": ["6.2", "6.3", "6.4", "6.5", "6.6", "8.5", "9.1"] },
    { "id": 5, "tasks": ["9.2", "9.3", "9.4", "10.1"] },
    { "id": 6, "tasks": ["10.2", "12.1", "13.1"] },
    { "id": 7, "tasks": ["12.2", "13.2", "13.3"] }
  ]
}
```
