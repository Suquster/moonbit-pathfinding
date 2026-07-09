// cli_config_proof.mbt —— INFRA 家族第六批证明谓词：命令行前端
// （infra_cli：DL 编辑距离 / 拼写建议 / 帮助与补全生成）与配置解析
// （infra_config：INI / TOML 查找一致性）的不变量接入。
//
// 复用约定：与其余 `*_proof.mbt` 相同——每条不变量编码为纯、全（total）的
// `Bool` 谓词，proofs 生产代码不引入新依赖（仅 @core），跨包驱动只发生在
// 测试期（cli_config_proof_test.mbt 以真实包实现接地）。
//
// 覆盖的不变量家族：
//   * 伪度量律（编辑距离：自距离为零、对称、非负、长度差下界/最大长度上界）；
//   * 文本完备（帮助/补全脚本必须包含全部已注册选项名）；
//   * 查找一致（ini_get/toml_get 与解析结构逐项一致，测试期直接驱动）。

///|
/// `pseudo_metric_laws(x, y, d)` —— 字符串编辑距离的伪度量律合取：
///   * 自距离为零：`d(x, x) == 0 && d(y, y) == 0`；
///   * 对称：`d(x, y) == d(y, x)`；
///   * 非负：`d(x, y) >= 0`。
/// 注：OSA 变体的 DL 距离不保证三角不等式，故谓词刻意不含它。
/// 纯、全函数，供随机字符串对 PBT 驱动。
pub fn pseudo_metric_laws(
  x : String,
  y : String,
  d : (String, String) -> Int,
) -> Bool {
  d(x, x) == 0 && d(y, y) == 0 && d(x, y) == d(y, x) && d(x, y) >= 0
}

///|
/// `distance_bounds(x, y, d)` —— 编辑距离的夹逼律：
/// `|len(x) - len(y)| <= d(x, y) <= max(len(x), len(y))`。
/// 下界：长度差至少需要等量插入/删除；上界：整串替换 + 补齐即可完成。
/// 纯、全函数，供随机字符串对 PBT 驱动。
pub fn distance_bounds(
  x : String,
  y : String,
  d : (String, String) -> Int,
) -> Bool {
  let lx = x.length()
  let ly = y.length()
  let lo = if lx > ly { lx - ly } else { ly - lx }
  let hi = if lx > ly { lx } else { ly }
  let dist = d(x, y)
  dist >= lo && dist <= hi
}

///|
/// `contains_all(hay, needles)` —— 文本完备性谓词：`hay` 包含每个
/// `needles` 子串。用于「help_text / 补全脚本必须提及全部已注册选项名」
/// 等生成文本的完备性后置条件。纯、全函数（空 needles 平凡为真）。
pub fn contains_all(hay : String, needles : Array[String]) -> Bool {
  let mut i = 0
  while i < needles.length() {
    if !hay.contains(needles[i]) {
      return false
    }
    i += 1
  }
  true
}
