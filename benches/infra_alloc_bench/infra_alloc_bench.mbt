// benches/infra_alloc_bench — E3 Slab vs 朴素句柄管理的 churn 基准。
//
// 负载：稳态高 churn——保持 ≤4096 存活对象（3:1 偏置使占用率趋满），交替 alloc/free/get 共 n 次，
// 模拟调度器任务表/定时器表项的真实生命周期。
//
// 两个参照实现：
//   * 线性扫描槽池（工程中最常见的 ad-hoc 对象池：固定数组 + 扫描找空位，
//     alloc O(capacity)）；
//   * 自增 id + Map[Int, Int]（「句柄=map 键」做法，每操作哈希+探测）。
// Slab 用 free-list 槽位复用 + 数组直接索引，alloc/free/get 均 O(1)。
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
const LIVE_CAP : Int = 4096

///|
/// swap-remove：用末尾顶替后 pop，O(1)（三侧一致）。
fn[T] swap_remove(arr : Array[T], j : Int) -> Unit {
  let last = arr.length() - 1
  if j != last {
    arr[j] = arr[last]
  }
  let _ = arr.pop()
}

///|
test "bench: slab vs linear-scan pool vs map handles (churn, n=32000/128000, live<=4096)" (
  b : @bench.T,
) {
  for n in [32000, 128000] {
    b.bench(name="slab_churn_\{n}", fn() {
      let s : @alloc.Slab[Int] = @alloc.Slab::with_capacity(LIVE_CAP)
      let live : Array[@alloc.SlabKey] = []
      let mut seed = 20260705UL
      let mut acc = 0
      for i in 0..<n {
        seed = xorshift(seed)
        if live.length() < LIVE_CAP && (live.length() == 0 || seed % 4UL != 0UL) {
          live.push(s.alloc(i))
        } else {
          seed = xorshift(seed)
          let j = (seed % live.length().to_uint64()).to_int()
          match s.get(live[j]) {
            Some(v) => acc = acc + v
            None => ()
          }
          let _ = s.free(live[j])
          swap_remove(live, j)
        }
      }
      b.keep(acc)
    })
    b.bench(name="linear_scan_pool_churn_\{n}", fn() {
      // ad-hoc 对象池：固定槽数组，alloc 线性扫描找空位 O(capacity)。
      let slots : Array[Int?] = Array::make(LIVE_CAP, None)
      let live : Array[Int] = []
      let mut seed = 20260705UL
      let mut acc = 0
      for i in 0..<n {
        seed = xorshift(seed)
        if live.length() < LIVE_CAP && (live.length() == 0 || seed % 4UL != 0UL) {
          // 线性扫描第一个空槽。
          let mut idx = -1
          for k in 0..<LIVE_CAP {
            if slots[k] is None {
              idx = k
              break
            }
          }
          slots[idx] = Some(i)
          live.push(idx)
        } else {
          seed = xorshift(seed)
          let j = (seed % live.length().to_uint64()).to_int()
          match slots[live[j]] {
            Some(v) => acc = acc + v
            None => ()
          }
          slots[live[j]] = None
          swap_remove(live, j)
        }
      }
      b.keep(acc)
    })
    b.bench(name="map_handles_churn_\{n}", fn() {
      let m : Map[Int, Int] = Map([])
      let live : Array[Int] = []
      let mut next_id = 0
      let mut seed = 20260705UL
      let mut acc = 0
      for i in 0..<n {
        seed = xorshift(seed)
        if live.length() < LIVE_CAP && (live.length() == 0 || seed % 4UL != 0UL) {
          m[next_id] = i
          live.push(next_id)
          next_id = next_id + 1
        } else {
          seed = xorshift(seed)
          let j = (seed % live.length().to_uint64()).to_int()
          match m.get(live[j]) {
            Some(v) => acc = acc + v
            None => ()
          }
          let _ = m.remove(live[j])
          swap_remove(live, j)
        }
      }
      b.keep(acc)
    })
  }
}
