# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Regex_Engine（方向二）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开类型与 API（语法树 `Regex`、`CharClass`/`ClassItem`/`AnchorKind`、含位置的 `ParseError`、`Match`、自动机类型 `Nfa`/`Dfa`/`CharSet`，以及函数 `parse_regex`/`print_regex`/`build_nfa`/`to_dfa`/`Nfa::find`/`Dfa::find`/`find`/`is_match`），并在既有 `syntax → parser → nfa → dfa → matcher` 流水线之上扩展为一套对标 Google RE2、Rust `regex` crate 与 PCRE 的旗舰级正则引擎库。

旗舰目标聚焦八条主线：

- **捕获与子匹配**：在自动机流水线上引入编号捕获组、命名捕获组与非捕获组 `(?:...)`，提取各组匹配区间。
- **Pike VM 执行引擎**：在不退化为回溯指数复杂度的前提下，以 Thompson NFA + 捕获寄存器的 Pike VM（Russ Cox）支持捕获与子匹配提取。
- **量词语义与匹配策略**：补齐惰性/非贪婪量词 `*?` `+?` `??` `{m,n}?`，并明确 leftmost-longest（POSIX）与 leftmost-first（PCRE/Perl）两种可选匹配语义。
- **零宽断言与字符类增强**：词边界 `\b`/`\B`、可选前瞻 `(?=...)`/`(?!...)`，预定义字符类 `\d \D \w \W \s \S`、点号 `.` 与 dotall、大小写不敏感 `i`、多行 `m` 标志。
- **性能路径**：Hopcroft DFA 最小化与可选惰性 DFA 构造，作为高吞吐路径，并与 NFA/Pike VM 保持差分一致。
- **高层搜索 API**：`find_all`/`find_iter`（全部不重叠匹配）、`replace`/`replace_all`、`split`、`captures` 提取，语义与底层匹配策略一致。
- **可解释性**：paper-to-code 可追溯（Thompson 1968、Glushkov、子集构造、Hopcroft 1971、Russ Cox / Pike VM、POSIX 最左最长），并与 RE2、Rust `regex`、PCRE 的语义与性能模型对比、显式声明本库差异。
- **质量门禁**：完整属性测试（往返、三路差分一致、最小化前后等价、捕获正确性、贪婪/惰性语义、`find_all` 不重叠且穷尽、`replace` 正确性、错误位置单调性等），三后端（`wasm-gc`/`js`/`native`）一致性，`README.mbt.md` 可执行文档扩充，性能基准与回归基线 guard，以及独立 SemVer 版本推进。

本规格承袭仓库统一质量基线（见 Requirement 13），并复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **Regex_Engine**：本方向的正则表达式引擎库系统（子包 `src/regex_engine`），是本文档所有验收标准的主体系统。
- **Regex**：正则语法树类型，含 `Char`/`Class`/`Star`/`Plus`/`Opt`/`Repeat`/`Concat`/`Alt`/`Anchor`/`Group` 等节点。
- **CharClass / ClassItem**：字符类及其成员项（单字符 `Single` 或范围 `Range`），`negated` 标记否定字符类。
- **CharSet**：以有序整数区间数组 `intervals` 表示的字符集合（Unicode 标量码点闭区间），用于自动机的字符转移。
- **AnchorKind**：位置锚点类型，`Start`（`^`）与 `End`（`$`）。
- **ParseError**：含字符偏移位置的解析错误枚举（`Unexpected`/`Unbalanced`/`DanglingQuantifier`/`InvalidRepeat`/`TrailingInput`），均可经 `ParseError::pos` 提取位置。
- **Match**：单次匹配区间 `{ start, end }`，为半开区间 `[start, end)`，偏移基于输入的 Unicode 标量字符序列。
- **Captures（捕获结果）**：一次匹配中整体匹配区间与各捕获组区间的集合；第 0 组为整体匹配，第 1..n 组按左括号出现顺序编号，未参与匹配的组为「未设置」。
- **捕获组（Capturing Group）**：以 `( ... )` 包裹并被编号、其匹配区间会被提取的分组。
- **命名捕获组（Named Capturing Group）**：以 `(?<name>...)`（亦记 `(?P<name>...)`）语法命名、可按名称检索区间的捕获组。
- **非捕获组（Non-Capturing Group）**：以 `(?:...)` 包裹、仅用于约束量词/择一作用范围而不分配捕获编号的分组。
- **Nfa**：Thompson 构造得到的非确定有限自动机，含 ε 转移、字符转移（基于 `CharSet`）与建模为位置受限 ε 转移的锚点转移。
- **Dfa**：经子集构造（subset construction）从 `Nfa` 得到的确定有限自动机，字母表按原子区间划分。
- **Pike VM**：以 Thompson NFA 程序 + 捕获寄存器线程列表执行匹配的虚拟机（Russ Cox），在保证线性时间复杂度的同时支持子匹配提取。
- **DFA 最小化（DFA Minimization）**：以 Hopcroft 1971 算法将 DFA 合并等价状态，得到状态数最小且语言等价的 DFA。
- **惰性 DFA（Lazy DFA）**：按需在匹配过程中增量构造并缓存 DFA 状态（on-the-fly subset construction）的执行路径。
- **leftmost-longest（POSIX 最左最长）**：在所有起点最靠左的匹配中选取最长者的匹配语义（既有 `find`/`Dfa::find` 采用）。
- **leftmost-first（PCRE/Perl 最左优先）**：起点最靠左、并按正则书写的择一与量词优先顺序选取首个成功匹配的语义。
- **贪婪量词（Greedy Quantifier）**：在不破坏整体匹配的前提下尽可能多匹配的量词（`*` `+` `?` `{m,n}`）。
- **惰性量词（Lazy / Reluctant Quantifier）**：在不破坏整体匹配的前提下尽可能少匹配的量词（`*?` `+?` `??` `{m,n}?`）。
- **零宽断言（Zero-Width Assertion）**：不消费字符、仅对当前位置施加条件的构造，如词边界 `\b`/`\B` 与前瞻 `(?=...)`/`(?!...)`。
- **词边界（Word Boundary）**：`\b` 在词字符与非词字符（或串首/串尾）的过渡位置成立，`\B` 在其补集位置成立；词字符即 `\w` 所定义的集合。
- **前瞻（Lookahead）**：正向前瞻 `(?=p)`（当前位置之后能匹配 `p`）与负向前瞻 `(?!p)`（当前位置之后不能匹配 `p`），均不消费输入。
- **预定义字符类（Predefined Character Class）**：`\d`/`\D`（数字/非数字）、`\w`/`\W`（词字符/非词字符）、`\s`/`\S`（空白/非空白）。
- **dotall 标志**：标志 `s`，使点号 `.` 匹配包含换行在内的任意字符；未启用时 `.` 不匹配换行符。
- **大小写不敏感标志（Case-Insensitive Flag）**：标志 `i`，使字面字符与字符类按大小写折叠（case folding）进行匹配。
- **多行标志（Multiline Flag）**：标志 `m`，使锚点 `^`/`$` 分别匹配每一行的行首与行尾，而非仅整串首尾。
- **标志集（Flag Set）**：编译正则时生效的标志组合（至少含 `i`/`m`/`s`），影响匹配语义。
- **find_all / find_iter**：返回输入中全部互不重叠匹配区间的搜索 API（按从左到右扫描、每次匹配后从其末尾继续）。
- **replace / replace_all**：以替换文本替换首个/全部不重叠匹配的搜索 API；替换文本可引用捕获组。
- **split**：以匹配区间作为分隔符将输入切分为子串数组的搜索 API。
- **不重叠（Non-Overlapping）**：相邻两次匹配区间不共享任何字符，即后一匹配的 `start` 不小于前一匹配的 `end`。
- **穷尽（Exhaustive）**：`find_all` 在每个可匹配起点（按扫描顺序、不重叠约束下）均产出匹配，扫描覆盖整个输入。
- **差分一致性（Differential Consistency）**：对同一正则与输入，多条执行路径（NFA / DFA / Pike VM / 最小化 DFA）给出一致的匹配判定与匹配区间。
- **往返（Round-Trip）**：`parse_regex` 与 `print_regex` 互逆，对合法语法树先打印再解析得到等价语法树。
- **错误位置单调性（Error-Position Monotonicity）**：对结构上更长的非法前缀，所报告的错误位置不早于其更短非法前缀的错误位置（在可比较的同类错误下）。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：捕获组与子匹配提取

**用户故事（User Story）：** 作为从文本中抽取结构化片段的开发者，我想要编号与命名捕获组以及非捕获组，以便我能在一次匹配中提取出感兴趣的各个子串区间。

#### 验收标准（Acceptance Criteria）

1. WHEN 解析含 `( ... )` 的正则，THE Regex_Engine SHALL 按左括号在源文本中出现的顺序为每个捕获组分配从 `1` 起始的整数编号。
2. WHEN 解析含 `(?:...)` 的正则，THE Regex_Engine SHALL 将该分组识别为非捕获组，使其约束量词与择一的作用范围但不分配捕获编号。
3. WHEN 解析含 `(?<name>...)` 形式的正则，THE Regex_Engine SHALL 将该分组识别为命名捕获组，既分配整数编号又登记其名称。
4. WHEN 一次匹配成功，THE Regex_Engine SHALL 产出第 `0` 组为整体匹配区间、第 `1..n` 组为各捕获组匹配区间的捕获结果。
5. IF 某捕获组在成功匹配中未参与匹配（如位于未走通的择一分支），THEN THE Regex_Engine SHALL 将该组标记为未设置（无区间）而非报告整体匹配失败。
6. WHEN 调用方按名称检索命名捕获组的区间，THE Regex_Engine SHALL 返回该名称对应编号的捕获组区间或未设置标记。
7. IF 正则中出现重复的捕获组名称，THEN THE Regex_Engine SHALL 返回携带冲突位置的解析错误，且不构造自动机。

---

### Requirement 2：Pike VM 执行引擎与捕获

**用户故事（User Story）：** 作为处理可能引发灾难性回溯输入的开发者，我想要一个线性时间且支持捕获的执行引擎，以便我能在病态输入上既提取子匹配又避免指数级耗时。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 提供基于 Thompson NFA 程序与捕获寄存器线程列表的 Pike VM 执行入口，对正则与输入产出含捕获结果的匹配。
2. WHILE 执行 Pike VM，THE Regex_Engine SHALL 维护每个输入位置至多保留一条等价线程，使运行步数与「正则规模 × 输入长度」成线性关系。
3. WHEN 多条线程在同一状态汇合，THE Regex_Engine SHALL 依所选匹配策略的优先级保留唯一线程的捕获寄存器，丢弃低优先级线程。
4. WHEN Pike VM 匹配成功，THE Regex_Engine SHALL 产出与该正则各捕获组对应的子匹配区间。
5. IF 输入在 Pike VM 上无任何匹配，THEN THE Regex_Engine SHALL 返回无匹配结果且不抛出运行期异常。
6. FOR ALL 由生成器产生的正则与输入，THE Regex_Engine SHALL 保证 Pike VM 的整体匹配区间判定与既有 `Nfa::find` 在同一匹配策略下一致（NFA/Pike VM 差分一致，以 PBT 验证）。

---

### Requirement 3：量词贪婪性与惰性量词

**用户故事（User Story）：** 作为需要精确控制匹配范围的开发者，我想要惰性量词与既有贪婪量词共存，以便我能表达「尽可能少」的匹配并得到可预期的子匹配区间。

#### 验收标准（Acceptance Criteria）

1. WHEN 解析量词后缀 `*?`、`+?`、`??` 或 `{m,n}?`，THE Regex_Engine SHALL 将对应量词标记为惰性量词，且保留既有贪婪量词 `*`、`+`、`?`、`{m,n}` 的语法与语义。
2. WHILE 以贪婪量词匹配，THE Regex_Engine SHALL 在不破坏整体匹配成功的前提下使该量词匹配尽可能多的字符。
3. WHILE 以惰性量词匹配，THE Regex_Engine SHALL 在不破坏整体匹配成功的前提下使该量词匹配尽可能少的字符。
4. IF 惰性量词的最少重复次数无法满足整体匹配，THEN THE Regex_Engine SHALL 在必要范围内增加重复次数直至整体匹配成功或确定无匹配。
5. FOR ALL 由生成器产生的含量词正则与输入，THE Regex_Engine SHALL 保证贪婪量词所得整体匹配区间长度不小于同位置惰性变体所得整体匹配区间长度（贪婪/惰性单调性，以 PBT 验证）。

---

### Requirement 4：匹配策略 —— leftmost-longest 与 leftmost-first

**用户故事（User Story）：** 作为同时面向 POSIX 与 PCRE 习惯的开发者，我想要可选的匹配语义，以便我能按目标生态选择最左最长或最左优先的匹配行为。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 提供匹配策略选项，至少包含 leftmost-longest（POSIX）与 leftmost-first（PCRE/Perl）两种语义。
2. WHERE 未显式指定匹配策略，THE Regex_Engine SHALL 采用 leftmost-longest 语义，以保持与既有 `find`/`is_match` 行为兼容。
3. WHILE 采用 leftmost-longest 语义，THE Regex_Engine SHALL 在所有起点最靠左的匹配中选取末尾位置最大（最长）的匹配区间。
4. WHILE 采用 leftmost-first 语义，THE Regex_Engine SHALL 选取起点最靠左、并按择一分支书写顺序与量词贪婪/惰性优先级确定的首个成功匹配区间。
5. FOR ALL 由生成器产生的正则与输入，THE Regex_Engine SHALL 保证在 leftmost-longest 策略下整体匹配区间的起点不晚于、长度不小于同输入 leftmost-first 策略下的整体匹配区间（策略序关系不变量，以 PBT 验证）。

---

### Requirement 5：零宽断言 —— 词边界与前瞻

**用户故事（User Story）：** 作为需要按上下文约束匹配的开发者，我想要词边界与前瞻断言，以便我能在不消费字符的前提下根据相邻内容限定匹配位置。

#### 验收标准（Acceptance Criteria）

1. WHEN 解析 `\b` 或 `\B`，THE Regex_Engine SHALL 将其识别为零宽词边界断言，匹配时不消费字符。
2. WHILE 匹配 `\b`，THE Regex_Engine SHALL 仅在词字符与非词字符之间的过渡位置（含串首前与串尾后视为非词字符）判定成立。
3. WHILE 匹配 `\B`，THE Regex_Engine SHALL 仅在 `\b` 不成立的位置判定成立。
4. WHEN 解析 `(?=p)`，THE Regex_Engine SHALL 将其识别为正向前瞻：仅当当前位置之后能匹配 `p` 时该断言成立且不消费输入。
5. WHEN 解析 `(?!p)`，THE Regex_Engine SHALL 将其识别为负向前瞻：仅当当前位置之后不能匹配 `p` 时该断言成立且不消费输入。
6. WHERE 前瞻断言所需的能力超出本库自动机执行模型可支持的范围，THE Regex_Engine SHALL 在文档中显式声明该实现边界与取舍。
7. FOR ALL 由生成器产生的含零宽断言正则与输入，THE Regex_Engine SHALL 保证零宽断言所在位置的匹配不改变整体匹配区间中由该断言贡献的消费长度（零宽不变量恒为 0，以 PBT 验证）。

---

### Requirement 6：字符类增强与编译标志

**用户故事（User Story）：** 作为编写实用正则的开发者，我想要预定义字符类与大小写、点号、多行等标志，以便我能简洁表达常见字符集合并按场景调整匹配语义。

#### 验收标准（Acceptance Criteria）

1. WHEN 解析 `\d`、`\D`、`\w`、`\W`、`\s`、`\S`，THE Regex_Engine SHALL 将其分别解析为数字、非数字、词字符、非词字符、空白、非空白的字符集合。
2. WHILE 未启用 dotall 标志，THE Regex_Engine SHALL 使点号 `.` 匹配除换行符之外的任意单个字符。
3. WHILE 启用 dotall 标志（`s`），THE Regex_Engine SHALL 使点号 `.` 匹配包含换行符在内的任意单个字符。
4. WHILE 启用大小写不敏感标志（`i`），THE Regex_Engine SHALL 对字面字符与字符类成员按大小写折叠进行匹配。
5. WHILE 启用多行标志（`m`），THE Regex_Engine SHALL 使锚点 `^` 匹配每行行首、`$` 匹配每行行尾。
6. WHILE 未启用多行标志，THE Regex_Engine SHALL 使锚点 `^` 仅匹配整串起始、`$` 仅匹配整串末尾，以保持与既有锚点语义兼容。
7. THE Regex_Engine SHALL 将预定义字符类与标志的语义统一规约为基于 `CharSet` 的区间集合运算，使其与既有字符类匹配路径一致。

---

### Requirement 7：DFA 最小化与惰性 DFA

**用户故事（User Story）：** 作为追求高吞吐匹配的开发者，我想要最小化 DFA 与按需构造的惰性 DFA，以便我能在保持语义一致的同时降低状态规模与构造开销。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 提供以 Hopcroft 算法将 `Dfa` 最小化的入口，产出状态数最小且语言等价的 DFA。
2. WHEN 对一个 `Dfa` 执行最小化，THE Regex_Engine SHALL 合并所有不可区分的等价状态，且不改变任一输入的匹配判定。
3. THE Regex_Engine SHALL 提供惰性 DFA 执行路径，在匹配过程中按需增量构造并缓存所需 DFA 状态。
4. WHILE 以惰性 DFA 匹配，THE Regex_Engine SHALL 对同一正则与输入产出与完整子集构造 DFA 一致的匹配判定。
5. FOR ALL 由生成器产生的正则与输入，THE Regex_Engine SHALL 保证最小化前后的 DFA 在同一输入上产生一致的整体匹配区间（最小化语言等价，以 PBT 验证）。
6. FOR ALL 由生成器产生的正则与输入，THE Regex_Engine SHALL 保证 NFA、子集构造 DFA、最小化 DFA 与 Pike VM 四条路径在同一匹配策略下的整体匹配判定一致（四路差分一致，以 PBT 验证）。

---

### Requirement 8：高层搜索 API

**用户故事（User Story）：** 作为在真实文本上做查找替换的开发者，我想要 `find_all`/`replace`/`split`/`captures` 等高层 API，以便我能直接完成扫描、抽取、替换与切分而无需手写循环。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用 `find_all`（或 `find_iter`），THE Regex_Engine SHALL 按从左到右扫描产出输入中全部互不重叠的匹配区间。
2. WHILE 枚举不重叠匹配，THE Regex_Engine SHALL 在每次匹配后从该匹配末尾位置继续扫描，使相邻匹配区间不共享任何字符。
3. IF 某次匹配为空匹配（`start == end`），THEN THE Regex_Engine SHALL 将扫描位置至少前进一个字符以保证枚举终止。
4. WHEN 调用 `captures`，THE Regex_Engine SHALL 返回整体匹配区间与各捕获组（含命名组）的区间集合。
5. WHEN 调用 `replace`，THE Regex_Engine SHALL 以替换文本替换首个匹配；WHEN 调用 `replace_all`，THE Regex_Engine SHALL 替换全部不重叠匹配。
6. WHERE 替换文本含捕获组引用（如 `$1` 或 `${name}`），THE Regex_Engine SHALL 以对应捕获组的匹配子串替换该引用。
7. WHEN 调用 `split`，THE Regex_Engine SHALL 以全部不重叠匹配区间作为分隔符将输入切分为子串数组。
8. FOR ALL 由生成器产生的正则与输入，THE Regex_Engine SHALL 保证 `find_all` 产出的相邻匹配区间满足后一匹配 `start` 不小于前一匹配 `end`（不重叠不变量，以 PBT 验证）。
9. FOR ALL 由生成器产生的正则与输入，THE Regex_Engine SHALL 保证 `split` 所得子串按序拼接所有分隔符匹配子串后能逐字符重建原输入（split/replace 重建一致性，以 PBT 验证）。

---

### Requirement 9：性能基准（benches/）

**用户故事（User Story）：** 作为关心匹配性能的开发者，我想要可复现的基准证据，以便我能比较 NFA、DFA 与 Pike VM 在病态输入与真实负载上的表现并防止性能回归。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 在 `benches/` 下提供正则匹配基准包，覆盖 NFA、DFA 与 Pike VM 三种执行路径。
2. THE Regex_Engine SHALL 在基准中同时包含病态输入（如 `a?^n a^n` 形态）与真实负载（如 email、URL、数字字面量）两类工作负载。
3. WHEN 运行基准，THE Regex_Engine SHALL 输出包含机器标识、后端目标、输入规模与计时统计的基准结果工件（JSON 或 Markdown）。
4. WHERE 提供基准回归基线，THE Regex_Engine SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告。
5. THE Regex_Engine SHALL 在基准文档中记录运行命令，且在 native 后端要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。

---

### Requirement 10：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键算法可追溯到源论文并与主流开源引擎对比，以便我能理解设计依据与取舍。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 在文档中将 NFA 构造追溯到 Thompson 1968《Regular Expression Search Algorithm》（并视情对照 Glushkov 构造）。
2. THE Regex_Engine SHALL 在文档中将 NFA 到 DFA 的转换追溯到子集构造（subset construction），将 DFA 最小化追溯到 Hopcroft 1971 算法。
3. THE Regex_Engine SHALL 在文档中将 Pike VM 与线性时间匹配追溯到 Russ Cox《Regular Expression Matching Can Be Simple And Fast》及 Pike VM 设计。
4. THE Regex_Engine SHALL 在文档中将 leftmost-longest 匹配语义追溯到 POSIX 正则规范。
5. THE Regex_Engine SHALL 在文档中提供与 Google RE2、Rust `regex` crate 及 PCRE 的语义与性能模型对比，覆盖匹配策略、捕获支持与复杂度保证的差异。
6. WHERE 本库不支持某类构造（如回溯型反向引用 backreference）或在前瞻等能力上存在实现边界，THE Regex_Engine SHALL 显式声明该差异及其理由，而非隐式留白。

---

### Requirement 11：端到端实战 demo

**用户故事（User Story）：** 作为评估该库可用性的开发者，我想要一个贯穿文档与基准的实战正则集，以便我能看到匹配、捕获与替换在真实模式上的端到端用法。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 提供一个贯穿文档与基准的实战正则集，至少覆盖 email、IPv4 地址、ISO 日期与数字字面量四类模式。
2. WHEN 对实战正则集中的某一模式与匹配输入运行匹配，THE Regex_Engine SHALL 产出整体匹配区间及该模式定义的各捕获组区间。
3. WHEN 对实战正则集运行替换演示，THE Regex_Engine SHALL 经 `replace_all` 并引用捕获组产出预期的替换结果。
4. THE Regex_Engine SHALL 在 `README.mbt.md` 可执行文档中以该实战正则集演示匹配、捕获与替换，且全部示例通过 `moon test *.mbt.md` 验证。

---

### Requirement 12：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有代码在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 保留既有公开类型 `Regex`、`CharClass`、`ClassItem`、`AnchorKind`、`CharSet`、`Match`、`ParseError`、`Nfa`、`Dfa` 及其现有公开方法的签名与语义。
2. THE Regex_Engine SHALL 保留既有函数 `parse_regex`、`print_regex`、`build_nfa`、`to_dfa`、`Nfa::find`、`Dfa::find`、`find`、`is_match` 的现有公开签名与行为。
3. WHERE 新增能力需要扩展行为，THE Regex_Engine SHALL 以新增 API（如捕获、Pike VM、标志、高层搜索）的方式提供，而不破坏既有 API 的调用方。
4. THE Regex_Engine SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板。
5. THE Regex_Engine SHALL 复用 `@release_meta` 的 `DirectionRelease`/`QualityGates`/SemVer 模型登记本方向发布元数据，并保持 `release_info`/`release_info_with_gates` 的现有语义。
6. FOR ALL 由生成器产生的合法语法树，THE Regex_Engine SHALL 满足往返性质：`parse_regex(print_regex(r))` 得到与 `r` 等价的语法树（round-trip property，以 PBT 验证）。

---

### Requirement 13：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Regex_Engine SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Regex_Engine SHALL 为本规格的核心正确性属性（往返、NFA/DFA/Pike VM/最小化 DFA 多路差分一致、最小化前后等价、捕获正确性、贪婪/惰性语义、`find_all` 不重叠且穷尽、`replace`/`split` 重建一致性、错误位置单调性）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE Regex_Engine SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖捕获、惰性量词、零宽断言、字符类标志、高层搜索 API 与实战 demo，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE Regex_Engine SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Regex_Engine SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE Regex_Engine SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
