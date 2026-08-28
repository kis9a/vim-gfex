scriptencoding utf-8
" gfex/resolve.vim - target -> absolute path
" Maintainer: kis9a
" License: MIT

let s:save_cpo = &cpoptions
set cpoptions&vim

" expand('%:p:h') returns getcwd() for an unnamed buffer (V5), so no extra
" fallback is needed here.
function! gfex#resolve#base() abort
  if gfex#core#opt('gfex_base', 'file', 'file') ==# 'cwd'
    return getcwd()
  endif
  return expand('%:p:h')
endfunction

function! s:readable(path) abort
  return filereadable(a:path) || isdirectory(a:path)
endfunction

" -> {'path': '/abs/...', 'found': 0|1}
function! gfex#resolve#abs(target, base) abort
  if empty(a:target)
    return {'path': '', 'found': 0}
  endif

  if a:target =~# '^/'
    let l:p = simplify(a:target)
  elseif a:target =~# '^[~$]'
    " expand() is what keeps a literal '~' directory from being created (V9).
    " expand() does not understand ${VAR}, so rewrite it to $VAR first.
    let l:t = substitute(a:target, '^\${\(\w\+\)}', '$\1', '')
    " expand() runs `cmd` through the shell and expands glob wildcards, so a
    " crafted document could execute arbitrary commands just by being open
    " when gf is pressed.  Refuse those shapes outright.  This must come
    " AFTER the ${VAR} -> $VAR rewrite, or the '{' of the legitimate
    " ${GIT_ROOT}/x.md form would be rejected.
    if l:t =~# '[`*?[{]'
      return {'path': '', 'found': 0}
    endif
    if l:t =~# '^\$'
      let l:name = matchstr(l:t, '^\$\zs\w\+')
      if empty(l:name) || !exists('$' . l:name)
        " An undefined variable would expand to nothing and silently turn
        " ${NOPE}/x.md into /x.md.  Refuse instead.
        return {'path': '', 'found': 0}
      endif
    endif
    let l:e = expand(l:t)
    let l:p = simplify(empty(l:e) ? l:t : l:e)
  else
    let l:p = simplify(a:base . '/' . a:target)
    if !s:readable(l:p)
      " Do not cover a file the builtin gf would have found with an empty
      " buffer.  findfile() honours both 'path' and 'suffixesadd' and lands
      " on the same file as the builtin gf (V12).
      let l:f = findfile(a:target)
      if !empty(l:f)
        return {'path': fnamemodify(l:f, ':p'), 'found': 1}
      endif
      let l:d = finddir(a:target)
      if !empty(l:d)
        return {'path': fnamemodify(l:d, ':p'), 'found': 1}
      endif
    endif
  endif

  return {'path': l:p, 'found': s:readable(l:p)}
endfunction

" Used as the tier5 existence gate (injected through gfex#core#options()).
function! gfex#resolve#target_exists(target) abort
  return gfex#resolve#abs(a:target, gfex#resolve#base()).found
endfunction

let &cpoptions = s:save_cpo
unlet s:save_cpo
