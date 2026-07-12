# INFRA hash / compress native benchmarks — 2026-07-12

- Toolchain: moon 0.1.20260703 (native backend, release)
- Command:
  `export LIBRARY_PATH=/usr/lib64:/usr/lib && moon bench -p benches/infra_hash_bench --target native`
  and `moon bench -p benches/infra_compress_bench --target native`
- Payloads are deterministic (seeded LCG bytes for hashing; repetitive
  structured log text for compression), so runs are reproducible.

## Hashing: crypto digests vs fast non-crypto hashes

`benches/infra_hash_bench` — one-shot digest over the same byte payload.

| name | time (mean ± σ) | range (min … max) |
|---|---|---|
| sha256_1024 | 5.57 µs ± 19.13 ns | 5.54 µs … 5.59 µs |
| sha3_256_1024 | 23.10 µs ± 42.43 ns | 23.06 µs … 23.18 µs |
| blake2b_1024 | 10.29 µs ± 276.23 ns | 9.96 µs … 10.66 µs |
| xxhash64_1024 | 680.25 ns ± 0.24 ns | 679.85 ns … 680.62 ns |
| fnv1a_64_1024 | 996.79 ns ± 0.66 ns | 996.18 ns … 997.87 ns |
| crc32_1024 | 2.04 µs ± 0.90 ns | 2.04 µs … 2.04 µs |
| sha256_16384 | 80.18 µs ± 2.14 µs | 78.86 µs … 84.59 µs |
| sha3_256_16384 | 348.40 µs ± 786.41 ns | 347.68 µs … 350.35 µs |
| blake2b_16384 | 153.84 µs ± 287.37 ns | 153.36 µs … 154.36 µs |
| xxhash64_16384 | 10.63 µs ± 11.89 ns | 10.62 µs … 10.66 µs |
| fnv1a_64_16384 | 16.45 µs ± 23.54 ns | 16.43 µs … 16.50 µs |
| crc32_16384 | 33.46 µs ± 870.00 ns | 32.89 µs … 34.85 µs |

Reading: at 16 KiB, xxHash64 is ~7.5× faster than SHA-256 and ~33× faster
than SHA3-256 — use non-crypto hashes for sharding/dedup keys and crypto
digests only where integrity/authentication matters. The smoke test in the
same package proves streaming (`Sha256Hasher`/`Crc32Hasher`) equals one-shot.

## Compression: compress + decompress round-trip

`benches/infra_compress_bench` — full round-trip (compress then decompress)
on repetitive log text; smoke test asserts all three are lossless.

| name | time (mean ± σ) | range (min … max) |
|---|---|---|
| deflate_roundtrip_4588B | 77.08 µs ± 280.67 ns | 76.74 µs … 77.52 µs |
| zstd_roundtrip_4588B | 168.45 µs ± 208.90 ns | 168.10 µs … 168.80 µs |
| lz4_roundtrip_4588B | 10.83 µs ± 44.70 ns | 10.76 µs … 10.89 µs |
| deflate_roundtrip_36734B | 360.15 µs ± 11.79 µs | 346.09 µs … 373.87 µs |
| zstd_roundtrip_36734B | 323.31 µs ± 1.28 µs | 321.15 µs … 325.01 µs |
| lz4_roundtrip_36734B | 70.53 µs ± 197.55 ns | 70.32 µs … 70.94 µs |

Reading: LZ4 is the speed king (~7× faster round-trip than DEFLATE at 36 KB)
at a lower compression ratio; zstd's entropy path scales better than DEFLATE
as payloads grow (faster at 36 KB despite losing at 4.5 KB). For ratio
numbers on the same class of payload, see `moon run examples/compress_workbench`
(deflate ≈46‰, zstd ≈44‰, lz4 ≈48‰ on a 2 880-byte log payload).
