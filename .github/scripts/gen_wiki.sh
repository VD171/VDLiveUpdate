#!/usr/bin/env bash
# ======================================================================
#  VDLiveUpdate (VDLU)  ::  flashless, incremental module updates
#  Curated standalone wiki generator for the VDLiveUpdate docs model.
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
# vendor-parity: standalone - curated VDLiveUpdate wiki model, intentionally NOT the fleet
# canonical (VD-ModuleKit tooling/gen_wiki.sh); different CLI and layout by design.
#
# gen_wiki.sh <wiki-src-dir> <wiki-clone-dir>
#
# Assemble the published VDLiveUpdate wiki from the repo-managed source in
# <wiki-src-dir> and write it into <wiki-clone-dir>. For every content page in
# every language it prepends the "**Languages:**" switcher and the "---"
# separator to the stored body, then emits the generated _Sidebar.md (curated
# source, copied), _Footer.md and Languages.md. The output must reproduce the
# published wiki byte for byte.
#
# Source layout: EN at <src>/<Page>.md, translations at <src>/<lang>/<Page>.md,
# curated sidebar at <src>/_Sidebar.md. README.md in the source is ignored.
set -eu

SRC=${1:?usage: gen_wiki.sh <wiki-src-dir> <wiki-clone-dir>}
OUT=${2:?usage: gen_wiki.sh <wiki-src-dir> <wiki-clone-dir>}

# Content pages, in sidebar order is not required; publish order is irrelevant.
PAGES="Home Architecture Engine Producer WebUI Security-and-Trust-Model Feed-Format Reboot-Handling Quick-Start FAQ Contributing"

# Languages: "<code> <endonym>", EN first. The endonym may contain spaces, so
# the code is the first field and the endonym is the remainder of the line.
LANGS='en English
ar العربية
cs Čeština
de Deutsch
es Español
fa فارسی
fr Français
hi हिन्दी
id Bahasa Indonesia
it Italiano
ja 日本語
ko 한국어
nl Nederlands
pl Polski
pt Português
ru Русский
sv Svenska
th ไทย
tr Türkçe
uk Українська
vi Tiếng Việt
zh 中文'

# target <code> <page> -> published page name the switcher links to.
target() {
	if [ "$1" = en ]; then
		printf '%s' "$2"
	else
		printf '%s-%s' "$1" "$2"
	fi
}

# switcher <page> <current-code> -> the "**Languages:**" line for that page.
switcher() {
	_page=$1
	_cur=$2
	_out="**Languages:**"
	_sep=" "
	while read -r _code _endo; do
		[ -n "$_code" ] || continue
		if [ "$_code" = "$_cur" ]; then
			_item=$_endo
		else
			_item="[$_endo]($(target "$_code" "$_page"))"
		fi
		_out="$_out$_sep$_item"
		_sep=" | "
	done <<EOF
$LANGS
EOF
	printf '%s' "$_out"
}

[ -d "$SRC" ] || { echo "gen_wiki: source dir not found: $SRC" >&2; exit 1; }
mkdir -p "$OUT"

# Content pages: switcher + separator + stored body.
_n=0
while read -r code _endo; do
	[ -n "$code" ] || continue
	for page in $PAGES; do
		if [ "$code" = en ]; then
			body="$SRC/$page.md"
			pub="$OUT/$page.md"
		else
			body="$SRC/$code/$page.md"
			pub="$OUT/$code-$page.md"
		fi
		[ -f "$body" ] || { echo "gen_wiki: missing body: $body" >&2; exit 1; }
		{
			switcher "$page" "$code"
			printf '\n\n---\n\n'
			cat "$body"
		} >"$pub"
		_n=$((_n + 1))
	done
done <<EOF
$LANGS
EOF

# Languages.md: one bullet per language, linking to its Home.
{
	printf '# Languages\n\n'
	while read -r code endo; do
		[ -n "$code" ] || continue
		printf -- '- [%s](%s)\n' "$endo" "$(target "$code" Home)"
	done <<EOF
$LANGS
EOF
} >"$OUT/Languages.md"

# _Footer.md: global attribution, one source of truth (applied by the wiki host
# to every rendered page).
printf '%s\n' '_Generated with Claude (Anthropic), maintained by VD171. Corrections and improvements welcome - see [[Contributing]]._ | [[Languages]]' >"$OUT/_Footer.md"

# _Sidebar.md: curated navigation, copied verbatim from source.
if [ -f "$SRC/_Sidebar.md" ]; then
	cat "$SRC/_Sidebar.md" >"$OUT/_Sidebar.md"
fi

echo "gen_wiki: wrote $_n content pages + Languages.md + _Footer.md + _Sidebar.md into $OUT"
