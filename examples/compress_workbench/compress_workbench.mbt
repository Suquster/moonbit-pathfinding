// examples/compress_workbench — runnable demonstration of the
// `src/infra_compress` direction as a log-shipping workflow: compress a
// repetitive log payload with DEFLATE / zlib / gzip / zstd / LZ4, compare
// ratios, verify lossless round-trips, exploit shared dictionaries for
// small payloads, and reject corrupted archives.
//
// Run with:
//   moon run examples/compress_workbench

///|
fn build_log_payload() -> Array[Int] {
  let sb = StringBuilder::new()
  for i in 0..<40 {
    sb.write_string(
      "2026-07-12T18:0\{i % 10}:00Z INFO request handled path=/api/v1/route status=200\n",
    )
  }
  @codec.utf8_bytes_of_string(sb.to_string())
}

///|
fn ratio_permille(compressed : Int, original : Int) -> Int {
  compressed * 1000 / original
}

///|
fn main {
  let data = build_log_payload()
  let n = data.length()
  println("=== 1. codec shoot-out on a \{n}-byte log payload ===")
  let df = @compress.deflate(data)
  let zl = @compress.zlib_compress(data)
  let gz = @compress.gzip_compress(data)
  let zs = @compress.zstd_compress_entropy(data, true)
  let lz = @compress.lz4_compress(data)
  println(
    "deflate: \{df.length()} bytes (\{ratio_permille(df.length(), n)}‰)",
  )
  println(
    "zlib   : \{zl.length()} bytes (\{ratio_permille(zl.length(), n)}‰)",
  )
  println(
    "gzip   : \{gz.length()} bytes (\{ratio_permille(gz.length(), n)}‰)",
  )
  println(
    "zstd   : \{zs.length()} bytes (\{ratio_permille(zs.length(), n)}‰)",
  )
  println(
    "lz4    : \{lz.length()} bytes (\{ratio_permille(lz.length(), n)}‰)",
  )
  println("")
  println("=== 2. lossless round-trips ===")
  println("inflate(deflate)  == input: \{@compress.inflate(df) == Some(data)}")
  println(
    "zlib_decompress   == input: \{@compress.zlib_decompress(zl) == Some(data)}",
  )
  println(
    "gzip_decompress   == input: \{@compress.gzip_decompress(gz) == Some(data)}",
  )
  println(
    "zstd_decompress   == input: \{@compress.zstd_decompress(zs, n) == Some(data)}",
  )
  println(
    "lz4_decompress    == input: \{@compress.lz4_decompress(lz, n) == Some(data)}",
  )
  let frame = @compress.lz4_frame_compress(data)
  println(
    "lz4 frame decode  == input: \{@compress.lz4_frame_decompress(frame, n) == Some(data)}",
  )
  println("")
  println("=== 3. dictionary compression for small payloads ===")
  let dict = @codec.utf8_bytes_of_string(
    "INFO request handled path=/api/v1/route status=200",
  )
  let small = @codec.utf8_bytes_of_string(
    "INFO request handled path=/api/v1/route status=200 rt=3ms",
  )
  let plain = @compress.zlib_compress(small)
  let with_dict = @compress.zlib_compress_with_dict(small, dict)
  println("zlib plain    : \{plain.length()} bytes")
  println("zlib with dict: \{with_dict.length()} bytes")
  println(
    "dict round-trip ok: \{@compress.zlib_decompress_with_dict(with_dict, dict) == Some(small)}",
  )
  println("")
  println("=== 4. corrupted archives are rejected, not mis-decoded ===")
  let bad = gz.copy()
  bad[bad.length() - 1] = (bad[bad.length() - 1] + 1) % 256
  let bad_verdict = match @compress.gzip_decompress(bad) {
    Some(_) => "accepted (unexpected)"
    None => "rejected"
  }
  println("gzip with flipped CRC byte -> \{bad_verdict}")
  let truncated = zl.copy()
  let _ = truncated.pop()
  let trunc_verdict = match @compress.zlib_decompress(truncated) {
    Some(_) => "accepted (unexpected)"
    None => "rejected"
  }
  println("zlib truncated by 1 byte   -> \{trunc_verdict}")
}
