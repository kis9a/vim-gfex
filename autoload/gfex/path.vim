scriptencoding utf-8
" gfex/path.vim - Path vocabulary (pure functions, no buffer / no fs access)
" Maintainer: kis9a
" License: MIT

let s:save_cpo = &cpoptions
set cpoptions&vim

" An extension must start with a letter.  Version-like suffixes (v1.2.3, 3.x,
" 2.0, F1.4, 10.1.3.1) must not be mistaken for a file extension.
let s:EXT = '\.[A-Za-z][A-Za-z0-9]\{0,4}$'

" Anchored forms: these are paths by shape alone.
let s:ANCHORED = '^\%(\~/\|/\|\./\|\.\./\|\$\w\+/\|\${\w\+}/\)'

" Host-like trailing labels (example.com, example.dev, example.io, ...)
" Exactly the R4 list.  '.sh' is deliberately absent: build.sh is a far more
" common thing to write in notes than a .sh domain.
let s:TLD = '\c\.\%(com\|net\|org\|io\|dev\|jp\|co\|ai\|app\|me\|tv\|info\|biz\|xyz\)$'

function! gfex#path#is_url(raw) abort
  if a:raw =~? '^\a\{2,}://'
    return 1
  endif
  if a:raw =~# '^//'
    return 1
  endif
  if a:raw =~? '^mailto:'
    return 1
  endif
  return 0
endfunction

" Strip decoration that is never part of a file name.
" Used by every layer so that the three predicates share one vocabulary.
function! gfex#path#normalize(raw) abort
  let l:s = a:raw
  " Decoration can nest ("src/main.vim", -> "src/main.vim" -> src/main.vim),
  " so keep peeling until the string stops changing.
  while 1
    let l:before = l:s
    let l:s = substitute(l:s, '^\s\+', '', '')
    let l:s = substitute(l:s, '\s\+$', '', '')
    if empty(l:s)
      return ''
    endif

    " Markdown link title:  target "title" / target 'title' / target (title)
    let l:s = substitute(l:s, '\s\+".\{-}"$', '', '')
    let l:s = substitute(l:s, "\\s\\+'.\\{-}'$", '', '')
    let l:s = substitute(l:s, '\s\+(.\{-})$', '', '')

    " Enclosing pairs: `x` "x" 'x' (x) [x] <x>
    let l:s = substitute(l:s, '^`\(.*\)`$', '\1', '')
    let l:s = substitute(l:s, '^"\(.*\)"$', '\1', '')
    let l:s = substitute(l:s, "^'\\(.*\\)'$", '\1', '')
    let l:s = substitute(l:s, '^(\(.*\))$', '\1', '')
    let l:s = substitute(l:s, '^\[\(.*\)\]$', '\1', '')
    let l:s = substitute(l:s, '^<\(.*\)>$', '\1', '')

    " Fragment (#usage).  '#' is in 'isfname', so the builtin gf always fails
    " on it (V6c).  A leading '#' is not a fragment separator, and in a URL
    " the fragment belongs to the target.
    let l:hash = stridx(l:s, '#')
    if l:hash > 0 && !gfex#path#is_url(l:s)
      let l:s = strpart(l:s, 0, l:hash)
    endif

    " Trailing punctuation.  '}' and '>' are intentionally NOT stripped so
    " that ${VAR} is never broken into ${VAR (V17).
    let l:s = substitute(l:s, '[,.;:!?)\]]\+$', '', '')

    if l:s ==# l:before
      break
    endif
  endwhile

  " A URL cannot contain whitespace.  s:label_target() hands over everything
  " after the label, so "url: https://x - see also" would otherwise report
  " (and with g:gfex_url = 'edit' open) the prose as part of the URL (MT3).
  if gfex#path#is_url(l:s)
    let l:s = matchstr(l:s, '^\S\+')
  endif
  return l:s
endfunction

" -- shared shape / exclusion helpers ---------------------------------------

function! s:has_ext(s) abort
  return a:s =~# s:EXT
endfunction

function! s:is_anchored(s) abort
  return a:s =~# s:ANCHORED
endfunction

" Accepted shapes (R4 "候補として認める形")
function! s:shape_ok(s) abort
  if s:is_anchored(a:s)
    return 1
  endif
  if stridx(a:s, '/') >= 0 && stridx(a:s, '.') >= 0
    return 1
  endif
  return s:has_ext(a:s)
endfunction

" Exclusion rules shared by candidate() and explicit_cfile()
" (everything except the non-ASCII rule, which differs per layer).
function! s:excluded(s) abort
  " Bracket leftovers: [a](x.md , foo)bar - never a real target here.
  if a:s =~# '[][()]'
    return 1
  endif
  " Defence in depth: a backtick or a glob wildcard must never reach
  " expand(), which would run it through the shell.  resolve#abs() refuses
  " them as well; this keeps them from becoming a candidate at all.
  if a:s =~# '[`*?]'
    return 1
  endif
  " '/' '.' '~' only
  if a:s =~# '^[./~]\+$'
    return 1
  endif
  " $VAR without a slash: ${GIT_ROOT}, $SID, $HOME  (B1-3 / V17)
  if a:s =~# '^\$' && stridx(a:s, '/') < 0
    return 1
  endif
  " Nothing but numbers and separators: 1/2, 2026/10/08, 2.0, 10.1.3.1 and
  " the mixed forms 2.30/5.0 and 2026.08/2026.09.  Separate rules for '/'
  " and '.' let anything mixing the two slip through.
  if a:s =~# '^\d\+\%([./]\d\+\)*$'
    return 1
  endif
  " version-like leading token without a path separator: 3.x, v1.2.3
  if stridx(a:s, '/') < 0 && a:s =~# '^v\=\d'
    return 1
  endif
  " host-like: example.com, example.dev, example.com/foo.md
  if matchstr(a:s, '^[^/]*') =~# s:TLD
    return 1
  endif
  " unanchored 'A/B' without any dot: I/O, KYC/AML, blob/hash
  if !s:is_anchored(a:s) && stridx(a:s, '/') >= 0 && stridx(a:s, '.') < 0
    return 1
  endif
  return 0
endfunction

" -- tier1 / tier2: markdown link targets -----------------------------------
" The ](...) syntax itself declares "this is a path", so no guessing about
" file-ness.  Only URLs and non-path shapes are rejected (C3 / V12-c).
function! gfex#path#explicit(raw) abort
  let l:s = gfex#path#normalize(a:raw)
  if empty(l:s) || gfex#path#is_url(l:s)
    return ''
  endif
  if l:s =~# '\s'
    return ''
  endif
  if stridx(l:s, '/') < 0 && !s:has_ext(l:s)
    return ''
  endif
  return l:s
endfunction

" -- tier4: <cfile> under the cursor ----------------------------------------
" Explicit intent from the user, but <cfile> is cut out mechanically by
" 'isfname', so keep every exclusion rule but the non-ASCII one (C3).
function! gfex#path#explicit_cfile(raw) abort
  let l:s = gfex#path#normalize(a:raw)
  if empty(l:s) || gfex#path#is_url(l:s)
    return ''
  endif
  if l:s =~# '\s'
    return ''
  endif
  if !s:shape_ok(l:s) || s:excluded(l:s)
    return ''
  endif
  return l:s
endfunction

" -- tier3 / tier5: guessed from the line -----------------------------------
function! gfex#path#candidate(raw) abort
  let l:s = gfex#path#normalize(a:raw)
  if empty(l:s) || gfex#path#is_url(l:s)
    return ''
  endif
  " ASCII printable only.  Japanese prose has no word separators, so any
  " non-ASCII token is a sentence fragment, not a path (V10).
  if l:s =~# '[^\x21-\x7e]'
    return ''
  endif
  if !s:shape_ok(l:s) || s:excluded(l:s)
    return ''
  endif
  return l:s
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
