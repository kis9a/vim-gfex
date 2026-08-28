scriptencoding utf-8
" gfex - buffer-local mappings for markdown.
" after/ is read last, so this always runs after $VIMRUNTIME/ftplugin (M2).

let s:fts = get(g:, 'gfex_filetypes', ['markdown'])
if type(s:fts) != type([]) || index(s:fts, 'markdown') < 0
  finish
endif

call gfex#map_buffer()
