scriptencoding utf-8
" test/resolve.vim - integration tests for gfex#resolve# (real files)

let s:suite = themis#suite('resolve')
let s:assert = themis#helper('assert')

let s:dir = ''
let s:cwd = ''
let s:root = expand('<sfile>:p:h:h')

function! s:write(rel, text) abort
  let l:path = s:dir . '/' . a:rel
  let l:parent = fnamemodify(l:path, ':h')
  if !isdirectory(l:parent)
    call mkdir(l:parent, 'p')
  endif
  call writefile([a:text], l:path)
  return l:path
endfunction

function! s:suite.before_each() abort
  let s:cwd = getcwd()
  let s:dir = tempname()
  call mkdir(s:dir, 'p')
  " Defaults differ between Vim and Neovim (V7): pin them.
  set hidden
  let &path = '.,,'
  set suffixesadd=
  let &isfname = '@,48-57,/,.,-,_,+,,,#,$,%,~,='
  unlet! g:loaded_gfex
  execute 'source' fnameescape(s:root . '/plugin/gfex.vim')
endfunction

function! s:suite.after_each() abort
  execute 'lcd' fnameescape(s:cwd)
  silent! bwipeout!
  if !empty(s:dir) && isdirectory(s:dir)
    call delete(s:dir, 'rf')
  endif
endfunction

" ===========================================================================

function! s:suite.R01_tilde_is_expanded() abort
  let l:r = gfex#resolve#abs('~/dev', s:dir)
  call s:assert.equals(l:r.path, simplify(expand('~/dev')))
  call s:assert.not_match(l:r.path, '\~')
endfunction

function! s:suite.R02_absolute_is_not_prefixed_with_the_buffer_dir() abort
  let l:p = s:write('abs/README.md', 'x')
  let l:r = gfex#resolve#abs(l:p, '/somewhere/else')
  call s:assert.equals([l:r.path, l:r.found], [l:p, 1])
endfunction

function! s:suite.R02b_path_only_file_is_found() abort
  call s:write('inc/only.md', 'x')
  call mkdir(s:dir . '/work', 'p')
  execute 'lcd' fnameescape(s:dir . '/work')
  let &path = '.,,' . s:dir . '/inc'
  let l:r = gfex#resolve#abs('only.md', s:dir . '/work')
  call s:assert.equals(l:r.found, 1)
  call s:assert.equals(resolve(l:r.path), resolve(s:dir . '/inc/only.md'))
endfunction

function! s:suite.R02c_suffixesadd_is_honoured() abort
  call s:write('inc/bar.md', 'x')
  call mkdir(s:dir . '/work', 'p')
  execute 'lcd' fnameescape(s:dir . '/work')
  let &path = '.,,' . s:dir . '/inc'
  set suffixesadd=.md
  let l:r = gfex#resolve#abs('bar', s:dir . '/work')
  call s:assert.equals(l:r.found, 1)
  call s:assert.equals(resolve(l:r.path), resolve(s:dir . '/inc/bar.md'))
endfunction

function! s:suite.R03_relative_is_based_on_the_buffer_directory() abort
  call s:write('sub/target.md', 'x')
  call mkdir(s:dir . '/other', 'p')
  execute 'lcd' fnameescape(s:dir . '/other')
  execute 'edit' fnameescape(s:dir . '/sub/host.md')
  let l:r = gfex#resolve#abs('target.md', gfex#resolve#base())
  call s:assert.equals([resolve(l:r.path), l:r.found],
        \ [resolve(s:dir . '/sub/target.md'), 1])
endfunction

function! s:suite.R04_unnamed_buffer_uses_cwd() abort
  call s:write('cwdtarget.md', 'x')
  execute 'lcd' fnameescape(s:dir)
  enew!
  call s:assert.equals(gfex#resolve#base(), getcwd())
  let l:r = gfex#resolve#abs('cwdtarget.md', gfex#resolve#base())
  call s:assert.equals([resolve(l:r.path), l:r.found],
        \ [resolve(s:dir . '/cwdtarget.md'), 1])
endfunction

function! s:suite.R05_env_vars_are_expanded() abort
  call s:write('env/E.md', 'x')
  let $GFEX_TEST_ROOT = s:dir
  try
    let l:a = gfex#resolve#abs('$GFEX_TEST_ROOT/env/E.md', '/nowhere')
    let l:b = gfex#resolve#abs('${GFEX_TEST_ROOT}/env/E.md', '/nowhere')
    call s:assert.equals([l:a.found, l:b.found], [1, 1])
    call s:assert.equals(resolve(l:a.path), resolve(s:dir . '/env/E.md'))
    call s:assert.equals(resolve(l:b.path), resolve(s:dir . '/env/E.md'))
  finally
    let $GFEX_TEST_ROOT = ''
  endtry
endfunction

function! s:suite.R06_name_with_spaces_resolves() abort
  call s:write('a b.md', 'x')
  let l:r = gfex#resolve#abs('a b.md', s:dir)
  call s:assert.equals([resolve(l:r.path), l:r.found], [resolve(s:dir . '/a b.md'), 1])
endfunction

function! s:suite.R07_directory_target() abort
  call s:write('docs/api/x.md', 'x')
  let l:r = gfex#resolve#abs('./docs/api/', s:dir)
  call s:assert.equals(l:r.found, 1)
endfunction

function! s:suite.R08_missing_tilde_path_never_yields_a_literal_tilde() abort
  " The live bug in the old .vimrc: simplify(base . '/~/dev/...') (V9).
  let l:r = gfex#resolve#abs('~/gfex-no-such-dir-9d1/NEW.md', s:dir)
  call s:assert.equals(l:r.found, 0)
  call s:assert.not_match(l:r.path, '\~')
  call s:assert.match(l:r.path, '^' . escape(expand('~'), '\.*$^~[]'))
endfunction

function! s:suite.R09_tier5_never_accepts_a_missing_file() abort
  execute 'lcd' fnameescape(s:dir)
  enew!
  let l:d = gfex#core#decide('see docs/missing.md here', 1, 'see', 0, gfex#core#options())
  call s:assert.equals(l:d.kind, 'no_opinion')

  call s:write('docs/present.md', 'x')
  let l:d2 = gfex#core#decide('see docs/present.md here', 1, 'see', 0, gfex#core#options())
  call s:assert.equals([l:d2.kind, l:d2.tier, l:d2.target],
        \ ['recognized', 5, 'docs/present.md'])
endfunction

function! s:suite.R12_japanese_filename_resolves() abort
  call s:write('調査/設計メモ.md', 'x')
  let l:r = gfex#resolve#abs('./調査/設計メモ.md', s:dir)
  call s:assert.equals([resolve(l:r.path), l:r.found], [resolve(s:dir . '/調査/設計メモ.md'), 1])
endfunction

function! s:suite.R05b_undefined_env_var_is_refused() abort
  let l:r = gfex#resolve#abs('${GFEX_NO_SUCH_VAR_9d1}/x.md', s:dir)
  call s:assert.equals([l:r.path, l:r.found], ['', 0])
endfunction

function! s:suite.R10_recognized_but_missing_opens_a_new_buffer() abort
  let g:gfex_create = 'syntax'
  call writefile(['[new](./docs/NEW.md)'], s:dir . '/host.md')
  execute 'edit!' fnameescape(s:dir . '/host.md')
  call cursor(1, 2)
  execute 'normal ' . "\<Plug>(gfex-edit)"
  call s:assert.equals(resolve(expand('%:p')), resolve(s:dir . '/docs/NEW.md'))
  call s:assert.equals(filereadable(s:dir . '/docs/NEW.md'), 0)
endfunction

function! s:suite.R11_create_never_reports_the_target_and_stops() abort
  let g:gfex_create = 'never'
  try
    call writefile(['[new](./docs/NEW.md)'], s:dir . '/host.md')
    execute 'edit!' fnameescape(s:dir . '/host.md')
    call cursor(1, 2)
    let l:out = ''
    redir => l:out
    execute 'normal ' . "\<Plug>(gfex-edit)"
    redir END
    call s:assert.equals(resolve(expand('%:p')), resolve(s:dir . '/host.md'))
    call s:assert.match(l:out, 'E447')
    call s:assert.match(l:out, './docs/NEW.md')
  finally
    let g:gfex_create = 'syntax'
  endtry
endfunction
