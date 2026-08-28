scriptencoding utf-8
" gfex/open.vim - side effects: :edit / :split / :tabedit, builtin delegation,
"                 error reporting.  Absorbs the (thin) Vim/Neovim differences.
" Maintainer: kis9a
" License: MIT

let s:save_cpo = &cpoptions
set cpoptions&vim

" Only the two "cannot find a file" errors are ours.  E37 (no write since
" last change) and E347 (no more file in path) must reach the user (V2-2/V4).
let s:FIND_ERROR = '^Vim\%((\a\+)\)\=:E44[67]:'

function! gfex#open#error(msg) abort
  echohl ErrorMsg
  echomsg a:msg
  echohl NONE
endfunction

" 'gf'/'gF' -> edit, "\<C-w>gf" -> tabedit, "\<C-w>f" -> split (vimgoto's
" Open() trick: one function, one editcmd argument).
function! gfex#open#kind(editcmd) abort
  if a:editcmd[0] ==# 'g'
    return 'edit'
  elseif a:editcmd =~# "^\<C-w>g"
    return 'tabedit'
  endif
  return 'split'
endfunction

" The only door back to the builtin command.  No silent!: it would swallow
" the very exceptions we need to see (V2).
function! gfex#open#builtin(editcmd, count) abort
  try
    execute 'normal! ' . (a:count > 0 ? a:count : '') . a:editcmd
  catch /^Vim\%((\a\+)\)\=:E44[67]:/
    call gfex#open#error(substitute(v:exception, '\C^Vim.\{-}:', '', ''))
  endtry
endfunction

function! gfex#open#edit(editcmd, path, lnum) abort
  execute gfex#open#kind(a:editcmd) . ' ' . fnameescape(a:path)
  if a:lnum > 0
    execute a:lnum
  endif
endfunction

" Recognised URL.  Never falls back to the builtin: with the cursor on the
" link text `normal! gf` would open a *local* file instead (M1).
function! gfex#open#url(editcmd, url) abort
  if get(g:, 'gfex_url', 'error') ==# 'edit'
    if gfex#open#kind(a:editcmd) !=# 'edit'
      execute gfex#open#kind(a:editcmd)
    endif
    execute 'edit ' . fnameescape(a:url)
    return
  endif
  call gfex#open#error(printf('gfex: URL target "%s" (see g:gfex_url)', a:url))
endfunction

function! gfex#open#is_find_error(exception) abort
  return a:exception =~# s:FIND_ERROR
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
