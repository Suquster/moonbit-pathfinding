# T7.1 / T7.2 / T7.3 —— 真·OTLP 导出器 + OTel 语义对齐 + 采样器对标验证证据

日期：2026-07-05 · 工具链：moon 0.1.20260629 · 外部验证：官方 opentelemetry-proto（Python 绑定）

## 交付物

| 组件 | 文件 | 说明 |
| --- | --- | --- |
| OTLP 导出器 | `src/logging/otlp_export.mbt` | `otlp_export_traces`（protobuf 字节）/ `otlp_export_traces_json`（OTLP/JSON），把本包 `SpanData` 序列化为 `opentelemetry.proto.trace.v1.TracesData`，**复用方向九 @serialization 的模式驱动编码**（parse_proto_full + encode_typed / encode_json） |
| 线缆模式 | `otlp_trace_proto()` | opentelemetry-proto v1 trace.proto 子集，字段号逐一对齐官方定义（Span 1/2/4/5/6/7/8/9/11/15，AnyValue oneof 1–6，fixed64 时间戳） |
| 回归测试 | `src/logging/otlp_export_test.mbt` | 黄金字节快照（外部验证锚点）+ 无损解回 + traceparent 逐字节一致 + OTLP/JSON 字段对齐 + 100 迭代确定性/全函数 PBT |

## 外部验证（关键证据）

导出字节经**官方 opentelemetry-proto Python 绑定**（真实 collector 使用的同一 proto 定义）
`TracesData.ParseFromString` 解码，**全部字段逐一相等**：

- `resource.attributes["service.name"] == "pathfinding-demo"`
- `scope.name == "logging"`, `scope.version == "0.2.0"`
- `trace_id == 00000000000000001122334455667788`（与 W3C traceparent hex 逐字节一致）
- `span_id == 000000000000002a`, `parent_span_id == 0000000000000007`
- `name == "handle_request"`, `kind == SPAN_KIND_SERVER`
- `start/end_time_unix_nano == 1000/2500`（fixed64）
- 属性 `http.method=GET`、事件 `retry@1500{attempt:2}`、`status.code == STATUS_CODE_OK`

即：该字节流可直接 POST 到真实 OTel collector 的 `/v1/traces`
（`Content-Type: application/x-protobuf`）。

## 语义映射（逐字段对齐，T7.2 的地基）

| 本包 | OTLP |
| --- | --- |
| `SpanKind{Internal..Consumer}` | `SPAN_KIND_INTERNAL(1)..CONSUMER(5)` |
| `SpanStatus{Unset/Ok/Error}` | `STATUS_CODE_UNSET(0)/OK(1)/ERROR(2)` |
| `Value` 六构造（VStr/VInt/VBool/VFloat/VList/VMap） | `AnyValue` oneof（string/int/bool/double/array/kvlist，含递归嵌套） |
| `TraceId`/`SpanId`（Int64） | 16B/8B 大端字节，高位补零——与 traceparent hex 同一位序 |

## T7.2 —— OTel 数据模型逐字段对齐补全

- **links**：`SpanData::add_link(trace, span, attributes)` → OTLP `Span.links`
  （字段 13，`Link{trace_id=1, span_id=2, attributes=4}`）；
- **status.message**：`SpanData::set_status_with_message(status, message)` →
  OTLP `Status.message`（字段 2）。

第二组黄金字节（含 link + Error status "boom"）同样经官方 opentelemetry-proto
解码逐字段相等：`links[0].trace_id == ...abcd`、`links[0].span_id == ...1234`、
link 属性 `src=q`、`status == {code: ERROR, message: "boom"}`。

## T7.3 —— OTel 采样器对标（samplers.mbt）

对标 OTel SDK 规范四种内置采样器：`AlwaysOn` / `AlwaysOff` /
`TraceIdRatio(rate)`（复用 sampling.mbt 纯整型混合，trace-coherent、三后端
逐位一致）/ `ParentBased(root)`（父决策优先，根 span 委托 root，支持嵌套下钻）。
限流采样已有 `RateLimiter`（sampling.mbt，逻辑时间窗）。

验证（src/logging/samplers_test.mbt）：
- 边界：AlwaysOn/AlwaysOff 恒定；ParentBased 父采则采、父弃则弃、根委托；
- 确定性：同 trace/seed 判定恒定，父决策不影响 TraceIdRatio；
- 分布 PBT：rate ∈ {0.1, 0.25, 0.5, 0.9} 各 10_000 条随机 trace，
  命中率与 rate 偏差 < 2%；
- 单调性：同 seed 下 rate 越大保留集只增不减（阈值比较单调性，
  OTel TraceIdRatioBased 可组合性基石）。

## 复现

```bash
moon test -p src/logging          # 黄金 + 契约 + PBT
python3 - <<'EOF'                 # 外部解码（需 pip install opentelemetry-proto）
from opentelemetry.proto.trace.v1 import trace_pb2
# 粘贴 otlp_export_test.mbt 中的黄金 hex 后 ParseFromString 即可逐字段核对
EOF
```
