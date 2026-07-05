// roaring.mbt —— E1 核心数据结构：roaring 式压缩位图（RoaringBitmap）。
//
// paper-to-code：Chambi, Lemire, Kaser, Godin.
// *Better bitmap performance with Roaring bitmaps.* SPE 2016.
//
// 32 位非负整数集合按高 16 位分桶（chunk），每桶一个容器，两态自适应：
//   * array 容器：升序 Array[Int]（低 16 位），基数 ≤ 4096 —— 稀疏桶省内存；
//   * bitmap 容器：1024×UInt64 定长位图，基数 > 4096 —— 稠密桶 O(1) 位操作。
// add 越过 4096 时 array→bitmap；remove 降到 4096 时 bitmap→array（论文 §3）。
//
// 集合运算按桶键归并（双指针），容器级分派 array/bitmap 专用内核：
// bitmap∪bitmap / bitmap∩bitmap 走 64 位字级位或/位与——这正是 roaring 相对
// 朴素排序数组集合的数量级优势来源。
//
// 对外 API：new / add / remove / contains / cardinality / union_with /
// intersect_with / to_array。

///|
/// 容器：低 16 位集合的两态表示。
enum Container {
  /// 升序低位数组（基数 ≤ 4096）。
  ArrayC(Array[Int])
  /// 1024×UInt64 位图 + 基数缓存（基数 > 4096）。
  BitmapC(Array[UInt64], Int)
}

///|
/// array 容器 → bitmap 容器阈值（论文 §3：4096 = 65536/16，恰为位图
/// 固定 8KB 与 2B/元素数组的内存平衡点）。
const ROARING_THRESHOLD : Int = 4096

///|
/// roaring 压缩位图：`chunk_keys` 升序保存各桶高 16 位键。
pub struct RoaringBitmap {
  chunk_keys : Array[Int]
  containers : Array[Container]
}

///|
/// 空位图。
pub fn RoaringBitmap::new() -> RoaringBitmap {
  { chunk_keys: [], containers: [] }
}

///|
/// 桶键二分：返回首个 `chunk_keys[i] >= key` 的 i。
fn RoaringBitmap::chunk_lb(self : RoaringBitmap, key : Int) -> Int {
  let mut lo = 0
  let mut hi = self.chunk_keys.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if self.chunk_keys[mid] < key {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
/// 升序数组二分下界。
fn arr_lb(a : Array[Int], x : Int) -> Int {
  let mut lo = 0
  let mut hi = a.length()
  while lo < hi {
    let mid = (lo + hi) / 2
    if a[mid] < x {
      lo = mid + 1
    } else {
      hi = mid
    }
  }
  lo
}

///|
fn bitmap_of_array(a : Array[Int]) -> Array[UInt64] {
  let words : Array[UInt64] = Array::make(1024, 0UL)
  for x in a {
    words[x >> 6] = words[x >> 6] | (1UL << (x & 63))
  }
  words
}

///|
fn array_of_bitmap(words : Array[UInt64]) -> Array[Int] {
  let out : Array[Int] = []
  for w in 0..<1024 {
    let mut bits = words[w]
    while bits != 0 {
      let tz = trailing_zeros(bits)
      out.push(w * 64 + tz)
      bits = bits & (bits - 1)
    }
  }
  out
}

///|
/// UInt64 尾零计数（de Bruijn 免查表的朴素循环换成折半，仍 O(6)）。
fn trailing_zeros(x : UInt64) -> Int {
  if x == 0 {
    return 64
  }
  let mut v = x
  let mut n = 0
  if (v & 0xFFFFFFFFUL) == 0 {
    n = n + 32
    v = v >> 32
  }
  if (v & 0xFFFFUL) == 0 {
    n = n + 16
    v = v >> 16
  }
  if (v & 0xFFUL) == 0 {
    n = n + 8
    v = v >> 8
  }
  if (v & 0xFUL) == 0 {
    n = n + 4
    v = v >> 4
  }
  if (v & 0x3UL) == 0 {
    n = n + 2
    v = v >> 2
  }
  if (v & 0x1UL) == 0 {
    n = n + 1
  }
  n
}

///|
/// UInt64 置位计数（SWAR popcount）。
fn popcount64(x : UInt64) -> Int {
  let mut v = x
  v = v - ((v >> 1) & 0x5555555555555555UL)
  v = (v & 0x3333333333333333UL) + ((v >> 2) & 0x3333333333333333UL)
  v = (v + (v >> 4)) & 0x0F0F0F0F0F0F0F0FUL
  ((v * 0x0101010101010101UL) >> 56).to_int()
}

///|
/// 加入元素（x ≥ 0）；返回是否新增。
pub fn RoaringBitmap::add(self : RoaringBitmap, x : Int) -> Bool {
  let key = x >> 16
  let low = x & 0xFFFF
  let i = self.chunk_lb(key)
  if i >= self.chunk_keys.length() || self.chunk_keys[i] != key {
    arr_insert(self.chunk_keys, i, key)
    arr_insert(self.containers, i, Container::ArrayC([low]))
    return true
  }
  match self.containers[i] {
    ArrayC(a) => {
      let j = arr_lb(a, low)
      if j < a.length() && a[j] == low {
        return false
      }
      arr_insert(a, j, low)
      if a.length() > ROARING_THRESHOLD {
        self.containers[i] = Container::BitmapC(bitmap_of_array(a), a.length())
      }
      true
    }
    BitmapC(words, card) => {
      let w = low >> 6
      let bit = 1UL << (low & 63)
      if (words[w] & bit) != 0 {
        return false
      }
      words[w] = words[w] | bit
      self.containers[i] = Container::BitmapC(words, card + 1)
      true
    }
  }
}

///|
/// 移除元素；返回是否确实存在。
pub fn RoaringBitmap::remove(self : RoaringBitmap, x : Int) -> Bool {
  let key = x >> 16
  let low = x & 0xFFFF
  let i = self.chunk_lb(key)
  if i >= self.chunk_keys.length() || self.chunk_keys[i] != key {
    return false
  }
  match self.containers[i] {
    ArrayC(a) => {
      let j = arr_lb(a, low)
      if j >= a.length() || a[j] != low {
        return false
      }
      let _ = arr_remove(a, j)
      if a.length() == 0 {
        let _ = arr_remove(self.chunk_keys, i)
        let _ = arr_remove(self.containers, i)
      }
      true
    }
    BitmapC(words, card) => {
      let w = low >> 6
      let bit = 1UL << (low & 63)
      if (words[w] & bit) == 0 {
        return false
      }
      words[w] = words[w] ^ bit
      let nc = card - 1
      if nc <= ROARING_THRESHOLD {
        self.containers[i] = Container::ArrayC(array_of_bitmap(words))
      } else {
        self.containers[i] = Container::BitmapC(words, nc)
      }
      true
    }
  }
}

///|
/// 成员判定。
pub fn RoaringBitmap::contains(self : RoaringBitmap, x : Int) -> Bool {
  let key = x >> 16
  let low = x & 0xFFFF
  let i = self.chunk_lb(key)
  if i >= self.chunk_keys.length() || self.chunk_keys[i] != key {
    return false
  }
  match self.containers[i] {
    ArrayC(a) => {
      let j = arr_lb(a, low)
      j < a.length() && a[j] == low
    }
    BitmapC(words, _) => (words[low >> 6] & (1UL << (low & 63))) != 0
  }
}

///|
/// 元素个数。
pub fn RoaringBitmap::cardinality(self : RoaringBitmap) -> Int {
  let mut n = 0
  for c in self.containers {
    match c {
      ArrayC(a) => n = n + a.length()
      BitmapC(_, card) => n = n + card
    }
  }
  n
}

///|
fn container_to_words(c : Container) -> Array[UInt64] {
  match c {
    ArrayC(a) => bitmap_of_array(a)
    BitmapC(words, _) => words.copy()
  }
}

///|
/// 容器并：位图字级位或 / 数组归并，结果按基数自适应两态。
fn container_union(x : Container, y : Container) -> Container {
  match (x, y) {
    (ArrayC(a), ArrayC(b)) => {
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
      if out.length() > ROARING_THRESHOLD {
        Container::BitmapC(bitmap_of_array(out), out.length())
      } else {
        Container::ArrayC(out)
      }
    }
    _ => {
      let wa = container_to_words(x)
      let wb = container_to_words(y)
      let mut card = 0
      for i in 0..<1024 {
        wa[i] = wa[i] | wb[i]
        card = card + popcount64(wa[i])
      }
      if card <= ROARING_THRESHOLD {
        Container::ArrayC(array_of_bitmap(wa))
      } else {
        Container::BitmapC(wa, card)
      }
    }
  }
}

///|
/// 容器交。
fn container_intersect(x : Container, y : Container) -> Container? {
  match (x, y) {
    (ArrayC(a), ArrayC(b)) => {
      let out : Array[Int] = []
      let mut i = 0
      let mut j = 0
      while i < a.length() && j < b.length() {
        if a[i] < b[j] {
          i = i + 1
        } else if a[i] > b[j] {
          j = j + 1
        } else {
          out.push(a[i])
          i = i + 1
          j = j + 1
        }
      }
      if out.length() == 0 {
        None
      } else {
        Some(Container::ArrayC(out))
      }
    }
    (ArrayC(a), BitmapC(words, _)) | (BitmapC(words, _), ArrayC(a)) => {
      let out : Array[Int] = []
      for v in a {
        if (words[v >> 6] & (1UL << (v & 63))) != 0 {
          out.push(v)
        }
      }
      if out.length() == 0 {
        None
      } else {
        Some(Container::ArrayC(out))
      }
    }
    (BitmapC(wa, _), BitmapC(wb, _)) => {
      let words : Array[UInt64] = Array::make(1024, 0UL)
      let mut card = 0
      for i in 0..<1024 {
        words[i] = wa[i] & wb[i]
        card = card + popcount64(words[i])
      }
      if card == 0 {
        None
      } else if card <= ROARING_THRESHOLD {
        Some(Container::ArrayC(array_of_bitmap(words)))
      } else {
        Some(Container::BitmapC(words, card))
      }
    }
  }
}

///|
/// 并集（返回新位图，双指针桶键归并）。
pub fn RoaringBitmap::union_with(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  let out = RoaringBitmap::new()
  let mut i = 0
  let mut j = 0
  while i < self.chunk_keys.length() && j < other.chunk_keys.length() {
    let ka = self.chunk_keys[i]
    let kb = other.chunk_keys[j]
    if ka < kb {
      out.chunk_keys.push(ka)
      out.containers.push(container_clone(self.containers[i]))
      i = i + 1
    } else if ka > kb {
      out.chunk_keys.push(kb)
      out.containers.push(container_clone(other.containers[j]))
      j = j + 1
    } else {
      out.chunk_keys.push(ka)
      out.containers.push(
        container_union(self.containers[i], other.containers[j]),
      )
      i = i + 1
      j = j + 1
    }
  }
  while i < self.chunk_keys.length() {
    out.chunk_keys.push(self.chunk_keys[i])
    out.containers.push(container_clone(self.containers[i]))
    i = i + 1
  }
  while j < other.chunk_keys.length() {
    out.chunk_keys.push(other.chunk_keys[j])
    out.containers.push(container_clone(other.containers[j]))
    j = j + 1
  }
  out
}

///|
/// 交集（返回新位图）。
pub fn RoaringBitmap::intersect_with(
  self : RoaringBitmap,
  other : RoaringBitmap,
) -> RoaringBitmap {
  let out = RoaringBitmap::new()
  let mut i = 0
  let mut j = 0
  while i < self.chunk_keys.length() && j < other.chunk_keys.length() {
    let ka = self.chunk_keys[i]
    let kb = other.chunk_keys[j]
    if ka < kb {
      i = i + 1
    } else if ka > kb {
      j = j + 1
    } else {
      match container_intersect(self.containers[i], other.containers[j]) {
        Some(c) => {
          out.chunk_keys.push(ka)
          out.containers.push(c)
        }
        None => ()
      }
      i = i + 1
      j = j + 1
    }
  }
  out
}

///|
fn container_clone(c : Container) -> Container {
  match c {
    ArrayC(a) => Container::ArrayC(a.copy())
    BitmapC(words, card) => Container::BitmapC(words.copy(), card)
  }
}

///|
/// 升序导出全部元素。
pub fn RoaringBitmap::to_array(self : RoaringBitmap) -> Array[Int] {
  let out : Array[Int] = []
  for i in 0..<self.chunk_keys.length() {
    let base = self.chunk_keys[i] << 16
    match self.containers[i] {
      ArrayC(a) =>
        for v in a {
          out.push(base | v)
        }
      BitmapC(words, _) =>
        for v in array_of_bitmap(words) {
          out.push(base | v)
        }
    }
  }
  out
}
