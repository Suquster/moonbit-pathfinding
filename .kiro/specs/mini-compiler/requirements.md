# 需求文档（Requirements Document）

## 引言（Introduction）

本文档定义 **Mini_Compiler（方向一）** 在 **🟣 档位 3「业界顶尖（旗舰）」** 目标下的深化需求集。本规格不是从零重建，而是在已发布的 `0.1.0` 骨架之上做**增量深化**：完整保留并冻结既有 MiniLet 流水线（公开类型 `Token`、`BinOp`、`Ast`、`Type`、`TypedAst`、`Value`、`Diagnostic`、`DiagKind`、`Backend`，以及接口 `lex`、`parse`、`check`、`eval`、`print_ast`、`compile`），并在其**旁路**扩展出一套对标教学/研究级编译器（OCaml、Haskell、Rust 教学实现与《Write You a Haskell》）的旗舰级 **MiniML 语言前端 + 类型推断 + 解释器 + 字节码编译后端**。

为不破坏既有 `pub(all)` 枚举的字段与派生语义，本方向**不扩容**既有 `Token` / `Ast` / `Type` / `TypedAst` / `Value`，而是**旁路新增**更丰富的语言层 **MiniML** 平行类型（`Expr` / `Ty` / `TExpr` / `Val` 等，均携带源码跨度 span）与一个 `of_minilet` 桥，把既有 MiniLet `Ast` 提升为 MiniML `Expr` 子集，从而既复用既有流水线又解锁新能力。既有 MiniLet 的 `lex` / `parse` / `check` / `eval` 行为在本次深化中保持逐字不变（向后兼容，见 Requirement 12）。

本方向**显式声明实现边界**：Mini_Compiler 是一门**玩具/教学语言**的编译器与解释器模型层，停留在「词法 → 语法 → 类型推断 → 优化 → 求值 / 字节码编译 → 虚拟机执行」这一抽象层。其**字节码虚拟机以内存中的栈式抽象机建模**，**不**生成原生可执行文件、**不**汇编或链接、**不**绑定具体指令集架构（ISA）；可选的 wasm 文本 / js 源输出仅作为**额外文本后端**，不保证可被外部工具链消费。该边界使核心算法（合一、Algorithm W、求值、编译—执行等价）可被属性测试穷尽校验且三后端行为一致。


旗舰目标聚焦十条主线：

- **更丰富的源语言 MiniML**：在 MiniLet 之上扩展布尔字面量与布尔类型、比较运算（`<` `<=` `>` `>=` `==` `!=`）、逻辑运算（`&&` `||`）、`if-then-else`、一等函数（`lambda` / `fun` + 应用）、`let rec` 递归，并以可选方式支持元组与 let 多态泛化；MiniML AST 携带源码跨度（span，行列），使类型 / 语义错误携带准确位置。
- **Hindley-Milner 类型推断**：Algorithm W + 合一（unification with occurs-check）、类型变量与替换、`let` 泛化（generalization）与实例化（instantiation）、类型方案（type scheme）、主类型（principal type）；类型错误含位置与冲突类型。
- **树遍历解释器（求值器）**：扩展到布尔 / 比较 / 逻辑 / `if` / 闭包（捕获环境）/ 递归，确定性、全函数（除零 = 0 沿用 MiniLet 约定），词法作用域与遮蔽。
- **真实编译后端**：把 `TExpr` 编译为栈式字节码（`Bytecode` / `Instr`）+ 字节码虚拟机（`VM`）；`compile` → `VM` 执行结果与树遍历解释器一致（语义保持）；可选输出 wasm 文本 / js 源作为额外后端。
- **AST 优化**：常量折叠（constant folding）、死 `let` 消除（dead-let elimination）、可选 beta 化简，保持语义；优化前后求值结果一致。
- **错误处理**：词法 / 语法 / 类型 / 作用域错误均含行列 span；可选的解析错误恢复。
- **性能基准**：`benches/` 覆盖 lex / parse / infer / eval / compile+VM 在递增规模程序上的表现，含回归 guard，native 前置 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
- **可解释性**：paper-to-code 可追溯（Hindley 1969、Milner 1978、Damas-Milner 1982 Algorithm W、Pierce《TAPL》、Nystrom《Crafting Interpreters》、Appel《Modern Compiler Implementation》），与 OCaml / Haskell / Rust 教学编译器、《Write You a Haskell》对比，显式声明实现边界。
- **旗舰端到端示例**：一段贯穿文档与基准的 MiniML 程序（含 `let rec` 递归如阶乘 / 斐波那契、函数、`if`、比较），完整走 lex → parse → infer → 优化 → eval 与 compile → VM，并展示两路结果一致。
- **质量门禁**：完整属性测试、三后端一致、`README.mbt.md` 可执行文档扩充、SemVer 自 `0.1.0` 推进、`release_info_with_gates` 门禁。

本规格承袭仓库统一质量基线（见 Requirement 14），并复用 `@parser_combinator`（不可变游标 `Input`，提供 `peek` / `advance` / `pos` 及 1 起始行列）、`@infra_pbt`（`Gen` / `Rng` / `holds_for_all` / `round_trip`）、`@release_meta`（`DirectionRelease` / `QualityGates` / SemVer）与 `README.mbt.md`「文档即测试」模式。

---


## 术语表（Glossary）

- **Mini_Compiler**：本方向的编译器 / 解释器库（子包 `src/mini_compiler`），是本文档所有验收标准的主体系统。
- **MiniLet**：既有 `0.1.0` 骨架所实现的最小语言——整数字面量、变量、二元算术（`+ - * /`）与 `let ... in ...`，唯一类型为 `IntT`。本方向冻结其流水线行为。
- **MiniML**：本方向旁路新增的更丰富源语言——在 MiniLet 之上引入布尔、比较、逻辑、`if-then-else`、一等函数、`let rec`（及可选元组 / let 多态）；是新增前端 / 推断 / 求值 / 编译能力的目标语言。
- **Expr**：MiniML 抽象语法树节点类型（旁路新增，携带 span）；表达整数 / 布尔字面量、变量、二元运算、比较、逻辑、`if`、`lambda`、应用、`let` 与 `let rec`（及可选元组）。
- **span（源码跨度）**：源码中一段文本的起止位置（含 1 起始行列），挂载于 `Expr` 节点，使诊断可定位到源码（R8）。
- **Ty**：MiniML 类型项（旁路新增），含整数类型、布尔类型、类型变量、函数类型 `t1 -> t2`（及可选元组类型）。
- **TExpr**：MiniML 带类型标注的抽象语法树（旁路新增），与 `Expr` 同构但每个节点附带其推断得到的 `Ty`。
- **Val**：MiniML 运行期值（旁路新增），含整数值、布尔值、闭包值（捕获求值环境）（及可选元组值）。
- **of_minilet（提升桥）**：把既有 MiniLet `Ast` 转换为等价 MiniML `Expr` 子集的函数，使既有程序可走新流水线而不改变其语义。
- **类型变量（Type Variable）**：在推断期代表尚未确定类型的占位符，由合一逐步求解。
- **替换（Substitution）**：从类型变量到类型项的有限映射；施加替换即把类型项中出现的变量按映射替换。
- **合一（Unification）**：求解使两个类型项相等的最一般替换（most general unifier, mgu）的过程。
- **occurs-check（出现检查）**：合一时拒绝把类型变量绑定到一个**包含其自身**的类型项，以防止构造无限类型。
- **mgu（最一般合一子）**：使两类型项相等且最一般（任何其他合一子都是其实例）的替换。
- **Algorithm W**：Damas-Milner 提出的、自语法树自底向上同时产出主类型与替换的 Hindley-Milner 类型推断算法。
- **类型方案（Type Scheme）**：形如 `∀a1..an. t` 的多态类型，记录被泛化（全称量化）的类型变量。
- **泛化（Generalization）**：在 `let` 绑定处，把绑定表达式类型中**不被外层环境约束**的自由类型变量全称量化为类型方案的过程。
- **实例化（Instantiation）**：在使用某类型方案处，用**新鲜**类型变量替换其被量化变量，得到一个具体类型的过程。
- **主类型（Principal Type）**：一个良类型表达式所有可赋类型中最一般的那个——其他可赋类型都是它的实例。
- **类型可靠性 / 不卡住（Soundness / Progress）**：「良类型程序求值不会卡住」——通过类型推断的程序在求值时不会出现无规则可用的非值停滞状态。
- **捕获避免替换（Capture-Avoiding Substitution）**：在替换类型变量（或在 beta 化简替换项变量）时，对被绑定变量必要时重命名，避免自由变量被意外捕获。
- **树遍历解释器（Tree-Walking Interpreter）**：直接在 `TExpr` 上递归求值、以求值环境承载绑定的解释器；本方向的 `eval` 家族。
- **求值环境（Environment）**：从变量名到 `Val` 的不可变映射序列，承载 `let` / 函数参数绑定并实现词法作用域与遮蔽。
- **闭包（Closure）**：由函数体、形参与**定义处捕获的求值环境**组成的运行期值，使函数为一等值。
- **词法作用域（Lexical Scoping）**：变量引用按其在**源码中的静态嵌套**解析到最近的绑定，而非调用时的动态环境。
- **遮蔽（Shadowing）**：内层绑定与外层同名时，内层在其作用域内优先可见。
- **let rec（递归绑定）**：使被绑定名在**其自身绑定体**内可见的 `let`，用于定义递归函数。
- **常量折叠（Constant Folding）**：在编译前把仅由常量构成的子表达式预先求值为常量的优化。
- **死 let 消除（Dead-Let Elimination）**：删除其绑定变量在 body 中从不被使用且绑定体无可观察副作用的 `let` 的优化。
- **beta 化简（Beta Reduction，可选）**：把对字面 `lambda` 的应用 `(λx. e) v` 化简为对 `e` 施加 `x ↦ v` 的捕获避免替换的优化。
- **语义保持（Semantics-Preserving）**：变换前后程序对相同输入产出相同求值结果的性质。
- **字节码（Bytecode）**：面向栈式虚拟机的线性指令序列，结构记为 `Bytecode`，元素为指令 `Instr`。
- **Instr（指令）**：字节码的单条操作（如压入常量、变量取值、二元运算、比较、跳转、构造 / 调用闭包、返回等）。
- **栈式虚拟机（Stack VM）**：以操作数栈与调用帧执行 `Bytecode` 的内存抽象机，记为 `VM`；执行产出与解释器一致的 `Val`。
- **compile（编译）**：把 `TExpr` 编译为 `Bytecode` 的过程（本方向新增 MiniML 编译路径）；既有 MiniLet `compile(TypedAst, Backend) -> Bytes` 桩签名保持冻结。
- **编译—执行等价（Compile-Execute Equivalence）**：对任一良类型程序，`VM` 执行 `compile` 产物所得结果与树遍历解释器求值结果相等的性质。
- **额外文本后端（Extra Text Backend，可选）**：把 `TExpr` 或 `Bytecode` 渲染为 wasm 文本 / js 源串的可选输出，仅供展示，不保证外部工具链可消费。
- **诊断（Diagnostic）**：既有 `{ kind; line; col; msg }`，携带错误类别与 1 起始行列；本方向新增的 MiniML 诊断沿用同一模型并填入真实 span。
- **解析错误恢复（Error Recovery，可选）**：语法分析遇错后跳过到同步点继续解析、以在一次分析中报告多个诊断的能力。
- **@parser_combinator**：仓库共享解析基座包，提供不可变游标 `Input`（`peek` / `advance` / `pos`）与 1 起始行列定位。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen` / `Rng` / `holds_for_all` / `round_trip` 等模板。
- **@release_meta**：仓库共享发布元数据包，提供 `DirectionRelease` / `QualityGates` / SemVer 模型。
- **三后端（Three Backends）**：MoonBit 的 `wasm-gc`、`js`、`native` 三个编译目标。
- **可执行文档（Executable Documentation）**：通过 `moon test *.mbt.md` 编译并运行的 `README.mbt.md` 示例。
- **EARS**：Easy Approach to Requirements Syntax，本文档采用的需求句式规范。
- **PBT**：Property-Based Testing，属性测试。

---


## 需求（Requirements）

### Requirement 1：更丰富的源语言 MiniML（旁路语言层与 of_minilet 桥）

**用户故事（User Story）：** 作为编译器学习者与库使用者，我想要一门在 MiniLet 之上扩展了布尔、比较、逻辑、条件、一等函数与递归的源语言 MiniML，并能把既有 MiniLet 程序无损提升到该语言，以便我能在不破坏既有契约的前提下表达真实的程序。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 旁路新增 MiniML 抽象语法类型 `Expr`，覆盖整数字面量、布尔字面量、变量、二元算术、比较运算（`<` `<=` `>` `>=` `==` `!=`）、逻辑运算（`&&` `||`）、`if-then-else`、函数抽象（`lambda` / `fun`）、函数应用、`let` 绑定与 `let rec` 递归绑定。
2. THE Mini_Compiler SHALL 为每个 `Expr` 节点附带源码跨度 span（含 1 起始行号与列号），使后续阶段产生的诊断可定位到源码位置。
3. THE Mini_Compiler SHALL 旁路新增 MiniML 类型项 `Ty`，至少覆盖整数类型、布尔类型、类型变量与函数类型 `t1 -> t2`。
4. THE Mini_Compiler SHALL 提供 `of_minilet` 桥，将既有 MiniLet `Ast` 转换为等价的 MiniML `Expr` 子集（整数 / 变量 / 二元算术 / `let`）。
5. WHERE 启用可选的元组扩展，THE Mini_Compiler SHALL 在 `Expr`、`Ty` 与运行期值中以一致方式表达元组的构造与分量类型。
6. FOR ALL 由生成器产生的 MiniLet `Ast`，THE Mini_Compiler SHALL 保证经 `of_minilet` 提升为 MiniML `Expr` 后，其按 MiniML 语义的求值结果与既有 MiniLet `eval` 的求值结果一致（提升保持语义，以 PBT 验证）。

---

### Requirement 2：MiniML 词法与语法分析（含 span 与打印往返）

**用户故事（User Story）：** 作为编写 MiniML 程序的用户，我想要把源串解析为带位置信息的 MiniML 语法树、并能把语法树打印回可重新解析的源串，以便我能可靠地读写程序并验证解析器的正确性。

#### 验收标准（Acceptance Criteria）

1. WHEN 对 MiniML 源串执行词法分析，THE Mini_Compiler SHALL 在 `@parser_combinator` 的不可变游标之上扫描出词法单元序列，识别整数 / 布尔字面量、标识符与关键字（`let` / `rec` / `in` / `if` / `then` / `else` / `fun` / `lambda`）、算术 / 比较 / 逻辑 / 箭头 / 分组等符号，并以 1 起始行列跟踪位置。
2. WHEN 对词法单元序列执行语法分析，THE Mini_Compiler SHALL 以递归下降按声明的运算符优先级（自低到高：`let` / `if` / `lambda` → `||` → `&&` → 比较 → 加减 → 乘除 → 应用 → 原子）产出携带 span 的 `Expr`。
3. WHEN 顶层表达式解析完成后仍存在未消费的非空白输入，THE Mini_Compiler SHALL 返回 `SyntaxError` 诊断且不产出语法树。
4. THE Mini_Compiler SHALL 提供 `print_expr`，将 `Expr` 打印为 MiniML 源串，并对二元 / 比较 / 逻辑 / 应用节点采用足以消除优先级歧义的括号化。
5. FOR ALL 由生成器产生的合法 `Expr`，THE Mini_Compiler SHALL 保证「打印再解析」往返还原等价语法树：解析 `print_expr(e)` 所得 `Expr` 与原 `e` 在去除 span 后相等（解析 / 打印往返，以 PBT 验证）。

---


### Requirement 3：合一（Unification）、类型替换与 occurs-check

**用户故事（User Story）：** 作为实现类型推断的开发者，我想要在类型项上做带 occurs-check 的合一并以替换表达解，以便类型推断有一个正确且可终止的核心。

#### 验收标准（Acceptance Criteria）

1. WHEN 对两个类型项执行合一，THE Mini_Compiler SHALL 产出一个使二者相等的最一般合一子（mgu）替换，或在不可合一时返回携带冲突两类型的类型错误。
2. WHEN 合一一个类型变量与一个类型项，THE Mini_Compiler SHALL 执行 occurs-check：若该类型变量出现于该类型项中且二者不相等，则拒绝绑定并返回类型错误（避免构造无限类型）。
3. WHEN 合一两个函数类型 `a1 -> b1` 与 `a2 -> b2`，THE Mini_Compiler SHALL 先合一参数类型再在所得替换下合一结果类型，并返回二者复合后的替换。
4. WHEN 对类型项施加替换，THE Mini_Compiler SHALL 用映射目标递归替换其中出现的每个被映射类型变量。
5. FOR ALL 由生成器产生的可合一类型项对 `(t1, t2)`，THE Mini_Compiler SHALL 保证把合一所得替换分别施加于 `t1` 与 `t2` 后得到的类型项相等（合一正确性，以 PBT 验证）。
6. FOR ALL 类型变量 `v` 与包含 `v` 且不等于 `v` 的类型项 `t`，THE Mini_Compiler SHALL 保证合一 `v` 与 `t` 失败并返回类型错误（occurs-check 正确，以 PBT 验证）。
7. FOR ALL 由生成器产生的替换 `s` 与类型项 `t`，THE Mini_Compiler SHALL 保证对 `t` 施加 `s` 一次与施加两次结果相等（替换幂等，以 PBT 验证）。

---

### Requirement 4：Hindley-Milner 类型推断（Algorithm W）

**用户故事（User Story）：** 作为 MiniML 用户，我想要无需类型标注即可推断出表达式的主类型，并对 `let` 绑定获得 let 多态，以便我能像在 OCaml / Haskell 中那样写出通用且经类型检查的程序。

#### 验收标准（Acceptance Criteria）

1. WHEN 对 `Expr` 执行类型推断，THE Mini_Compiler SHALL 以 Algorithm W 自底向上同时产出一个替换与该表达式的类型，并在成功时返回携带类型标注的 `TExpr`。
2. WHEN 推断 `let x = e1 in e2`，THE Mini_Compiler SHALL 先推断 `e1` 的类型，再把其中不被当前类型环境约束的自由类型变量泛化为类型方案后将 `x` 引入环境，最后推断 `e2`。
3. WHEN 在使用处引用一个绑定为类型方案的变量，THE Mini_Compiler SHALL 以新鲜类型变量实例化该方案的被量化变量。
4. WHEN 推断 `if c then a else b`，THE Mini_Compiler SHALL 将 `c` 的类型合一为布尔类型，并将 `a` 与 `b` 的类型相互合一作为整体类型。
5. WHEN 推断函数应用 `f e`，THE Mini_Compiler SHALL 引入新鲜结果类型变量 `r` 并将 `f` 的类型合一为 `(typeof e) -> r`，以 `r` 为应用结果类型。
6. WHEN 推断 `let rec f = e1 in e2`，THE Mini_Compiler SHALL 在推断 `e1` 前先以新鲜类型变量将 `f` 引入环境，使 `f` 在其自身绑定体内可见。
7. IF 表达式无法被赋予一致类型（合一失败），THEN THE Mini_Compiler SHALL 返回携带源码位置与冲突类型信息的 `TypeError` 诊断。
8. FOR ALL 由生成器产生的良类型 `Expr`，THE Mini_Compiler SHALL 保证类型推断成功并返回一个类型（主类型存在性，以 PBT 验证）。
9. FOR ALL 由生成器产生的良类型 `Expr`，THE Mini_Compiler SHALL 保证对推断所得类型再施加推断结果替换不改变该类型（推断幂等 / 类型在最终替换下封闭，以 PBT 验证）。

---


### Requirement 5：树遍历解释器（求值器）扩展

**用户故事（User Story）：** 作为运行 MiniML 程序的用户，我想要一个支持布尔、比较、逻辑、条件、一等函数（闭包）与递归的确定性解释器，以便我能直接执行程序并获得可预期的结果。

#### 验收标准（Acceptance Criteria）

1. WHEN 对带类型标注的 MiniML `TExpr` 求值，THE Mini_Compiler SHALL 以不可变求值环境承载绑定，对整数 / 布尔字面量、变量、二元算术、比较、逻辑、`if`、函数抽象、应用、`let` 与 `let rec` 产出对应的 `Val`。
2. WHEN 求值函数抽象（`lambda` / `fun`），THE Mini_Compiler SHALL 产出一个捕获当前求值环境的闭包值，使函数成为一等值并遵循词法作用域。
3. WHEN 求值函数应用，THE Mini_Compiler SHALL 在闭包捕获的环境上扩展形参到实参值的绑定后求值函数体。
4. WHEN 求值二元算术除法且除数为零，THE Mini_Compiler SHALL 返回整数 `0`（沿用 MiniLet 约定，保证求值为全函数且三后端一致）。
5. WHEN 内层绑定与外层绑定同名，THE Mini_Compiler SHALL 在内层作用域内优先解析到内层绑定（遮蔽）。
6. WHEN 求值 `let rec` 定义的递归函数并应用之，THE Mini_Compiler SHALL 使该函数在其自身函数体内可被递归调用。
7. FOR ALL 由生成器产生的良类型 `Expr`，THE Mini_Compiler SHALL 保证对同一程序重复求值得到相等结果（求值确定性，以 PBT 验证）。
8. FOR ALL 由生成器产生的良类型 `Expr`，THE Mini_Compiler SHALL 保证求值要么产出一个 `Val`、要么按既有除零等全函数约定终止，而不进入无规则可用的卡住状态（类型可靠性 / 良类型不卡住，以 PBT 验证）。

---

### Requirement 6：字节码编译后端与栈式虚拟机（compile + VM）

**用户故事（User Story）：** 作为关注执行模型的开发者，我想要把 MiniML 程序编译为栈式字节码并由虚拟机执行，且其结果与解释器一致，以便我能理解从语法树到指令的真实编译链路而不牺牲正确性。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 旁路新增字节码模型 `Bytecode` 与指令 `Instr`，至少覆盖压入常量、变量取值、二元算术、比较、逻辑、条件跳转、构造闭包、调用、返回等操作。
2. WHEN 把 `TExpr` 编译为字节码，THE Mini_Compiler SHALL 为整棵语法树产出一条覆盖其全部子表达式的线性 `Bytecode`，不留未编译的节点。
3. WHEN 栈式虚拟机 `VM` 执行 `Bytecode`，THE Mini_Compiler SHALL 以操作数栈与调用帧解释每条 `Instr` 并在程序结束时产出一个 `Val`。
4. WHERE 启用可选的额外文本后端，THE Mini_Compiler SHALL 把 `TExpr` 或 `Bytecode` 渲染为 wasm 文本或 js 源串，并在文档中声明该输出仅供展示。
5. FOR ALL 由生成器产生的良类型 `Expr`，THE Mini_Compiler SHALL 保证 `VM` 执行其编译产物所得 `Val` 与树遍历解释器对该程序求值所得 `Val` 相等（编译—执行等价 / 语义保持，以 PBT 验证）。

---


### Requirement 7：AST 优化（常量折叠 / 死 let 消除 / 可选 beta 化简）

**用户故事（User Story）：** 作为关注代码质量的开发者，我想要在保持语义的前提下对 MiniML 语法树做常量折叠、死 `let` 消除与可选 beta 化简，以便程序在执行前被化简而结果不变。

#### 验收标准（Acceptance Criteria）

1. WHEN 执行常量折叠，THE Mini_Compiler SHALL 将仅由常量构成的算术 / 比较 / 逻辑子表达式预先求值为等价的字面量节点。
2. WHEN 执行死 `let` 消除，THE Mini_Compiler SHALL 删除其绑定变量在 body 中从不被引用且绑定体无可观察副作用的 `let`，并以其 body 取代之。
3. WHERE 启用可选的 beta 化简，THE Mini_Compiler SHALL 把对字面 `lambda` 的应用化简为对函数体施加形参到实参的捕获避免替换。
4. THE Mini_Compiler SHALL 使优化后的语法树仍为良类型（优化不改变可推断性）。
5. FOR ALL 由生成器产生的良类型 `Expr`，THE Mini_Compiler SHALL 保证常量折叠与死 `let` 消除前后程序的求值结果相等（优化保持语义，以 PBT 验证）。
6. FOR ALL 由生成器产生的、含字面 `lambda` 应用的良类型 `Expr`，WHERE 启用 beta 化简，THE Mini_Compiler SHALL 保证化简使用捕获避免替换从而求值结果与化简前相等（捕获避免替换正确，以 PBT 验证）。

---

### Requirement 8：错误处理（词法 / 语法 / 类型 / 作用域，含 span）

**用户故事（User Story）：** 作为调试程序的用户，我想要词法、语法、类型与作用域错误都带有准确的行列位置与清晰的消息，以便我能快速定位并修复问题。

#### 验收标准（Acceptance Criteria）

1. IF 词法分析遇到不属于 MiniML 字母表的字符，THEN THE Mini_Compiler SHALL 返回 `kind` 为 `LexError` 且 `line` / `col` 指向该字符位置的诊断且不产出后续产物。
2. IF 语法分析遇到不符合文法的输入，THEN THE Mini_Compiler SHALL 返回 `kind` 为 `SyntaxError` 且携带出错位置行列的诊断且不产出语法树。
3. IF 类型推断遇到不可合一的类型，THEN THE Mini_Compiler SHALL 返回 `kind` 为 `TypeError`、携带出错节点 span 行列且消息标注冲突两类型的诊断。
4. IF 表达式引用了当前作用域内未绑定的变量，THEN THE Mini_Compiler SHALL 返回携带该变量 span 行列并标注变量名的诊断。
5. WHERE 启用可选的解析错误恢复，THE Mini_Compiler SHALL 在遇到语法错误后跳过到同步点继续分析，以在单次分析中报告多个诊断。
6. FOR ALL 由生成器产生的 `Expr`，THE Mini_Compiler SHALL 保证作用域检查恰好接受其全部变量引用都能解析到某个绑定的程序、并拒绝含自由变量的程序（作用域检查正确，以 PBT 验证）。

---


### Requirement 9：旗舰端到端示例（完整前端到执行流水线）

**用户故事（User Story）：** 作为评估该库能力的开发者，我想要一份贯穿文档与基准的 MiniML 程序端到端示例，以便我能看到从源串到结果的完整链路，并确认解释器与编译—执行两路一致。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 提供一段含 `let rec` 递归（如阶乘或斐波那契）、一等函数、`if` 与比较运算的 MiniML 示例程序。
2. WHEN 对该示例依次执行 lex → parse → infer → 优化 → eval，THE Mini_Compiler SHALL 在每一阶段产出与示例文档所声明一致的结果（推断类型、优化后形态与求值结果）。
3. WHEN 对该示例执行 compile 并由 `VM` 执行其字节码，THE Mini_Compiler SHALL 产出与该示例解释器求值一致的 `Val`。
4. WHEN 对该示例进行类型推断，THE Mini_Compiler SHALL 产出与文档所声明一致的主类型。
5. THE Mini_Compiler SHALL 使该端到端示例在 `README.mbt.md` 中作为可执行文档通过 `moon test *.mbt.md` 验证。

---

### Requirement 10：性能基准（benches/）

**用户故事（User Story）：** 作为关心编译 / 执行性能的开发者，我想要可复现的基准证据覆盖各阶段在递增规模程序上的表现，以便我能确认扩展趋势并防止性能回归。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 在 `benches/` 下提供基准包，覆盖 lex、parse、infer、eval 与 compile+VM 五类工作负载在递增规模程序上的运行。
2. WHEN 运行基准，THE Mini_Compiler SHALL 输出包含机器标识、后端目标、程序规模（节点数 / 绑定数 / 应用深度等）与计时统计的基准结果工件（JSON 或 Markdown）。
3. WHERE 提供基准回归基线，THE Mini_Compiler SHALL 将新基准运行与已记入的基线中位数比较，并在超出声明容差时给出可审计的回归失败报告。
4. WHEN 运行 native 后端基准或测试，THE Mini_Compiler SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Mini_Compiler SHALL 在基准文档中记录可复现运行命令与规模参数，以保证基准可被独立重跑。

---

### Requirement 11：可解释性 —— paper-to-code 可追溯与开源对标

**用户故事（User Story）：** 作为评审与学习者，我想要每个关键算法可追溯到源论文 / 教材并与主流教学编译器对比，以便我能理解设计依据、取舍与实现边界。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 在文档中将 Hindley-Milner 类型推断追溯到 Hindley（1969）、Milner（1978）与 Damas-Milner（1982）的 Algorithm W。
2. THE Mini_Compiler SHALL 在文档中将类型系统与求值模型追溯到 Pierce《Types and Programming Languages》、Nystrom《Crafting Interpreters》与 Appel《Modern Compiler Implementation》。
3. THE Mini_Compiler SHALL 在文档中提供与 OCaml、Haskell 与 Rust 教学编译器实现以及《Write You a Haskell》的对比，覆盖类型推断、求值与编译模型差异。
4. THE Mini_Compiler SHALL 在文档中显式声明实现边界：本方向是玩具 / 教学语言模型层，字节码虚拟机为内存抽象机，不生成原生可执行文件、不汇编或链接、不绑定具体指令集架构。
5. WHERE 本库的语义与所对标语言 / 编译器存在差异（如除零定义为 0、可选特性的取舍），THE Mini_Compiler SHALL 显式声明该差异及其理由，而非隐式留白。

---


### Requirement 12：向后兼容与既有资产复用

**用户故事（User Story）：** 作为已使用 `0.1.0` MiniLet 骨架的开发者，我想要深化后既有 API 与行为保持不变，以便我的现有调用方在升级后无需重写。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 保留既有公开类型 `Token`、`BinOp`、`Ast`、`Type`、`TypedAst`、`Value`、`Diagnostic`、`DiagKind`、`Backend` 的现有字段、构造子与派生语义，不予扩容或改写。
2. THE Mini_Compiler SHALL 保留既有接口 `lex`、`parse`、`check`、`eval`、`print_ast`、`compile` 与 `Diagnostic::new` 的现有公开签名与行为。
3. WHEN 以既有 MiniLet 输入调用 `lex` / `parse` / `check` / `eval` / `print_ast`，THE Mini_Compiler SHALL 产出与 `0.1.0` 骨架逐字一致的词法单元、AST、TypedAst、Value 与源串。
4. THE Mini_Compiler SHALL 以**旁路新增** API 的方式提供全部新能力（MiniML `Expr` / `Ty` / `TExpr` / `Val`、推断、`VM` 等），既有 `0.1.0` 契约冻结而不破坏既有调用方。
5. THE Mini_Compiler SHALL 复用 `@parser_combinator` 的不可变游标 `Input`（`peek` / `advance` / `pos` 与 1 起始行列）作为 MiniML 词法 / 语法分析的基座，而非另起炉灶。
6. THE Mini_Compiler SHALL 复用 `@infra_pbt` 的 `Gen` / `Rng` / `holds_for_all` / `round_trip` 作为全部新增属性测试的模板。
7. FOR ALL 由生成器产生的 MiniLet `Ast`，THE Mini_Compiler SHALL 保证「打印再解析再检查再求值」往返结果与 `0.1.0` 骨架既有行为一致（MiniLet 向后兼容，以 PBT 验证）。

---

### Requirement 13：MiniML 流水线集成（端到端装配）

**用户故事（User Story）：** 作为库使用者，我想要一个把词法、语法、推断、优化、求值与编译—执行串联起来的统一 MiniML 流水线入口，以便我能用单次调用完成从源串到结果的处理且各阶段无悬空。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 提供统一的 MiniML 流水线入口，依次串联 `lex_ml` → `parse_ml` → `infer` →（可选）优化 → `eval_ml`，并将任一阶段的诊断作为整体结果向上传播。
2. WHEN 任一前置阶段返回诊断，THE Mini_Compiler SHALL 短路后续阶段并返回该诊断而不产出求值结果。
3. THE Mini_Compiler SHALL 提供与解释路径并列的编译—执行路径入口（`infer` → compile → `VM`），使两路接受相同的良类型输入。
4. FOR ALL 由生成器产生的良类型 MiniML 源串，THE Mini_Compiler SHALL 保证解释路径与编译—执行路径对同一源串产出相等的 `Val`（端到端两路一致，以 PBT 验证）。

---

### Requirement 14：贯穿性工程质量门禁

**用户故事（User Story）：** 作为方向维护者，我想要旗舰深化达到仓库统一质量基线，以便本方向可验证、可复现、可独立发布。

#### 验收标准（Acceptance Criteria）

1. THE Mini_Compiler SHALL 在 `wasm-gc`、`js`、`native` 三后端上运行同一测试套件，并将任意后端的输出分歧判定为构建失败。
2. THE Mini_Compiler SHALL 为本规格的核心正确性属性（提升保持语义、解析 / 打印往返、合一正确性、occurs-check 正确、替换幂等、主类型存在性、推断幂等、求值确定性、良类型不卡住、编译—执行等价、优化保持语义、捕获避免替换正确、作用域检查正确、端到端两路一致、MiniLet 向后兼容）提供以 `@infra_pbt` 实现的属性测试，每条属性至少运行 100 次迭代。
3. THE Mini_Compiler SHALL 扩充 `README.mbt.md` 可执行文档，使其覆盖 MiniML 词法 / 语法、类型推断、解释器、AST 优化、字节码编译与 `VM` 执行及旗舰端到端示例，且全部示例通过 `moon test *.mbt.md` 验证。
4. WHEN 运行三后端测试中的 native 后端，THE Mini_Compiler SHALL 在文档与脚本中要求先执行 `export LIBRARY_PATH=/usr/lib64:/usr/lib`。
5. THE Mini_Compiler SHALL 作为独立发布单元推进其 SemVer 版本号（自 `0.1.0` 起按本次旗舰深化做次版本或主版本推进）并更新独立的 `CHANGELOG.md`。
6. IF 本方向的三后端测试、属性测试或可执行文档校验未通过，THEN THE Mini_Compiler SHALL 经 `release_info_with_gates` 阻止该方向进入发布就绪（release-ready）状态。
