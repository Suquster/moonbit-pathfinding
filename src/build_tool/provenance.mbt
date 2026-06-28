// provenance.mbt —— 可复现构建与 provenance 溯源（旗舰深化，旁路新增）。
//
// paper-to-code（design.md §4.7）：本方向停留在图与缓存模型层、不执行真实动作，
// 故**可复现性建模为「输出哈希是 (输入哈希集合, 动作指纹) 的确定性单射函数」**
// ——这正是 Bazel / Nix 可复现构建的形式化内核（相同输入与动作必得相同输出）。
//
// `derive_output_hash` 采用**长度前缀单射编码**（与 `cache_key` 同构），使
// 「相同输入与动作恒得相同输出 / 记录」（R9.2 / R9.4）与「任一分量变异记录可
// 区分」（R9.3）成为**构造性定理**而非概率保证（正确性属性 15）。
// `record_provenance` 对 `input_hashes` 规范升序后参与计算，保证记录确定。

///|
/// 一次构建的溯源记录：目标 + 输入内容哈希（规范升序）+ 动作指纹 + 输出哈希。
pub(all) struct Provenance {
  target : String
  input_hashes : Array[String]
  action_fp : String
  output_hash : String
} derive(Eq, Debug)

///|
/// 模型层可复现假设：输出哈希为 (输入哈希序列, 动作指纹) 的**长度前缀单射编码**。
///
/// 相同输入 + 相同动作 → 相同输出哈希；任一分量不同 → 不同输出哈希（构造性
/// 单射，三后端逐位一致）。
pub fn derive_output_hash(
  input_hashes : Array[String],
  action_fp : String,
) -> String {
  // 动作指纹、输入数与各输入哈希的长度前缀单射编码经 `TextBuilder` 物化，
  // 消除循环内 `out = out + lp(h)` 的 O(n²) 拼接（Requirement 1.5 / 1.6）；
  // 逐片段 `push_str` 与原顺序 `+` 拼接逐字符相等，输出哈希不变。
  let out = @infra_text.TextBuilder::new()
  out.push_str(lp(action_fp))
  out.push_str(lp(input_hashes.length().to_string()))
  for h in input_hashes {
    out.push_str(lp(h))
  }
  out.build()
}

///|
/// 产出溯源记录（输出哈希由 `derive_output_hash` 给出）。`input_hashes` 规范
/// 升序后参与计算：相同输入与动作恒产生逐字段一致的记录（R9.1 / R9.2 / R9.4）；
/// 任一不同则记录体现差异（R9.3）。不修改调用方传入的数组。
pub fn record_provenance(
  target : String,
  input_hashes : Array[String],
  recipe : Recipe,
) -> Provenance {
  let sorted : Array[String] = []
  for h in input_hashes {
    sorted.push(h)
  }
  sorted.sort()
  let afp = action_fingerprint(recipe)
  {
    target,
    input_hashes: sorted,
    action_fp: afp,
    output_hash: derive_output_hash(sorted, afp),
  }
}
