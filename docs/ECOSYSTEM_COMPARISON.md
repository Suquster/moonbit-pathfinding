# 与 MoonBit 生态已有项目的对比与差异化定位

> 调研时间：2026-07-07，基于 mooncakes.io 全量包索引（1491 个包）逐一筛查。
> 目的：响应赛事章程"可解释性评估"中"对优秀开源工作借鉴（如有）取舍"的要求，
> 主动、如实地说明本项目与生态内同类包的关系，而非回避。

## 结论摘要

赛事章程未禁止同类实现并存（生态中 regex、TOML、readline、datetime 均有多个
实现共存并各自演进）；章程中"（除 MoonBit 生态已有项目）"针对的是**直接复刻
某个已有项目作为参赛作品本身**的情况。本项目的定位不是复刻任何单一已有包，
而是：

1. **寻路主线**：以论文为源头独立实现（BFS/Dijkstra/A*/Bellman-Ford/Yen/JPS/
   ALT/CH/CCH/Hub Labeling 等），配备可执行 proof predicates、真实 OSM 路网
   基准与三后端一致性门禁——这一"前沿加速梯队 + 可验证性"组合在生态内没有
   对应物。
2. **INFRA 工具集**：为支撑主线的工程闭环（基准、模糊测试、发布、文档、CI）
   而生长出的自洽基础设施层，全部对拍权威参考实现（CPython hashlib/zlib、
   python-lz4、python-xxhash、Go stdlib、RFC/FIPS 官方向量），并以统一的
   验收门禁（acceptance 4 gates、2369 测试）持续约束。

## 逐领域对照表

### 寻路 / 图算法（主线）

| 生态已有包 | 覆盖范围 | 本项目差异 |
|---|---|---|
| `hzc-666-ai/moonpathfinding` | 7 种基础算法、网格/图 | 本项目额外覆盖 CH/CCH/ALT/Hub Labeling 前沿加速梯队、Yen k 最短路、JPS，且带可执行最短性证明谓词与真实 OSM 路网（厦门 2.4 万 / 北京 16 万节点）基准 |
| `mizchi/pathfind` | 基于 terrain 网格的 A* 辅助 | 本项目为通用泛型图（`N : Eq + Hash` 后继函数式 API），不绑定网格 |
| `I3eg1nner/petgraph`、`morning-start/mbtgraph`、`OldPigxjk/moon_toolkit`、`smallbearrr/NetworkX` | 通用图数据结构/算法 | 定位不同：本项目以最短路为核心纵深（含预处理类加速结构），并以证明谓词+基准工件形成可复现证据链 |

### INFRA 子包（支撑层）

| 领域 | 生态已有包 | 本项目取舍说明 |
|---|---|---|
| hash | `gmlewis/sha256`、`Tigls/mb-hash`、`oboard/mooncrypto`、`tonyfettes/xxh64`、`AXiX-official/xxhash`、`PingGuoMiaoMiao/LunarKeccak256` | 生态内单算法散装分布；本项目提供统一 API 的全家族（SHA-1/2/3、BLAKE2b、MD5、HMAC/HKDF/PBKDF2、CRC-32/32C/64、xxHash32/64、SipHash、MurmurHash3），全部 FIPS/RFC/SMHasher 官方向量对拍，服务于内部基准指纹与去重 |
| compress | `bikallem/compress`、`hustcer/fzip`、`moonbit-community/flate`、`mizchi/zlib`、`gmlewis/{flate,gzip,zlib}` | 独立自 RFC 1951/1952 实现 DEFLATE/gzip/zlib/LZ4，未借用上述包代码；以 CPython zlib、python-lz4 黄金向量对拍 + 抗炸弹解压器 + 250 迭代 PBT 为特色 |
| TOML/INI | `bob/toml`、`tonyfettes/{amtoml,toml_parser}`、`maria/toml_parser`、`ShellWen/sw_ini` | 面向本项目配置读取的核心子集实现，随工程需要演进；不以替代上述通用解析器为目标 |
| diff | `myfreess/piediff`（patience）、`myfreess/myers-diff`、`ruifeng/diff` | 本项目将 Myers/patience/histogram 三算法 + unified diff 解析/apply + diff3 三方合并整合进同一 `DiffOp` 管线（供文档/基准回归对比使用），并有三算法 apply→new 恒等 PBT |
| datetime | `iceBear67/time`、`suiyunonghen/datetime`、`brickfrey/tempo`、`Asterless/MoonPtime` | 本项目补充 POSIX TZ/DST 规则解析（glibc 语义）与 Go 风格 Duration，服务于基准时间戳与日志 |
| CLI | `TheWaWaR/clap`、`DzmingLi/clap`、`Yoorkin/ArgParser`、`mizchi/admiral` | 本项目 CLI 层与 backend_cli/examples 深度耦合（typed 取值、声明式校验、did-you-mean、bash/zsh 补全生成），非独立通用 argparser |
| resilience | `tuya-me/fuse`（circuit breaker）、`ryota0624/circuit_breaker` | 本项目覆盖面更广（COUNT/TIME_BASED 熔断、Bulkhead、Hedging、AIMD、Finagle RetryBudget），语义对标 resilience4j/Finagle 并有不变式 PBT |
| regex | `moonbitlang/regexp`、`yj-qin/regexp`、`hackwaly/regex` | 本项目 regex_engine 为教学级+工程级双语义实现（含 `\p{Name}` Unicode 类），服务于内部文本处理，未复用上述实现 |

## 借鉴与独立性声明

- 所有实现均从原始论文 / RFC / FIPS / 官方规范独立派生，未复制生态内任何包的
  源码；对拍对象为语言无关的权威参考实现（CPython、Go stdlib、python-lz4 等）
  的**输出向量**，而非其代码。
- API 哲学借鉴 Rust `pathfinding` crate（详见申报书"对标与借鉴说明"），属于
  设计层面的致敬与取舍，实现完全独立。
- INFRA 子包首要角色是本项目工程闭环的支撑层（自举），其次才是可独立复用的
  生态贡献；这与"为造轮子而造轮子"有本质区别——每个子包都有主线内的真实
  消费方（基准指纹、发布校验、文档 diff、CI 韧性等）。

## 与集合闭包战略的关系

本文档回答的是"单个领域内与已有包的取舍"；项目整体定位则由
`docs/STRATEGY_CLOSURE.md` 的 L0⊂L1⊂…⊂L5 六层闭包叙事给出：生态内的
同类包均是单层内的单点实现，而本项目的不可复制性在于层与层之间的
有向依赖闭环（每个轮子都被链内上层真实消费）与贯穿全链的同一套
证据化工程流程（acceptance 门禁 + 向量对拍 + paper-to-code 追溯）。
定期刷新约定：每次闭包扩张（backlog G 区任一子项收官）后，重跑 mooncakes
全量索引筛查并更新本对照表（G-A3 目标是把这一步自动化）。
