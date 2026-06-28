// value_ext.mbt —— 嵌套结构化取值（`VMap` / `VList`）的助手（任务 1.2）。
//
// 设计依据：design.md §4.1「嵌套结构化取值与嵌套 JSON 往返」（Requirement 1.2）。
// 本文件为 types.mbt 中加性扩展的嵌套取值变体提供纯函数判定与度量助手，
// 不引入任何运行时副作用，三后端（wasm-gc / js / native）行为逐位一致：
//
//   * `Value::is_scalar` —— 标量取值（VStr/VInt/VBool/VFloat）判定为 true；
//   * `Value::is_nested` —— 嵌套取值（VMap/VList）判定为 true（is_scalar 的补）；
//   * `Value::depth`     —— 取值的嵌套深度：标量为 0，嵌套为 1 + max(子取值 depth)。
//
// 这些助手支撑「带深度上界的嵌套取值生成器」（属性测试 Property 1）与脱敏
// 「嵌套整体掩码」（Requirement 7.4）等场景对结构形态的判定。

///|
/// 判断取值是否为标量（`VStr` / `VInt` / `VBool` / `VFloat`）。
///
/// 标量取值不含子取值，深度恒为 0（见 `depth`）。
pub fn Value::is_scalar(self : Value) -> Bool {
  match self {
    VStr(_) | VInt(_) | VBool(_) | VFloat(_) => true
    VMap(_) | VList(_) => false
  }
}

///|
/// 判断取值是否为嵌套复合取值（`VMap` / `VList`）。`is_scalar` 的逻辑补。
pub fn Value::is_nested(self : Value) -> Bool {
  !self.is_scalar()
}

///|
/// 计算取值的嵌套深度（nesting depth）。
///
/// 定义（Requirement 1.2）：
///   * 标量取值深度为 0；
///   * 嵌套取值（`VMap` / `VList`）深度为 `1 + max(子取值深度)`；
///   * 空 `VMap` / 空 `VList` 无子取值，深度为 `1 + 0 = 1`。
///
/// 该度量与编解码递归层数一致，可用于约束生成器产出的最大嵌套层级。
pub fn Value::depth(self : Value) -> Int {
  match self {
    VStr(_) | VInt(_) | VBool(_) | VFloat(_) => 0
    VMap(m) => {
      let mut maxc = 0
      m.each(fn(_k, v) {
        let d = v.depth()
        if d > maxc {
          maxc = d
        }
      })
      1 + maxc
    }
    VList(xs) => {
      let mut maxc = 0
      for v in xs {
        let d = v.depth()
        if d > maxc {
          maxc = d
        }
      }
      1 + maxc
    }
  }
}
