// gaps82_test.mbt —— lz4/zstd 深层腐蚀路径收口（第八十二批）。

///|
/// lz4：字面量段后仅剩 1 字节（offset 需 2 字节）→ 截断拒绝。
test "lz4：offset 截断被拒绝" {
  // token 0x10：lit_len=1、match 低半字节 0；'A' 之后仅剩 1 字节。
  assert_true(@infra_compress.lz4_decompress([0x10, 0x41, 0x99], 100) is None)
}

///|
/// zstd 字典帧：校验和被篡改 → 内容校验失败拒绝。
test "zstd 字典帧：校验和篡改被拒绝" {
  let dict = zsd_raw_dict()
  let data = zsd_text(200)
  match @infra_compress.zstd_compress_with_dict(data, dict, true) {
    Some(frame) => {
      // 末 4 字节为 xxhash64 低 32 位校验和：翻转最后一字节。
      let bad = frame.copy()
      bad[bad.length() - 1] = bad[bad.length() - 1] ^ 0xFF
      assert_true(
        @infra_compress.zstd_decompress_with_dict(bad, dict, 1 << 20) is None,
      )
      // 截断校验和字段 → 读取失败拒绝。
      let cut : Array[Int] = []
      for k in 0..<(frame.length() - 1) {
        cut.push(frame[k])
      }
      assert_true(
        @infra_compress.zstd_decompress_with_dict(cut, dict, 1 << 20) is None,
      )
    }
    None => fail("字典压缩不应失败")
  }
}
