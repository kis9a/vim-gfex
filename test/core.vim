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

function! s:suite.C11b_url_under_the_cursor_is_recognised_not_delegated() abort
  " MT1 of the monkey run: left to the builtin, a bare URL under the cursor
  " becomes a buffer named after it - g:gfex_url never gets a say.
  let l:d = s:decide('https://example.com/README.md を参照', 1,
        \ 'https://example.com/README.md', 0)
  call s:assert_hit(l:d, 4, 'https://example.com/README.md')
  call s:assert.equals([l:d.create_ok, gfex#path#is_url(l:d.target)], [0, 1])

  " '//cdn/x.js' is a URL by the same rule, and gets the same exit.
  call s:assert_hit(s:decide('see //cdn/x.js', 5, '//cdn/x.js', 0),
        \ 4, '//cdn/x.js')
endfunction

function! s:suite.C11c_a_url_after_a_label_stops_at_the_first_blank() abort
  " Everything after ': ' is one token, but a URL cannot contain a space:
  " the prose behind it is not part of the target.
  let l:d = s:decide('参考: https://example.com/a.md ほか2件', 1, '参考', 0)
  call s:assert_hit(l:d, 3, 'https://example.com/a.md')
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

" The core ordering rule (V6e): a markdown link is examined before <cfile>,
" because the link text is often a file name too.  Inverting tiers 1/2 and 4
" used to break nothing in this suite.
function! s:suite.C22_link_under_cursor_beats_cfile() abort
  let l:d = s:decide('[profile.md](./docs/real.md)', 3, 'profile.md', 0)
  call s:assert_hit(l:d, 1, './docs/real.md')
endfunction

function! s:suite.C23_sole_link_beats_cfile() abort
  " Cursor is outside the link, on a path-shaped word; the link still wins.
  let l:d = s:decide('see NOTES.md or [doc](./docs/real.md)', 5, 'NOTES.md', 0)
  call s:assert_hit(l:d, 2, './docs/real.md')
endfunction

function! s:suite.C24_tier3_may_create_but_tier5_may_not() abort
  call s:assert.equals(s:decide('資料: ./docs/new.md', 1, '資料', 0).create_ok, 1)
  let s:existing = ['./docs/here.md']
  call s:assert.equals(s:decide('see ./docs/here.md now', 1, 'see', 0).create_ok, 0)
endfunction

function! s:suite.C18b_bracketed_label_without_a_link() abort
  " Without the bracket rule the label '[a' would be accepted and tier3
  " would open docs/x.md from a line that is really a broken link.
  call s:assert.not_equals(s:decide('[a: docs/x.md]', 1, '', 0).tier, 3)
endfunction

function! s:suite.C25_full_width_colon_needs_no_space() abort
  call s:assert_hit(s:decide('資料：~/a.md', 1, '資料', 0), 3, '~/a.md')
  call s:assert_hit(s:decide('資料： ~/a.md', 1, '資料', 0), 3, '~/a.md')
  " An ASCII colon still requires one, which is what keeps http:// out.
  call s:assert.not_equals(s:decide('a:b.md', 1, '', 0).tier, 3)
endfunction

function! s:suite.C26_scan_line_option_is_wired_through_options() abort
  let g:gfex_scan_line = 0
  try
    call s:assert.equals(gfex#core#options().scan_line, 0)
  finally
    let g:gfex_scan_line = 1
  endtry
  call s:assert.equals(gfex#core#options().scan_line, 1)
endfunction

function! s:suite.C27_option_reader_ignores_non_string_values() abort
  " Vim compares a Number to a String by converting the String, so 0 would
  " equal every option value and invert the setting.
  let g:gfex_test_opt = 0
  try
    " 0 reads as the off setting, which is what `let g:x = 0` means.
    call s:assert.equals(gfex#core#opt('gfex_test_opt', 'syntax', 'never'), 'never')
    let g:gfex_test_opt = 1
    call s:assert.equals(gfex#core#opt('gfex_test_opt', 'syntax', 'never'), 'syntax')
    let g:gfex_test_opt = ['x']
    call s:assert.equals(gfex#core#opt('gfex_test_opt', 'error', 'error'), 'error')
    let g:gfex_test_opt = 'edit'
    call s:assert.equals(gfex#core#opt('gfex_test_opt', 'error', 'error'), 'edit')
  finally
    unlet! g:gfex_test_opt
  endtry
endfunction
