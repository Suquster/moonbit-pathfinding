// incremental_ext_gaps_wbtest.mbt —— 恢复策略 Show 输出收口
// （INFRA 第四十二批）。

///|
test "RecoveryStrategy：SyncTo Show 多标记逗号分隔输出" {
  let s : RecoveryStrategy = SyncTo([';', ')'])
  assert_eq("\{s}", "SyncTo([;,)])")
  let s1 : RecoveryStrategy = SyncTo([','])
  assert_eq("\{s1}", "SyncTo([,])")
}
