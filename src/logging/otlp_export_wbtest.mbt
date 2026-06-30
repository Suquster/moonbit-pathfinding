// otlp_export_wbtest.mbt —— 方向七 T7.1 私有枚举映射器的白盒回归。
//
// `otlp_status_code` 的 `Unset => 0` 分支在公开导出路径上不可达（`otlp_span`
// 仅在 status ≠ Unset 时才写 status 字段），故用白盒测试直接断言三种状态码与
// 五种 SpanKind 码的映射，锁定与 OTel proto 枚举一致。

///|
test "T7.1 (wb): otlp_status_code maps every SpanStatus to its OTel code" {
  assert_eq(otlp_status_code(Unset), 0)
  assert_eq(otlp_status_code(Ok), 1)
  assert_eq(otlp_status_code(Error), 2)
}

///|
test "T7.1 (wb): otlp_kind_code maps every SpanKind to its OTel code" {
  assert_eq(otlp_kind_code(Internal), 1)
  assert_eq(otlp_kind_code(Server), 2)
  assert_eq(otlp_kind_code(Client), 3)
  assert_eq(otlp_kind_code(Producer), 4)
  assert_eq(otlp_kind_code(Consumer), 5)
}
