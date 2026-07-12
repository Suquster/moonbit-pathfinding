// gaps90_test.mbt —— INI 空键拒绝余臂（第九十批）。

///|
/// ini_parse：键为空（"=value" 行）→ 整体解析拒绝。
test "ini_parse：空键行拒绝" {
  assert_true(ini_parse("[s]\n=value\n") is None)
}
