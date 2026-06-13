// demo.mbt —— 旗舰端到端实战示例（旗舰深化，旁路新增）。
//
// design.md §4.8 / R10：一份贯穿文档与基准的实战构建规则集——多模块 C / MoonBit
// 工程依赖图，覆盖源文件 → 目标文件 → 库 → 顶层可执行产物的依赖层级。
// `README.mbt.md` 与基准复用同一规则集，演示 `parse_rules` → `detect_cycle`
// （无环）→ `schedule`（拓扑 + 批内独立）→ 单源变更下 `minimal_rebuild_set`
// （仅含该源下游、相对全量目标数缩减）的端到端流程。
//
// 工程结构（边 `(dep, target)`：dep 必须在 target 之前）：
//   app          ← libcore.a, libutil.a
//   libcore.a    ← core_a.o, core_b.o
//   libutil.a    ← util_a.o
//   core_a.o     ← core_a.c, common.h
//   core_b.o     ← core_b.c, common.h
//   util_a.o     ← util_a.c, common.h

///|
/// 多模块 C / MoonBit 工程的实战构建规则集（R10.1）。
pub fn demo_rules() -> String {
  "# 顶层可执行产物\n" +
  "app: libcore.a libutil.a\n" +
  "# 静态库\n" +
  "libcore.a: core_a.o core_b.o\n" +
  "libutil.a: util_a.o\n" +
  "# 目标文件（各依赖对应源与共享头）\n" +
  "core_a.o: core_a.c common.h\n" +
  "core_b.o: core_b.c common.h\n" +
  "util_a.o: util_a.c common.h\n"
}

///|
/// `demo_rules` 经 `parse_rules` 的期望产物（节点集合 + 依赖边集合，供文档与
/// 测试断言）。节点按首次出现去重保序，边为全部 `(dep, target)`。
pub fn demo_graph() -> BuildGraph {
  let app = Target::new("app")
  let libcore = Target::new("libcore.a")
  let libutil = Target::new("libutil.a")
  let core_a_o = Target::new("core_a.o")
  let core_b_o = Target::new("core_b.o")
  let util_a_o = Target::new("util_a.o")
  let core_a_c = Target::new("core_a.c")
  let common_h = Target::new("common.h")
  let core_b_c = Target::new("core_b.c")
  let util_a_c = Target::new("util_a.c")
  let nodes = [
    app, libcore, libutil, core_a_o, core_b_o, util_a_o, core_a_c, common_h, core_b_c,
    util_a_c,
  ]
  let edges = [
    (libcore, app),
    (libutil, app),
    (core_a_o, libcore),
    (core_b_o, libcore),
    (util_a_o, libutil),
    (core_a_c, core_a_o),
    (common_h, core_a_o),
    (core_b_c, core_b_o),
    (common_h, core_b_o),
    (util_a_c, util_a_o),
    (common_h, util_a_o),
  ]
  BuildGraph::new(nodes, edges)
}
