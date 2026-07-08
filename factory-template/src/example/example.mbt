// example.mbt —— 最小合规实现示例。
//
// 约定示范：每个公开函数都有文档注释；范围外输入显式返回 None
// （诚实边界），不静默吞掉。

///|
/// 非负整数的整数平方根（floor(sqrt(n))）；负数返回 None。
pub fn isqrt(n : Int) -> Int? {
  if n < 0 {
    return None
  }
  let mut x = 0
  while (x + 1) * (x + 1) <= n {
    x = x + 1
  }
  Some(x)
}
