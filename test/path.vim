scriptencoding utf-8
" test/path.vim - unit tests for gfex#path# (pure, no fs / no buffer)

let s:suite = themis#suite('path')
let s:assert = themis#helper('assert')

" Compare as [input, value] pairs so a failure names the offending input.
function! s:eq(func, input, expected) abort
  call s:assert.equals([a:input, call(a:func, [a:input])], [a:input, a:expected])
endfunction

function! s:strong(func, inputs) abort
  for l:i in a:inputs
    call s:assert.equals([l:i, call(a:func, [l:i])], [l:i, l:i])
  endfor
endfunction

function! s:weak(func, inputs) abort
  for l:i in a:inputs
    call s:assert.equals([l:i, call(a:func, [l:i])], [l:i, ''])
  endfor
endfunction

" ===========================================================================
" candidate()  -- tier3 / tier5
" ===========================================================================

function! s:suite.P01_home_relative() abort
  call s:strong('gfex#path#candidate', ['~/dev/foo/README.md'])
endfunction

function! s:suite.P02_absolute() abort
  call s:strong('gfex#path#candidate', ['/Users/foo/dev/README.md'])
endfunction

function! s:suite.P03_dot_relative() abort
  call s:strong('gfex#path#candidate', ['./README.md', '../README.md', '../../docs/spec.md'])
endfunction

function! s:suite.P04_env_var_with_slash() abort
  call s:strong('gfex#path#candidate',
        \ ['$VIMRUNTIME/ftplugin/fortran.vim', '${GIT_ROOT}/src/a.vim', '$HOME/dev/x.md'])
endfunction

function! s:suite.P05_relative_with_slash_and_dot() abort
  call s:strong('gfex#path#candidate', ['docs/README.md', 'src/foo.c'])
endfunction

function! s:suite.P06_plain_name_with_extension() abort
  call s:strong('gfex#path#candidate', ['NOTES.md', 'config.json', '.vimrc'])
endfunction

function! s:suite.P07_bare_word_is_not_strong() abort
  call s:weak('gfex#path#candidate', ['a', 'foo', 'README', 'Makefile', '2'])
endfunction

function! s:suite.P08c_japanese_word_is_not_strong() abort
  call s:weak('gfex#path#candidate', ['資料', '作業', '見出し'])
endfunction

function! s:suite.P09_non_ascii_with_slash_is_not_strong() abort
  call s:weak('gfex#path#candidate', ['1000円/個', 'A4/横書き'])
endfunction

function! s:suite.P10_numeric_slash_segments() abort
  call s:weak('gfex#path#candidate', ['1/2', '7/8', '2026/10/08'])
endfunction

function! s:suite.P11_version_like() abort
  call s:weak('gfex#path#candidate', ['v1.2.3', '3.x', 'F1.4', '2.0'])
endfunction

function! s:suite.P12_hostname_like() abort
  call s:weak('gfex#path#candidate', ['example.com', 'example.dev', 'example.org'])
endfunction

function! s:suite.P13_hostname_with_path() abort
  call s:weak('gfex#path#candidate', ['example.com/foo.md'])
endfunction

function! s:suite.P14_slash_without_dot() abort
  call s:weak('gfex#path#candidate', ['I/O', 'KYC/AML', 'TypeScript/JS', 'blob/hash'])
endfunction

function! s:suite.P15_url() abort
  call s:weak('gfex#path#candidate',
        \ ['https://example.com/README.md', '//cdn/x.js', 'mailto:a@b'])
endfunction

function! s:suite.P16_punctuation_only() abort
  call s:weak('gfex#path#candidate', ['/', '//', './', '..'])
endfunction

function! s:suite.P16b_dollar_without_slash() abort
  call s:weak('gfex#path#candidate', ['${GIT_ROOT}', '$SID', '$HOME'])
endfunction

function! s:suite.P17_trailing_punctuation() abort
  call s:eq('gfex#path#candidate', 'README.md,', 'README.md')
  call s:eq('gfex#path#candidate', 'README.md.', 'README.md')
  call s:eq('gfex#path#candidate', 'README.md;', 'README.md')
endfunction

function! s:suite.P18_backticks() abort
  call s:eq('gfex#path#candidate', '`README.md`', 'README.md')
endfunction

function! s:suite.P19_enclosures() abort
  call s:eq('gfex#path#candidate', '(README.md)', 'README.md')
  call s:eq('gfex#path#candidate', '"README.md"', 'README.md')
endfunction

function! s:suite.P20_dotfile_and_trailing_slash() abort
  call s:strong('gfex#path#candidate', ['~/.vimrc', '~/.vim/'])
endfunction

function! s:suite.P21_whitespace_is_never_a_candidate() abort
  call s:weak('gfex#path#candidate', ['README.md SPEC.md'])
endfunction

" ===========================================================================
" explicit()  -- tier1 / tier2 (markdown link targets)
" ===========================================================================

function! s:suite.E01_non_ascii_allowed() abort
  call s:strong('gfex#path#explicit', ['./資料/設計メモ-第1版.md'])
endfunction

function! s:suite.E02_prose_annotation_rejected() abort
  call s:weak('gfex#path#explicit', ['本文一次確認・読了', '注記のみ', '一次確認'])
endfunction

function! s:suite.E03_section_number_rejected() abort
  call s:weak('gfex#path#explicit', ['§10.1.3.1'])
endfunction

function! s:suite.E04_no_extension_no_slash() abort
  call s:weak('gfex#path#explicit', ['URL', 'URL =640x'])
endfunction

function! s:suite.E05_fragment_removed() abort
  call s:eq('gfex#path#explicit', './README.md#usage', './README.md')
endfunction

function! s:suite.E06_angle_bracket_with_space() abort
  call s:weak('gfex#path#explicit', ['<./foo bar.md>'])
endfunction

function! s:suite.E07_title_removed() abort
  call s:eq('gfex#path#explicit', 'README.md "title"', 'README.md')
  call s:eq('gfex#path#explicit', "README.md 'title'", 'README.md')
endfunction

function! s:suite.E08_url_rejected() abort
  call s:weak('gfex#path#explicit', ['https://example.com/a.md'])
endfunction

function! s:suite.E09_directory_target() abort
  call s:strong('gfex#path#explicit', ['./docs/api/'])
endfunction

function! s:suite.E10_tld_and_numeric_allowed() abort
  call s:strong('gfex#path#explicit', ['example.com', '3.x', '1/2'])
endfunction

function! s:suite.E11_angle_bracket_removed() abort
  call s:eq('gfex#path#explicit', '<./foo.md>', './foo.md')
endfunction

" ===========================================================================
" explicit_cfile()  -- tier4 (<cfile> under the cursor)
" ===========================================================================

function! s:suite.X01_non_ascii_allowed() abort
  call s:strong('gfex#path#explicit_cfile', ['./資料/設計メモ-第1版.md'])
endfunction

function! s:suite.X02_japanese_word_rejected() abort
  call s:weak('gfex#path#explicit_cfile', ['資料', '見出し'])
endfunction

function! s:suite.X03_tld_and_numeric_rejected() abort
  call s:weak('gfex#path#explicit_cfile', ['example.com', '3.x', '1/2'])
endfunction

function! s:suite.X04_dollar_without_slash_rejected() abort
  call s:weak('gfex#path#explicit_cfile', ['${GIT_ROOT}'])
endfunction

function! s:suite.X05_ordinary_paths_accepted() abort
  call s:strong('gfex#path#explicit_cfile',
        \ ['~/dev/foo/README.md', 'NOTES.md', 'docs/README.md', '$VIMRUNTIME/x.vim'])
endfunction

" ===========================================================================
" is_url()
" ===========================================================================

function! s:suite.is_url_true() abort
  for l:u in ['https://example.com/a.md', 'http://x/y', 'ftp://a/b', '//cdn/x.js', 'mailto:a@b']
    call s:assert.equals([l:u, gfex#path#is_url(l:u)], [l:u, 1])
  endfor
endfunction

function! s:suite.is_url_false() abort
  for l:u in ['./a.md', '~/a.md', '/a/b.md', 'a:b']
    call s:assert.equals([l:u, gfex#path#is_url(l:u)], [l:u, 0])
  endfor
endfunction

function! s:suite.normalize_keeps_the_fragment_of_a_url() abort
  call s:assert.equals(
        \ gfex#path#normalize('https://example.com/a/#sec03'),
        \ 'https://example.com/a/#sec03')
  call s:assert.equals(gfex#path#normalize('./README.md#usage'), './README.md')
endfunction

function! s:suite.normalize_cuts_a_url_at_the_first_blank() abort
  call s:assert.equals(
        \ gfex#path#normalize('https://example.com/a.md ほか2件'),
        \ 'https://example.com/a.md')
  call s:assert.equals(
        \ gfex#path#normalize('http://x `touch pwned`'),
        \ 'http://x')
  " A local path with a space is untouched: only URLs are cut.
  call s:assert.equals(
        \ gfex#path#normalize('~/dev/my notes.md'), '~/dev/my notes.md')
endfunction

" A backtick reaching expand() is command execution, so it must never survive
" as a path.  A fully wrapped `README.md` is different: normalize() strips the
" pair, and what is left has no backtick at all (P18).
function! s:suite.backtick_in_a_path_position_is_never_a_candidate() abort
  call s:weak('gfex#path#candidate',
        \ ['~/`id`', '~/`id>/tmp/x`', '$HOME/`id`/a.md', './`id`.md', 'a`b.md'])
  call s:weak('gfex#path#explicit_cfile', ['~/`id>/tmp/x`', './`id`.md'])
  call s:eq('gfex#path#candidate', '`README.md`', 'README.md')
endfunction

function! s:suite.glob_wildcards_are_never_a_candidate() abort
  call s:weak('gfex#path#candidate', ['~/*', '~/*.md', '$HOME/*.md', 'docs/?.md'])
  call s:weak('gfex#path#explicit_cfile', ['~/*.md'])
endfunction

" A ratio mixes the two numeric forms: neither the all-slash rule nor the
" all-dot rule catches 2.30/5.0, and the "leading digit" rule is disabled as
" soon as there is a slash.  tier3 used to open <dir>/2.30/5.0 for it.
function! s:suite.P22_numeric_ratios_are_not_paths() abort
  call s:weak('gfex#path#candidate',
        \ ['2.30/5.0', '3.5/10.0', '2026.08/2026.09', '1/2', '2.0',
        \  '2026/10/08', '10.1.3.1', '2026'])
  call s:weak('gfex#path#explicit_cfile', ['2.30/5.0', '2026.08/2026.09'])
  " A path that merely contains numbers is still a path.
  call s:strong('gfex#path#candidate', ['docs/2026/notes.md', './2026.md'])
endfunction

" The five-character cap is a deliberate, measured limit (see :help gfex).
function! s:suite.P23_extension_length_cap() abort
  call s:strong('gfex#path#candidate', ['a.md', 'a.json', 'a.vimrc'])
  call s:weak('gfex#path#candidate', ['README.markdown', 'a.properties'])
  call s:weak('gfex#path#explicit_cfile', ['README.markdown'])
  " The cap applies to explicit() too - only the path-shape sanity check
  " stands between a markdown link and a create.  A slash lifts it.
  call s:weak('gfex#path#explicit', ['README.markdown'])
  call s:strong('gfex#path#explicit', ['./README.markdown'])
endfunction
