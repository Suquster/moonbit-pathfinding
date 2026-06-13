// zigzag.mbt —— zigzag 编解码与定长位级 reinterpret 辅助（旗舰深化，旁路新增）。
//
// 设计依据（design.md §4.3「zigzag 与定长位级辅助」，R1.2 / R1.4）与
// paper-to-code 可追溯（design.md §「算法说明」）：
//
//   * zigzag（sint32 / sint64）—— Protocol Buffers 编码规范定义的有符号→无符号
//     映射：`(n << 1) ^ (n >> k)`（k = 31 / 63，算术右移实现符号位扩散）。把小
//     幅负值映射为短 varint（`-1→1`、`1→2`），避免负数恒占 10 字节。
//   * 定长位级 reinterpret（IEEE-754）—— `double`/`float` 一律经**位级**
//     reinterpret 与 `I64`/`I32` 定长字节互转（而非数值层往返），规避 js 后端
//     "数字底层皆 double" 导致的 `Float` 精度漂移，保证三后端位级一致
//     （design.md §「三后端一致性」）。
//
// 严格旁路扩展：本文件不修改任何既有 `pub`/`pub(all)` 声明；既有 `types.mbt`/
// `wire.mbt` 的形态与运行时行为保持冻结。

///|
/// zigzag 编码 32 位有符号整数为无符号：`(n << 1) ^ (n >> 31)`。
///
/// 以算术右移 `asr(31)` 得到全 0（非负）或全 1（负）的符号掩码，与左移一位的
/// 结果异或，从而把符号位折叠到最低位。`-1 → 1`、`1 → 2`、`0 → 0`。
pub fn zigzag_encode_32(n : Int) -> UInt {
  (n.shl(1) ^ n.asr(31)).reinterpret_as_uint()
}

///|
/// zigzag 解码：上述映射的逆 `(u >>> 1) ^ -(u & 1)`（逻辑右移 + 最低位符号还原）。
pub fn zigzag_decode_32(u : UInt) -> Int {
  let n = u.reinterpret_as_int()
  n.lsr(1) ^ -(n & 1)
}

///|
/// zigzag 编码 64 位有符号整数为无符号：`(n << 1) ^ (n >> 63)`。
pub fn zigzag_encode_64(n : Int64) -> UInt64 {
  (n.shl(1) ^ n.asr(63)).reinterpret_as_uint64()
}

///|
/// zigzag 解码 64 位：`(u >>> 1) ^ -(u & 1)`。
pub fn zigzag_decode_64(u : UInt64) -> Int64 {
  let n = u.reinterpret_as_int64()
  n.lsr(1) ^ -(n & 1L)
}

///|
/// 把 `Double` 重解释为其 IEEE-754 64 位比特（供 `I64` 定长编码）。
pub fn double_to_bits(d : Double) -> UInt64 {
  d.reinterpret_as_uint64()
}

///|
/// 由 IEEE-754 64 位比特还原 `Double`（供 `I64` 定长解码）。
pub fn bits_to_double(u : UInt64) -> Double {
  u.reinterpret_as_double()
}

///|
/// 把 `Float` 重解释为其 IEEE-754 32 位比特（供 `I32` 定长编码）。
pub fn float_to_bits(f : Float) -> UInt {
  f.reinterpret_as_uint()
}

///|
/// 由 IEEE-754 32 位比特还原 `Float`（供 `I32` 定长解码）。
pub fn bits_to_float(u : UInt) -> Float {
  Float::reinterpret_from_uint(u)
}
