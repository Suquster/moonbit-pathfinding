// types.mbt —— Build_Tool 的核心类型定义。
//
// 设计依据（design.md §「组件与接口 → 方向六：Build_Tool」）：
//
//   pub struct BuildGraph { nodes : Array[Target]; edges : Array[(Target, Target)] }
//   pub fn parse_rules(src : String) -> Result[BuildGraph, ParseError]
//   pub fn detect_cycle(g : BuildGraph) -> Array[Target]?
//   pub fn topo_order(g : BuildGraph) -> Result[Array[Target], Cycle]
//   pub fn is_dirty(t : Target, cache : BuildCache) -> Bool
//   pub fn schedule(g : BuildGraph, jobs : Int) -> Array[Array[Target]]
//
// 本文件锁定模块边界与数据模型：构建图由「构建目标 `Target`」与「依赖边
// `(Target, Target)`」构成；脏检查以 `BuildCache`（mtime + 内容哈希）为依据；
// 解析失败由 `ParseError` 承载、环检测结果由 `Cycle` 承载。各接口的完整
// 算法实现属任务 9.2。

///|
/// 构建目标（build target），以名字唯一标识。
///
/// 名字通常是产物路径或规则名。派生 `Eq + Hash` 以便作为图节点参与
/// `@directed` 的拓扑/强连通分量算法（其类型约束为 `N : Eq + Hash`）；
/// `Show` 以手写 impl 提供（输出目标名），便于诊断与测试快照阅读，
/// 同时规避 `derive(Debug)` 的弃用告警。
pub struct Target {
  name : String
} derive(Eq, Hash)

///|
/// 由名字构造构建目标。
pub fn Target::new(name : String) -> Target {
  { name, }
}

///|
/// 以目标名展示构建目标（便于诊断信息与测试快照阅读）。
pub impl Show for Target with fn output(self : Target, logger : &Logger) -> Unit {
  logger.write_string(self.name)
}

///|
/// 构建图（build graph）。
///
/// 严格对应 design.md 签名 `BuildGraph { nodes : Array[Target];
/// edges : Array[(Target, Target)] }`：
///   * `nodes` —— 全部构建目标；
///   * `edges` —— 依赖边 `(u, v)` 表示「`u` 必须在 `v` 之前构建」
///     （即 `v` 依赖 `u`），供拓扑排序与并行调度使用。
pub struct BuildGraph {
  nodes : Array[Target]
  edges : Array[(Target, Target)]
}

///|
/// 由节点与依赖边构造构建图。
pub fn BuildGraph::new(
  nodes : Array[Target],
  edges : Array[(Target, Target)],
) -> BuildGraph {
  { nodes, edges }
}

///|
/// 构建缓存（build cache）—— 脏检查（dirty check）的依据。
///
/// 脏检查需要比对目标输入的「两份指纹」：
///   * `recorded_*` —— 上次成功构建时固化的输入指纹（mtime + 内容哈希），
///     即「基线」；
///   * `current_*`  —— 当前观测到的输入指纹（真实构建中由扫描文件系统得到，
///     本骨架阶段由调用方通过 `observe` 注入）。
///
/// `is_dirty` 据此判定目标是否需要重建：当前指纹缺失（无从判断）或与基线
/// 不一致（mtime 或内容哈希变化）即为「脏」；当前与基线一致则为「干净」，
/// 从而支撑「输入未变 → 零重建」的增量空操作（Requirement 6.6）。
pub struct BuildCache {
  // 基线指纹：上次成功构建时记录的输入修改时间（按目标名索引）。
  recorded_mtimes : Map[String, Int64]
  // 基线指纹：上次成功构建时记录的输入内容哈希（按目标名索引）。
  recorded_hashes : Map[String, String]
  // 当前指纹：本次构建前观测到的输入修改时间（按目标名索引）。
  current_mtimes : Map[String, Int64]
  // 当前指纹：本次构建前观测到的输入内容哈希（按目标名索引）。
  current_hashes : Map[String, String]
}

///|
/// 构造空构建缓存（无任何基线或当前指纹）。
pub fn BuildCache::new() -> BuildCache {
  {
    recorded_mtimes: Map([]),
    recorded_hashes: Map([]),
    current_mtimes: Map([]),
    current_hashes: Map([]),
  }
}

///|
/// 记录目标的「当前观测指纹」（mtime + 内容哈希）。
///
/// 真实构建中由扫描输入文件系统得到；骨架阶段供调用方与测试注入，作为脏
/// 检查比对的当前一侧。
pub fn BuildCache::observe(
  self : BuildCache,
  name : String,
  mtime : Int64,
  hash : String,
) -> Unit {
  self.current_mtimes[name] = mtime
  self.current_hashes[name] = hash
}

///|
/// 将目标的「当前观测指纹」固化为「基线指纹」，表示该目标已成功构建。
///
/// 构建成功后调用：把当前 mtime/哈希复制到基线。此后若输入未变（当前 ==
/// 基线），`is_dirty` 返回 `false`，再次构建对该目标零重建（增量空操作）。
pub fn BuildCache::mark_built(self : BuildCache, name : String) -> Unit {
  match self.current_mtimes.get(name) {
    Some(m) => self.recorded_mtimes[name] = m
    None => ()
  }
  match self.current_hashes.get(name) {
    Some(h) => self.recorded_hashes[name] = h
    None => ()
  }
}

///|
/// 构建规则解析错误（parse error）。
///
/// 携带人类可读的错误信息 `message` 与出错行号 `line`（1 起始），供
/// `parse_rules` 在规则文件非法时向调用方报告稳定定位。任务 9.2 的完整
/// 规则解析将填充具体的语法诊断。
pub struct ParseError {
  message : String
  line : Int
} derive(Eq)

///|
/// 由错误信息与行号构造解析错误。
pub fn ParseError::new(message : String, line : Int) -> ParseError {
  { message, line }
}

///|
/// 环检测结果（cycle）—— 构建图中构成依赖环的目标序列。
///
/// 对应 design.md 中 `topo_order` 的错误分量 `Cycle`：当构建图存在依赖环
/// 时，拓扑排序失败并返回参与环的目标序列。任务 9.2 将复用
/// `@directed.condensation` / `tarjan_scc` 填充具体的环节点序列。
pub struct Cycle {
  nodes : Array[Target]
}

///|
/// 由参与环的目标序列构造环检测结果。
pub fn Cycle::new(nodes : Array[Target]) -> Cycle {
  { nodes, }
}
