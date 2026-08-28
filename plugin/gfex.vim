scriptencoding utf-8
" gfex - gf that understands the line it is on
" Maintainer: kis9a
" License: MIT

if exists('g:loaded_gfex') && g:loaded_gfex
  finish
endif
let g:loaded_gfex = 1

let s:save_cpo = &cpoptions
set cpoptions&vim

" A bad value must not abort the rest of this file: 'cpoptions' would stay
" clobbered and g:loaded_gfex is already set, so nothing would retry.
if !exists('g:gfex_filetypes')
  let g:gfex_filetypes = ['markdown']
elseif type(g:gfex_filetypes) == type('')
  let g:gfex_filetypes = [g:gfex_filetypes]
elseif type(g:gfex_filetypes) != type([])
  let g:gfex_filetypes = ['markdown']
endif
if !exists('g:gfex_create')
  let g:gfex_create = 'syntax'
endif
if !exists('g:gfex_url')
  let g:gfex_url = 'error'
endif
if !exists('g:gfex_base')
  let g:gfex_base = 'file'
endif
if !exists('g:gfex_scan_line')
  let g:gfex_scan_line = 1
endif

nnoremap <silent> <Plug>(gfex-edit)       :<C-U>call gfex#find('gf')<CR>
nnoremap <silent> <Plug>(gfex-line)       :<C-U>call gfex#find('gF')<CR>
nnoremap <silent> <Plug>(gfex-split)      :<C-U>call gfex#find("\<lt>C-w>f")<CR>
nnoremap <silent> <Plug>(gfex-split-line) :<C-U>call gfex#find("\<lt>C-w>F")<CR>
nnoremap <silent> <Plug>(gfex-tab)        :<C-U>call gfex#find("\<lt>C-w>gf")<CR>
nnoremap <silent> <Plug>(gfex-tab-line)   :<C-U>call gfex#find("\<lt>C-w>gF")<CR>

" markdown is handled by after/ftplugin/markdown.vim, which is guaranteed to
" run after $VIMRUNTIME/ftplugin/markdown.vim.  Any other filetype the user
" adds gets this autocmd, whose ordering is not guaranteed (M2 / V15).
let s:extra = filter(copy(g:gfex_filetypes), 'v:val !=# "markdown"')
if !empty(s:extra)
  augroup gfex_ftmap
    autocmd!
    execute 'autocmd FileType ' . join(s:extra, ',') . ' call gfex#map_buffer()'
  augroup END
endif
unlet s:extra

let &cpoptions = s:save_cpo
unlet s:save_cpo
