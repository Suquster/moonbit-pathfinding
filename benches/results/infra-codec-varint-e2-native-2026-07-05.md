# E2 · varint/zigzag 二进制编解码基准（native，2026-07-05）

- 实现：`src/infra_codec/codec.mbt`——protobuf wire format 同构子集：
  varint（LEB128 低 7 位载荷 + 续传位，UInt64 ≤10 字节）、zigzag
  （(n<<1)^(n>>63) 折叠，小绝对值负数编码短，protobuf sint64 语义）、
  定长小端 fixed32/fixed64、length-prefixed bytes/string；解码器对
  截断/超长 varint/长度越界等畸形输入一律返回 None 不 panic。
- 环境：moon 0.1.20260629，native release，`moon bench -p benches/infra_codec_bench`。
- 负载：n 个确定性 xorshift 随机 Int64（混合正负与位跨度）完整
  round-trip；朴素侧 to_string 逗号拼接 + 逐字符解析回 Int64。

| n | zigzag varint round-trip | 朴素字符串 round-trip | 吞吐倍率 |
|---|---|---|---|
| 2000 | 72.43 µs ± 1.05 | 161.59 µs ± 2.58 | 2.2× |
| 8000 | 324.87 µs ± 1.12 | 668.69 µs ± 1.94 | 2.1× |
| 32000 | 1.34 ms ± 5.57µs | 2.81 ms ± 26.35µs | 2.1× |

- 体积（n=32000）：二进制 162,855 字节 vs 字符串 364,221 字符
  （UTF-16 内存占用 728,442 字节）——线上传输 2.24×、内存 4.47× 压缩。
- 编解码两侧同为 O(n)，优势为常数级吞吐 + 体积压缩双维度；真实收益在
  网络/磁盘 IO 侧随体积压缩线性放大。

## 正确性证据

`src/infra_codec/codec_test.mbt`：
- 定向：varint 边界值（0/127/128/16383/16384/u32max/u64max）编码字节数
  逐个与 LEB128 规范一致并 round-trip；zigzag 小负数短编码
  （-1→1 字节、-64→1 字节、i64 极值→10 字节）；fixed32/64 小端字节序
  显式断言；混合 bytes/中英文字符串 round-trip。
- 畸形输入安全：截断 varint、11 字节超长 varint、长度前缀越界、定长
  越界一律 None 不 panic。
- **E2 round-trip PBT 200 迭代**：随机混排 varint/zigzag/fixed64/bytes
  字段流，逐值一致 + 流精确耗尽（无多写无漏读）。
- 三后端（native/wasm-gc/js）全绿。
