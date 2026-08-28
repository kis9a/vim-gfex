scriptencoding utf-8
" gfex/markdown.vim - Markdown syntax scanning
" Maintainer: kis9a
" License: MIT
"
" at() / all() / code_spans() are pure (line string in, value out).
" in_fence() reads the current buffer and is therefore not pure.

let s:save_cpo = &cpoptions
set cpoptions&vim

" [text](target) / [](target) / ![alt](target).  The text part may contain
" one level of brackets, so a badge - [![img](i.png)](x.md) - is read as the
" outer link rather than as the image inside it.
let s:TEXT = '!\=\[\%([^][]\|\[[^][]*\]\)*\]'
let s:LINK = s:TEXT . '([^)]*)'
" A fence may be nested in a blockquote: the JSON in a quoted example is
" still a code fence.
let s:FENCE = '^\s*\%(>\s*\)*\%(`\{3,}\|\~\{3,}\)'
let s:MARKER = '^\s*\%(>\s*\)*\zs\%(`\{3,}\|\~\{3,}\)'

" Byte ranges [start, end] (0-based, inclusive) of inline code spans.
function! gfex#markdown#code_spans(line) abort
  let l:spans = []
  let l:pos = 0
  while 1
    let l:m = matchstrpos(a:line, '`[^`]*`', l:pos)
    if l:m[1] < 0
      break
    endif
    call add(l:spans, [l:m[1], l:m[2] - 1])
    let l:pos = l:m[2]
  endwhile
  return l:spans
endfunction

function! s:in_spans(idx, spans) abort
  for l:s in a:spans
    if a:idx >= l:s[0] && a:idx <= l:s[1]
      return 1
    endif
  endfor
  return 0
endfunction

" A link target is accepted when it is a URL (routed to the URL exit) or
" when it passes explicit().  Everything else is prose in link clothing.
function! s:accept(raw) abort
  let l:n = gfex#path#normalize(a:raw)
  if gfex#path#is_url(l:n)
    return l:n
  endif
  return gfex#path#explicit(l:n)
endfunction

" All markdown links on the line, outside inline code spans.
" -> [{'start': byte, 'end': byte, 'target': string}]  (target may be '')
function! gfex#markdown#links(line) abort
  let l:spans = gfex#markdown#code_spans(a:line)
  let l:out = []
  let l:pos = 0
  while 1
    let l:m = matchstrpos(a:line, s:LINK, l:pos)
    if l:m[1] < 0
      break
    endif
    let l:pos = l:m[2]
    if s:in_spans(l:m[1], l:spans) || s:in_spans(l:m[2] - 1, l:spans)
      continue
    endif
    let l:raw = matchstr(l:m[0], '^' . s:TEXT . '(\zs.*\ze)$')
    call add(l:out, {'start': l:m[1], 'end': l:m[2] - 1, 'target': s:accept(l:raw)})
  endwhile
  return l:out
endfunction

" Target of the link containing the cursor (1-based byte column), or ''.
function! gfex#markdown#at(line, col) abort
  let l:idx = a:col - 1
  for l:link in gfex#markdown#links(a:line)
    if l:idx >= l:link.start && l:idx <= l:link.end
      return l:link.target
    endif
  endfor
  return ''
endfunction

" Every accepted link target on the line.
function! gfex#markdown#all(line) abort
  let l:out = []
  for l:link in gfex#markdown#links(a:line)
    if !empty(l:link.target)
      call add(l:out, l:link.target)
    endif
  endfor
  return l:out
endfunction

" Is line {lnum} inside (or on) a fenced code block?
" Collects only the fence marker lines with search() and runs a state machine
" over them: 13x faster than reading every line (V14).
function! gfex#markdown#in_fence(lnum) abort
  if a:lnum <= 0
    return 0
  endif
  if getline(a:lnum) =~# s:FENCE
    return 1
  endif

  let l:view = winsaveview()
  let l:lnums = []
  try
    call cursor(a:lnum, 1)
    while 1
      let l:n = search(s:FENCE, 'bW')
      if l:n <= 0
        break
      endif
      call insert(l:lnums, l:n)
    endwhile
  finally
    call winrestview(l:view)
  endtry

  let l:open = ''
  for l:n in l:lnums
    let l:line = getline(l:n)
    let l:marker = matchstr(l:line, s:MARKER)
    if empty(l:open)
      let l:open = l:marker
      continue
    endif
    " A closing fence carries no info string (CommonMark): ```vim inside a
    " ``` block opens nothing and closes nothing.
    if l:marker[0] ==# l:open[0] && len(l:marker) >= len(l:open)
          \ && matchstr(l:line, s:MARKER . '\zs.*') =~# '^\s*$'
      let l:open = ''
    endif
  endfor
  return empty(l:open) ? 0 : 1
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
