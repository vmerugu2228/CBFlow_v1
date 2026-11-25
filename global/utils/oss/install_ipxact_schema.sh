#!/usr/bin/env bash
# =============================================================================
# install_ipxact_schema.sh — the IEEE 1685-2014 (IP-XACT) XML schema, for
# validating the IP-XACT the RTL_SPEC flow generates.
#
#   install_ipxact_schema.sh [<tools_dir>]     default: $HOME/eda/tools/oss
#   → <tools_dir>/ipxact/1685-2014/index.xsd (+ every schema it includes)
#
# Source: Accellera, http://www.accellera.org/XMLSchema/IPXACT/1685-2014/.
# Schemas referenced through schemaLocation are fetched transitively (relative
# ones beside index.xsd, absolute ones by URL into ext/ with the reference
# rewritten).
# =============================================================================
set -euo pipefail

BASE="http://www.accellera.org/XMLSchema/IPXACT/1685-2014"
TOOLS_DIR="${1:-${CBFLOW_OSS_TOOLS:-$HOME/eda/tools/oss}}"
DST="$TOOLS_DIR/ipxact/1685-2014"
mkdir -p "$DST/ext"

python3 - "$BASE" "$DST" <<'PY'
import os, re, sys, urllib.request
base, dst = sys.argv[1], sys.argv[2]
todo, done = ['index.xsd'], set()
while todo:
    name = todo.pop()
    if name in done:
        continue
    done.add(name)
    url = name if name.startswith('http') else f'{base}/{name}'
    data = urllib.request.urlopen(url, timeout=60).read().decode('utf-8')
    def fix(m):
        loc = m.group(1)
        if loc.startswith('http'):
            local = 'ext/' + re.sub(r'[^A-Za-z0-9_.-]', '_', loc.split('://', 1)[1])
            todo.append(loc)
            return f'schemaLocation="{os.path.relpath(local, os.path.dirname(name) if not name.startswith("http") else "ext")}"'
        todo.append(os.path.normpath(os.path.join(os.path.dirname(name), loc)) if not name.startswith('http') else loc)
        return m.group(0)
    data = re.sub(r'schemaLocation="([^"]+)"', fix, data)
    out = os.path.join(dst, 'ext/' + re.sub(r'[^A-Za-z0-9_.-]', '_', name.split('://', 1)[1])) if name.startswith('http') else os.path.join(dst, name)
    os.makedirs(os.path.dirname(out), exist_ok=True)
    open(out, 'w').write(data)
print(f'{len(done)} schema files -> {dst}')
PY
