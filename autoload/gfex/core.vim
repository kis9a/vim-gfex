scriptencoding utf-8
" gfex/core.vim - Tier decision (pure: no buffer, no fs, no 'path')
" Maintainer: kis9a
" License: MIT
"
" 'cfile' and 'fence' are injected by the caller so that this module never has
" to reimplement Vim's 'isfname' parser nor read the buffer (C4).
"
"   -1. inside a code fence          -> no_opinion
"    1. markdown link under cursor   -> its target        [explicit]
"    2. exactly one markdown link    -> its target        [explicit]
"    3. "<label>: <target>"          -> target            [candidate]
"    4. <cfile> under the cursor     -> it                [explicit_cfile]
"    5. exactly one existing path    -> it                [candidate]
"    6. otherwise                    -> no_opinion

let s:save_cpo = &cpoptions
set cpoptions&vim

" Read a string-valued option defensively.  Vim converts a String to a
" Number when comparing the two, so `0 ==# 'syntax'` is true and a numeric
" value would silently inverts every setting.  A Number 0 is read as the
" {off} setting, because that is what a Vim user writing `let g:x = 0`
" means; anything else that is not a String falls back to {default}.
function! gfex#core#opt(name, default, off) abort
  let l:v = get(g:, a:name, a:default)
  if type(l:v) == type('')
    return l:v
  endif
  if type(l:v) == type(0)
    return l:v == 0 ? a:off : a:default
  endif
  return a:default
endfunction

function! gfex#core#options() abort
  let l:scan = get(g:, 'gfex_scan_line', 1)
  return {
        \ 'scan_line': type(l:scan) == type(0) ? (l:scan != 0) : 1,
        \ 'exists': 'gfex#resolve#target_exists',
        \ }
endfunction

function! s:none(tier, reason) abort
  return {'kind': 'no_opinion', 'tier': a:tier, 'target': '',
        \ 'create_ok': 0, 'reason': a:reason}
endfunction

function! s:hit(tier, target, create_ok, reason) abort
  return {'kind': 'recognized', 'tier': a:tier, 'target': a:target,
        \ 'create_ok': a:create_ok, 'reason': a:reason}
endfunction

" R3-a: everything after the first ': ' is ONE token.  A label containing
" [ ] ( ) is a markdown link fragment, not a label.
" An ASCII colon must be followed by a space (that is what keeps http:// and
" a:b out).  A full-width colon cannot occur in a URL, and Japanese does not
" put a space after it, so there it is optional.
function! s:label_target(line) abort
  let l:m = matchlist(a:line, '^\([^:：]\{-}\)\%(:\s\+\|：\s*\)\(.\{-}\)\s*$')
  if empty(l:m) || l:m[1] =~# '[][()]'
    return ''
  endif
  return l:m[2]
endfunction

function! s:target_exists(target, opts) abort
  let l:f = get(a:opts, 'exists', '')
  if empty(l:f)
    return 0
  endif
  return call(l:f, [a:target]) ? 1 : 0
endfunction

" tier5: whitespace separated tokens that are candidates AND exist.
function! s:scan(line, opts) abort
  let l:hits = []
  for l:tok in split(a:line, '\s\+')
    let l:c = gfex#path#candidate(l:tok)
    if empty(l:c) || index(l:hits, l:c) >= 0
      continue
    endif
    if s:target_exists(l:c, a:opts)
      call add(l:hits, l:c)
    endif
  endfor
  return l:hits
endfunction

function! gfex#core#decide(line, col, cfile, fence, opts) abort
  if a:fence
    return s:none(-1, 'inside a code fence')
  endif

  " tier1 / tier2 -- markdown links come before the <cfile> layer because the
  " link text itself often looks like a path (V6e).
  let l:t = gfex#markdown#at(a:line, a:col)
  if !empty(l:t)
    return s:hit(1, l:t, 1, 'markdown link under the cursor')
  endif

  let l:all = gfex#markdown#all(a:line)
  if len(l:all) == 1
    return s:hit(2, l:all[0], 1, 'the only markdown link on the line')
  endif

  " tier3 -- "<label>: <target>"
  let l:raw = s:label_target(a:line)
  if !empty(l:raw)
    let l:norm = gfex#path#normalize(l:raw)
    if gfex#path#is_url(l:norm)
      return s:hit(3, l:norm, 0, 'URL after a label')
    endif
    let l:c = gfex#path#candidate(l:raw)
    if !empty(l:c)
      return s:hit(3, l:c, 1, 'path after a label')
    endif
  endif

  " tier4 -- <cfile> under the cursor
  let l:c = gfex#path#explicit_cfile(a:cfile)
  if !empty(l:c)
    return s:hit(4, l:c, 1, 'path under the cursor')
  endif

  " tier5 -- line scan.  Never creates: existence is the only defence here.
  if get(a:opts, 'scan_line', 1)
    let l:hits = s:scan(a:line, a:opts)
    if len(l:hits) == 1
      return s:hit(5, l:hits[0], 0, 'the only existing path on the line')
    endif
  endif

  return s:none(6, 'no recognizable target')
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
