// engine_select_wbtest.mbt —— 引擎选择器内部路径白盒测试：program_literal
// 结构防御分支、惰性 DFA 状态容量饱和回退、字面量扫描候选失配。

///|
test "program_literal：首指令非 ISave(0) / 尾指令形态不符 → 拒绝" {
  // 首指令不是 ISave(0)。
  let p1 : Program = {
    insts: [IMatch, IChar('a'), ISave(1), IMatch],
    num_groups: 1,
    names: Map([]),
    flags: Flags::default(),
    prefilter: PfNone,
  }
  assert_true(program_literal(p1) is None)
  // 尾部不是 ISave(1) + IMatch。
  let p2 : Program = {
    insts: [ISave(0), IChar('a'), IMatch, IMatch],
    num_groups: 1,
    names: Map([]),
    flags: Flags::default(),
    prefilter: PfNone,
  }
  assert_true(program_literal(p2) is None)
  // 正常形态对照：提取出字面量。
  let p3 : Program = {
    insts: [ISave(0), IChar('a'), IChar('b'), ISave(1), IMatch],
    num_groups: 1,
    names: Map([]),
    flags: Flags::default(),
    prefilter: PfNone,
  }
  guard program_literal(p3) is Some(lit)
  assert_true(lit.length() == 2 && lit[0] == 'a' && lit[1] == 'b')
}

///|
test "PvLazyDfa::intern 容量饱和返回 -1，find_from 走无记忆 core_accepts 路径" {
  guard parse_pattern("abcdefghij") is Ok(ast)
  let prog = compile_program(ast)
  let ld = PvLazyDfa::new(prog)
  let m = prog.insts.length()
  // 以位掩码枚举指令下标子集，构造大量互异 core，撑满状态缓存。
  let mut mask = 1
  let mut saturated = false
  while mask < 1 << m {
    let core : Array[Int] = []
    for pc in 0..<m {
      if ((mask >> pc) & 1) == 1 {
        core.push(pc)
      }
    }
    if ld.intern(core) == -1 {
      saturated = true
      break
    }
    mask = mask + 1
  }
  assert_true(saturated)
  // 饱和后起始状态 intern 返回 -1，find_from 落入 core_accepts 无记忆路径。
  let chars = "abcdefghij".iter().to_array()
  guard ld.find_from(chars, chars.length(), 0) is Some(mm)
  assert_true(mm.start == 0 && mm.end == chars.length())
}

///|
test "literal_find_from：AC 候选与目标字面量失配时跳过继续扫描" {
  // 以另一个字面量构建 AC，使候选位置的后续字符与目标 lit 失配。
  let lit = "ab".iter().to_array()
  let ac = AcAutomaton::build(["ax".iter().to_array()])
  let chars = "axab".iter().to_array()
  // AC 报 "ax" 起点 0，但与 lit="ab" 失配 → eq=false → 继续推进。
  // 失配后继续扫描；"ax" 仅出现一次 → 无更多候选 → None（不误报）。
  assert_true(literal_find_from(lit, ac, chars, chars.length(), 0) is None)
}

///|
test "Dfa::minimize：零状态 DFA 直接返回自身" {
  let d : Dfa = {
    num_states: 0,
    start: 0,
    bounds: [0, 0x110000],
    accept: [],
    trans: [],
  }
  let md = d.minimize()
  assert_true(md.num_states == 0)
}
