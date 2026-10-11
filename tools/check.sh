#!/usr/bin/env bash
# Build the place from src/, verify it with Lune, run Luau unit tests and static analysis.
#
# Requirements (paths can be overridden by env vars):
#   PYTHON    python3 with zstandard + lz4 (pip install -r tools/requirements.txt)
#   LUNE      lune >= 0.10.5           https://github.com/lune-org/lune/releases
#   LUAU_LSP  luau-lsp 1.53.0          https://github.com/JohnnyMorganz/luau-lsp/releases
#   LUAU_DEFS Roblox type definitions  luau-lsp repo scripts/globalTypes.d.luau @ 1.53.0
#   WORK      scratch directory for exported scripts
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
LUNE="${LUNE:-lune}"
LUAU_LSP="${LUAU_LSP:-luau-lsp}"
LUAU_DEFS="${LUAU_DEFS:-globalTypes.d.luau}"
WORK="${WORK:-$ROOT/.work}"

cd "$ROOT"
mkdir -p "$WORK/empty_src"
"$PYTHON" -I tools/build.py
"$LUNE" run tools/verify.luau build/DOGROTS_MINING.rbxl src "$WORK/analyze"

if [ -d tests ]; then
	for t in tests/*.luau; do
		echo "== $t"
		"$LUNE" run "$t"
	done
fi

# Static analysis: only diagnostics that are new compared with the base place are printed.
if [ ! -f "$WORK/base_analyze/sourcemap.json" ]; then
	"$LUNE" run tools/verify.luau place/DOGROTS_base.rbxl "$WORK/empty_src" "$WORK/base_analyze" >/dev/null 2>&1 || true
fi
"$PYTHON" -I tools/analyze_diff.py "$LUAU_LSP" "$LUAU_DEFS" "$WORK/base_analyze" "$WORK/analyze" src
