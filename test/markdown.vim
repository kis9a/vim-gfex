scriptencoding utf-8
" test/markdown.vim - unit tests for gfex#markdown#

let s:suite = themis#suite('markdown')
let s:assert = themis#helper('assert')

" A table row carrying several links, with multibyte text between them so
" that the byte columns are not the character columns.  Byte ranges:
"   [docs/](...)      3.. 18
"   [概要](...)      49.. 76
"   [設計](...)      80..105
"   [運用](...)     109..131
let s:TABLE_ROW = '| [docs/](./docs/) | ドキュメント一式（[概要](./docs/overview.md)・[設計](./docs/design.md)・[運用](./docs/ops.md)） |'

" ===========================================================================
" Link extraction
" ===========================================================================

function! s:suite.M01_plain_link() abort
  call s:assert.equals(gfex#markdown#at('[README](./README.md)', 3), './README.md')
endfunction

function! s:suite.M02_empty_text() abort
  call s:assert.equals(gfex#markdown#at('[](./README.md)', 3), './README.md')
endfunction

function! s:suite.M03_fragment_stripped() abort
  call s:assert.equals(gfex#markdown#at('[README](./README.md#usage)', 3), './README.md')
endfunction

function! s:suite.M04_image_link() abort
  call s:assert.equals(gfex#markdown#at('![alt](./img.png)', 3), './img.png')
endfunction

function! s:suite.M05_angle_bracket_with_space_rejected() abort
  call s:assert.equals(gfex#markdown#at('[a](<./foo bar.md>)', 2), '')
endfunction

function! s:suite.M06_title_stripped() abort
  call s:assert.equals(gfex#markdown#at('[a](README.md "title")', 2), 'README.md')
endfunction

function! s:suite.M07_table_row_cursor_in_first_link() abort
  call s:assert.equals(gfex#markdown#at(s:TABLE_ROW, 5), './docs/')
endfunction

function! s:suite.M08_table_row_cursor_in_second_link() abort
  call s:assert.equals(gfex#markdown#at(s:TABLE_ROW, 60), './docs/overview.md')
endfunction

function! s:suite.M09_table_row_cursor_in_third_link() abort
  call s:assert.equals(gfex#markdown#at(s:TABLE_ROW, 90), './docs/design.md')
endfunction

function! s:suite.M10_table_row_cursor_outside_links() abort
  call s:assert.equals(gfex#markdown#at(s:TABLE_ROW, 30), '')
  call s:assert.equals(len(gfex#markdown#all(s:TABLE_ROW)), 4)
endfunction

function! s:suite.M11_cursor_on_link_text_uses_target() abort
  " The link text itself looks like a path; the target must win.
  call s:assert.equals(
        \ gfex#markdown#at('[README.md](./docs/README.md)', 3),
        \ './docs/README.md')
endfunction

function! s:suite.M12_url_target() abort
  let l:t = gfex#markdown#at('[x](https://example.com/a.md)', 2)
  call s:assert.equals(l:t, 'https://example.com/a.md')
  call s:assert.equals(gfex#path#is_url(l:t), 1)
endfunction

function! s:suite.M13_japanese_filename_link() abort
  call s:assert.equals(
        \ gfex#markdown#at('[設計メモ](./資料/設計メモ.md)', 2),
        \ './資料/設計メモ.md')
endfunction

function! s:suite.M14_citation_note_is_not_a_target() abort
  let l:line = '- Smith 1978 [S20](本文未確認・二次資料経由): 主張の要約…'
  call s:assert.equals(gfex#markdown#at(l:line, 15), '')
  call s:assert.equals(gfex#markdown#all(l:line), [])
endfunction

function! s:suite.M15_link_inside_inline_code_ignored() abort
  let l:line = '理由: `[README.md](./docs/README.md)` でリンクテキスト側に'
  call s:assert.equals(gfex#markdown#at(l:line, 12), '')
  call s:assert.equals(gfex#markdown#all(l:line), [])
endfunction

function! s:suite.M16_link_form_documentation_ignored() abort
  let l:line = '- リンク形式: `[表示名](./ディレクトリ/ファイル名.md)`'
  call s:assert.equals(gfex#markdown#all(l:line), [])
endfunction

" ===========================================================================
" Inline code spans
" ===========================================================================

function! s:suite.S01_two_spans() abort
  let l:line = '例: `a.md` と `b.md`'
  let l:spans = gfex#markdown#code_spans(l:line)
  call s:assert.equals(len(l:spans), 2)
  call s:assert.equals(l:line[l:spans[0][0] : l:spans[0][1]], '`a.md`')
  call s:assert.equals(l:line[l:spans[1][0] : l:spans[1][1]], '`b.md`')
endfunction

function! s:suite.S02_odd_backticks_do_not_break() abort
  let l:spans = gfex#markdown#code_spans('a `b` c `d')
  call s:assert.equals(len(l:spans), 1)
  call s:assert.equals(gfex#markdown#code_spans('`'), [])
endfunction

" ===========================================================================
" Fence detection (reads a real buffer)
" ===========================================================================

function! s:suite.before_each() abort
  enew!
endfunction

function! s:suite.after_each() abort
  bwipeout!
endfunction

function! s:fill(lines) abort
  call setline(1, a:lines)
endfunction

function! s:suite.F01_backtick_fence() abort
  call s:fill(['plain ./a.md', '```json', '  "path": "src/main.vim",', '```', 'after ./b.md'])
  call s:assert.equals(gfex#markdown#in_fence(1), 0)
  call s:assert.equals(gfex#markdown#in_fence(2), 1)
  call s:assert.equals(gfex#markdown#in_fence(3), 1)
  call s:assert.equals(gfex#markdown#in_fence(4), 1)
  call s:assert.equals(gfex#markdown#in_fence(5), 0)
endfunction

function! s:suite.F02_tilde_fence() abort
  call s:fill(['head', '~~~yaml', 'root: ${GIT_ROOT}', '~~~', 'tail ./c.md'])
  call s:assert.equals(gfex#markdown#in_fence(1), 0)
  call s:assert.equals(gfex#markdown#in_fence(3), 1)
  call s:assert.equals(gfex#markdown#in_fence(5), 0)
endfunction

function! s:suite.F03_longer_fence_not_closed_by_shorter() abort
  call s:fill(['head', '````', 'a', '```', 'b', '````', 'tail'])
  call s:assert.equals(gfex#markdown#in_fence(3), 1)
  call s:assert.equals(gfex#markdown#in_fence(5), 1)
  call s:assert.equals(gfex#markdown#in_fence(7), 0)
endfunction

function! s:suite.F04_mixed_markers() abort
  call s:fill(['head', '```', 'a', '~~~', 'b', '```', 'tail'])
  call s:assert.equals(gfex#markdown#in_fence(3), 1)
  call s:assert.equals(gfex#markdown#in_fence(5), 1)
  call s:assert.equals(gfex#markdown#in_fence(7), 0)
endfunction

function! s:suite.F05_inline_code_is_not_a_fence() abort
  call s:fill(['`inline README.md` stays', 'x'])
  call s:assert.equals(gfex#markdown#in_fence(1), 0)
  call s:assert.equals(gfex#markdown#in_fence(2), 0)
endfunction

function! s:suite.F06_large_file_performance() abort
  let l:lines = []
  let l:i = 0
  while l:i < 30000
    if l:i % 140 == 0
      call add(l:lines, '```')
    else
      call add(l:lines, 'line ' . l:i)
    endif
    let l:i += 1
  endwhile
  call s:fill(l:lines)
  let l:t = reltime()
  let l:r = gfex#markdown#in_fence(30000)
  let l:elapsed = reltimefloat(reltime(l:t))
  call s:assert.true(l:r == 0 || l:r == 1)
  call s:assert.true(l:elapsed < 0.05, 'in_fence took ' . string(l:elapsed) . 's')
endfunction
