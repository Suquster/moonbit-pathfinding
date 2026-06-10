#!/usr/bin/env bash
# benches/osm/download.sh — Download OSM road network data for benchmarking.
#
# Tasks.md 41.1 / Requirement R21.1.
#
# Downloads a medium-scale road network (~100k nodes) from Geofabrik and
# converts it to a simple edge-list TSV that `bench_osm.mbt` can parse.
#
# Usage:
#   chmod +x benches/osm/download.sh
#   ./benches/osm/download.sh
#
# Output:
#   benches/osm/data/xiamen.tsv   — tab-separated (src_id  dst_id  weight_meters)
#
# Dependencies:
#   - curl or wget
#   - osmium-tool (for filtering highway=*)
#   - Python 3 + osmnx (pip install osmnx) for graph extraction
#
# If dependencies are unavailable, the script creates a synthetic 100k-node
# grid graph as a fallback so benchmarks can still run offline.

set -euo pipefail

DATA_DIR="$(dirname "$0")/data"
mkdir -p "$DATA_DIR"

OUTPUT="$DATA_DIR/xiamen.tsv"

if [ -f "$OUTPUT" ]; then
  echo "[osm/download] $OUTPUT already exists, skipping download."
  exit 0
fi

# Try osmnx-based extraction first (most accurate).
if command -v python3 &>/dev/null && python3 -c "import osmnx" 2>/dev/null; then
  echo "[osm/download] Using osmnx to fetch Xiamen driving network..."
  python3 - <<'PYEOF'
import osmnx as ox
import csv, os

G = ox.graph_from_place("Xiamen, China", network_type="drive")
G = ox.add_edge_lengths(G)

out_path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "data", "xiamen.tsv")
# Remap node IDs to contiguous 0..n-1
nodes = list(G.nodes())
node_map = {n: i for i, n in enumerate(nodes)}

with open(out_path, "w", newline="") as f:
    writer = csv.writer(f, delimiter="\t")
    writer.writerow(["src", "dst", "length_m"])
    for u, v, data in G.edges(data=True):
        length = data.get("length", 1.0)
        writer.writerow([node_map[u], node_map[v], f"{length:.1f}"])

print(f"[osm/download] Wrote {G.number_of_edges()} edges to {out_path}")
PYEOF
  exit 0
fi

# Fallback: generate a synthetic 316x316 grid (~100k nodes, ~200k edges).
echo "[osm/download] osmnx not available; generating synthetic 100k-node grid..."
python3 -c "
import csv, os
n = 316  # 316*316 = 99856 nodes
out = os.path.join('$(echo $DATA_DIR)', 'xiamen.tsv')
with open(out, 'w', newline='') as f:
    w = csv.writer(f, delimiter='\t')
    w.writerow(['src', 'dst', 'length_m'])
    for r in range(n):
        for c in range(n):
            node = r * n + c
            if c + 1 < n:
                w.writerow([node, node + 1, '100.0'])
                w.writerow([node + 1, node, '100.0'])
            if r + 1 < n:
                w.writerow([node, node + n, '100.0'])
                w.writerow([node + n, node, '100.0'])
print(f'[osm/download] Wrote synthetic grid to {out}')
" 2>/dev/null || {
  echo "[osm/download] Python3 not available. Please install Python 3 or provide benches/osm/data/xiamen.tsv manually."
  exit 1
}
