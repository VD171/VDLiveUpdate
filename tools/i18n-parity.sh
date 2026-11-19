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
# i18n-parity.sh - assert every WebUI translation defines the SAME key set.
#
# Each webui/i18n/<lang>.js must carry exactly the key set of the English base.
# The base is webui/i18n/en.js if present, else the DEFAULT_I18N object in
# webui/vdlu.js. Any drift (a missing or an extra key in any translation) is an
# error: the offending file is printed with its missing/extra keys and the tool
# exits 1. No drift -> "OK" and exit 0.
#
#   tools/i18n-parity.sh
#
# Pure POSIX sh + awk; no node, no jq.

set -u

here=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
i18n_dir="$here/webui/i18n"
vdlu_js="$here/webui/vdlu.js"

# extract_keys <file> <open-regex>: print the sorted, unique key set of the
# first object literal opened on a line matching <open-regex>. The scan is
# quote-aware (handles \' and \\ inside single-quoted values) so a ':' or a
# brace inside a string value is never mistaken for structure.
extract_keys() {
  awk -v re="$2" '
    BEGIN { seen = 0; depth = 0; instr = 0; esc = 0; tok = ""; SQ = sprintf("%c", 39) }
    !seen {
      if ($0 ~ re) {
        p = index($0, "{")
        if (p == 0) next
        seen = 1
        $0 = substr($0, p)
      } else next
    }
    {
      n = length($0)
      for (j = 1; j <= n; j++) {
        c = substr($0, j, 1)
        if (instr) {
          if (esc) esc = 0
          else if (c == "\\") esc = 1
          else if (c == SQ) instr = 0
          continue
        }
        if (c == SQ) { instr = 1; tok = ""; continue }
        if (c == "{") { depth++; tok = ""; continue }
        if (c == "}") { depth--; tok = ""; if (depth <= 0) exit; continue }
        if (c ~ /[A-Za-z0-9_]/) { tok = tok c; continue }
        if (c == ":") { if (depth == 1 && tok != "") print tok; tok = ""; continue }
        if (c == " " || c == "\t") continue
        tok = ""
      }
    }
  ' "$1" | sort -u
}

if [ -f "$i18n_dir/en.js" ]; then
  base_file="$i18n_dir/en.js"
  base_re='VDLU_I18N[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[{]'
else
  base_file="$vdlu_js"
  base_re='DEFAULT_I18N[[:space:]]*=[[:space:]]*[{]'
fi

if [ ! -f "$base_file" ]; then
  echo "MISSING base: $base_file" >&2
  exit 2
fi

tmpd=$(mktemp -d "${TMPDIR:-/tmp}/vdlu-i18n.XXXXXX") || exit 2
trap 'rm -rf "$tmpd"' EXIT

extract_keys "$base_file" "$base_re" > "$tmpd/base"
if [ ! -s "$tmpd/base" ]; then
  echo "MISSING base keys: could not extract any key from $base_file" >&2
  exit 2
fi

tr_re='VDLU_I18N[A-Za-z0-9_]*[[:space:]]*=[[:space:]]*[{]'
drift=0

for f in "$i18n_dir"/*.js; do
  [ -f "$f" ] || continue
  [ "$f" = "$base_file" ] && continue
  rel=${f#"$here"/}
  extract_keys "$f" "$tr_re" > "$tmpd/cur"
  missing=$(comm -23 "$tmpd/base" "$tmpd/cur")
  extra=$(comm -13 "$tmpd/base" "$tmpd/cur")
  if [ -n "$missing" ] || [ -n "$extra" ]; then
    drift=1
    echo "DRIFT $rel"
    [ -n "$missing" ] && echo "$missing" | sed 's/^/    missing: /'
    [ -n "$extra" ] && echo "$extra" | sed 's/^/    extra:   /'
  fi
done

if [ "$drift" = 1 ]; then
  echo "--- vdlu i18n: key-set DRIFT found ---" >&2
  exit 1
fi
echo "OK"
