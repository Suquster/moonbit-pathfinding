# E2 · 零拷贝惰性字段视图 vs eager 全量解码 — native

- 日期：2026-07-05 · 后端：native · 命令：`moon bench -p benches/infra_codec_bench --target native`
- 实现：`src/infra_codec/lazy_view.mbt`——对标 protobuf lazy parsing /
  flatbuffers 按需访问：消息保持编码态缓冲，字段访问=键扫描（LEN 字段按
  长度前缀 O(1) 跳过）+ 定点解码，不物化未访问字段；嵌套消息返回同一
  缓冲上的零拷贝子视图（[start, end) 窗口）逐层惰性。畸形/截断一律
  None 不 panic。

## 稀疏访问（2000 条消息 × 32 字段，其中 30 个 48 字符字符串；只取 2 个 varint 键）

| 负载 | 惰性视图 | eager 单趟顺序全量解码（字符串全物化） | 倍率 |
|---|---|---|---|
| 2000×32 | 242.96 µs ± 9.55 µs | 39.65 ms ± 952.46 µs | **163×** |

- eager 基线为公平的单趟顺序解码器（每字段只扫一次，`ByteReader::
  read_string_payload` 物化字符串）；差距来源=跳过 30 个字符串的解码与
  物化（RPC 网关取路由键、日志管道取时间戳等典型稀疏访问负载）。

## 验证

- 三后端（native / wasm-gc / js）全绿、`moon check` 0 告警。
- 差分 PBT：随机消息（1..12 字段、四种 wire type 混合、多语种字符串）
  惰性乱序访问 vs eager 参照逐字段等价 200 迭代；全 wire type round-trip、
  嵌套零拷贝子视图、每个截断前缀 + 纯续传位垃圾安全性定向锁定。
