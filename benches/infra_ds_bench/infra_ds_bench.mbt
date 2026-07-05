// benches/infra_ds_bench — E1 BTreeMap vs 朴素参照的吞吐基准。
//
// 参照实现（对标 E1 KPI「与朴素实现比较达数量级优势」）：
//   * 线性扫描映射：未排序 (K,V) 数组，get/insert 逐项线性查找 O(n)；
//   * 范围查询：参照为全量过滤 O(n)，BTreeMap 为 O(log n + 命中数)。
//
// 工作负载确定性（xorshift64 固定种子），保证跨机器/后端可复现。

///|
fn xorshift(x : UInt64) -> UInt64 {
  let mut v = x
  v = v ^ (v << 13)
  v = v ^ (v >> 7)
  v = v ^ (v << 17)
  v
}

///|
/// 确定性键序列（值域 [0, space)）。
fn make_keys(n : Int, space : Int, seed : UInt64) -> Array[Int] {
  let out : Array[Int] = []
  let mut s = seed
  for _ in 0..<n {
    s = xorshift(s)
    out.push((s % space.to_uint64()).to_int())
  }
  out
}

///|
/// 朴素线性映射 insert。
fn linear_insert(entries : Array[(Int, Int)], k : Int, v : Int) -> Unit {
  for i in 0..<entries.length() {
    if entries[i].0 == k {
      entries[i] = (k, v)
      return
    }
  }
  entries.push((k, v))
}

///|
/// 朴素线性映射 get。
fn linear_get(entries : Array[(Int, Int)], k : Int) -> Int? {
  for e in entries {
    if e.0 == k {
      return Some(e.1)
    }
  }
  None
}

///|
test "bench: btree vs linear map (insert+get, n=2000/8000/32000)" (b : @bench.T) {
  for n in [2000, 8000, 32000] {
    let keys = make_keys(n, n * 2, 20260705UL)
    b.bench(name="btree_insert_get_\{n}", fn() {
      let m : @ds.BTreeMap[Int, Int] = @ds.BTreeMap::new()
      for k in keys {
        let _ = m.insert(k, k)
      }
      let mut acc = 0
      for k in keys {
        match m.get(k) {
          Some(v) => acc = acc + v
          None => ()
        }
      }
      b.keep(acc)
    })
    b.bench(name="linear_insert_get_\{n}", fn() {
      let entries : Array[(Int, Int)] = []
      for k in keys {
        linear_insert(entries, k, k)
      }
      let mut acc = 0
      for k in keys {
        match linear_get(entries, k) {
          Some(v) => acc = acc + v
          None => ()
        }
      }
      b.keep(acc)
    })
  }
}

///|
/// 朴素有序数组集合并（双指针归并）。
fn sorted_union(a : Array[Int], b : Array[Int]) -> Array[Int] {
  let out : Array[Int] = []
  let mut i = 0
  let mut j = 0
  while i < a.length() && j < b.length() {
    if a[i] < b[j] {
      out.push(a[i])
      i = i + 1
    } else if a[i] > b[j] {
      out.push(b[j])
      j = j + 1
    } else {
      out.push(a[i])
      i = i + 1
      j = j + 1
    }
  }
  while i < a.length() {
    out.push(a[i])
    i = i + 1
  }
  while j < b.length() {
    out.push(b[j])
    j = j + 1
  }
  out
}

///|
test "bench: roaring vs sorted-array set union (dense, n=50000)" (b : @bench.T) {
  let n = 50000
  let ka = make_keys(n, 65536, 1UL)
  let kb = make_keys(n, 65536, 2UL)
  // roaring 两位图。
  let ra = @ds.RoaringBitmap::new()
  let rb = @ds.RoaringBitmap::new()
  for x in ka {
    let _ = ra.add(x)
  }
  for x in kb {
    let _ = rb.add(x)
  }
  // 朴素有序去重数组。
  let sa = dedup_sorted(ka)
  let sb = dedup_sorted(kb)
  b.bench(name="roaring_union_dense", fn() {
    b.keep(ra.union_with(rb).cardinality())
  })
  b.bench(name="sorted_array_union_dense", fn() {
    b.keep(sorted_union(sa, sb).length())
  })
}

///|
fn dedup_sorted(a : Array[Int]) -> Array[Int] {
  let c = a.copy()
  c.sort()
  let out : Array[Int] = []
  for x in c {
    if out.length() == 0 || out[out.length() - 1] != x {
      out.push(x)
    }
  }
  out
}

///|
/// 朴素不可变映射：copy-on-write 数组，每次 put 复制整表（对标 HAMT 的
/// 持久化语义——两者都保留旧版本）。
fn cow_put(m : Array[(Int, Int)], k : Int, v : Int) -> Array[(Int, Int)] {
  let out : Array[(Int, Int)] = []
  let mut replaced = false
  for e in m {
    if e.0 == k {
      out.push((k, v))
      replaced = true
    } else {
      out.push(e)
    }
  }
  if !replaced {
    out.push((k, v))
  }
  out
}

///|
test "bench: hamt vs cow-array persistent insert (n=2000/8000)" (b : @bench.T) {
  for n in [2000, 8000] {
    let keys = make_keys(n, n * 2, 20260707UL)
    b.bench(name="hamt_persistent_insert_\{n}", fn() {
      let mut m : @ds.HamtMap[Int, Int] = @ds.HamtMap::new()
      for k in keys {
        m = m.insert(k, k)
      }
      b.keep(m.length())
    })
    b.bench(name="cow_array_persistent_insert_\{n}", fn() {
      let mut m : Array[(Int, Int)] = []
      for k in keys {
        m = cow_put(m, k, k)
      }
      b.keep(m.length())
    })
  }
}

///|
test "bench: btree range vs full filter (n=8000, 1000 queries)" (b : @bench.T) {
  let n = 8000
  let keys = make_keys(n, n * 2, 20260705UL)
  let m : @ds.BTreeMap[Int, Int] = @ds.BTreeMap::new()
  let entries : Array[(Int, Int)] = []
  for k in keys {
    let _ = m.insert(k, k)
    linear_insert(entries, k, k)
  }
  let queries = make_keys(1000, n * 2 - 64, 42UL)
  b.bench(name="btree_range_1000q", fn() {
    let mut acc = 0
    for lo in queries {
      acc = acc + m.range(lo, lo + 64).length()
    }
    b.keep(acc)
  })
  b.bench(name="filter_range_1000q", fn() {
    let mut acc = 0
    for lo in queries {
      let mut cnt = 0
      for e in entries {
        if e.0 >= lo && e.0 < lo + 64 {
          cnt = cnt + 1
        }
      }
      acc = acc + cnt
    }
    b.keep(acc)
  })
}
