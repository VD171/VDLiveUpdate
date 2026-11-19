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
# webui-parity.sh - guard the single source of the VDLU WebUI widget.
#
# vdlu.js / vdlu.css have ONE canonical copy: VDLiveUpdate/webui/. Every module
# that embeds the widget re-vendors that copy byte-for-byte, never edits its own
# in place. This finds every embedded copy in the sibling source tree and flags
# any that drift, so a stale widget is caught, not shipped. Only vdlu.js/css are
# compared; the keyring is "verify, do not copy" and is never touched here.
#
#   tools/webui-parity.sh         report; exit 1 on any drift
#   tools/webui-parity.sh --fix   re-vendor every drifted copy from canonical
#
# Discovery is dynamic (no hardcoded module names): scans the parent of this repo.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
canon_dir="$here/webui"
search_root=$(CDPATH= cd -- "$here/.." && pwd)
fix=0
[ "${1:-}" = "--fix" ] && fix=1

drift=$(mktemp "${TMPDIR:-/tmp}/vdlu-parity.XXXXXX") || exit 2
trap 'rm -f "$drift"' EXIT

for name in vdlu.js vdlu.css; do
  canon="$canon_dir/$name"
  if [ ! -f "$canon" ]; then
    echo "MISSING canonical: $canon" >&2
    echo x >> "$drift"
    continue
  fi
  canon_sum=$(md5sum "$canon" | cut -d' ' -f1)
  find "$search_root" -name .git -prune -o -type f -name "$name" -print 2>/dev/null \
  | while IFS= read -r copy; do
      [ "$copy" = "$canon" ] && continue
      rel=${copy#"$search_root"/}
      if [ "$(md5sum "$copy" | cut -d' ' -f1)" = "$canon_sum" ]; then
        echo "OK    $rel"
      elif [ "$fix" = 1 ]; then
        cp -- "$canon" "$copy" && echo "FIXED $rel  (re-vendored from canonical)"
      else
        echo "DRIFT $rel"
        echo x >> "$drift"
      fi
    done
done

if [ -s "$drift" ]; then
  echo "--- vdlu webui widget: DRIFT found (run with --fix to re-vendor) ---" >&2
  exit 1
fi
echo "--- vdlu webui widget: all copies match canonical ---"
