# Wiki source

This directory is the **source of truth** for the published GitHub Wiki at
`https://github.com/VD171/VDLiveUpdate/wiki` (the separate `VDLiveUpdate.wiki.git` repo).

Do **not** edit the wiki in the GitHub web UI. Any edit made there is overwritten on the next
push to `main`. Edit the sources here, in `wiki/`, instead. A workflow assembles the published
pages from this directory and pushes them to the wiki repo automatically.

## What gets published

The published wiki is **generated**: each page body stored here is wrapped with a language
switcher and a separator, and three navigation pages are produced from scratch. The pieces are:

- a per-page `**Languages:** ...` switcher line, then a blank line, `---`, and a blank line,
- the page body (stored here),
- `_Sidebar.md` (curated navigation, copied verbatim from this directory),
- `_Footer.md` (global attribution, generated),
- `Languages.md` (index of all languages, generated).

`_Footer.md` and `Languages.md` are **100% generated** and are not stored here. `_Sidebar.md`
**is** stored here because its navigation is curated.

## Layout

```
wiki/
  <Page>.md          English page bodies (no switcher, no footer)
  <lang>/<Page>.md   translated page bodies, one subdir per language
  _Sidebar.md        curated navigation (copied verbatim to the wiki)
  README.md          this file (not published)
```

### Pages (11)

`Home`, `Architecture`, `Engine`, `Producer`, `WebUI`, `Security-and-Trust-Model`,
`Feed-Format`, `Reboot-Handling`, `Quick-Start`, `FAQ`, `Contributing`.

### Languages (22)

English (`en`, stored at the top level) plus 21 translations, each in its own subdirectory:
`ar` العربية, `cs` Čeština, `de` Deutsch, `es` Español, `fa` فارسی, `fr` Français, `hi` हिन्दी,
`id` Bahasa Indonesia, `it` Italiano, `ja` 日本語, `ko` 한국어, `nl` Nederlands, `pl` Polski,
`pt` Português, `ru` Русский, `sv` Svenska, `th` ไทย, `tr` Türkçe, `uk` Українська,
`vi` Tiếng Việt, `zh` 中文.

Only the body is stored. The switcher and separator are added by the generator, so a stored body
starts directly with the page content (its `#` heading).

## Edit or add a page

1. **Edit an existing page:** change the body file, e.g. `wiki/Engine.md` (English) or
   `wiki/pt/Engine.md` (Portuguese). Do not add a `**Languages:**` line or a `---` separator; the
   generator adds them.
2. **Add a translation** of an existing page: create `wiki/<lang>/<Page>.md` for one of the 22
   languages already listed.
3. **Add a brand-new page** (a new topic): add the body to `wiki/<Page>.md` for English **and** to
   `wiki/<lang>/<Page>.md` for every language, then add the page name to the `PAGES` list in
   `.github/scripts/gen_wiki.sh` and, if it belongs in the navigation, to `wiki/_Sidebar.md`. The
   generator requires a body file for every page in every language and fails if one is missing.
4. **Add a new language:** create `wiki/<lang>/<Page>.md` for every page, then add the
   `<code> <endonym>` pair to the `LANGS` block in `.github/scripts/gen_wiki.sh` (English stays
   first; keep the existing order for the rest).
5. Run the generator locally and the fidelity check (below) before committing.

## Generate locally

`gen_wiki.sh <wiki-src-dir> <wiki-clone-dir>` reads this directory and writes the fully assembled
published pages into the output directory:

```sh
mkdir -p /tmp/wiki-out
sh .github/scripts/gen_wiki.sh wiki /tmp/wiki-out
```

The output in `/tmp/wiki-out` is exactly what gets pushed to the wiki repo.

## Fidelity check

To prove the generator reproduces the live wiki with zero churn, generate into a fresh directory
and diff against a clone of the published wiki:

```sh
git clone --depth 1 https://github.com/VD171/VDLiveUpdate.wiki.git /tmp/wiki-current
rm -rf /tmp/wiki-out && mkdir -p /tmp/wiki-out
sh .github/scripts/gen_wiki.sh wiki /tmp/wiki-out
diff -r --exclude=.git /tmp/wiki-current /tmp/wiki-out && echo "OK: identical"
```

An empty diff means the sources and the generator match the published wiki exactly. Run this after
editing any body, after touching the generator, and whenever you want to confirm the next automatic
sync will be a no-op.

## Automatic publishing

`.github/workflows/wiki-sync.yml` runs on **every push to `main`** (and on manual
`workflow_dispatch`). It checks out the repo, clones `VDLiveUpdate.wiki.git`, runs
`gen_wiki.sh wiki wiki-clone`, stages the result, and commits/pushes **only if something changed**
(`git diff --cached --quiet` guard). An unchanged wiki produces no commit, so pushing to `main`
without touching `wiki/` is a cheap no-op. The commit is authored by `github-actions[bot]` with
message `wiki: sync @ <sha>`. A `concurrency` group serializes runs so two pushes cannot race.

## Bootstrap and recovery

The GitHub Wiki is a separate git repo (`VDLiveUpdate.wiki.git`) that does not exist until the wiki
is initialized. **Before the first sync run**, create any one page in the wiki web UI once (for
example save an empty `Home`), otherwise `git clone` of the wiki repo fails and the workflow errors.

To recreate the whole wiki from scratch (for example after accidental deletion):

1. In the GitHub web UI, create any one wiki page so `VDLiveUpdate.wiki.git` exists.
2. Trigger the workflow from the Actions tab (`workflow_dispatch`), or push any commit to `main`.

The workflow regenerates all 245 published pages from this directory. Because the sources here are
the single source of truth, nothing needs to be re-typed in the web UI.
