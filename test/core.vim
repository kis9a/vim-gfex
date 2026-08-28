scriptencoding utf-8
" test/core.vim - unit tests for gfex#core#decide (pure; cfile/fence/exists
" are all injected, so no buffer and no filesystem is touched)

let s:suite = themis#suite('core')
let s:assert = themis#helper('assert')

let s:existing = []

function! GfexCoreTestExists(target) abort
  return index(s:existing, a:target) >= 0
endfunction

function! s:decide(line, col, cfile, fence) abort
  return gfex#core#decide(a:line, a:col, a:cfile, a:fence,
        \ {'scan_line': 1, 'exists': 'GfexCoreTestExists'})
endfunction

function! s:suite.before_each() abort
  let s:existing = []
endfunction

function! s:assert_hit(d, tier, target) abort
  call s:assert.equals(
        \ [a:d.kind, a:d.tier, a:d.target],
        \ ['recognized', a:tier, a:target])
endfunction

function! s:assert_none(d) abort
  call s:assert.equals([a:d.kind, a:d.target], ['no_opinion', ''])
endfunction

" ===========================================================================

function! s:suite.C01_decoy_line_scan_finds_the_real_path() abort
  let s:existing = ['~/dev/foo/README.md']
  let l:d = s:decide('2    a    ~/dev/foo/README.md', 1, '2', 0)
  call s:assert_hit(l:d, 5, '~/dev/foo/README.md')
  call s:assert.equals(l:d.create_ok, 0)
endfunction

function! s:suite.C02_cursor_on_the_path_uses_tier4() abort
  let l:d = s:decide('2    a    ~/dev/foo/README.md', 11, '~/dev/foo/README.md', 0)
  call s:assert_hit(l:d, 4, '~/dev/foo/README.md')
  call s:assert.equals(l:d.create_ok, 1)
endfunction

function! s:suite.C03_japanese_label() abort
  call s:assert_hit(s:decide('資料: ~/dev/foo/README.md', 1, '資料', 0),
        \ 3, '~/dev/foo/README.md')
endfunction

function! s:suite.C04_label_with_plain_name() abort
  call s:assert_hit(s:decide('関連メモ: NOTES.md', 1, '関連メモ', 0),
        \ 3, 'NOTES.md')
endfunction

function! s:suite.C05_label_with_url() abort
  let l:d = s:decide('参考資料: https://example.com/x', 1, '参考資料', 0)
  call s:assert_hit(l:d, 3, 'https://example.com/x')
  call s:assert.equals(l:d.create_ok, 0)
endfunction

function! s:suite.C06_japanese_prose_with_a_date() abort
  call s:assert_none(s:decide('* 定例 (次回: 2026/10/08, 第2会議室)', 3, '定例', 0))
endfunction

function! s:suite.C07_label_with_two_targets_falls_through() abort
  " The remainder contains a space, so it is not a strong path (M3).
  let l:d = s:decide('関連: README.md SPEC.md', 1, '関連', 0)
  call s:assert.not_equals(l:d.tier, 3)
endfunction

function! s:suite.C08_cfile_wins_when_tier3_fails() abort
  call s:assert_hit(s:decide('関連: README.md SPEC.md', 17, 'SPEC.md', 0), 4, 'SPEC.md')
endfunction

function! s:suite.C09_bare_words_are_no_opinion() abort
  call s:assert_none(s:decide('2    a    foo', 1, '2', 0))
endfunction

function! s:suite.C10_makefile_is_not_guessed() abort
  call s:assert_none(s:decide('build target Makefile', 1, 'build', 0))
endfunction

function! s:suite.C11_url_after_label_is_not_a_local_file() abort
  let l:d = s:decide('参考: https://example.com/README.md', 1, '参考', 0)
  call s:assert_hit(l:d, 3, 'https://example.com/README.md')
  call s:assert.equals(gfex#path#is_url(l:d.target), 1)
endfunction

function! s:suite.C12_blank_and_symbol_only_lines() abort
  call s:assert_none(s:decide('', 1, '', 0))
  call s:assert_none(s:decide('----', 1, '', 0))
endfunction

function! s:suite.C13_io_slash_is_not_a_path() abort
  call s:assert_none(s:decide('I/O は安全に扱い、順序も保つ', 1, 'I/O', 0))
endfunction

function! s:suite.C14_two_links_outside_both() abort
  let s:existing = []
  let l:d = s:decide('[a](x.md) と [b](y.md)', 11, '', 0)
  call s:assert.not_equals(l:d.tier, 2)
  call s:assert_none(l:d)
endfunction

function! s:suite.C15_fence_suppresses_everything() abort
  call s:assert.equals(s:decide('[a](./x.md)', 3, '', 1).tier, -1)
  call s:assert_none(s:decide('[a](./x.md)', 3, '', 1))
  call s:assert_none(s:decide('~/dev/foo/README.md', 1, '~/dev/foo/README.md', 1))
endfunction

function! s:suite.C16_json_inside_fence() abort
  call s:assert_none(s:decide('  "path": "src/main.vim",', 3, 'path', 1))
endfunction

function! s:suite.C17_json_outside_fence_fires() abort
  call s:assert_hit(s:decide('  "path": "src/main.vim",', 3, 'path', 0), 3, 'src/main.vim')
endfunction

function! s:suite.C18_label_containing_brackets_is_not_tier3() abort
  let l:d = s:decide('- [GitHub: foo/bar](https://x)', 25, '', 0)
  call s:assert.not_equals(l:d.tier, 3)
endfunction

function! s:suite.C19_prose_with_a_relative_path() abort
  let s:existing = ['docs/a.md']
  call s:assert_hit(s:decide('詳細は docs/a.md を参照', 1, '詳細は', 0), 5, 'docs/a.md')
endfunction

function! s:suite.C20_scan_line_option_off() abort
  let s:existing = ['docs/a.md']
  let l:d = gfex#core#decide('詳細は docs/a.md を参照', 1, '詳細は', 0,
        \ {'scan_line': 0, 'exists': 'GfexCoreTestExists'})
  call s:assert_none(l:d)
endfunction

function! s:suite.C21_tier5_needs_exactly_one_hit() abort
  let s:existing = ['docs/a.md', 'docs/b.md']
  call s:assert_none(s:decide('see docs/a.md and docs/b.md', 1, 'see', 0))
endfunction

function! s:suite.G09_cfile_injection_is_stable() abort
  " Whatever 'isfname' produced, core only ever looks at the injected value.
  call s:assert_none(s:decide('資料', 1, '資料', 0))
  call s:assert_hit(s:decide('資料', 1, './調査/設計メモ.md', 0), 4, './調査/設計メモ.md')
endfunction
