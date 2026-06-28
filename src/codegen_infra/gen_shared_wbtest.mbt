// gen_shared_wbtest.mbt —— 白盒属性测试（*_wbtest.mbt）的共享 CFG 生成器。
//
// 白盒测试单元与黑盒测试单元相互独立（编译单元不同），故此处提供与
// gen_shared_test.mbt 的 `gen_cfg` 等价的白盒版本 `gen_cfg_wb`，供
// prop_ssa_single_assign_wbtest.mbt / prop_pipeline_wbtest.mbt 复用。
// 结构同黑盒版：唯一入口 `b0`、前向边 DAG、出度 ≤ 2、含汇合块、条件取外部 `p`。

///|
/// 变量名池（白盒）。
let wb_var_pool : Array[String] = ["a", "b", "c", "x"]

///|
/// 运算符池（白盒）。
let wb_op_pool : Array[String] = ["+", "-", "*"]

///|
/// 数组是否含某整数（白盒本地）。
fn wb_contains_int(arr : Array[Int], x : Int) -> Bool {
  for v in arr {
    if v == x {
      return true
    }
  }
  false
}

///|
/// 生成一个块的指令（白盒）。
fn wb_block_instrs(
  rng : @infra_pbt.Rng,
  succ_labels : Array[String],
) -> Array[String] {
  let instrs : Array[String] = []
  let ndef = rng.next_below(3)
  let mut d = 0
  while d < ndef {
    let lhs = wb_var_pool[rng.next_below(wb_var_pool.length())]
    if rng.next_bool() {
      instrs.push(lhs + " = " + rng.next_range(0, 9).to_string())
    } else {
      let a = wb_var_pool[rng.next_below(wb_var_pool.length())]
      let b = wb_var_pool[rng.next_below(wb_var_pool.length())]
      let op = wb_op_pool[rng.next_below(wb_op_pool.length())]
      instrs.push(lhs + " = " + a + " " + op + " " + b)
    }
    d = d + 1
  }
  if succ_labels.length() == 0 {
    instrs.push("ret " + wb_var_pool[rng.next_below(wb_var_pool.length())])
  } else if succ_labels.length() == 1 {
    instrs.push("br " + succ_labels[0])
  } else {
    instrs.push("cbr p " + succ_labels[0] + " " + succ_labels[1])
  }
  instrs
}

///|
/// 随机 CFG 生成器（白盒）：唯一入口 b0、前向边 DAG、出度 ≤ 2、含汇合块。
fn gen_cfg_wb() -> @infra_pbt.Gen[Array[BasicBlock]] {
  @infra_pbt.Gen::new(fn(rng) {
    let n = rng.next_range(3, 7)
    let succ : Array[Array[Int]] = []
    for _ in 0..<n {
      succ.push([])
    }
    for i in 1..<n {
      let start = rng.next_below(i)
      for off in 0..<i {
        let j = (start + off) % i
        if succ[j].length() < 2 && !(wb_contains_int(succ[j], i)) {
          succ[j].push(i)
          break
        }
      }
    }
    let extra = rng.next_below(n)
    let mut e = 0
    while e < extra {
      let a = rng.next_below(n - 1)
      let b = rng.next_range(a + 1, n - 1)
      if succ[a].length() < 2 && !(wb_contains_int(succ[a], b)) {
        succ[a].push(b)
      }
      e = e + 1
    }
    let blocks : Array[BasicBlock] = []
    for i in 0..<n {
      succ[i].sort()
      let succ_labels : Array[String] = []
      for t in succ[i] {
        succ_labels.push("b" + t.to_string())
      }
      let instrs = wb_block_instrs(rng, succ_labels)
      blocks.push({ label: "b" + i.to_string(), instrs, succs: succ_labels })
    }
    blocks
  })
}
