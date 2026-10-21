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
"$LUNE" run tools/compare_places.luau "$BASE" "$OUT"

# Every test file runs. The source place already fails 20 tests (docs/HALLOWEEN_PART2.md §13): a file may print at
# most its known number of FAIL lines; anything more, or a file that exits with an error without FAIL lines (a crash),
# fails the check (after the static analysis below).
known_failures() {
	case "$1" in
	animations) echo 6 ;; dogdex) echo 2 ;; lab) echo 2 ;; mining_rules) echo 7 ;; uikit) echo 1 ;; upgrade_tree) echo 2 ;;
	*) echo 0 ;;
	esac
}
unexpected=""
if [ -d tests ]; then
	for t in tests/*.luau; do
		echo "== $t"
		if "$LUNE" run "$t" >"$WORK/test.log" 2>&1; then status=0; else status=1; fi
		cat "$WORK/test.log"
		# FAIL lines count whatever the exit status (a file may print failures and still exit 0)
		n="$(grep -c '^FAIL ' "$WORK/test.log" || true)"
		k="$(known_failures "$(basename "$t" .luau)")"
		if [ "$n" -gt "$k" ] || { [ "$status" -ne 0 ] && [ "$n" -eq 0 ]; }; then
			unexpected="$unexpected $t"
		elif [ "$n" -gt 0 ]; then
			echo "(known failures of the source place: $n)"
		fi
	done
fi

# Static analysis: only diagnostics that are new compared with the base place are printed.
if [ ! -f "$WORK/base_analyze/sourcemap.json" ]; then
	"$LUNE" run tools/verify.luau "$BASE" "$WORK/empty_src" "$WORK/base_analyze" >/dev/null 2>&1 || true
fi
"$PYTHON" -I tools/analyze_diff.py "$LUAU_LSP" "$LUAU_DEFS" "$WORK/base_analyze" "$WORK/analyze" src

if [ -n "$unexpected" ]; then
	echo "FAILED test files:$unexpected"
	exit 1
fi
echo "check.sh: build, verify, compare, tests and analysis done"
