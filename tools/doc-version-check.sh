#!/system/bin/sh
# ======================================================================
#  VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
#  A self-update engine for KernelSU/APatch/Magisk modules.
#
#  Copyright (C) 2026  VD171
#  SPDX-License-Identifier: Apache-2.0
#
#  Site           : https://vd171.ru
#  Site           : https://vd.priv8.ru
#  Source         : https://github.com/VD171/VDLiveUpdate
#  GitHub         : @VD171 https://github.com/VD171
#  XDA-Developers : @VD171 https://xdaforums.com/m/vd171.4699873/
#  Telegram       : @VD_Priv8 https://t.me/VD_Priv8
#  Channel        : @Priv8_VD https://t.me/Priv8_VD
#  Discord        : @VD.Priv8 https://discord.com/users/1296831918989639721
#  E-mail         : vd.priv8@pm.me
# ======================================================================
# doc-version-check.sh - guard against doc/engine drift.
#
# Asserts, fail-closed:
#   1. engine/update.sh ENGINE_VERSION == the "(current)" row in TRUST-MODEL.md
#      == the top CHANGELOG.md entry.
#   2. Every `cfg <key>` the engine reads is documented in docs/INTERFACES.md §5.
#
# No drift -> "OK" + exit 0. Any drift -> the mismatch on stderr + exit 1.
# Pure POSIX sh + grep/sed/awk; no jq, no bashisms.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
engine="$here/engine/update.sh"
security="$here/docs/TRUST-MODEL.md"
changelog="$here/CHANGELOG.md"
interfaces="$here/docs/INTERFACES.md"

fail=0
for f in "$engine" "$security" "$changelog" "$interfaces"; do
	[ -f "$f" ] || { echo "MISSING: $f" >&2; fail=1; }
done
[ "$fail" = 0 ] || exit 2

# 1. the three version sources ----------------------------------------------
# engine: ENGINE_VERSION=<n>
ev=$(grep -E '^ENGINE_VERSION=[0-9]+' "$engine" | head -n1 | sed -E 's/^ENGINE_VERSION=([0-9]+).*/\1/')
# TRUST-MODEL.md: the table row "| <n> (current) |"
sv=$(grep -E '^\|[[:space:]]*[0-9]+[[:space:]]*\(current\)' "$security" | head -n1 | sed -E 's/^\|[[:space:]]*([0-9]+).*/\1/')
# CHANGELOG.md: the first "## ENGINE_VERSION <n>" heading
cv=$(grep -E '^##[[:space:]]+ENGINE_VERSION[[:space:]]+[0-9]+' "$changelog" | head -n1 | sed -E 's/^##[[:space:]]+ENGINE_VERSION[[:space:]]+([0-9]+).*/\1/')

for pair in "engine:$ev" "TRUST-MODEL.md:$sv" "CHANGELOG.md:$cv"; do
	case "$pair" in *:) echo "DRIFT: could not read a version from ${pair%:*}" >&2; fail=1 ;; esac
done

if [ "$fail" = 0 ] && { [ "$ev" != "$sv" ] || [ "$ev" != "$cv" ]; }; then
	echo "DRIFT: ENGINE_VERSION mismatch - engine=$ev TRUST-MODEL.md=$sv CHANGELOG.md=$cv" >&2
	fail=1
fi
[ "$fail" = 0 ] && echo "version: ENGINE_VERSION=$ev (engine == TRUST-MODEL.md == CHANGELOG.md)"

# 2. every cfg <key> the engine reads is documented in INTERFACES.md §5 ------
# §5 config block = from "## 5." up to the next "## " heading.
sec5=$(awk '/^##[[:space:]]+5\./{on=1;next} on&&/^##[[:space:]]/{exit} on{print}' "$interfaces")

# distinct keys read via cfg (`cfg <key>` at a word boundary)
keys=$(grep -oE 'cfg[[:space:]]+[a-z_][a-z0-9_]*' "$engine" | awk '{print $2}' | sort -u)

for k in $keys; do
	# §5 documents a key as a line beginning "<key>="
	if ! printf '%s\n' "$sec5" | grep -qE "^$k=" ; then
		echo "DRIFT: engine reads 'cfg $k' but docs/INTERFACES.md §5 does not document '$k='" >&2
		fail=1
	fi
done
[ "$fail" = 0 ] && echo "config: all engine cfg keys documented in INTERFACES.md §5"

[ "$fail" = 0 ] || { echo "--- doc-version-check: DRIFT found ---" >&2; exit 1; }
echo "OK"
