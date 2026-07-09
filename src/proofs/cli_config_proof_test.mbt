// cli_config_proof_test.mbt —— 命令行/配置家族证明谓词的真实实现接地测试。
//
// 以 @infra_cli / @infra_config 的真实包实现驱动 cli_config_proof.mbt 中
// 的谓词（跨包驱动只发生在测试期）：
//   * dl_distance：伪度量律（自距离零、对称、非负）+ 长度夹逼（随机字符串对 PBT）；
//   * suggest_option：建议必来自候选集且距离 ≤ max_distance；
//   * help_text / completion_bash / completion_zsh：包含全部已注册选项名；
//   * ini_get / toml_get：与解析结构逐项一致。

// --- dl_distance：伪度量律 + 夹逼 ---

///|
/// 随机短字符串对生成器（字母表 {a, b, c}，长度 ∈ [0, 8]，高碰撞率覆盖
/// 换位/替换/插删混合路径）。
fn cc_string_pair_gen() -> @infra_pbt.Gen[(String, String)] {
  @infra_pbt.Gen::new(fn(rng) {
    let alphabet = ["a", "b", "c"]
    let one = fn() -> String {
      let n = rng.next_range(0, 8)
      let mut s = ""
      for _i in 0..<n {
        s = s + alphabet[rng.next_range(0, 2)]
      }
      s
    }
    (one(), one())
  })
}

///|
test "dl_distance satisfies pseudo-metric laws and length bounds" {
  let ok = @infra_pbt.holds_for_all(
    cc_string_pair_gen(),
    fn(pair : (String, String)) -> Bool {
      let (x, y) = pair
      pseudo_metric_laws(x, y, @infra_cli.dl_distance) &&
      distance_bounds(x, y, @infra_cli.dl_distance)
    },
    iters=200,
  )
  assert_true(ok)
}

///|
test "distance_bounds rejects a metric exceeding max length" {
  assert_false(distance_bounds("ab", "cd", fn(_x, _y) { 5 }))
}

// --- suggest_option：来源封闭 + 距离预算 ---

///|
test "suggest_option returns a candidate within the distance budget" {
  let candidates = ["--verbose", "--version", "--help", "--output"]
  match @infra_cli.suggest_option("--verbos", candidates, max_distance=2) {
    Some(s) => {
      // 建议必来自候选集。
      let mut found = false
      for c in candidates {
        if c == s {
          found = true
        }
      }
      assert_true(found)
      assert_true(@infra_cli.dl_distance("--verbos", s) <= 2)
    }
    None => abort("expected a suggestion for --verbos")
  }
  // 距离预算外不得给出建议。
  assert_true(
    @infra_cli.suggest_option("--zzzzzzzz", candidates, max_distance=2) is None,
  )
}

// --- help/completion 文本完备性 ---

///|
fn cc_demo_command() -> @infra_cli.Command {
  {
    name: "router",
    about: "shortest path demo",
    specs: [
      @infra_cli.flag_spec("verbose", "v", "enable verbose output"),
      @infra_cli.value_spec("output", "o", "output file", None),
      @infra_cli.value_spec("format", "f", "output format", Some("text")),
    ],
    subcommands: [],
  }
}

///|
test "help text and completions mention every registered option" {
  let cmd = cc_demo_command()
  let names = ["--verbose", "--output", "--format"]
  assert_true(contains_all(@infra_cli.help_text(cmd), names))
  assert_true(contains_all(@infra_cli.completion_bash(cmd), names))
  assert_true(contains_all(@infra_cli.completion_zsh(cmd), names))
}

///|
test "contains_all rejects a missing needle" {
  assert_false(contains_all("only --verbose here", ["--verbose", "--output"]))
}

// --- infra_config：查找一致性 ---

///|
test "ini_get agrees with the parsed structure for every entry" {
  let text = "[server]\nhost = localhost\nport = 8080\n\n[client]\nretries = 3\n"
  match @infra_config.ini_parse(text) {
    Some(doc) => {
      // 逐项一致：解析结构中每个 (section, key, value) 均可经 ini_get 还原。
      for section in doc {
        for kv in section.1 {
          assert_true(@infra_config.ini_get(doc, section.0, kv.0) == Some(kv.1))
        }
      }
      // 未注册键返回 None。
      assert_true(@infra_config.ini_get(doc, "server", "missing") is None)
      assert_true(@infra_config.ini_get(doc, "absent", "host") is None)
    }
    None => abort("expected ini_parse to succeed")
  }
}

///|
test "toml_get agrees with the parsed structure for top-level keys" {
  let text = "title = \"demo\"\ncount = 42\nenabled = true\n"
  match @infra_config.toml_parse(text) {
    Some(doc) => {
      for kv in doc {
        assert_true(@infra_config.toml_get(doc, kv.0) == Some(kv.1))
      }
      assert_true(@infra_config.toml_get(doc, "missing") is None)
    }
    None => abort("expected toml_parse to succeed")
  }
}
