#!/usr/bin/env bash
# Build the place from place/ + src/ + tools/edits/, verify it with Lune, run Luau unit tests and static analysis.
#
# Requirements (paths can be overridden by env vars):
#   LUNE      lune 0.10.x              https://github.com/lune-org/lune/releases
#   LUAU_LSP  luau-lsp 1.53.0          https://github.com/JohnnyMorganz/luau-lsp/releases
#   LUAU_DEFS Roblox type definitions  luau-lsp repo scripts/globalTypes.d.luau @ 1.53.0
#   PYTHON    python3 (static analysis diff only)
#   WORK      scratch directory for exported scripts
#   BASE      base place (default: the Halloween Chapter I place)
#   OUT       output place
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PYTHON="${PYTHON:-python3}"
LUNE="${LUNE:-lune}"
LUAU_LSP="${LUAU_LSP:-luau-lsp}"
LUAU_DEFS="${LUAU_DEFS:-globalTypes.d.luau}"
WORK="${WORK:-$ROOT/.work}"
BASE="${BASE:-$ROOT/place/DOGROTS_HALLOWEEN_NIGHT_OF_THE_BURIED_MOON.rbxl}"
OUT="${OUT:-$ROOT/build/DOGROTS_HALLOWEEN_PART2_THE_UNDERYARD.rbxl}"

cd "$ROOT"
mkdir -p "$WORK/empty_src" "$(dirname "$OUT")"
"$LUNE" run tools/place_build.luau "$BASE" src "$OUT" tools/edits
"$LUNE" run tools/verify.luau "$OUT" src "$WORK/analyze"
"$LUNE" run tools/verify_world.luau "$OUT"

if [ -d tests ]; then
	for t in tests/*.luau; do
		echo "== $t"
		"$LUNE" run "$t"
	done
fi

# Static analysis: only diagnostics that are new compared with the base place are printed.
if [ ! -f "$WORK/base_analyze/sourcemap.json" ]; then
	"$LUNE" run tools/verify.luau "$BASE" "$WORK/empty_src" "$WORK/base_analyze" >/dev/null 2>&1 || true
fi
"$PYTHON" -I tools/analyze_diff.py "$LUAU_LSP" "$LUAU_DEFS" "$WORK/base_analyze" "$WORK/analyze" src
