#!/usr/bin/env python3
import re, sys

sites = []
with open('/tmp/warnsites.txt') as f:
    for line in f:
        parts = line.strip().split(':')
        if len(parts) >= 2:
            sites.append((parts[0], int(parts[1])))

# group by file, process from bottom to top
from collections import defaultdict
byfile = defaultdict(list)
for f, l in sites:
    byfile[f].append(l)

def split_top(s):
    depth = 0; instr = False; esc = False
    for i, ch in enumerate(s):
        if instr:
            if esc: esc = False
            elif ch == '\\': esc = True
            elif ch == '"': instr = False
            continue
        if ch == '"': instr = True
        elif ch in '([{': depth += 1
        elif ch in ')]}': depth -= 1
        elif ch == ',' and depth == 0:
            return s[:i], s[i+1:]
    return None

changed = 0
for path, lines in byfile.items():
    with open(path) as fh:
        src = fh.readlines()
    for ln in sorted(lines, reverse=True):
        i = ln - 1
        text = src[i]
        if 'Ref::new(' in text:
            src[i] = text.replace('Ref::new(', 'Ref({ val: ', 1).replace(')', ' })', 1)
            changed += 1
            continue
        if 'fail(' in text and 'assert_eq' not in text:
            src[i] = re.sub(r'fail\("[^"]*"\)', 'fail("不应失败")', text)
            changed += 1
            continue
        # find assert_eq( starting at this line, capture balanced parens possibly multiline
        m = re.search(r'assert_eq\(', text)
        if not m:
            print('skip', path, ln, text.strip())
            continue
        start_line = i
        # collect until balanced
        buf = text[m.end():]
        depth = 1; j = i
        # find end position
        full = ''
        k = m.end(); line_idx = i; cur = text
        instr = False; esc = False
        collected = []
        while True:
            while k < len(cur):
                ch = cur[k]
                if instr:
                    if esc: esc = False
                    elif ch == '\\': esc = True
                    elif ch == '"': instr = False
                else:
                    if ch == '"': instr = True
                    elif ch in '([{': depth += 1
                    elif ch in ')]}':
                        depth -= 1
                        if depth == 0:
                            break
                collected.append(ch)
                k += 1
            if depth == 0:
                break
            line_idx += 1
            cur = src[line_idx]
            k = 0
        inner = ''.join(collected)
        sp = split_top(inner)
        if not sp:
            print('nosplit', path, ln)
            continue
        a, b = sp[0].strip(), sp[1].strip()
        indent = re.match(r'\s*', text).group(0)
        prefix = text[:m.start()]
        suffix = cur[k+1:]  # after closing paren
        new = f'{prefix}assert_true({a} == ({b})){suffix}'
        src[start_line:line_idx+1] = [new]
        changed += 1
    with open(path, 'w') as fh:
        fh.writelines(src)
print('changed', changed)
