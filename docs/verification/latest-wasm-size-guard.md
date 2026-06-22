# WASM Size Guard Report

- Generated at: 2026-06-21T15:37:32Z
- Script: scripts/wasm_size_guard.ps1
- MoonBit: moon 0.1.20260608 (60bc8c3 2026-06-08)  Feature flags enabled: rr_moon_mod,rr_moon_pkg
- Package: src/playground
- Artifact: _build/wasm-gc/release/build/src/playground/playground.wasm
- Locate method: options(link:) 链接产物 <build-root>/src/playground/playground.wasm
- Measured size: 12407 字节（12.1 KB，占上限 12.1%）
- Limit: 102400 字节（100 KB）
- Margin: 89993 字节
- SHA-256: 009ed784bd87e897fbb1374de2e6df95435d20a9115c68289b3d6a2d5001e78c
- Determinism (R1.5): True（两次构建字节数/SHA-256 一致性校验）
- Status: PASSED

