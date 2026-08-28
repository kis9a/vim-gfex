# vim-gfex

`gf` that reads the line before it reads the cursor.

The builtin `gf` only looks at the file name under *or after* the cursor,
cut out according to `'isfname'`. In notes and index files the path is usually
somewhere else on the line — and worse, the token the cursor happens to be on
may exist in `'path'`, so `gf` succeeds and opens the wrong file:

```
2    a    ~/dev/foo/README.md      " cursor at 'a' -> opens ./a if it exists
資料: ~/dev/foo/README.md          " cursor at 資 -> <cfile> is 資料
| [docs/](./docs/) | 一式（[概要](./docs/overview.md)） |
```

vim-gfex recognises the syntax of the line first, and only delegates to the
builtin command when it has nothing to say.

## Installation

Use your favorite plugin manager.

Example: [vim-plug](https://github.com/junegunn/vim-plug)

```vim
Plug 'kis9a/vim-gfex'
```

Requires Vim 8.0+ or Neovim 0.5+. No external commands, no other plugins.

## Features

- **Reads the line, not just the cursor** — markdown links, `label: path`, and
  a single existing path anywhere on the line.
- **Cursor anywhere inside a markdown link works**, including several links in
  one table row.
- **Link target beats link text.** In `[README.md](./docs/README.md)` the
  parenthesised target wins, which is what `<cfile>` gets wrong.
- **Recognised means committed.** Once gfex has a target it never hands the
  line back to the builtin, which would re-search from the cursor and open a
  decoy sitting in `'path'`.
- **Never creates a file by guessing.** The line-scanning layer only accepts
  paths that already exist.
- **Silent inside fenced code blocks** (` ``` ` and `~~~`), where `"key":
  "value"` would otherwise look exactly like a path.
- **`'path'`, `'suffixesadd'` and counts still work.** `2gf` still means "the
  second match in `'path'`", and a relative target that is not next to the
  current file is looked up with `findfile()`.
- **Japanese file names are supported** where the syntax is explicit, and
  Japanese prose does not produce garbage buffers.
- **Buffer-local, opt-in, and polite** — it never touches a key you have
  already mapped buffer-locally (a global `gf` in your vimrc is shadowed, as
  a buffer-local mapping should be).

## Usage

### Decision order

| tier | condition | result |
| --- | --- | --- |
| -1 | inside a fenced code block | no opinion |
| 0 | a count was given | builtin, unchanged |
| 1 | the cursor is inside a markdown link | that link's target |
| 2 | the line has exactly one markdown link | that target |
| 3 | the line reads `<label>: <target>`, target is path shaped | that target |
| 4 | `'isfname'` picks a path-shaped `<cfile>` | that |
| 5 | exactly one path on the line that exists | that |
| 6 | anything else | no opinion |

"No opinion" runs the builtin `gf` / `gF` / `<C-w>f` / `<C-w>gf` unchanged.

Links inside inline code spans (`` `[a](b.md)` ``) are ignored so that a
document explaining markdown syntax is not a minefield. tier 3 deliberately
does not do that, so ``see: `README.md` `` keeps working.

### Mappings

For every filetype in `g:gfex_filetypes` (default `['markdown']`), gfex maps
buffer-locally, checking each key individually and skipping any key you have
already mapped:

| key | `<Plug>` |
| --- | --- |
| `gf` | `<Plug>(gfex-edit)` |
| `gF` | `<Plug>(gfex-line)` |
| `<C-w>f` | `<Plug>(gfex-split)` |
| `<C-w>gf` | `<Plug>(gfex-tab)` |

Also available: `<Plug>(gfex-split-line)` (`<C-w>F`) and
`<Plug>(gfex-tab-line)` (`<C-w>gF`).

Normal mode only — Visual `gf` already takes the selection literally, which
covers file names with spaces.

### Functions

#### `gfex#find({editcmd})`

Run gfex for `'gf'`, `'gF'`, `"\<C-w>f"`, `"\<C-w>F"`, `"\<C-w>gf"` or
`"\<C-w>gF"`. It reads `v:count`, so call it from a mapping beginning with
`:<C-U>` (the `<Plug>` mappings do).

#### `gfex#target()`

What gfex *would* do, with no side effects:

```vim
:echo gfex#target()
{'kind': 'recognized', 'tier': 1, 'target': './docs/overview.md',
 'path': '/home/me/notes/docs/overview.md', 'found': 1,
 'create_ok': 1, 'reason': 'markdown link under the cursor'}
```

#### `gfex#map_buffer()` / `gfex#unmap_buffer()`

Add or remove the buffer-local mappings — call `map_buffer()` from your own
ftplugin to enable gfex for a filetype by hand.

### Options

| option | default | meaning |
| --- | --- | --- |
| `g:gfex_filetypes` | `['markdown']` | filetypes that get the mappings; `[]` for none |
| `g:gfex_create` | `'syntax'` | `'syntax'`: tiers 1–4 may open a new buffer / `'never'`: never |
| `g:gfex_url` | `'error'` | `'error'`: report and stop / `'edit'`: `:edit <url>` — see the warning below |
| `g:gfex_base` | `'file'` | base for relative targets: `'file'` = `expand('%:p:h')` / `'cwd'` |
| `g:gfex_scan_line` | `1` | enable tier 5 (one existing path on the line) |

`g:no_plugin_maps` and `g:no_gfex_maps` disable all mappings.

> **`g:gfex_url = 'edit'` trusts every URL in every file of an enabled
> filetype.** The scheme comes from the document and netrw shells out to the
> matching transfer tool, so `scp://`, `ssh://`, `rcp://` and `dav://` reach an
> address the document chose — possibly with a credential prompt. Enable it
> only for documents you would run commands from.

A target containing a backtick or a glob wildcard is never resolved: Vim's
`expand()` runs backticks through the shell, so a `~/…` or `$VAR/…` path
carrying one would execute a command from the file you are reading.

## Creating files, and how often that misfires

With the default `g:gfex_create = 'syntax'`, a target recognised by tiers 1–4
opens a **new, unwritten buffer** when the file does not exist. Nothing
reaches the disk until you `:write`. That is how you follow a link to a note
you have not written yet — but it does misfire, and you should know where.

Measured over 196 files / 85,295 non-blank lines of real notes:

```
tier 1/2 markdown link : EXIST 64 / MISSING  5  -> miss rate  7%
tier 3 "label: target" : EXIST 80 / MISSING 37  -> miss rate 31%
tier 5 line scan       : existence required     -> miss rate  0%
lines gfex never touches                        ->           81%
```

- **tier 3 is the noisy one, at 31%.** The cost is structural: ``see:
  `README.md` `` has to keep working, so tier 3 cannot ignore inline code
  spans — and that is where most of its misses come from: lines like
  ``example: `config/agents/worker.md` `` that describe a path rather than
  point at one.
- A typo (`RAEDME.md`), or a configuration example written **outside** a code
  fence, will open an empty buffer.
- Fenced code blocks (` ``` ` and `~~~`) are excluded entirely, because
  `"key": "value"` in JSON or YAML is exactly the tier 3 syntax.
- tier 5 never creates anything, under any setting.

To turn creation off completely:

```vim
let g:gfex_create = 'never'
```

A recognised but missing target then reports
`E447: Can't find file "..." in path` and stops. It does **not** fall back to
the builtin `gf`, because that would re-search from the cursor and open
whatever happens to match there.

## Configuration

### Key mappings (example)

Use gfex for markdown only (the default needs no configuration):

```vim
let g:gfex_filetypes = ['markdown']
```

Add more filetypes:

```vim
let g:gfex_filetypes = ['markdown', 'text', 'gitcommit']
```

> markdown is mapped from `after/ftplugin/markdown.vim`, which always runs
> after the runtime ftplugin. Other filetypes are mapped from a `FileType`
> autocommand, whose ordering is not guaranteed; if that filetype's ftplugin
> *assigns* `b:undo_ftplugin` the mapping can be dropped.

Map it yourself instead:

```vim
let g:gfex_filetypes = []
augroup my_gfex
  autocmd!
  autocmd FileType markdown,text nmap <buffer> gf <Plug>(gfex-edit)
augroup END
```

## Non goals

Windows paths, a full markdown parser, guessing extension-less names
(`Makefile`) from a line, scoring several candidates, Visual mode, a handler
registration framework, creating files from the line scan, and opening URLs in
a browser.

## Development

```sh
make deps        # clone pinned vim-themis / vim-vimlparser / vim-vimlint
make lint        # vimlint
make lint-vint   # vint
make test        # vim-themis, Vim and Neovim
```

## Architecture

vim-gfex follows the
[vimplugin-cookbook](https://github.com/kis9a/vimplugin-cookbook)
architecture:

- **plugin/gfex.vim** — options, `<Plug>` mappings, `FileType` autocommand
- **after/ftplugin/markdown.vim** — ordering-safe mapping for markdown
- **autoload/gfex.vim** — public API
- **autoload/gfex/core.vim** — tier decision (pure)
- **autoload/gfex/path.vim** — path vocabulary (pure)
- **autoload/gfex/markdown.vim** — markdown scanning (pure, plus fence lookup)
- **autoload/gfex/resolve.vim** — target → absolute path
- **autoload/gfex/open.vim** — `:edit` / `:split`, builtin delegation, errors

`core#decide()` receives the line, the column, `<cfile>` and the fence flag as
arguments, so it never touches a buffer, the filesystem or `'path'`. There is
no `deps/` layer (no external dependencies) and no `compat/` layer: the
`gf` behaviour of Vim and Neovim is identical, only option defaults differ,
and the tests pin those explicitly.

See `:help gfex` for details.

## License

MIT
