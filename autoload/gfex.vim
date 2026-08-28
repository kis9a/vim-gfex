scriptencoding utf-8
" gfex.vim - Public API
" Maintainer: kis9a
" License: MIT

let s:save_cpo = &cpoptions
set cpoptions&vim

let s:MAP_PAIRS = [
      \ ['gf',      '<Plug>(gfex-edit)'],
      \ ['gF',      '<Plug>(gfex-line)'],
      \ ['<C-w>f',  '<Plug>(gfex-split)'],
      \ ['<C-w>gf', '<Plug>(gfex-tab)'],
      \ ]

" Decision + resolution, without side effects.  Exposed so that users can
" build their own mappings on top of gfex (Q5).
"   -> {'kind','tier','target','create_ok','reason','path','found'}
function! gfex#target() abort
  let l:d = gfex#core#decide(
        \ getline('.'), col('.'), expand('<cfile>'),
        \ gfex#markdown#in_fence(line('.')), gfex#core#options())
  let l:d.path = ''
  let l:d.found = 0
  if l:d.kind ==# 'recognized' && !gfex#path#is_url(l:d.target)
    let l:r = gfex#resolve#abs(l:d.target, gfex#resolve#base())
    let l:d.path = l:r.path
    let l:d.found = l:r.found
  endif
  return l:d
endfunction

" gF-style "file:line" suffix for the recognised target, or 0.
function! s:line_suffix(target) abort
  let l:line = getline('.')
  let l:cur = col('.') - 1
  let l:idx = -1
  let l:from = 0
  " The same target can appear twice on one line; prefer the occurrence the
  " cursor is on or before, and fall back to the last one.
  while 1
    let l:at = stridx(l:line, a:target, l:from)
    if l:at < 0
      break
    endif
    let l:idx = l:at
    if l:at + strlen(a:target) > l:cur
      break
    endif
    let l:from = l:at + 1
  endwhile
  if l:idx < 0
    return 0
  endif
  let l:rest = strpart(l:line, l:idx + strlen(a:target))
  return str2nr(matchstr(l:rest, '^:\zs\d\+'))
endfunction

" editcmd: 'gf' | 'gF' | "\<C-w>f" | "\<C-w>F" | "\<C-w>gf" | "\<C-w>gF"
function! gfex#find(editcmd) abort
  " tier0: a count means "the Nth match in 'path'".  Never reinterpret it.
  if v:count > 0
    return gfex#open#builtin(a:editcmd, v:count)
  endif

  let l:d = gfex#target()

  " Exit A -- nothing recognised.  The only door to the builtin command.
  if l:d.kind ==# 'no_opinion'
    return gfex#open#builtin(a:editcmd, 0)
  endif

  " Exit B -- recognised.  Never returns to the builtin from here: it would
  " re-search from the cursor and open a decoy sitting in 'path' (C1/V3).
  if gfex#path#is_url(l:d.target)
    return gfex#open#url(a:editcmd, l:d.target)
  endif

  let l:lnum = a:editcmd =~# 'F' ? s:line_suffix(l:d.target) : 0

  if l:d.found
    return gfex#open#edit(a:editcmd, l:d.path, l:lnum)
  endif

  if l:d.create_ok && get(g:, 'gfex_create', 'syntax') ==# 'syntax'
        \ && !empty(l:d.path)
    return gfex#open#edit(a:editcmd, l:d.path, l:lnum)
  endif

  return gfex#open#error(
        \ printf('E447: Can''t find file "%s" in path', l:d.target))
endfunction

function! gfex#map_buffer() abort
  " An unscoped name inside a function resolves to l:, so g: is mandatory
  " here (B3 / V17).
  if exists('g:no_plugin_maps') || exists('g:no_gfex_maps')
    return
  endif

  let l:undo = []
  for [l:lhs, l:rhs] in s:MAP_PAIRS
    " Per key: checking one key and mapping four would silently take over
    " a <C-w>f the user already owns (G10).  Only a BUFFER-LOCAL mapping
    " counts as owned: shadowing a global mapping is the whole point of a
    " buffer-local one, and treating a global gf as "taken" would leave the
    " plugin silently half-mapped.
    let l:m = maparg(l:lhs, 'n', 0, 1)
    if (!empty(l:m) && get(l:m, 'buffer', 0)) || hasmapto(l:rhs, 'n')
      continue
    endif
    execute 'nmap <buffer> <silent> ' . l:lhs . ' ' . l:rhs
    call add(l:undo, 'silent! nunmap <buffer> ' . l:lhs)
  endfor

  if !empty(l:undo)
    " A leading '|' is executed as :print and aborts the undo with E749,
    " leaving the mappings in place.  Only separate when there is something
    " to separate from.
    let l:prev = get(b:, 'undo_ftplugin', '')
    let b:undo_ftplugin = (empty(l:prev) ? '' : l:prev . '|') . join(l:undo, '|')
  endif
endfunction

function! gfex#unmap_buffer() abort
  for l:pair in s:MAP_PAIRS
    let l:lhs = l:pair[0]
    if maparg(l:lhs, 'n') =~# '(gfex-'
      execute 'silent! nunmap <buffer> ' . l:lhs
    endif
  endfor
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
