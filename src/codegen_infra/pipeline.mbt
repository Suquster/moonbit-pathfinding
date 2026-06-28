// pipeline.mbt —— pass 框架（不动点驱动），旗舰深化旁路新增。
//
// 设计落点（design.md §4.7，R10）：`Pass` 枚举冻结（`ConstFold`/`DeadCodeElim`/
// `CopyProp`），故新优化遍（SCCP/GVN）经新增 `OptPass` 枚举 + 新驱动
// `run_pipeline`/`run_to_fixpoint` 旁路提供；既有 `run_passes(SsaProgram,
// Array[Pass])` 行为完全冻结，旗舰驱动为其旁路超集。
//   * `run_pipeline`：按声明顺序施加一遍（R10.1）；
//   * `run_to_fixpoint`：反复施加直到一轮内不变或达安全上界（R10.2）；
//   * 每个 pass 后保持 SSA 单赋值不变量（R10.3/10.5，见 prop_pipeline_wbtest.mbt）。

///|
/// 旗舰优化遍枚举。既有三遍委托冻结的 `run_passes`，`Sccp`/`Gvn` 委托新增实现。
pub(all) enum OptPass {
  ConstFold
  DeadCodeElim
  CopyProp
  Sccp
  Gvn
} derive(Eq, Debug)

///|
/// 按声明顺序对程序施加一遍各 `OptPass`。
///
/// `ConstFold`/`DeadCodeElim`/`CopyProp` 委托既有 `run_passes`（行为冻结），
/// `Sccp`/`Gvn` 委托 §4.5/§4.6 的新增实现。
pub fn run_pipeline(p : SsaProgram, passes : Array[OptPass]) -> SsaProgram {
  let mut cur = p
  for pass in passes {
    cur = match pass {
      ConstFold => run_passes(cur, [Pass::ConstFold])
      DeadCodeElim => run_passes(cur, [Pass::DeadCodeElim])
      CopyProp => run_passes(cur, [Pass::CopyProp])
      Sccp => sccp(cur)
      Gvn => gvn(cur)
    }
  }
  cur
}

///|
/// 反复施加 `passes` 直到程序在一轮内不再变化（收敛）或达安全上界 `max_iters`。
pub fn run_to_fixpoint(
  p : SsaProgram,
  passes : Array[OptPass],
  max_iters? : Int = 64,
) -> SsaProgram {
  let mut cur = p
  let mut sig = program_signature(cur)
  let mut i = 0
  while i < max_iters {
    let next = run_pipeline(cur, passes)
    let nsig = program_signature(next)
    if nsig == sig {
      return next
    }
    cur = next
    sig = nsig
    i = i + 1
  }
  cur
}
