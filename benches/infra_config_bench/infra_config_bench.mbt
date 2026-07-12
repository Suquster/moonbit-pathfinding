// infra_config_bench.mbt —— 配置方向基准：TOML / INI 解析与取值
// 在确定性多段配置文本上的吞吐对比。

///|
fn cfg_toml_text(sections : Int) -> String {
  let buf = StringBuilder::new()
  buf.write_string("title = \"service config\"\nport = 8080\ndebug = false\n")
  for i in 0..<sections {
    buf.write_string("\n[service_\{i}]\n")
    buf.write_string("name = \"svc-\{i}\"\n")
    buf.write_string("replicas = \{i % 8 + 1}\n")
    buf.write_string("timeout_ms = \{100 + i * 7}\n")
    buf.write_string("enabled = \{i % 2 == 0}\n")
  }
  buf.to_string()
}

///|
fn cfg_ini_text(sections : Int) -> String {
  let buf = StringBuilder::new()
  for i in 0..<sections {
    buf.write_string("[service_\{i}]\n")
    buf.write_string("name = svc-\{i}\n")
    buf.write_string("replicas = \{i % 8 + 1}\n")
    buf.write_string("timeout_ms = \{100 + i * 7}\n")
  }
  buf.to_string()
}

///|
test "smoke: toml/ini parse and lookup behave as documented" {
  let toml = cfg_toml_text(4)
  match @config.toml_parse(toml) {
    Some(doc) => assert_true(@config.toml_get(doc, "port") is Some(_))
    None => assert_true(false)
  }
  let ini = cfg_ini_text(4)
  match @config.ini_parse(ini) {
    Some(doc) =>
      assert_true(@config.ini_get(doc, "service_2", "name") is Some("svc-2"))
    None => assert_true(false)
  }
}

///|
test "bench: toml / ini parse + lookup throughput" (b : @bench.T) {
  for n in [16, 64] {
    let toml = cfg_toml_text(n)
    let ini = cfg_ini_text(n)
    b.bench(name="toml_parse_\{n}_sections", fn() {
      let mut ok = 0
      match @config.toml_parse(toml) {
        Some(_) => ok = ok + 1
        None => ()
      }
      b.keep(ok)
    })
    b.bench(name="ini_parse_\{n}_sections", fn() {
      let mut ok = 0
      match @config.ini_parse(ini) {
        Some(_) => ok = ok + 1
        None => ()
      }
      b.keep(ok)
    })
  }
  let ini_doc = match @config.ini_parse(cfg_ini_text(64)) {
    Some(doc) => doc
    None => abort("ini parse failed")
  }
  b.bench(name="ini_get_64x3_lookups", fn() {
    let mut hits = 0
    for i in 0..<64 {
      for key in ["name", "replicas", "timeout_ms"] {
        match @config.ini_get(ini_doc, "service_\{i}", key) {
          Some(_) => hits = hits + 1
          None => ()
        }
      }
    }
    b.keep(hits)
  })
}
