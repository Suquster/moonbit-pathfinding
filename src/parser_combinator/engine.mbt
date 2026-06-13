// engine.mbt —— L1 运行期引擎层地基（Grammar / PCtx / Outcome / lift / 运行入口）。
//
// 对应 tasks.md 任务 6.1，落地 design.md §「组件与接口 → 5. 运行期引擎层」。
// 本层承载「需要 per-run 可变运行期上下文」的能力（提交/恢复 R7、packrat R8、
// 左递归 R9、流式 R10）的公共地基：把任意 L0 `Parser[T]` 经 `lift` 提升为
// 不透明富解析器 `Grammar[T]`，并提供两种运行入口 `run_naive`（不记忆化，朴素
// 参照）与 `run_packrat`（记忆化）。
//
// 封装策略（design.md）：`PCtx` / `Outcome` 为包内私有（priv），`Grammar[T]`
// 公开但其字段私有（对外不透明），从而把运行期上下文细节封装在引擎内部，
// 不泄漏进公开 `ParseResult`（保持冻结契约，R14.1）。

/// 封装策略（design.md）：`PCtx` / `Outcome` 为**导出但抽象**（`pub`，类型名
/// 对外可见而内部表示对外不可构造/解构），`Grammar[T]` 公开但其字段私有
/// （对外不透明），从而把运行期上下文细节封装在引擎内部，不泄漏进公开
/// `ParseResult`（保持冻结契约，R14.1）。

///|
/// per-run 运行期上下文（per-run context）。
///
/// 随单次解析运行而新建、随其结束而丢弃：
///   * `run_id` —— 本次运行的唯一标识；packrat / 左递归的 per-node 缓存以它判定
///     是否属于本次运行，从而把缓存生命周期限定于单次运行（R8.5 缓存隔离）。
///   * `enable_memo` —— 由运行入口决定（`run_packrat` 为 `true`，`run_naive` 为
///     `false`），控制 `memoize` 是否实际缓存（R8.4 入口选择）。
pub struct PCtx {
  run_id : Int
  enable_memo : Bool
}

///|
/// 内部解析结果（engine outcome）。
///
/// 在公开 `ParseResult` 基础上额外携带「是否已提交」（committed）标志，供
/// `commit` / `choice` 实现软/硬失败分离（R7）。该标志只在引擎内部流转，运行
/// 入口投影回 `ParseResult` 时丢弃，故不泄漏到冻结契约。
///   * `OOk(value, rest)` —— 成功，携带产出值与剩余输入；
///   * `OFail(pos, expected, committed)` —— 失败，携带失败位置、期望集合与提交标志。
pub enum Outcome[T] {
  OOk(T, Input)
  OFail(Pos, Array[String], Bool)
}

///|
/// 不透明富解析器（opaque rich parser）。
///
/// 以**抽象 newtype**承载「(运行期上下文, 输入) → 内部结果」函数：`pub type` 使
/// 类型名对外可见但其内部表示（含私有的 `PCtx` / `Outcome`）对外不透明——
/// 调用方只能经 `lift` 构造、经 `run_naive` / `run_packrat` 运行，无法窥探或
/// 依赖其内部上下文结构（满足 design.md「Grammar 对外不透明」且保持 `PCtx` /
/// `Outcome` 包内私有）。
pub struct Grammar[T] {
  run_ctx : (PCtx, Input) -> Outcome[T]
}

///|
/// 由「(上下文, 输入) → 内部结果」函数构造 `Grammar`（包内私有构造器）。
fn[T] Grammar::new(run_ctx : (PCtx, Input) -> Outcome[T]) -> Grammar[T] {
  { run_ctx, }
}

///|
/// 在给定上下文与输入上运行富解析器（包内调用便捷封装）。
fn[T] pc_run(g : Grammar[T], ctx : PCtx, input : Input) -> Outcome[T] {
  (g.run_ctx)(ctx, input)
}

///|
/// run_id 全局自增计数器（构造期/运行期共享的进程内单调计数）。
///
/// 以数组单元格承载「包级可变状态」；仅用于为每次运行分配唯一 `run_id`，
/// 其绝对值不影响解析结果（packrat 差分一致性是兜底）。
let pc_run_id_counter : Array[Int] = [0]

///|
/// 新建一个 per-run 上下文，分配唯一 `run_id`。
fn pc_new_ctx(enable_memo : Bool) -> PCtx {
  pc_run_id_counter[0] = pc_run_id_counter[0] + 1
  { run_id: pc_run_id_counter[0], enable_memo }
}

///|
/// 把内部 `Outcome` 投影回公开 `ParseResult`（丢弃 committed 标志，归一期望）。
fn[T] pc_project(o : Outcome[T]) -> ParseResult[T] {
  match o {
    OOk(v, rest) => ParseResult::Ok(v, rest)
    OFail(pos, exp, _) =>
      ParseResult::Fail(pos, expected=normalize_expected(exp))
  }
}

///|
/// `lift`：把任意 L0 解析器 `Parser[T]` 提升进引擎层 `Grammar[T]`。
///
/// 提升后即可叠加 `commit` / `memoize` / `left_recursive` / `run_incremental`
/// 等运行期能力（R14.5 以新增 API 提供扩展能力）。成功 → `OOk`；失败 → 软失败
/// `OFail(..., committed=false)`（提交标志默认未提交）。
pub fn[T] lift(p : Parser[T]) -> Grammar[T] {
  Grammar::new(fn(_ctx, input) {
    match p.parse(input) {
      Ok(v, rest) => OOk(v, rest)
      Fail(pos, expected~) => OFail(pos, expected, false)
    }
  })
}

///|
/// 引擎层 `pure`：不消费输入、恒成功、携带给定值。
pub fn[T] Grammar::pure(value : T) -> Grammar[T] {
  Grammar::new(fn(_ctx, input) { OOk(value, input) })
}

///|
/// 引擎层 `map`：对成功产出值施加 `f`，失败原样透传（含 committed 标志）。
pub fn[A, B] Grammar::map(self : Grammar[A], f : (A) -> B) -> Grammar[B] {
  Grammar::new(fn(ctx, input) {
    match pc_run(self, ctx, input) {
      OOk(v, rest) => OOk(f(v), rest)
      OFail(p, e, c) => OFail(p, e, c)
    }
  })
}

///|
/// 引擎层 `bind`：成功后在剩余输入上运行 `f(v)` 返回的富解析器；失败原样透传
/// （含 committed 标志，从而提交点之后的依赖式串联保持硬失败语义）。
pub fn[A, B] Grammar::bind(
  self : Grammar[A],
  f : (A) -> Grammar[B],
) -> Grammar[B] {
  Grammar::new(fn(ctx, input) {
    match pc_run(self, ctx, input) {
      OOk(v, rest) => pc_run(f(v), ctx, rest)
      OFail(p, e, c) => OFail(p, e, c)
    }
  })
}

///|
/// 运行入口（朴素参照）：新建**不启用记忆化**的上下文并运行，投影回 `ParseResult`。
///
/// 作为 packrat 的差分参照（Property 23）：与 `run_packrat` 对同一文法、同一
/// 输入应产生逐字段一致的结果。
pub fn[T] Grammar::run_naive(
  self : Grammar[T],
  input : Input,
) -> ParseResult[T] {
  pc_project(pc_run(self, pc_new_ctx(false), input))
}

///|
/// 运行入口（记忆化）：新建**启用记忆化**的上下文并运行，投影回 `ParseResult`。
///
/// 调用方无需改动文法定义即可在 `run_packrat` / `run_naive` 间切换（R8.4）。
pub fn[T] Grammar::run_packrat(
  self : Grammar[T],
  input : Input,
) -> ParseResult[T] {
  pc_project(pc_run(self, pc_new_ctx(true), input))
}

///|
/// 便捷入口：直接在字符串上以记忆化运行（内部构造 `Input`）。
pub fn[T] Grammar::run_packrat_string(
  self : Grammar[T],
  source : String,
) -> ParseResult[T] {
  self.run_packrat(Input::from_string(source))
}

///|
/// 便捷入口：直接在字符串上以朴素方式运行（内部构造 `Input`）。
pub fn[T] Grammar::run_naive_string(
  self : Grammar[T],
  source : String,
) -> ParseResult[T] {
  self.run_naive(Input::from_string(source))
}
