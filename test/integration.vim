scriptencoding utf-8
" test/integration.vim - real buffers, real files, builtin delegation

let s:suite = themis#suite('integration')
let s:assert = themis#helper('assert')

let s:dir = ''
let s:cwd = ''
let s:root = expand('<sfile>:p:h:h')

function! s:write(rel, lines) abort
  let l:path = s:dir . '/' . a:rel
  let l:parent = fnamemodify(l:path, ':h')
  if !isdirectory(l:parent)
    call mkdir(l:parent, 'p')
  endif
  call writefile(a:lines, l:path)
  return l:path
endfunction

function! s:host(lines) abort
  call s:write('host.md', a:lines)
  execute 'edit!' fnameescape(s:dir . '/host.md')
  setfiletype markdown
endfunction

function! s:suite.before_each() abort
  let s:cwd = getcwd()
  let s:dir = tempname()
  call mkdir(s:dir, 'p')
  execute 'lcd' fnameescape(s:dir)
  set hidden
  let &path = '.,,'
  set suffixesadd=
  set includeexpr=
  let &isfname = '@,48-57,/,.,-,_,+,,,#,$,%,~,='
  unlet! g:no_gfex_maps
  unlet! g:no_plugin_maps
  unlet! g:loaded_gfex
  execute 'source' fnameescape(s:root . '/plugin/gfex.vim')
endfunction

function! s:suite.after_each() abort
  execute 'lcd' fnameescape(s:cwd)
  silent! bwipeout!
  silent! bwipeout!
  if !empty(s:dir) && isdirectory(s:dir)
    call delete(s:dir, 'rf')
  endif
  let g:gfex_create = 'syntax'
  let g:gfex_url = 'error'
endfunction

" Always drive through the <Plug> mapping: that is the real entry point and
" it is what resets v:count for the invocation.
function! s:gf(plug) abort
  execute 'normal ' . a:plug
endfunction

function! s:opened() abort
  return resolve(expand('%:p'))
endfunction

function! s:messages(cmd) abort
  let l:out = ''
  redir => l:out
  execute a:cmd
  redir END
  return l:out
endfunction

" ===========================================================================

function! s:suite.I01_c_include_line() abort
  call s:write('foo.h', ['h'])
  call s:host(['#include "foo.h"'])
  call cursor(1, 1)
  call s:gf("\<Plug>(gfex-edit)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/foo.h'))
endfunction

function! s:suite.I01b_no_opinion_when_nothing_exists() abort
  call s:host(['#include "foo.h"'])
  call cursor(1, 1)
  call s:assert.equals(gfex#target().kind, 'no_opinion')
endfunction

function! s:suite.I02_path_entry_is_used_by_the_builtin() abort
  call s:write('inc/lib.h', ['x'])
  let &path = '.,,' . s:dir . '/inc'
  call s:host(['include lib.h here'])
  call cursor(1, 9)
  call s:gf("\<Plug>(gfex-edit)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/inc/lib.h'))
endfunction

function! s:suite.I03_suffixesadd_via_builtin() abort
  call s:write('inc/bar.md', ['x'])
  let &path = '.,,' . s:dir . '/inc'
  set suffixesadd=.md
  call s:host(['see bar somewhere'])
  call cursor(1, 5)
  call s:gf("\<Plug>(gfex-edit)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/inc/bar.md'))
endfunction

function! s:suite.I03b_includeexpr_only_fires_when_the_name_is_missing() abort
  call s:write('real_foo.md', ['x'])
  set includeexpr=substitute(v:fname,'^foo$','real_foo.md','')
  call s:host(['token foo end'])
  call cursor(1, 7)
  call s:gf("\<Plug>(gfex-edit)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/real_foo.md'))

  " With a real 'foo' present, 'includeexpr' must not fire.
  call s:write('foo', ['x'])
  execute 'edit!' fnameescape(s:dir . '/host.md')
  call cursor(1, 7)
  call s:gf("\<Plug>(gfex-edit)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/foo'))
  set includeexpr=
endfunction

function! s:suite.I04_count_opens_the_nth_match() abort
  call s:write('d1/dup.md', ['one'])
  call s:write('d2/dup.md', ['two'])
  let &path = '.,,' . s:dir . '/d1,' . s:dir . '/d2'
  call s:host(['use dup.md now'])
  call cursor(1, 5)
  call s:gf("\<Plug>(gfex-edit)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/d1/dup.md'))

  execute 'edit!' fnameescape(s:dir . '/host.md')
  call cursor(1, 5)
  execute "normal 2\<Plug>(gfex-edit)"
  call s:assert.equals(s:opened(), resolve(s:dir . '/d2/dup.md'))
endfunction

function! s:suite.I05_count_overflow_raises_E347() abort
  call s:write('d1/dup.md', ['one'])
  let &path = '.,,' . s:dir . '/d1'
  call s:host(['use dup.md now'])
  call cursor(1, 5)
  let l:err = ''
  try
    execute "normal 5\<Plug>(gfex-edit)"
  catch
    let l:err = v:exception
  endtry
  call s:assert.match(l:err, 'E347')
endfunction

function! s:suite.I06_E37_is_not_swallowed() abort
  call s:write('other.md', ['x'])
  call s:host(['see other.md here'])
  set nohidden
  call setline(2, 'dirty')
  call cursor(1, 5)
  let l:err = ''
  try
    call s:gf("\<Plug>(gfex-edit)")
  catch
    let l:err = v:exception
  endtry
  set hidden
  call s:assert.match(l:err, 'E37:')
endfunction

function! s:suite.I07_builtin_find_error_is_reformatted() abort
  call s:host(['nothing here at all'])
  call cursor(1, 1)
  let l:out = s:messages('normal ' . "\<Plug>(gfex-edit)")
  call s:assert.match(l:out, 'E44[67]:')
  call s:assert.not_match(l:out, 'Vim(normal)')
endfunction

function! s:suite.I08_split_mapping() abort
  call s:write('split.md', ['x'])
  call s:host(['[a](./split.md)'])
  call cursor(1, 2)
  let l:before = winnr('$')
  call s:gf("\<Plug>(gfex-split)")
  call s:assert.equals(winnr('$'), l:before + 1)
  call s:assert.equals(s:opened(), resolve(s:dir . '/split.md'))
  close
endfunction

function! s:suite.I09_tab_mapping() abort
  call s:write('tab.md', ['x'])
  call s:host(['[a](./tab.md)'])
  call cursor(1, 2)
  let l:before = tabpagenr('$')
  call s:gf("\<Plug>(gfex-tab)")
  call s:assert.equals(tabpagenr('$'), l:before + 1)
  call s:assert.equals(s:opened(), resolve(s:dir . '/tab.md'))
  tabclose
endfunction

function! s:suite.I10_no_gfex_maps_guard() abort
  call s:host(['x'])
  let g:no_gfex_maps = 1
  call gfex#map_buffer()
  call s:assert.equals(maparg('gf', 'n'), '')
  unlet g:no_gfex_maps

  " The guard must look at g:.  An unscoped name is l: inside a function and
  " would never be seen (B3 / V17).
  let l:no_gfex_maps = 1
  call gfex#map_buffer()
  call s:assert.match(maparg('gf', 'n'), '(gfex-edit)')
  call gfex#unmap_buffer()
endfunction

function! s:suite.I10b_no_plugin_maps_guard() abort
  call s:host(['x'])
  let g:no_plugin_maps = 1
  call gfex#map_buffer()
  call s:assert.equals(maparg('gf', 'n'), '')
  unlet g:no_plugin_maps
endfunction

function! s:suite.I11_after_ftplugin_survives_a_later_undo_ftplugin_assignment() abort
  call s:host(['x'])
  " A stock ftplugin *assigns* b:undo_ftplugin (273 of 340 runtime files do).
  let b:undo_ftplugin = 'setlocal comments< commentstring<'
  execute 'source' fnameescape(s:root . '/after/ftplugin/markdown.vim')
  call s:assert.match(maparg('gf', 'n'), '(gfex-edit)')
  call s:assert.match(b:undo_ftplugin, 'nunmap <buffer> gf')
  call gfex#unmap_buffer()
endfunction

function! s:suite.I12_gF_jumps_to_the_line_number() abort
  call s:write('target.md', ['L1', 'L2', 'L3', 'L4', 'L5'])
  call s:host(['see target.md:4 here'])
  call cursor(1, 5)
  call s:gf("\<Plug>(gfex-line)")
  call s:assert.equals(s:opened(), resolve(s:dir . '/target.md'))
  call s:assert.equals(line('.'), 4)
  call s:assert.equals(getline('.'), 'L4')
endfunction
