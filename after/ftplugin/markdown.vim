scriptencoding utf-8
" gfex - buffer-local mappings for markdown.
" after/ is read last, so this always runs after $VIMRUNTIME/ftplugin (M2).

if index(get(g:, 'gfex_filetypes', ['markdown']), 'markdown') < 0
  finish
endif

call gfex#map_buffer()
