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
"$PYTHON" -I tools/build.py
"$LUNE" run tools/verify.luau build/DOGROTS_MINING.rbxl src "$WORK/analyze"

if [ -d tests ]; then
	for t in tests/*.luau; do
		echo "== $t"
		"$LUNE" run "$t"
	done
fi

# Static analysis of every script that lives in src/ (exported names are path-mangled).
files=()
while IFS= read -r f; do
	rel="${f#src/}"
	rel="${rel%.server.luau}"; rel="${rel%.client.luau}"; rel="${rel%.luau}"
	mangled="$(printf '%s' "$rel" | sed 's/[^A-Za-z0-9._-]/_/g')"
	match="$(cd "$WORK/analyze" && ls | grep -E "^[0-9]{5}_${mangled//./\\.}\.luau$" || true)"
	[ -n "$match" ] && files+=("$match")
done < <(find src -name '*.luau' | sort)
if [ "${#files[@]}" -gt 0 ]; then
	echo "== luau-lsp analyze (${#files[@]} files)"
	(cd "$WORK/analyze" && "$LUAU_LSP" analyze --sourcemap=sourcemap.json --definitions="$LUAU_DEFS" "${files[@]}") || true
fi
