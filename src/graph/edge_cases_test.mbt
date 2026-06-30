// Negative / edge-case regression tests for the `graph` package.
//
// Complements the property tests (`prop_osm_parse_test.mbt`,
// `prop_adapter_oob_test.mbt`, ...) with explicit, deterministic regressions
// for the structured-error and malformed-representation branches that random
// generators rarely hit:
//
//   * `CsrGraph::from_osm_edge_list` structured failures on invalid TSV
//     (non-numeric / empty node id, unparseable or negative edge weight,
//     short data row) and benign skips (short header row, comments, blanks).
//   * `GraphRepr::neighbors` defensive clipping on malformed inputs
//     (adjacency-matrix row shorter than N, CSR `col_idx`/`weights` mismatch).
//
// Backlog: docs/CHAMPIONSHIP_BACKLOG.md "Add regression tests for negative and
// edge cases across algorithms" — the "invalid graph" acceptance case.

///|
/// Extract `(src, dst, weight)` directed edges from a CSR graph, source first.
fn ec_csr_edges(g : CsrGraph[Double]) -> Array[(Int, Int, Double)] {
  let out : Array[(Int, Int, Double)] = []
  for v in 0..<g.n {
    for k in g.row_ptr[v]..<g.row_ptr[v + 1] {
      out.push((v, g.col_idx[k], g.weights[k]))
    }
  }
  out
}

///|
test "from_osm_edge_list rejects a non-numeric source node id" {
  // First row is valid, so the bad second row is a structured error rather
  // than a tolerated header.
  let result = CsrGraph::from_osm_edge_list("0\t1\t5\nX\t2\t6")
  assert_true(result is Err(InvalidArgument(_)))
}

///|
test "from_osm_edge_list rejects an empty node id field" {
  // The destination field is empty; a leading-empty field would be trimmed
  // away, so the gap is placed on the second column to exercise the
  // empty-string branch of node-id parsing.
  let result = CsrGraph::from_osm_edge_list("0\t1\t5\n2\t\t6")
  assert_true(result is Err(InvalidArgument(_)))
}

///|
test "from_osm_edge_list rejects an unparseable edge weight" {
  let result = CsrGraph::from_osm_edge_list("0\t1\t5\n1\t2\tNaNaN")
  assert_true(result is Err(InvalidArgument(_)))
}

///|
test "from_osm_edge_list rejects a negative edge weight" {
  let result = CsrGraph::from_osm_edge_list("0\t1\t-5")
  assert_true(result is Err(InvalidArgument(_)))
}

///|
test "from_osm_edge_list rejects a data row with fewer than three columns" {
  // Second row has only two columns; the first row already established
  // content, so this is a structured failure (not a header).
  let result = CsrGraph::from_osm_edge_list("0\t1\t5\n2\t3")
  assert_true(result is Err(InvalidArgument(_)))
}

///|
test "from_osm_edge_list skips a short header row on the first line" {
  // A two-column first line is tolerated once as a header candidate.
  let result = CsrGraph::from_osm_edge_list("src\tdst\n0\t1\t5\n1\t2\t7")
  match result {
    Ok(g) => {
      @test.assert_eq(g.n, 3)
      let edges = ec_csr_edges(g)
      @test.assert_eq(edges, [(0, 1, 5.0), (1, 2, 7.0)])
    }
    Err(_) => assert_true(false)
  }
}

///|
test "from_osm_edge_list skips comment and blank lines" {
  let result = CsrGraph::from_osm_edge_list("# region: test\n\n0\t1\t5\n")
  match result {
    Ok(g) => {
      @test.assert_eq(g.n, 2)
      @test.assert_eq(ec_csr_edges(g), [(0, 1, 5.0)])
    }
    Err(_) => assert_true(false)
  }
}

///|
test "from_osm_edge_list on empty content yields an empty graph" {
  match CsrGraph::from_osm_edge_list("") {
    Ok(g) => {
      @test.assert_eq(g.n, 0)
      @test.assert_eq(g.row_ptr, [0])
      @test.assert_eq(g.col_idx.length(), 0)
    }
    Err(_) => assert_true(false)
  }
}

///|
test "from_osm_edge_list keeps parallel edges between the same pair" {
  match CsrGraph::from_osm_edge_list("0\t1\t5\n0\t1\t9") {
    Ok(g) => {
      @test.assert_eq(g.n, 2)
      @test.assert_eq(ec_csr_edges(g), [(0, 1, 5.0), (0, 1, 9.0)])
    }
    Err(_) => assert_true(false)
  }
}

///|
test "neighbors clips an adjacency-matrix row shorter than the node count" {
  // Declared node count is 3 but row 0 only stores two columns; neighbors
  // must clip to the available row length instead of reading out of bounds.
  let matrix : Array[Array[Double?]] = [
    [Some(7.0), Some(8.0)],
    [None, None, None],
    [None, None, None],
  ]
  let repr : GraphRepr[Double] = AdjMatrix(3, matrix)
  match repr.neighbors(0) {
    Ok(ns) => @test.assert_eq(ns, [(0, 7.0), (1, 8.0)])
    Err(_) => assert_true(false)
  }
}

///|
test "neighbors clips a malformed CSR with mismatched col_idx/weights" {
  // `weights` is longer than `col_idx`; neighbors must clip to the shorter
  // of the two arrays rather than read past `col_idx`.
  let g : CsrGraph[Double] = {
    n: 2,
    row_ptr: [0, 1, 1],
    col_idx: [1],
    weights: [5.0, 6.0],
  }
  let repr : GraphRepr[Double] = Csr(g)
  match repr.neighbors(0) {
    Ok(ns) => @test.assert_eq(ns, [(1, 5.0)])
    Err(_) => assert_true(false)
  }
}
