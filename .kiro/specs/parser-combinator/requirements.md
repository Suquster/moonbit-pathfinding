# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Parser_Combinator（方向四）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并复用既有公开 API（`Parser[T]{run}`、`ParseResult[T]{Ok(T,Input) | Fail(Pos, expected~)}`、不可变游标 `Input`、`Pos`、`ParseResult::to_path_error` 到 `@core.PathError` 的桥接，以及现有原语 `pchar`/`satisfy`/`any_char`/`ptoken` 与组合子 `seq`/`alt`/`many`/`many1`/`optional`），并在其上扩展为一套对标 Haskell `parsec`/`megaparsec` 与 Rust `nom` 的旗舰级解析器组合子库。

旗舰目标聚焦六条主线：

- **完整组合子代数**：补齐 functor/monad/applicative 层（`map`/`bind`/`pure`）与衍生组合子（`sep_by`/`sep_by1`/`between`/`chainl`/`chainl1`/`chainr`/`chainr1`/`lookahead`/`not_followed_by`/`lazy`/`label`/`<?>`），形成可组合的代数地基。
- **错误处理与恢复**：引入消费提交语义（`commit`/`cut`）、期望集合合并、最远失败位置（farthest-failure）报告与含位置的友好错误信息。
- **性能工程**：packrat 记忆化、直接左递归处理（seed-growing，Warth et al. 2008）、流式/增量输入支持，并提供可复现基准（`benches/`）。
- **旗舰端到端示例**：JSON 解析器（递归结构、字符串转义、错误定位与恢复）与算术表达式求值器（运算符优先级、`chainl`/`chainr`、左递归）贯穿文档、基准与对标。
- **可解释性**：paper-to-code 可追溯（Hutton & Meijer 1998、Leijen & Meijer Parsec、Ford 2002 PEG/packrat、Warth 2008 左递归），以及与 `parsec`/`megaparsec`/`nom` 的 API 与语义对比说明。
- **质量门禁**：完整属性测试（functor/monad/alternative 代数定律、往返、错误位置单调性、packrat 与朴素实现一致性等），三后端（`wasm-gc`/`js`/`native`）一致性，`README.mbt.md` 可执行文档扩充，以及独立 SemVer 版本推进。

本规格承袭仓库统一质量基线（见 Requirement 12），并复用 `@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、`@release_meta`（`DirectionRelease`/`QualityGates`/SemVer）与 `README.mbt.md`「文档即测试」模式。

---

## 术语表（Glossary）

- **Parser_Combinator**：本方向的解析器组合子库系统（子包 `src/parser_combinator`），是本文档所有验收标准的主体系统。
- **Parser[T]**：解析器类型，包装一个 `(Input) -> ParseResult[T]` 函数，产出类型为 `T` 的值。
- **ParseResult[T]**：解析结果枚举，`Ok(value, rest)` 表示成功（携带产出值与剩余未消费输入）、`Fail(pos, expected~)` 表示失败（携带失败位置与期望符号集合）。
- **Input**：不可变解析输入游标，持有只读字符序列与当前位置 `pos`，所有推进返回新 `Input`，天然支持回溯。
- **Pos**：源码位置，含 `line`（1 起始行号）、`col`（1 起始列号）、`offset`（0 起始字符偏移）。
- **组合子（Combinator）**：接收若干 `Parser` 并返回新 `Parser` 的高阶构造，如 `seq`/`alt`/`map`/`bind`/`chainl`。
- **原语（Primitive）**：直接匹配终结符的叶子解析器，如 `pchar`/`satisfy`/`ptoken`。
- **Functor 定律（Functor Laws）**：`map(p, id) ≡ p`（恒等）与 `map(p, g ∘ f) ≡ map(map(p, f), g)`（复合）。
- **Monad 定律（Monad Laws）**：左单位元 `bind(pure(a), f) ≡ f(a)`、右单位元 `bind(p, pure) ≡ p`、结合律 `bind(bind(p, f), g) ≡ bind(p, fn(x) { bind(f(x), g) })`。
- **Applicative 定律（Applicative Laws）**：以 `pure` 与序列应用为基础的恒等/复合/同态/交换律（本规格至少校验恒等与同态）。
- **Alternative 定律（Alternative Laws）**：`alt` 与失败元素构成的左/右单位元律与结合性（在 PEG 有序选择语义下校验）。
- **回溯（Backtracking）**：择一分支失败时恢复到分支起始 `Input`、不消费输入的语义。
- **消费提交语义（Commit / Cut）**：`commit`（亦记 `cut`）将其内部解析标记为「已提交」；提交后该分支的失败不再被外层 `alt` 回溯吞掉，而是作为硬失败向上传播。
- **硬失败（Committed Failure）**：发生在已提交点之后的失败，`alt` 不再尝试后续分支。
- **软失败（Recoverable Failure）**：未跨越提交点的失败，`alt` 可回溯并尝试后续分支。
- **最远失败位置（Farthest-Failure Position）**：在多分支尝试中记录到的、推进得最远（`offset` 最大）的失败位置，用于生成更贴近用户意图的错误信息。
- **期望集合合并（Expected-Set Merge）**：当多个分支在同一最远位置失败时，将各分支的期望符号去重合并为单一期望集合。
- **label / `<?>`**：为解析器附加人类可读名称的组合子；失败时以该名称替换底层期望符号，产出友好错误。
- **chainl / chainl1**：以左结合方式用二元运算符解析器折叠操作数序列的组合子（`chainl1` 要求至少一个操作数）。
- **chainr / chainr1**：以右结合方式折叠操作数序列的组合子（`chainr1` 要求至少一个操作数）。
- **sep_by / sep_by1**：以分隔符解析器分隔、收集零个或多个（`sep_by1` 为一个或多个）元素的组合子。
- **between**：先消费开括号、再运行主体、最后消费闭括号并仅保留主体产出的组合子。
- **lookahead**：前瞻组合子，尝试运行内部解析器但成功时不消费输入。
- **not_followed_by**：否定前瞻，仅当内部解析器在当前位置失败时成功，且不消费输入。
- **lazy**：延迟构造组合子，把解析器的构造推迟到运行时，用于打破递归文法的构造期循环依赖。
- **packrat 记忆化（Packrat Memoization）**：对「解析器 × 输入位置」的结果进行缓存，使每个解析器在每个位置至多计算一次，从而把回溯型解析的最坏复杂度降为线性。
- **左递归（Left Recursion）**：产生式直接以自身作为最左符号（形如 `A := A op b | b`）的文法，朴素递归下降会无限递归。
- **seed-growing（种子增长）**：Warth 等人 2008 提出的、在 packrat 框架内通过「先置失败种子、迭代增长」支持直接左递归的算法。
- **增量输入 / 流式输入（Incremental / Streaming Input）**：以分段（chunk）方式逐步喂入源文本，解析器可在已到达数据上推进、在数据不足时报告「需要更多输入」的能力。
- **朴素实现（Naive Reference）**：不带记忆化的直接回溯解析器，作为 packrat 实现的差分一致性参照。
- **错误位置单调性（Error-Position Monotonicity）**：对同一解析器与输入，所报告的最终失败位置不早于其任一已成功消费前缀的末尾（失败位置随成功消费推进而不回退）。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease`/`QualityGates`/SemVer 模型。
- **@core.PathError**：仓库共享错误类型，`ParseResult::to_path_error` 将解析失败桥接为该类型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---

## 需求（Requirements）

### Requirement 1：核心代数层 —— functor / monad / applicative

**用户故事（User Story）：** 作为构建复杂解析器的开发者，我想要 `map`/`bind`/`pure` 等核心代数组合子，以便我能以单子风格组合解析器并对产出值做变换与依赖式串联。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 提供 `pure`，对任意值产出一个不消费输入且恒成功并携带该值的解析器。
2. WHEN 一个解析器成功并产出值 `v`，THE Parser_Combinator SHALL 经 `map(p, f)` 产出值 `f(v)` 且保持与 `p` 相同的输入消费量。
3. IF `map(p, f)` 中的 `p` 失败，THEN THE Parser_Combinator SHALL 原样传播 `p` 的失败位置与期望符号集合，且不调用 `f`。
4. WHEN `bind(p, f)` 中的 `p` 成功产出值 `v`，THE Parser_Combinator SHALL 在 `p` 的剩余输入上运行 `f(v)` 所返回的解析器。
5. IF `bind(p, f)` 中的 `p` 失败，THEN THE Parser_Combinator SHALL 原样传播 `p` 的失败，且不调用 `f`。
6. THE Parser_Combinator SHALL 在保留既有 `seq`/`alt`/`many`/`many1`/`optional` 公开签名不变的前提下提供上述核心代数组合子。

---

### Requirement 2：核心代数定律（functor / monad / applicative / alternative）

**用户故事（User Story）：** 作为依赖代数推理的库使用者，我想要核心组合子满足公认的代数定律，以便我能安全地重构解析器表达式而不改变其行为。

#### 验收标准（Acceptance Criteria）

1. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 满足 functor 恒等律 `map(p, fn(x){x})` 与 `p` 产生逐字段一致的解析结果（以 PBT 验证）。
2. FOR ALL 由生成器产生的解析器、输入与两个函数 `f`、`g`，THE Parser_Combinator SHALL 满足 functor 复合律 `map(p, fn(x){g(f(x))})` 与 `map(map(p, f), g)` 产生一致的解析结果（以 PBT 验证）。
3. FOR ALL 由生成器产生的值 `a`、函数 `f` 与输入，THE Parser_Combinator SHALL 满足 monad 左单位元律 `bind(pure(a), f)` 与 `f(a)` 产生一致的解析结果（以 PBT 验证）。
4. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 满足 monad 右单位元律 `bind(p, pure)` 与 `p` 产生一致的解析结果（以 PBT 验证）。
5. FOR ALL 由生成器产生的解析器、函数 `f`、`g` 与输入，THE Parser_Combinator SHALL 满足 monad 结合律 `bind(bind(p, f), g)` 与 `bind(p, fn(x){bind(f(x), g)})` 产生一致的解析结果（以 PBT 验证）。
6. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 满足 alternative 左单位元律：`alt([fail_parser, p])` 与 `p` 产生一致的解析结果，其中 `fail_parser` 为恒失败且不消费输入的解析器（以 PBT 验证）。
7. FOR ALL 由生成器产生的解析器三元组与输入，THE Parser_Combinator SHALL 满足在 PEG 有序选择语义下的 alternative 结合律：`alt([alt([p, q]), r])` 与 `alt([p, alt([q, r])])` 产生一致的解析结果（以 PBT 验证）。

---

### Requirement 3：衍生组合子代数

**用户故事（User Story）：** 作为解析结构化文本的开发者，我想要 `sep_by`/`between`/`chainl`/`chainr` 等高层组合子，以便我能直接表达列表、括号包裹与带优先级的运算符表达式而无需手写递归。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 提供 `sep_by(p, sep)`，对零个或多个由 `sep` 分隔的 `p` 实例收集为产出值数组，零个时产出空数组且不消费输入。
2. THE Parser_Combinator SHALL 提供 `sep_by1(p, sep)`，要求至少匹配一个 `p`，否则在 `p` 起始位置失败并报告 `p` 的期望符号。
3. WHEN 接收到形如「开符号 主体 闭符号」的输入，THE Parser_Combinator SHALL 经 `between(open, body, close)` 仅产出 `body` 的值并消费三者覆盖的全部输入。
4. WHEN 接收到操作数与左结合二元运算符交替的序列，THE Parser_Combinator SHALL 经 `chainl1(operand, op)` 以左结合方式折叠为单一产出值。
5. WHEN 接收到操作数与右结合二元运算符交替的序列，THE Parser_Combinator SHALL 经 `chainr1(operand, op)` 以右结合方式折叠为单一产出值。
6. WHERE 操作数序列可能为空，THE Parser_Combinator SHALL 经 `chainl(operand, op, default)` 与 `chainr(operand, op, default)` 在零操作数时产出 `default` 且不消费输入。
7. THE Parser_Combinator SHALL 提供 `lazy(thunk)`，将内部解析器的构造推迟到首次运行时求值，以支持递归文法的定义。

---

### Requirement 4：前瞻与否定前瞻

**用户故事（User Story）：** 作为需要上下文判定的开发者，我想要 `lookahead` 与 `not_followed_by`，以便我能在不消费输入的前提下根据后续内容决定解析分支。

#### 验收标准（Acceptance Criteria）

1. WHEN `lookahead(p)` 中的 `p` 在当前位置成功，THE Parser_Combinator SHALL 产出 `p` 的值且不消费输入（剩余输入位置与进入前一致）。
2. IF `lookahead(p)` 中的 `p` 失败，THEN THE Parser_Combinator SHALL 在进入位置失败并报告 `p` 的期望符号，且不消费输入。
3. WHEN `not_followed_by(p)` 中的 `p` 在当前位置失败，THE Parser_Combinator SHALL 成功、产出单位值且不消费输入。
4. IF `not_followed_by(p)` 中的 `p` 在当前位置成功，THEN THE Parser_Combinator SHALL 在进入位置失败且不消费输入。
5. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 保证 `lookahead(p)` 与 `not_followed_by(p)` 运行后的剩余输入偏移恒等于进入时的输入偏移（零消费不变量，以 PBT 验证）。

---

### Requirement 5：友好错误信息与 label

**用户故事（User Story）：** 作为调试解析失败的开发者，我想要带位置与可读名称的错误信息，以便我能快速定位失败处并理解解析器期望的内容。

#### 验收标准（Acceptance Criteria）

1. IF 任一解析器失败，THEN THE Parser_Combinator SHALL 返回 `Fail(pos, expected~)`，其中 `pos` 携带 `line`/`col`/`offset`、`expected` 为非空期望符号集合。
2. WHEN 对解析器应用 `label(p, name)`（亦记 `p <?> name`）且 `p` 在其起始位置失败，THE Parser_Combinator SHALL 以 `name` 替换 `p` 的期望符号集合作为失败的期望符号。
3. WHILE `label(p, name)` 中的 `p` 已消费了至少一个字符后再失败，THE Parser_Combinator SHALL 保留 `p` 原始的失败位置与期望符号，而不以 `name` 覆盖。
4. WHEN 调用方将失败结果经 `to_path_error` 桥接，THE Parser_Combinator SHALL 返回携带失败位置与期望符号文本的 `@core.PathError::InvalidInput` 值。
5. THE Parser_Combinator SHALL 在同一失败结果中以确定性顺序排列期望符号集合，使同一输入的重复解析产生逐元素一致的期望符号序列。

---

### Requirement 6：最远失败位置与期望集合合并

**用户故事（User Story）：** 作为面对多分支文法的开发者，我想要错误信息指向推进得最远的失败点并合并各分支的期望，以便错误更贴近真实意图而非停在第一个分支。

#### 验收标准（Acceptance Criteria）

1. WHEN `alt` 的所有分支均失败，THE Parser_Combinator SHALL 报告各分支失败中 `offset` 最大的最远失败位置。
2. WHILE 多个失败分支在同一最远失败位置上失败，THE Parser_Combinator SHALL 将这些分支的期望符号去重合并为单一期望集合。
3. WHEN 多个失败分支推进到不同位置，THE Parser_Combinator SHALL 仅采用最远位置分支的期望符号，并舍弃较早位置分支的期望符号。
4. FOR ALL 由生成器产生的解析器列表与输入，THE Parser_Combinator SHALL 保证 `alt` 报告的最远失败位置不早于任一分支单独失败时的位置（最远性不变量，以 PBT 验证）。
5. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 保证报告的失败位置不早于该解析器在该输入上任一成功子解析所消费前缀的末尾位置（错误位置单调性，以 PBT 验证）。

---

### Requirement 7：消费提交语义（commit / cut）与错误恢复

**用户故事（User Story）：** 作为构建大型文法的开发者，我想要在确认进入某产生式后「提交」该分支，以便后续失败产生精确的硬错误而非被回溯吞没，并支持局部错误恢复。

#### 验收标准（Acceptance Criteria）

1. WHEN 解析进入 `commit(p)` 且 `p` 之前的前缀已匹配，THE Parser_Combinator SHALL 将 `p` 范围内的后续失败标记为硬失败（committed failure）。
2. IF 某个 `alt` 分支在跨越提交点之后失败，THEN THE Parser_Combinator SHALL 停止尝试该 `alt` 的后续分支并向上传播该硬失败。
3. WHILE 某个 `alt` 分支在跨越提交点之前失败，THE Parser_Combinator SHALL 回溯到分支起始位置并继续尝试后续分支（软失败可恢复）。
4. WHEN 提供错误恢复组合子 `recover(p, sync)` 且 `p` 产生硬失败，THE Parser_Combinator SHALL 记录该失败并将输入推进到 `sync` 同步点之后以继续解析。
5. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 保证未包含任何提交点的解析器其 `commit` 语义为恒等：`commit(p)` 与 `p` 产生一致的解析结果（提交透明性，以 PBT 验证）。

---

### Requirement 8：packrat 记忆化

**用户故事（User Story）：** 作为解析大输入的开发者，我想要 packrat 记忆化，以便回溯型文法获得线性时间复杂度而不改变解析结果。

#### 验收标准（Acceptance Criteria）

1. WHERE 启用 packrat 记忆化，THE Parser_Combinator SHALL 对「被记忆解析器 × 输入位置」的解析结果至多计算一次，后续相同查询返回缓存结果。
2. WHEN 在同一输入位置以同一被记忆解析器重复求值，THE Parser_Combinator SHALL 返回与首次求值逐字段一致的 `ParseResult`（含产出值、剩余输入位置与失败诊断）。
3. FOR ALL 由生成器产生的解析器与输入，THE Parser_Combinator SHALL 保证启用 packrat 与朴素实现（naive reference）在同一输入上产生逐字段一致的解析结果（差分一致性，以 PBT 验证）。
4. THE Parser_Combinator SHALL 提供以记忆化执行解析器的入口，使调用方能在不修改解析器定义的情况下选择启用记忆化。
5. WHILE 记忆化缓存对应于某次解析运行，THE Parser_Combinator SHALL 将缓存生命周期限定于该次运行，使不同输入的解析互不污染缓存。

---

### Requirement 9：直接左递归处理（seed-growing）

**用户故事（User Story）：** 作为以自然左结合文法书写运算符表达式的开发者，我想要库支持直接左递归，以便我能直接写出 `expr := expr op term | term` 而不发生无限递归。

#### 验收标准（Acceptance Criteria）

1. WHERE 一个解析器经左递归入口（如 `lazy` 配合记忆化）定义为直接左递归，THE Parser_Combinator SHALL 以 seed-growing 算法求值而不进入无限递归。
2. WHEN 对直接左递归解析器在某位置求值，THE Parser_Combinator SHALL 以失败种子起始并迭代增长，直至增长不再消费更多输入时停止并返回最长匹配结果。
3. WHEN 直接左递归解析器成功，THE Parser_Combinator SHALL 产出与等价左结合文法（以 `chainl1` 表达）一致的左结合解析结果。
4. IF 左递归解析器在起始位置无任何可匹配的基础情形，THEN THE Parser_Combinator SHALL 返回携带起始位置与期望符号的失败，且不消费输入。
5. FOR ALL 由生成器产生的左结合运算符表达式输入，THE Parser_Combinator SHALL 保证 seed-growing 左递归解析器与 `chainl1` 参照实现产生一致的求值结果（左递归一致性，以 PBT 验证）。

---

### Requirement 10：流式 / 增量输入支持

**用户故事（User Story）：** 作为处理分段到达数据的开发者，我想要增量喂入输入的能力，以便我能在数据尚未完整到达时推进解析并在不足时请求更多数据。

#### 验收标准（Acceptance Criteria）

1. WHEN 调用方分多段（chunk）依次喂入源文本，THE Parser_Combinator SHALL 在已到达字符上推进解析而无需一次性持有完整输入。
2. IF 解析在已到达数据的末尾仍需更多字符才能判定，THEN THE Parser_Combinator SHALL 返回「需要更多输入」（needs-more-input）状态，而不报告语法失败。
3. WHEN 在「需要更多输入」状态下追加新数据段，THE Parser_Combinator SHALL 从上次中断的输入位置继续解析。
4. WHEN 输入被标记为已结束（end-of-input）且仍不满足解析器，THE Parser_Combinator SHALL 返回携带位置与期望符号的失败。
5. FOR ALL 由生成器产生的输入及其任意分段方式，THE Parser_Combinator SHALL 保证增量喂入的最终解析结果与一次性喂入完整输入的解析结果逐字段一致（分段无关性，以 PBT 验证）。

---

### Requirement 11：旗舰端到端示例 —— JSON 解析器与算术表达式求值器

**用户故事（User Story）：** 作为评估该库能力的开发者，我想要两个完整的旗舰示例，以便我能看到递归结构、转义处理、错误恢复、运算符优先级与左递归在真实场景中的端到端用法。

#### 验收标准（Acceptance Criteria）

1. WHEN 接收到一段符合 JSON 文法的文本，THE Parser_Combinator SHALL 经 JSON 示例解析器产出对应的 JSON 值结构（对象、数组、字符串、数值、布尔、null）。
2. WHEN JSON 字符串字面量包含转义序列（`\"`、`\\`、`\/`、`\b`、`\f`、`\n`、`\r`、`\t`、`\uXXXX`），THE Parser_Combinator SHALL 将其解码为对应字符。
3. IF JSON 文本存在语法错误，THEN THE Parser_Combinator SHALL 返回携带失败行列位置与期望符号的诊断，且不产生部分构造的 JSON 值。
4. WHERE 启用错误恢复，THE Parser_Combinator SHALL 在 JSON 数组或对象元素发生硬失败时记录该错误并同步到下一个分隔符以继续解析后续元素。
5. WHEN 接收到一段中缀算术表达式（含 `+ - * /`、括号与右结合幂运算 `^`），THE Parser_Combinator SHALL 经算术示例求值器按运算符优先级与结合性求出数值结果。
6. THE Parser_Combinator SHALL 以 `chainl1` 表达加减与乘除的左结合层级、以 `chainr1` 或左递归入口表达幂运算的右结合层级。
7. FOR ALL 由生成器产生的合法 JSON 值，THE Parser_Combinator SHALL 满足往返性质：解析其打印结果得到等价 JSON 值（round-trip property，以 PBT 验证）。
8. FOR ALL 由生成器产生的合法算术表达式抽象语法树，THE Parser_Combinator SHALL 满足求值一致性：对其打印形式求值得到与按 AST 直接求值一致的数值结果（以 PBT 验证）。

---

### Requirement 12：性能基准（benches/）

**用户故事（User Story）：** 作为关心解析性能的开发者，我想要可复现的基准证据，以便我能比较 packrat 与朴素实现并确认线性扩展趋势。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 在 `benches/` 下提供解析器基准包，覆盖 JSON 解析与算术表达式求值两类工作负载。
2. WHEN 运行基准，THE Parser_Combinator SHALL 输出包含机器标识、后端目标、输入规模与计时统计的基准结果工件（JSON 或 Markdown）。
3. THE Parser_Combinator SHALL 在基准中同时记录 packrat 记忆化与朴素实现在递增输入规模下的计时，以呈现两者的复杂度趋势对比。
4. WHERE 提供基准回归基线，THE Parser_Combinator SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的失败报告。
5. THE Parser_Combinator SHALL 在基准文档中记录运行命令（含 native 后端前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`）以保证可复现。

---

### Requirement 13：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键算法可追溯到源论文并与主流开源库对比，以便我能理解设计依据与取舍。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 在文档中将核心组合子代数追溯到 Hutton & Meijer 1998《Monadic Parser Combinators》的对应构造。
2. THE Parser_Combinator SHALL 在文档中将消费提交语义与最远失败错误模型追溯到 Leijen & Meijer 的 Parsec 设计。
3. THE Parser_Combinator SHALL 在文档中将 PEG 有序选择与 packrat 记忆化追溯到 Ford 2002 的 PEG/packrat 论文。
4. THE Parser_Combinator SHALL 在文档中将左递归处理追溯到 Warth et al. 2008 的 seed-growing 算法。
5. THE Parser_Combinator SHALL 在文档中提供与 Haskell `parsec`/`megaparsec` 及 Rust `nom` 的 API 与语义对比，覆盖回溯默认行为、提交语义与错误模型的差异。
6. WHERE 本库的语义与所对标库存在差异，THE Parser_Combinator SHALL 显式声明该差异及其理由，而非隐式留白。

---

### Requirement 14：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` 骨架的开发者，我想要深化后保持既有 API 可用，以便我的现有解析器在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 保留既有公开类型 `Parser[T]`、`ParseResult[T]`、`Input`、`Pos` 及其现有公开方法的签名与语义。
2. THE Parser_Combinator SHALL 保留既有原语 `pchar`、`satisfy`、`any_char`、`ptoken` 与组合子 `seq`、`alt`、`many`、`many1`、`optional` 的现有公开签名与行为。
3. THE Parser_Combinator SHALL 复用 `@core.PathError` 作为对外错误桥接类型，并保持 `ParseResult::to_path_error` 的现有语义。
4. THE Parser_Combinator SHALL 复用 `@infra_pbt` 的 `Gen`/`Rng`/`holds_for_all`/`round_trip` 作为全部新增属性测试的模板。
5. WHERE 新增能力需要扩展行为，THE Parser_Combinator SHALL 以新增 API 的方式提供，而不破坏既有 API 的调用方。

---

### Requirement 15：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Parser_Combinator SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Parser_Combinator SHALL 为本规格的核心正确性属性（functor/monad/alternative 定律、往返、最远失败、错误位置单调性、packrat 与朴素一致性、左递归一致性、分段无关性）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE Parser_Combinator SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖核心代数、衍生组合子、错误处理与两个旗舰示例，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE Parser_Combinator SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Parser_Combinator SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. WHEN 本方向的三后端测试、属性测试或可执行文档校验未通过，THE Parser_Combinator SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
