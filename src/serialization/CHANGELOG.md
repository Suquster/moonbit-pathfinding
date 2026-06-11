# Changelog —— Serialization（方向九）

本文件记录 **Serialization**（序列化框架）方向（子包 `src/serialization`）
作为**独立发布单元**的全部值得关注的变更。

格式基于 [Keep a Changelog](https://keepachangelog.com/en/1.1.0/)，
版本号遵循 [语义化版本 SemVer](https://semver.org/spec/v2.0.0.html)。

> 🌐 语言：简体中文为主，标识符 / API 保留英文。
>
> 本方向维护**独立**于仓库根 `CHANGELOG.md` 的版本线（独立 SemVer），
> 与 umbrella 模块 `moon.mod.json` 的版本解耦——主版本号 `0` 表示骨架阶段
> 公共 API 仍可能演进。发布元数据由 `release_info()` 登记为
> `DirectionRelease`（见 `release.mbt`）。

---

## [Unreleased]

## [0.1.0] - 2026-06-11

骨架首版（breadth-first 第一版）：达成「可编译 + 跑通三后端（wasm-gc / js /
native）+ protobuf wire format 编解码 + `.proto` 解析 + 代码生成 + 往返/错误
属性测试 + 可执行文档」的方向骨架基线。

### Added
- 核心类型：`Message`、`Schema`（消息 / 字段 / 枚举的模式描述）、
  `DecodeError`（含出错字节偏移）、`ParseError`（含行列位置）等数据模型
  （新增序列化核心类型与模式描述）。
- wire format 编解码：`encode`（内存对象 → protobuf wire format 字节序列）
  与 `decode`（字节 + 模式 → 消息对象）；解码失败返回**含出错字节偏移**的
  错误且不产生部分构造对象（新增 protobuf wire format 编解码）。
- `.proto` 解析：`parse_proto` 构建于 `@parser_combinator`，将 `.proto`
  文件解析为消息 / 字段 / 枚举模式描述，语法错误返回含行列位置的解析错误
  （新增 `.proto` 解析器）。
- 代码生成：`gen_moonbit` 由合法 `.proto` 模式产出对应的 MoonBit 消息类型
  定义与编解码代码（新增模式驱动的代码生成）。
- 属性测试：编码 ↔ 解码往返性质与非法字节错误条件性质，跨三后端一致
  （新增往返 / 错误属性测试）。
- 可执行文档：覆盖编码再解码往返用法的 `*.mbt.md` 端到端样例
  （新增序列化可执行文档示例）。
- release: 通过 `release_info()` 登记本方向 `DirectionRelease`（版本
  `0.1.0`，changelog 路径 `src/serialization/CHANGELOG.md`）
  （新增方向发布元数据登记）。

[Unreleased]: https://github.com/Suquster/moonbit-pathfinding/compare/serialization-v0.1.0...HEAD
[0.1.0]: https://github.com/Suquster/moonbit-pathfinding/releases/tag/serialization-v0.1.0
