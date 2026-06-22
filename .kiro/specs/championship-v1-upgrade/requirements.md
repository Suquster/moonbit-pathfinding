# Requirements Document

> 需求文档 · 全程中文撰写 · 默认 🟣 档位3「业界顶尖（旗舰）」标准

## Introduction

> 引言

本规格 **Championship_V1_Upgrade（冠军级 v1.0.0 升级）** 的目标，是把 `moonbit-pathfinding`（当前 v0.0.3，已落地 30 种经典图/路径算法 + 3 种实验级前沿算法 CH/JPS/ALT）从「功能完备的算法库」整体拔高到面向 **OSC 2026 竞赛的冠军级、可发布的 v1.0.0**。本规格不是从零重建，而是在既有公开 API 之上做**增量升级**：以「冻结现有公开 API + bypass 新增」为基本盘，复用既有算法实现、`@infra_pbt`（`Gen`/`Rng`/`holds_for_all`/`round_trip`）、运行时证明谓词框架（当前仅 BFS/Dijkstra）、三后端一致性 CI（`wasm-gc`/`js`/`native`）与可复现基准框架雏形，并补齐交互可视化、性能证据、形式验证广度、API 人机工程学、差分/模糊测试与文档卓越六大维度。

本规格覆盖 6 个升级方向：

1. **WASM Playground 交互可视化** —— 部署至 GitHub Pages，用户拖拽起点/终点，实时动画展示 BFS/DFS/Dijkstra/A\*/JPS 扩展过程，wasm-gc 包体积 ≤100KB，64×64 网格 ≥60fps。
2. **性能冠军** —— 可复现基准框架、与 Rust `pathfinding` crate 对比报告、10k 节点压力测试，并将 CH/JPS/ALT 从实验级升级为生产级（OSM 真实路网子集验证）。
3. **形式验证升级** —— 将运行时证明谓词从 BFS/Dijkstra 扩展至全部 30 种经典算法，系统性添加循环不变式注解，建立可审计的证明报告生成管线。
4. **API 人机工程学与类型安全** —— 流式 `GraphBuilder`、结构化 `PathError` 错误枚举、惰性路径迭代器、通用图适配器（邻接矩阵/边表/CSR）。
5. **差分测试与模糊测试** —— 跨算法差分验证、结构化图生成器模糊测试，行覆盖率 ≥95%。
6. **文档卓越** —— 自动生成算法复杂度表、文档注释 ASCII 可视化、20+ 真实用例 Cookbook、所有 pub API ≥5 行文档注释。

本规格按 workspace 三档递进规则呈现升级深度选择，**默认采用 🟣 档位 3「业界顶尖（旗舰）」**：最大广度与难度、前沿特性、性能优化、paper-to-code 可追溯、开源对标、完整属性测试（PBT ≥100 次迭代）、三后端一致性。用户可在评审阶段对个别方向降档（🟢 档位1 夯实基础 / 🔵 档位2 进阶完善），或统一选择某一档位。

本规格承袭仓库统一质量基线：禁止 O(n²) 字符串拼接、禁止占位实现（`abort`/`todo!`/`panic`）、禁止字符串模拟结构化数据、API 冻结 + bypass（只新增不修改既有公开签名）、向后兼容、`README.mbt.md`「文档即测试」模式。

---

## Glossary

> 术语表（所有 EARS 需求中出现的系统名与技术术语均在此定义）

### 总体与横切

- **Championship_V1_Upgrade**：本规格定义的冠军级 v1.0.0 升级工作集，是横切质量约束（Requirement 22）的主体系统。
- **API 冻结（API Freeze）**：将既有公开 API 标记为冻结基线、仅允许新增、不允许变更或删除的策略。
- **bypass 新增**：在不修改既有公开签名的前提下，以新增类型/函数/模块形式扩展能力的方式。
- **三后端一致性（Tri-Backend Consistency）**：同一行为在 `wasm-gc`、`js`、`native` 三个后端上测试结果逐字符一致。
- **`.mbti` 接口文件**：`moon info` 生成的包公开接口快照；本规格要求其只增不减以保证向后兼容。
- **@infra_pbt**：仓库共享属性测试包，提供 `Gen`/`Rng`/`holds_for_all`/`round_trip` 等模板，PBT 默认迭代次数 ≥100。
- **PBT（Property-Based Testing，属性测试）**：以随机生成输入验证程序性质的测试方法，本规格要求每个新增公开函数至少一个属性测试且迭代 ≥100 次。
- **生产级（Production-Grade）**：满足可直接集成、性能合理（无 O(n²) 热路径）、错误处理完备、API 成熟、边界覆盖五项标准的实现状态。

### 方向1：WASM Playground

- **WASM_Playground**：编译为 `wasm-gc` 后端、部署至 GitHub Pages 的浏览器交互式寻路可视化应用系统。
- **Playground_Wasm_Module**：`WASM_Playground` 的核心 `.wasm` 产物，由 `moon build --target wasm-gc` 生成，承载算法逐步执行逻辑。
- **Grid_Canvas**：`WASM_Playground` 中展示网格、障碍、起点/终点与算法扩展过程的可视化画布区域。
- **Step_Trace（逐步轨迹）**：算法执行过程中按访问/松弛/扩展顺序记录的节点序列，供动画逐帧回放。
- **Frame_Rate（帧率）**：`Grid_Canvas` 每秒渲染的动画帧数，单位 fps。
- **GitHub_Pages_Deployment**：将 `WASM_Playground` 静态资源发布到 `https://Suquster.github.io/moonbit-pathfinding/` 的部署产物与流程。

### 方向2：性能冠军

- **Benchmark_Framework**：可复现、可 CI 回归的性能基准测试框架，记录机器/后端/输入规模/种子/原始计时与统计量。
- **Benchmark_Report**：由 `Benchmark_Framework` 生成的结构化基准结果（Markdown + JSON 双产物）。
- **Rust_Comparison_Report**：将本库基准结果与 Rust `pathfinding` crate 在等价工作负载下对比的报告，含方法学声明与可复现脚本。
- **Stress_Test（压力测试）**：以 10000 节点规模图为输入、验证算法在大规模下正确终止并产出有效结果的测试。
- **Production_Algorithm（生产级算法）**：满足生产级标准、API 冻结且具备真实路网基准证据的算法。
- **OSM_Roadmap_Dataset**：从 OpenStreetMap 提取的真实路网子集数据，用于验证 CH/JPS/ALT 的正确性与性能。
- **Contraction_Hierarchies（CH）**：收缩层次算法，通过节点收缩预处理加速最短路查询。
- **Jump_Point_Search（JPS）**：跳点搜索算法，在均匀代价网格上通过跳点剪枝加速 A\*。
- **ALT**：A\* + Landmarks + Triangle inequality 算法，使用地标与三角不等式生成可采纳启发式。
- **Regression_Guard（回归门禁）**：将当前基准结果与已签入基线比较、超过容差则失败的守卫机制。

### 方向3：形式验证升级

- **Proof_Predicate（证明谓词）**：以普通 MoonBit 函数编码的算法后置条件断言，在 CI 中运行时校验。
- **Proof_Pipeline（证明报告管线）**：收集全部算法证明谓词运行结果、生成可审计证明报告（Markdown + JSON）的流程。
- **Proof_Report（证明报告）**：列出每个算法、其证明性质、运行结果与证据链的结构化文档。
- **Loop_Invariant（循环不变式）**：在循环每次迭代前后均成立的断言，用于论证算法正确性。
- **Bad_Witness（坏见证）**：故意构造的违反后置条件的输入/输出，用于验证证明谓词能正确拒绝错误结果。
- **Classic_Algorithm_Set（30 种经典算法集）**：README 算法目录中编号 1–30 的全部经典图/路径算法。

### 方向4：API 人机工程学与类型安全

- **Graph_Builder**：流式（链式调用）构建图结构的构造器系统，支持逐步添加节点与边并最终物化为图表示。
- **PathError**：结构化的寻路错误枚举类型，区分不同失败原因（如节点不存在、负权环、不可达、输入非法）。
- **Lazy_Path_Iterator（惰性路径迭代器）**：按需逐个产出路径节点而非一次性物化整条路径的迭代器，适配内存受限环境。
- **Graph_Adapter（通用图适配器）**：将不同底层图表示统一暴露为算法所需邻居访问接口的适配层。
- **Adjacency_Matrix（邻接矩阵）**：以二维布尔/权重矩阵表示图的存储格式。
- **Edge_List（边表）**：以 `(源, 目标, 权重)` 三元组序列表示图的存储格式。
- **CSR（Compressed Sparse Row，压缩稀疏行）**：以行偏移数组 + 列索引数组紧凑表示稀疏图的存储格式。

### 方向5：差分测试与模糊测试

- **Differential_Tester（差分测试器）**：对同一输入运行两个或多个应当等价的算法并比对结果的测试组件。
- **Fuzz_Generator（模糊图生成器）**：基于结构化策略随机生成多样图实例（含畸形/极端输入）的生成器。
- **Line_Coverage（行覆盖率）**：测试执行所覆盖源代码行占可执行行的百分比，由 `moon coverage analyze` 度量。
- **Equivalence_Class（等价类）**：在特定约束下结果必然一致的算法集合（如单位权图上 BFS 与 Dijkstra）。

### 方向6：文档卓越

- **Doc_Generator（文档生成器）**：从算法元数据自动生成复杂度表等文档内容的工具。
- **Complexity_Table（复杂度表）**：列出每个算法时间/空间复杂度与适用条件的表格。
- **Ascii_Visualization（ASCII 可视化）**：在文档注释中以纯文本字符绘制图/网格/路径示意的内容。
- **Cookbook（实用手册）**：包含 20 个以上真实可运行用例的使用指南文档。
- **Pub_Api（公开 API）**：以 `pub` 修饰、对外可见的函数、类型或方法。
- **Doc_Comment（文档注释）**：MoonBit `///` 风格的 API 文档注释。

---

## Requirements

> 需求（每条验收标准遵循 EARS 六大模式之一）

---

## 方向 1：WASM Playground 交互可视化

### Requirement 1: WASM 产物体积与构建

**User Story:** 作为库的潜在使用者，我想要一个体积极小的 WASM 寻路模块，以便在浏览器中快速加载并流畅运行可视化，无需漫长等待。

#### Acceptance Criteria

1. WHEN 执行 `moon build --target wasm-gc` 成功构建 `Playground_Wasm_Module`，THE Championship_V1_Upgrade SHALL 产出磁盘字节数不超过 102400 字节（100 KB）的单个 `.wasm` 文件，其中体积定义为该 `.wasm` 文件在磁盘上的字节数。
2. WHEN 宿主页面以指定算法（BFS、DFS、Dijkstra、A\* 或 Jump_Point_Search 之一）对 `Playground_Wasm_Module` 发起一次逐步执行调用，THE Playground_Wasm_Module SHALL 返回包含已访问节点集合、待扩展边界集合、当前节点与终止标志的单步可观察输出。
3. IF 宿主页面请求的算法逐步执行入口在 `Playground_Wasm_Module` 中缺失，THEN THE Playground_Wasm_Module SHALL 返回携带 PathError 的失败结果而非静默返回空输出。
4. IF 构建产物的 `.wasm` 文件磁盘字节数超过 102400 字节，THEN THE Championship_V1_Upgrade SHALL 在构建报告中记录实测字节数与 102400 字节上限、使体积门禁失败并阻止发布。
5. WHEN 任意执行者在 `wasm-gc` 后端重复运行所提供的可复现构建脚本，THE Championship_V1_Upgrade SHALL 产出与前次测量字节数完全一致的 `.wasm` 产物。

### Requirement 2: 交互式起点/终点拖拽

**User Story:** 作为可视化的访问者，我想要用鼠标拖拽起点和终点并设置障碍，以便直观地探索不同布局下的寻路行为。

#### Acceptance Criteria

1. WHEN 用户在 `Grid_Canvas` 上将起点标记拖拽到某个可通行单元格（可通行单元格定义为位于网格边界内且非障碍的单元格），THE WASM_Playground SHALL 在 200 毫秒内将起点更新为该单元格并依据当前起点、终点与障碍布局重新计算当前算法的 `Step_Trace`。
2. WHEN 用户在 `Grid_Canvas` 上将终点标记拖拽到某个可通行单元格，THE WASM_Playground SHALL 在 200 毫秒内将终点更新为该单元格并依据当前起点、终点与障碍布局重新计算当前算法的 `Step_Trace`。
3. IF 用户将起点或终点拖拽到障碍单元格、网格边界之外，或拖拽至与另一端点重叠的单元格，THEN THE WASM_Playground SHALL 拒绝该次放置、恢复到拖拽前的最后有效位置并给出视觉反馈。
4. WHEN 用户在既非起点也非终点的可通行单元格上切换障碍状态，THE WASM_Playground SHALL 在 200 毫秒内更新网格障碍布局并依据当前起点、终点与障碍布局重新计算 `Step_Trace`。
5. IF 用户尝试在起点或终点所在单元格上切换障碍状态，THEN THE WASM_Playground SHALL 拒绝该操作、保持网格障碍布局不变并给出视觉反馈。
6. WHERE 用户从算法选择控件选择 BFS、DFS、Dijkstra、A\* 或 Jump_Point_Search 之一，THE WASM_Playground SHALL 使用所选算法并依据当前起点、终点与障碍布局生成 `Step_Trace`。

### Requirement 3: 实时动画与帧率

**User Story:** 作为可视化的访问者，我想要看到算法扩展过程的流畅逐帧动画，以便理解每种算法如何探索网格。

#### Acceptance Criteria

1. WHEN 算法的 `Step_Trace` 计算完成，THE WASM_Playground SHALL 在 100 毫秒内启动动画并按访问/扩展顺序逐帧高亮节点以展示扩展过程。
2. WHILE 在 64×64 网格上播放扩展动画，THE WASM_Playground SHALL 维持滚动 1 秒窗口平均 `Frame_Rate` 不低于 60 帧每秒。
3. WHEN 动画播放到 `Step_Trace` 末尾且目标可达，THE WASM_Playground SHALL 以区别于扩展高亮的视觉样式绘制算法回溯得到的最终路径（对 BFS、Dijkstra 与 A\* 即最短路径，对 DFS 与 Jump_Point_Search 即算法回溯得到的最终路径）。
4. IF 动画播放到 `Step_Trace` 末尾时检测到目标在当前网格布局下不可达，THEN THE WASM_Playground SHALL 显示「不可达」状态提示、保留扩展高亮且不绘制路径。
5. WHILE 动画播放进行中，THE WASM_Playground SHALL 每 500 毫秒刷新一次实测 `Frame_Rate` 显示，并显示以行数×列数表示的网格规模与所选算法名称。
6. IF 实测滚动 1 秒窗口平均 `Frame_Rate` 低于 60 帧每秒，THEN THE WASM_Playground SHALL 显示帧率警告且不中断正在播放的动画。

### Requirement 4: GitHub Pages 部署

**User Story:** 作为评审与公众用户，我想要通过一个公开 URL 直接访问 Playground，以便无需本地构建即可体验。

#### Acceptance Criteria

1. WHEN `GitHub_Pages_Deployment` 成功发布完成，THE GitHub_Pages_Deployment SHALL 使匿名用户可通过 `https://Suquster.github.io/moonbit-pathfinding/` 访问 `WASM_Playground`，且页面在 5 秒内完成响应。
2. WHEN 向主干分支推送变更，THE Championship_V1_Upgrade SHALL 通过 CI 工作流在 600 秒内完成 `GitHub_Pages_Deployment` 的重新构建与发布。
3. THE GitHub_Pages_Deployment SHALL 在所发布页面中包含 `Playground_Wasm_Module`、宿主 HTML 与全部必需静态资源（脚本、样式、字体与 WASM 二进制），使页面在仅加载同源资源、不请求任何外部网络服务的情况下完成至少一次完整的寻路可视化。
4. IF 构建步骤以非成功退出码结束，THEN THE Championship_V1_Upgrade SHALL 中止发布、保留上一个成功发布的版本并输出失败诊断信息。
5. IF `Playground_Wasm_Module` 的 `.wasm` 文件磁盘字节数超过 102400 字节的体积门禁阈值，THEN THE Championship_V1_Upgrade SHALL 中止发布、保留上一个成功发布的版本并在诊断中记录实际体积与门禁阈值。

---

## 方向 2：性能冠军

### Requirement 5: 可复现基准测试框架

**User Story:** 作为库的维护者，我想要一个可复现、可 CI 回归的基准框架，以便用具体数据讨论性能而非凭空声称加速比。

#### Acceptance Criteria

1. WHEN 运行基准套件，THE Benchmark_Framework SHALL 生成同时包含 Markdown 与 JSON 两种格式的 `Benchmark_Report`。
2. THE Benchmark_Report SHALL 记录 MoonBit 版本、目标后端、机器/操作系统/CPU、输入生成器与随机种子、算法名称、图规模、边数、查询数、原始计时与汇总统计量，其中汇总统计量包含最小值、最大值、中位数、算术平均值、p95 与标准差。
3. WHEN 对每个基准用例运行测量，THE Benchmark_Framework SHALL 在测量前执行不少于 3 次预热并采集不少于 10 次计时样本。
4. WHEN 使用相同随机种子与相同输入规模重复运行同一基准，THE Benchmark_Framework SHALL 产出逐元素相同的输入图，且两次运行的中位计时相对差异不超过可比较容差（默认 5%）。
5. IF 当前基准结果相对已签入基线的中位计时回归超过回归容差（默认 10%），THEN THE Regression_Guard SHALL 使基准门禁失败并在报告中记录算法名称、基线中位计时、当前中位计时与回归百分比。
6. IF 执行环境缺少外部凭据或外部数据集，THEN THE Benchmark_Framework SHALL 给出明确的环境告警并继续运行其余基准而非中止整个套件。

### Requirement 6: 与 Rust pathfinding crate 对比报告

**User Story:** 作为 OSC 2026 评审，我想要看到本库与 Rust `pathfinding` crate 在等价工作负载下的可复现对比，以便客观评估竞争力。

#### Acceptance Criteria

1. THE Rust_Comparison_Report SHALL 针对至少 BFS、Dijkstra 与 A\* 三种算法，在 1000、10000 与 100000 节点三种图规模、平均出度 4 与 16 两种边密度、每组不少于 100 次查询的工作负载上，记录两个库以最小值、中位数、算术平均值与 p95 毫秒表示的计时数据。
2. WHEN 为对比生成输入，THE Championship_V1_Upgrade SHALL 使本库侧与 Rust 侧以相同随机种子生成逐元素相同的图与相同的查询集合以保证输入一致。
3. WHEN 对每个对比用例运行测量，THE Rust_Comparison_Report SHALL 记录不少于 5 次预热与不少于 30 次计时样本，并记录 CPU、操作系统与本库及 Rust 两套工具链版本。
4. THE Rust_Comparison_Report SHALL 包含完整方法学声明，说明输入生成方式、随机种子、预热与测量次数及测量环境。
5. THE Championship_V1_Upgrade SHALL 提供可复现脚本，使执行者重新生成的本库侧中位计时数据与报告值的相对差异不超过 15%。
6. THE Rust_Comparison_Report SHALL 统一以中位计时口径计算并呈现加速比。
7. IF 某对比用例发生失败、超时（执行时间超过 60 秒）或两库结果不一致，THEN THE Rust_Comparison_Report SHALL 标注该情形并将其排除出加速比计算。
8. WHERE 对比数据来自不同机器或不同工具链版本，THE Rust_Comparison_Report SHALL 在报告中显式标注该差异且不据此声明加速比。

### Requirement 7: 大规模压力测试

**User Story:** 作为在生产环境集成本库的开发者，我想要确认算法在大规模图上仍能正确终止，以便放心处理真实业务数据量。

#### Acceptance Criteria

1. WHEN 在包含 10000 个节点的图上运行 BFS、Dijkstra 与 A\*，THE Stress_Test SHALL 使每种算法在 60000 毫秒（60 秒）超时上界内终止，并返回有效结果（一条有效路径或一个明确的无解指示），且不修改输入图、不触发 panic。
2. WHEN 压力测试在 10000 节点图上返回非空路径结果，THE Stress_Test SHALL 验证返回路径的每条相邻节点对在输入图中存在对应边，否则使该用例失败。
3. WHEN 压力测试目标可达，THE Stress_Test SHALL 验证返回路径的首节点等于查询起点、末节点等于查询目标，且返回的路径代价与沿返回路径各边权重之和的偏差不超过 1e-9。
4. IF 压力测试图中目标不可达，THEN THE Stress_Test SHALL 使对应算法返回明确的无解结果（空路径或 None）而非异常终止。
5. IF 某算法在 60000 毫秒超时上界内未终止，THEN THE Stress_Test SHALL 将该用例标记为失败并记录诊断信息而非挂起。

### Requirement 8: CH/JPS/ALT 升级为生产级

**User Story:** 作为追求极致查询性能的开发者，我想要 CH、JPS 与 ALT 三种前沿算法达到生产级且经真实路网验证，以便在大规模路网上获得显著加速。

#### Acceptance Criteria

1. THE Championship_V1_Upgrade SHALL 为 Contraction_Hierarchies、Jump_Point_Search 与 ALT 各提供完整的公开 API，且其实现不含 `abort`、`todo!`、`unimplemented` 或 `panic` 占位，也不含空壳函数。
2. WHEN 在 `OSM_Roadmap_Dataset` 上以不少于 100 组随机源/目标查询对分别运行 Contraction_Hierarchies、ALT 与基准 Dijkstra，THE Championship_V1_Upgrade SHALL 验证三者对每组查询返回的最短路径代价相等（整数权重精确相等，浮点权重偏差不超过 1e-9）。
3. WHEN 在均匀代价网格上以不少于 100 组随机源/目标查询对分别运行 Jump_Point_Search 与 A\*，THE Championship_V1_Upgrade SHALL 验证两者对每组查询返回的最短路径代价相等（整数权重精确相等，浮点权重偏差不超过 1e-9）。
4. THE Championship_V1_Upgrade SHALL 为 Contraction_Hierarchies、Jump_Point_Search 与 ALT 在 `Benchmark_Report` 中记录基于 `OSM_Roadmap_Dataset` 的可复现计时证据，包含预处理耗时、不少于 10 次重复的平均与中位查询耗时、查询样本量、数据集标识与图规模。
5. THE Championship_V1_Upgrade SHALL 为 Contraction_Hierarchies 与 ALT 记录其相对基准 Dijkstra 的中位查询加速比，并断言两者的平均查询耗时不高于基准 Dijkstra 的平均查询耗时。
6. WHEN 将 Contraction_Hierarchies、Jump_Point_Search 与 ALT 升级为 Production_Algorithm，THE Championship_V1_Upgrade SHALL 逐项保持其既有公开签名不变并仅以新增方式扩展能力。
7. IF `OSM_Roadmap_Dataset` 在执行环境中不可用，THEN THE Championship_V1_Upgrade SHALL 跳过真实路网基准、在报告中记录数据缺失诊断，并继续以合成数据完成正确性验证而不使套件失败。

---

## 方向 3：形式验证升级

### Requirement 9: 证明谓词扩展至全部 30 种经典算法

**User Story:** 作为重视正确性的库使用者，我想要每一种经典算法都有运行时可校验的后置条件，以便信任其输出在 CI 中持续被验证。

#### Acceptance Criteria

1. THE Championship_V1_Upgrade SHALL 为 Classic_Algorithm_Set 中编号 1 至 30 的全部 30 种经典算法各提供至少一个 Proof_Predicate。
2. WHEN 对算法的某次结果调用 Proof_Predicate，THE Proof_Predicate SHALL 输出布尔判定，对满足后置条件的结果输出真、对违反后置条件的结果输出假。
3. WHEN 某算法返回非空路径结果，THE Proof_Predicate SHALL 在路径首节点等于查询源、末节点等于查询目标且每条相邻节点对在输入图中存在对应有向边时判定为真，否则判定为假。
4. WHEN 某最短路算法返回带权结果，THE Proof_Predicate SHALL 在返回代价与沿返回路径各边权重之和的偏差不超过 1e-9 时判定为真，否则判定为假。
5. WHEN 某算法对无解查询返回空路径结果，THE Proof_Predicate SHALL 校验该查询在输入图中确无从源到目标的路径并据此输出布尔判定。
6. IF 向 Proof_Predicate 提供一个 Bad_Witness，THEN THE Proof_Predicate SHALL 将该 Bad_Witness 判定为假，且不修改或丢弃所提供的输入。
7. WHEN 在三后端（`wasm-gc`、`js`、`native`）上运行全部 Proof_Predicate，THE Championship_V1_Upgrade SHALL 要求每个 Proof_Predicate 在三后端给出相同的通过/失败判定。
8. IF 某 Proof_Predicate 在三后端间出现判定分歧，THEN THE Championship_V1_Upgrade SHALL 使证明门禁失败并报告出现分歧的谓词与后端。

### Requirement 10: 循环不变式注解

**User Story:** 作为算法的审阅者，我想要核心算法的关键循环带有不变式注解与运行时校验，以便理解并验证算法在每步迭代中维持的正确性条件。

#### Acceptance Criteria

1. THE Championship_V1_Upgrade SHALL 为 Classic_Algorithm_Set 中每种算法的主循环以注释形式记录其 Loop_Invariant，注释须包含不变式的布尔陈述、初始化成立说明与迭代保持说明。
2. WHERE 某算法的 Loop_Invariant 可表达为对算法状态求值的布尔判定函数，THE Championship_V1_Upgrade SHALL 提供对应的运行时断言并在主循环每次迭代后对该不变式求值。
3. WHEN Dijkstra 主循环每次从优先队列弹出一个节点，THE Proof_Predicate SHALL 校验该节点的已确定距离不小于此前所有已弹出节点的已确定距离（单调性不变式）。
4. WHEN BFS 主循环每次将节点加入队列，THE Proof_Predicate SHALL 校验队列中任意两节点的层级差绝对值不超过 1（层序不变式）。
5. WHILE 在测试中验证某算法的 Loop_Invariant，THE Championship_V1_Upgrade SHALL 对该算法运行不少于 100 个随机生成的输入图。
6. IF 某次迭代后不变式断言求值为假，THEN THE Championship_V1_Upgrade SHALL 立即终止该测试用例并报告被违反的不变式名称与迭代序号。

### Requirement 11: 可审计证明报告管线

**User Story:** 作为 OSC 2026 评审，我想要一份可审计的证明报告汇总全部算法的验证状态，以便快速评估本库的形式化严谨程度。

#### Acceptance Criteria

1. WHEN 运行 Proof_Pipeline，THE Proof_Pipeline SHALL 生成 Markdown 与 JSON 两种格式且逐项语义一致的 Proof_Report。
2. THE Proof_Report SHALL 覆盖全部公开寻路与图算法、为每种算法列出不少于一条证明性质，并为每条性质列出运行结果（仅取通过或失败）与证据来源，其中证据来源为产生该结果的谓词测试用例标识或静态验证条目标识。
3. THE Proof_Report SHALL 记录所运行的后端（取自 `wasm-gc`、`js`、`native` 子集）、MoonBit 版本与采用 ISO 8601 UTC 格式的生成时间戳以保证可审计性。
4. IF 任一 Proof_Predicate 在管线运行中失败，THEN THE Proof_Pipeline SHALL 以非零退出状态使证明门禁失败并在 Proof_Report 中标记失败的算法与性质。
5. IF Proof_Report 的生成或写出失败，THEN THE Proof_Pipeline SHALL 以非零退出状态使证明门禁失败并输出失败诊断信息。
6. WHERE 官方 `moon prove` 静态验证在执行环境中不可用，THE Proof_Pipeline SHALL 在 Proof_Report 中记录该环境限制并仍输出运行时谓词的验证结果。

---

## 方向 4：API 人机工程学与类型安全

### Requirement 12: 流式 GraphBuilder 模式

**User Story:** 作为构建图的开发者，我想要一个链式调用的图构造器，以便用可读、不易出错的方式逐步声明节点与边。

#### Acceptance Criteria

1. THE Graph_Builder SHALL 提供创建空构造器、添加节点、添加带权有向边、添加带权无向边与物化为图表示的操作，并支持不少于 1000000 个节点与不超过 10000000 条边。
2. WHEN 调用方依次添加 N 条边后物化，THE Graph_Builder SHALL 产出包含全部已添加边且无遗漏、无重复引入的图表示。
3. WHEN 调用方对同一对源/目标节点重复添加边，THE Graph_Builder SHALL 仅保留该有向边的一条实例并采用末次添加的权重。
4. WHEN 调用方在未添加任何节点或边时物化空构造器，THE Graph_Builder SHALL 产出一个有效的空图而非失败结果。
5. IF 调用方添加引用未声明节点的边，THEN THE Graph_Builder SHALL 返回携带 PathError 的失败结果并保持已累积的节点与边集合不被修改。
6. WHEN 调用方调用添加节点或添加边操作，THE Graph_Builder SHALL 返回构造器自身使连续链式调用可组合。
7. WHEN 物化由 Graph_Builder 构建的图并交给既有算法查询，THE Championship_V1_Upgrade SHALL 产出与以既有方式构建的等价图相同的查询结果，其中等价图定义为具有相同节点集合与相同带权边集合的图，相同定义为查询结果逐项相等。

### Requirement 13: 结构化错误类型 PathError

**User Story:** 作为调用算法的开发者，我想要结构化的错误类型而非含糊的失败，以便针对不同失败原因编写精确的处理逻辑。

#### Acceptance Criteria

1. THE PathError SHALL 以枚举区分且仅区分以下五种互斥失败原因，每种原因对应唯一变体：源节点不存在、目标节点不存在、目标不可达、检测到负权环、输入参数非法。
2. IF 算法因源节点不在图中而无法执行，THEN THE Championship_V1_Upgrade SHALL 返回携带「源节点不存在」PathError 变体的失败结果并保持输入图不被修改。
3. IF 算法因目标节点不在图中而无法执行，THEN THE Championship_V1_Upgrade SHALL 返回携带「目标节点不存在」PathError 变体的失败结果并保持输入图不被修改。
4. IF 源节点与目标节点均在图中但目标在图中不可达，THEN THE Championship_V1_Upgrade SHALL 返回携带「目标不可达」PathError 变体的失败结果。
5. IF 在源到目标的某条可达路径上存在负权环致使无法给出有限最短路，THEN THE Championship_V1_Upgrade SHALL 返回携带「负权环」PathError 变体的失败结果。
6. IF 算法接收到非法的输入参数，THEN THE Championship_V1_Upgrade SHALL 返回携带「输入参数非法」PathError 变体的失败结果并保持输入图不被修改。
7. THE PathError SHALL 提供非空且可唯一标识其所属失败原因变体的人类可读诊断消息字符串，且该消息构建过程不使用循环内字符串累加拼接。
8. THE Championship_V1_Upgrade SHALL 以新增 API 形式提供返回 PathError 的算法入口，且保持既有返回 `Option` 的算法签名不变。

### Requirement 14: 惰性路径迭代器

**User Story:** 作为在内存受限环境工作的开发者，我想要按需逐个获取路径节点，以便处理超长路径时不必一次性物化整条路径。

#### Acceptance Criteria

1. THE Lazy_Path_Iterator SHALL 提供一个取值操作，按调用语义逐个产出路径中的下一个节点或在路径耗尽时给出终止信号，其中终止信号定义为返回不含任何节点的终止值。
2. WHEN 路径中仍存在尚未产出的节点而调用取值操作，THE Lazy_Path_Iterator SHALL 产出路径中的下一个节点并向前推进一个位置。
3. WHEN 路径中已无尚未产出的节点而调用取值操作，THE Lazy_Path_Iterator SHALL 返回不含任何节点的终止值。
4. WHEN 完整消费 Lazy_Path_Iterator 产出的全部节点，THE Championship_V1_Upgrade SHALL 使所得节点序列与一次性物化的完整路径在序列长度相等且每个位置逐元素相等。
5. THE Lazy_Path_Iterator SHALL 使其额外状态规模不超过单条路径的节点数，且在任意时刻不物化多于一条候选路径。
6. WHEN 查询无解，THE Lazy_Path_Iterator SHALL 在首次调用取值操作时即返回不含任何节点的终止值。
7. IF 在路径耗尽后重复调用取值操作，THEN THE Lazy_Path_Iterator SHALL 持续返回相同的终止值且不再产出任何节点。

### Requirement 15: 通用图适配器

**User Story:** 作为已有不同图存储格式的开发者，我想要将邻接矩阵、边表与 CSR 格式统一接入算法，以便无需手动改写数据结构即可复用全部算法。

#### Acceptance Criteria

1. THE Graph_Adapter SHALL 为 Adjacency_Matrix、Edge_List 与 CSR 三种存储格式各提供将其暴露为算法所需邻居访问接口的适配实现，该接口返回指定节点的全部出边邻居标识及其对应边权重。
2. WHEN 同一逻辑图分别以 Adjacency_Matrix、Edge_List 与 CSR 表示并经 Graph_Adapter 接入同一算法，THE Championship_V1_Upgrade SHALL 使三者产出的查询结果相等，其中逻辑图等价定义为具有相同节点集合、相同出边集合与相同边权重，结果相等定义为邻居集合与对应边权重完全相等且不区分底层内部排列。
3. WHEN 通过 Graph_Adapter 查询某节点的邻居，THE Graph_Adapter SHALL 返回该节点在底层格式中记录的全部出边邻居且不遗漏、不重复，并以节点标识升序排列，且对同一节点的重复调用返回顺序一致。
4. WHEN 通过 Graph_Adapter 查询一个无出边的孤立节点，THE Graph_Adapter SHALL 返回空邻居的成功结果。
5. IF 向 Graph_Adapter 提供小于 0 或不小于 N 的越界节点标识（节点标识有效范围为 0 至 N-1），THEN THE Graph_Adapter SHALL 返回携带 PathError 的失败结果并保持底层图不被修改。
6. THE Championship_V1_Upgrade SHALL 以新增适配器类型形式提供 Graph_Adapter，且不修改既有算法的公开签名。

---

## 方向 5：差分测试与模糊测试

### Requirement 16: 跨算法差分验证

**User Story:** 作为库的维护者，我想要在应当等价的算法之间进行差分验证，以便用一种算法交叉检验另一种算法的正确性。

#### Acceptance Criteria

1. WHEN 在边权全部为单位权的图上对同一源/目标分别运行 BFS 与 Dijkstra，THE Differential_Tester SHALL 验证两者返回的最短路径代价精确相等（整数单位权）。
2. WHEN 在同一带权图上对同一源/目标分别运行 Dijkstra 与 Bellman-Ford（无负权边），THE Differential_Tester SHALL 验证两者返回的最短路径代价偏差不超过 1e-9。
3. WHEN 在同一带权图上对全部节点对分别运行 Floyd-Warshall 与 Johnson，THE Differential_Tester SHALL 验证两者返回的全对最短距离矩阵逐元素偏差不超过 1e-9。
4. WHEN 同一 Equivalence_Class 中两算法对同一源/目标查询均判定目标不可达，THE Differential_Tester SHALL 验证两者一致地给出不可达结果。
5. THE Differential_Tester SHALL 为每个 Equivalence_Class 以属性测试方式运行不少于 100 次随机生成的图实例，图实例规模约束为节点数 1 至 500、边数 0 至 5000、边权值 0.01 至 1000000.00。
6. WHERE 差分验证涉及 Dijkstra、BFS 或 Bellman-Ford，THE Differential_Tester SHALL 仅生成非负权边的图实例。
7. IF 某个 Equivalence_Class 中两算法在某输入上结果不一致，THEN THE Differential_Tester SHALL 使测试失败并报告导致不一致的图实例、两算法各自的输出、经收缩得到的最小反例与所用随机种子。

### Requirement 17: 结构化图生成器模糊测试

**User Story:** 作为库的维护者，我想要用结构化随机生成的多样图实例对算法进行模糊测试，以便在发布前发现边界与畸形输入引发的缺陷。

#### Acceptance Criteria

1. THE Fuzz_Generator SHALL 能够生成节点数 0 至 10000、边数 0 至 100000 的多样图实例，覆盖空图、单节点图、稠密图（边数不少于 N×(N-1)/4，N 为节点数）、稀疏图（边数不超过 2×N）、至少 1 个自环、至少 1 组平行边与至少 2 个不连通分量等情形。
2. THE Fuzz_Generator SHALL 为每个被模糊测试的算法生成不少于 100 个图实例。
3. WHEN 以 Fuzz_Generator 生成的图实例运行任一算法，THE Championship_V1_Upgrade SHALL 使该算法在 10 秒内正常终止并返回有效结果或结构化错误，且不抛出异常、不进入死循环、不崩溃。
4. IF 算法在 10 秒内未终止，THEN THE Championship_V1_Upgrade SHALL 将该用例标记为失败并记录触发该用例的随机种子。
5. IF 向算法提供非法参数，THEN THE Championship_V1_Upgrade SHALL 以结构化错误处理该输入而非崩溃。
6. WHEN 模糊测试发现导致失败的图实例，THE Fuzz_Generator SHALL 在不超过 1000 次收缩迭代内将该反例收缩为满足局部最小性的最小失败实例，局部最小性定义为移除其中任一节点或任一边后失败不再复现。
7. THE Fuzz_Generator SHALL 接受 64 位整数随机种子参数，使任一发现的失败实例可通过相同种子逐字节一致地复现。

### Requirement 18: 行覆盖率目标

**User Story:** 作为 OSC 2026 评审，我想要测试套件达到高行覆盖率，以便确信代码路径已被充分验证。

#### Acceptance Criteria

1. WHEN 运行 `moon coverage analyze`，THE Championship_V1_Upgrade SHALL 使被测源代码的 Line_Coverage 不低于 95.0%，其中被测源定义为既非测试也非基准的 `*.mbt` 文件（排除 `*_test.mbt`、`*_wbtest.mbt` 以及 `benches/` 目录下的文件）。
2. THE Championship_V1_Upgrade SHALL 在 `wasm-gc`、`js` 与 `native` 三后端中至少一个后端上度量并记录 Line_Coverage 数值（百分比保留至少一位小数）及对应后端名称。
3. IF Line_Coverage 低于 95.0%，THEN THE Championship_V1_Upgrade SHALL 使覆盖率门禁失败、以「文件路径 + 行号」列出未覆盖的代码位置并返回非成功状态。
4. IF `moon coverage analyze` 执行失败或其输出不可解析，THEN THE Championship_V1_Upgrade SHALL 使覆盖率门禁失败、输出失败原因且不判定覆盖率达标。

---

## 方向 6：文档卓越

### Requirement 19: 自动生成算法复杂度表

**User Story:** 作为评估本库的开发者，我想要一份准确的算法复杂度表，以便为我的场景选择合适的算法。

#### Acceptance Criteria

1. THE Doc_Generator SHALL 从算法元数据生成 Complexity_Table，为每种算法列出算法名称、最坏时间复杂度、平均时间复杂度、空间复杂度与适用条件五个字段，且每个字段均非空。
2. THE Complexity_Table SHALL 覆盖 Classic_Algorithm_Set 全部 30 种算法以及 Contraction_Hierarchies、Jump_Point_Search 与 ALT，共恰好 33 行，每种算法唯一对应一行且无重复、无遗漏。
3. WHEN 算法元数据发生变更，THE Doc_Generator SHALL 重新生成 Complexity_Table 使其每个字段与最新元数据完全相等。
4. THE Doc_Generator SHALL 在生成 Complexity_Table 时使生成耗时随算法数量呈 O(n) 线性增长，且在构建文本输出时不使用循环内字符串累加拼接。
5. IF 某算法元数据缺失或其必填字段为空，THEN THE Doc_Generator SHALL 使生成失败、不产生部分写入并保留上一份有效的 Complexity_Table。

### Requirement 20: 文档注释中的 ASCII 可视化

**User Story:** 作为阅读 API 文档的开发者，我想要在文档注释中看到图与路径的 ASCII 示意，以便直观理解算法的输入输出。

#### Acceptance Criteria

1. THE Championship_V1_Upgrade SHALL 为 BFS、DFS、Dijkstra、A\*、Jump_Point_Search 与 Contraction_Hierarchies 六种算法的每个公开入口在 Doc_Comment 中提供不少于一个 Ascii_Visualization 示意块，每个示意块的网格规模介于 3×3 与 20×20 之间。
2. THE Ascii_Visualization SHALL 使用 5 个互不相同的单字符分别表示起点、终点、障碍、路径与空闲单元格，并在示意中附带说明各字符含义的图例。
3. WHEN 某 Ascii_Visualization 示意所对应的网格布局不存在可行路径，THE Ascii_Visualization SHALL 省略路径字符并在图例中标明「无可行路径」。
4. WHERE 某公开算法入口包含可运行的文档示例，THE Championship_V1_Upgrade SHALL 通过 `moon test README.mbt.md` 模式使该示例作为测试被编译与运行校验。
5. IF `moon test README.mbt.md` 下的某文档示例编译失败或运行结果与预期不符，THEN THE Championship_V1_Upgrade SHALL 使构建失败并输出定位到该示例的诊断信息。

### Requirement 21: Cookbook 与公开 API 文档完整性

**User Story:** 作为初次使用本库的开发者，我想要一份覆盖真实用例的实用手册并确保每个公开 API 都有充分文档，以便快速上手并正确调用。

#### Acceptance Criteria

1. THE Cookbook SHALL 包含不少于 20 个真实用例，覆盖网格寻路、网络路由、任务调度、最大流与匹配五类场景，且每一类场景至少包含 1 个用例。
2. WHEN 运行 Cookbook 中的任一用例，THE Championship_V1_Upgrade SHALL 使该用例在 `wasm-gc`、`js` 与 `native` 三后端上均以成功状态完成。
3. THE Championship_V1_Upgrade SHALL 使每个 Pub_Api 的 Doc_Comment 不少于 5 行非空注释行，非空注释行定义为去除首尾空白后长度大于 0 的注释行。
4. IF 某个 Pub_Api 的 Doc_Comment 非空注释行少于 5 行，THEN THE Championship_V1_Upgrade SHALL 使文档完整性门禁失败并报告该 API 标识与其实际非空注释行数。
5. THE Cookbook 中的每个用例 SHALL 提供可执行命令与预期输出。
6. IF 某用例的实际输出与其预期输出不符，THEN THE Championship_V1_Upgrade SHALL 使可重现性校验失败并报告差异位置。

---

## 横切质量约束

### Requirement 22: 冠军级质量基线（横切约束）

**User Story:** 作为库的维护者，我想要所有升级工作遵循统一的冠军级质量基线，以便整个 v1.0.0 在性能、类型安全、测试与兼容性上无短板。

#### Acceptance Criteria

1. THE Championship_V1_Upgrade SHALL 为每个新增的 Pub_Api（定义为 `.mbti` 接口文件中新增的公开函数或类型）提供至少一个属性测试，且该属性测试对应 `holds_for_all` 的 `count` 参数不小于 100。
2. THE Championship_V1_Upgrade SHALL 在 `wasm-gc`、`js` 与 `native` 三个后端上运行测试套件并使结果一致，结果一致定义为各后端给出相同的通过/失败判定、相同的断言、相同的用例数且无任一后端独有的失败。
3. THE Championship_V1_Upgrade SHALL 保持既有公开函数与类型的签名不变，并使 `moon info` 生成的 `.mbti` 接口文件仅新增条目、不删除或修改既有条目。
4. THE Championship_V1_Upgrade SHALL 在所有非测试源文件（不以 `_test.mbt` 或 `_wbtest.mbt` 结尾的 `.mbt` 文件）的循环或递归体内不使用字符串累加拼接（`out = out + s` 模式）。
5. THE Championship_V1_Upgrade SHALL 不使用 `abort`、`todo!`、`unimplemented` 或 `panic` 作为功能占位，每个公开函数均具备完整可工作的实现。
6. THE Championship_V1_Upgrade SHALL 以精确类型（枚举/结构体）表示结构化数据，不使用字符串模拟结构化数据。
7. IF 同一测试在三后端间给出不一致的通过/失败判定，THEN THE Championship_V1_Upgrade SHALL 判定该测试套件不通过并报告出现差异的后端。
8. IF `.mbti` 接口文件中的任一既有条目被删除或被修改，THEN THE Championship_V1_Upgrade SHALL 判定破坏向后兼容并使兼容性门禁失败。
9. IF 任一既有测试由通过变为失败，THEN THE Championship_V1_Upgrade SHALL 判定不通过并要求修复升级代码而非修改既有测试。
10. WHEN 完成任一方向的升级，THE Championship_V1_Upgrade SHALL 通过 `moon info && moon fmt && moon test` 且既有测试保持通过。
