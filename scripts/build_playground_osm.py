#!/usr/bin/env python3
"""Build the playground's real-OSM road network artifact.

Reads a cached Overpass API response (OpenStreetMap data, ODbL 1.0 — see
README attribution) and emits a compact JSON graph for the in-browser
playground's OSM mode:

  {
    "name": ...,            # human-readable network name
    "attribution": ...,     # OSM/ODbL attribution string
    "node_count": N,
    "lat": [int * N],       # latitude  * 1e5, rounded to int
    "lon": [int * N],       # longitude * 1e5, rounded to int
    "edges": [src0, dst0, w0, src1, dst1, w1, ...]  # w = decimeters
  }

Only the largest strongly connected component is kept so every pair of
kept nodes is mutually reachable. Oneway tags are respected; other roads
get edges in both directions.

Usage:
  python3 scripts/build_playground_osm.py \
      cache/73d6fe07df5b....json playground/web/osm-xiamen.json "Xiamen"
"""

import json
import math
import sys


HIGHWAY_KEEP = {
    "motorway", "trunk", "primary", "secondary", "tertiary",
    "motorway_link", "trunk_link", "primary_link", "secondary_link",
    "tertiary_link", "unclassified", "residential",
}


def haversine_m(lat1, lon1, lat2, lon2):
    r = 6371000.0
    p1, p2 = math.radians(lat1), math.radians(lat2)
    dp = math.radians(lat2 - lat1)
    dl = math.radians(lon2 - lon1)
    a = math.sin(dp / 2) ** 2 + math.cos(p1) * math.cos(p2) * math.sin(dl / 2) ** 2
    return 2 * r * math.asin(math.sqrt(a))


def largest_scc(n, adj):
    """Iterative Tarjan SCC; returns set of node ids in the largest SCC."""
    index = [0] * n
    low = [0] * n
    on_stack = [False] * n
    idx_of = [0] * n
    visited = [False] * n
    counter = [1]
    stack = []
    best = set()

    for root in range(n):
        if visited[root]:
            continue
        work = [(root, 0)]
        while work:
            v, pi = work[-1]
            if pi == 0:
                visited[v] = True
                idx_of[v] = low[v] = counter[0]
                counter[0] += 1
                stack.append(v)
                on_stack[v] = True
            recurse = False
            neighbors = adj[v]
            while pi < len(neighbors):
                w = neighbors[pi]
                pi += 1
                if not visited[w]:
                    work[-1] = (v, pi)
                    work.append((w, 0))
                    recurse = True
                    break
                elif on_stack[w]:
                    low[v] = min(low[v], idx_of[w])
            if recurse:
                continue
            work.pop()
            if low[v] == idx_of[v]:
                comp = []
                while True:
                    w = stack.pop()
                    on_stack[w] = False
                    comp.append(w)
                    if w == v:
                        break
                if len(comp) > len(best):
                    best = set(comp)
            if work:
                parent = work[-1][0]
                low[parent] = min(low[parent], low[v])
    return best


def main():
    src, out, name = sys.argv[1], sys.argv[2], sys.argv[3]
    data = json.load(open(src))
    nodes = {}
    ways = []
    for e in data["elements"]:
        if e["type"] == "node":
            nodes[e["id"]] = (e["lat"], e["lon"])
        elif e["type"] == "way":
            tags = e.get("tags", {})
            if tags.get("highway") in HIGHWAY_KEEP:
                ways.append(e)

    used = set()
    raw_edges = []
    for w in ways:
        nds = [i for i in w["nodes"] if i in nodes]
        oneway = w.get("tags", {}).get("oneway") in ("yes", "true", "1")
        reverse = w.get("tags", {}).get("oneway") == "-1"
        for a, b in zip(nds, nds[1:]):
            la1, lo1 = nodes[a]
            la2, lo2 = nodes[b]
            dm = max(1, round(haversine_m(la1, lo1, la2, lo2) * 10))
            if reverse:
                raw_edges.append((b, a, dm))
            else:
                raw_edges.append((a, b, dm))
                if not oneway:
                    raw_edges.append((b, a, dm))
            used.add(a)
            used.add(b)

    ids = sorted(used)
    remap = {osm_id: i for i, osm_id in enumerate(ids)}
    n = len(ids)
    adj = [[] for _ in range(n)]
    for a, b, _ in raw_edges:
        adj[remap[a]].append(remap[b])
    keep = largest_scc(n, adj)
    kept_ids = [osm_id for osm_id in ids if remap[osm_id] in keep]
    final = {osm_id: i for i, osm_id in enumerate(kept_ids)}

    lat = [round(nodes[i][0] * 1e5) for i in kept_ids]
    lon = [round(nodes[i][1] * 1e5) for i in kept_ids]
    edges = []
    seen = set()
    for a, b, dm in raw_edges:
        if a in final and b in final:
            key = (final[a], final[b])
            if key in seen:
                continue
            seen.add(key)
            edges.extend((final[a], final[b], dm))

    doc = {
        "name": name,
        "attribution": "Map data (c) OpenStreetMap contributors, ODbL 1.0",
        "node_count": len(kept_ids),
        "lat": lat,
        "lon": lon,
        "edges": edges,
    }
    with open(out, "w") as f:
        json.dump(doc, f, separators=(",", ":"))
    print(f"{name}: {len(kept_ids)} nodes, {len(edges)//3} edges -> {out}")


if __name__ == "__main__":
    main()
