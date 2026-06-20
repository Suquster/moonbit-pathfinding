// actor_bench_backend_wasm.mbt —— wasm / wasm-gc 后端标识（按 moon.pkg
// `options(targets:)` 仅在 wasm / wasm-gc 后端编译）。

///|
/// 当前编译后端标识（用于基准工件的「后端目标」字段，Requirement 12.2）。
fn bench_backend_target() -> String {
  "wasm-gc"
}
