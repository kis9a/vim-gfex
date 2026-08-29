scriptencoding utf-8
" test/regression.vim - adversarial cases from V3 / V9 / V11 and the review
"
" Method: at every boundary where gfex could fall back, plant a decoy that the
" wrong branch would open, then assert the right file wins (G01, G06).

let s:suite = themis#suite('regression')
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

function! s:gf() abort
  execute 'normal ' . "\<Plug>(gfex-edit)"
endfunction

function! s:opened() abort
  return resolve(expand('%:p'))
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
  let g:gfex_create = 'syntax'
  let g:gfex_url = 'error'
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

" ===========================================================================

function! s:suite.G01_decoy_in_path_does_not_win() abort
  " V3: the builtin gf SUCCEEDS here and opens the decoy 'a'.
  call s:write('a', ['decoy'])
  call s:write('real/README.md', ['real'])
  call s:host(['2    a    ' . s:dir . '/real/README.md'])
  " col 6 is the decoy token: this is exactly where <cfile> becomes 'a'.
  call cursor(1, 6)
  call s:assert.equals(expand('<cfile>'), 'a')

  " Prove the decoy is live: the builtin gf opens it without any error.
  normal! gf
  call s:assert.equals(s:opened(), resolve(s:dir . '/a'))
  execute 'edit!' fnameescape(s:dir . '/host.md')
  call cursor(1, 6)

  call s:gf()
  call s:assert.equals(s:opened(), resolve(s:dir . '/real/README.md'))
endfunction

function! s:suite.G02_missing_tilde_path_creates_no_literal_tilde_dir() abort
  " V9: the old s:GfOrCreate() opened <curdir>/~/dev/engineer/README.md.
  call s:host(['~/gfex-no-such-dir-7f2/README.md'])
  call cursor(1, 1)
  call s:gf()
  call s:assert.not_match(expand('%:p'), '/\~/')
  call s:assert.match(expand('%:p'), '^' . escape(expand('~'), '\.*$^~[]'))
  call s:assert.equals(isdirectory(s:dir . '/~'), 0)
endfunction

function! s:suite.G03_japanese_prose_creates_no_garbage_buffer() abort
  " V9: prose like this used to become an empty buffer named after the first
  " Japanese word on the line, because <cfile> happily returns one.
  for l:line in ['資料: このあいだの件', '* 定例 (次回: 2026/10/08, 第2会議室)',
        \ '関連する項目、いろいろ']
    call s:host([l:line])
    call cursor(1, 1)
    let l:d = gfex#target()
    call s:assert.equals([l:line, l:d.kind], [l:line, 'no_opinion'])
    call s:gf()
    " no_opinion delegates; the builtin cannot find anything either, so we
    " must still be sitting in host.md with nothing created.
    call s:assert.equals([l:line, s:opened()], [l:line, resolve(s:dir . '/host.md')])
    call s:assert.equals([l:line, filereadable(s:dir . '/資料')], [l:line, 0])
    call s:assert.equals([l:line, bufexists(s:dir . '/定例')], [l:line, 0])
  endfor
endfunction

function! s:suite.G04_no_silent_bang_on_the_builtin_delegation() abort
  " V2: silent! swallows the exception, so E446/E447 could never be caught.
  let l:src = join(readfile(s:root . '/autoload/gfex/open.vim'), "\n")
  call s:assert.not_match(l:src, 'silent!\s*normal')
  call s:assert.not_match(l:src, 'silent\s*normal')
endfunction

function! s:suite.G05_does_not_depend_on_the_hidden_default() abort
  call s:write('there.md', ['x'])
  for l:hid in [0, 1]
    let &hidden = l:hid
    call s:host(['[a](./there.md)'])
    call cursor(1, 2)
    call s:gf()
    call s:assert.equals([l:hid, s:opened()], [l:hid, resolve(s:dir . '/there.md')])
  endfor
  set hidden
endfunction

function! s:suite.G06_create_never_does_not_fall_back_to_the_builtin() abort
  " The C1 boundary: a recognised-but-missing target with a decoy in 'path'.
  " Falling back to the builtin here would open the decoy.
  call s:write('decoys/MISSING.md', ['decoy'])
  let &path = '.,,' . s:dir . '/decoys'
  let g:gfex_create = 'never'
  call s:host(['参照: ./sub/MISSING.md'])
  call cursor(1, 1)
  let l:out = ''
  redir => l:out
  call s:gf()
  redir END
  call s:assert.equals(s:opened(), resolve(s:dir . '/host.md'))
  call s:assert.match(l:out, 'E447')
  call s:assert.match(l:out, './sub/MISSING.md')
endfunction

function! s:suite.G07_url_never_reaches_a_network_handler_by_default() abort
  " V6b: netrw fetches the URL for real once :edit sees it.
  call s:host(['参考: https://example.com/README.md'])
  call cursor(1, 1)
  let l:out = ''
  redir => l:out
  call s:gf()
  redir END
  call s:assert.equals(s:opened(), resolve(s:dir . '/host.md'))
  call s:assert.match(l:out, 'g:gfex_url')
  call s:assert.not_match(bufname('%'), 'https\?://')
endfunction

function! s:suite.G07b_url_opt_in_keeps_the_url_as_the_target() abort
  " M1: never delegate to the builtin here - it would open the *local*
  " README.md hiding under the cursor instead of the URL.
  call s:write('README.md', ['local decoy'])
  let g:gfex_url = 'edit'
  call s:host(['[README.md](https://example.com/README.md)'])
  call cursor(1, 3)
  call s:assert.equals(gfex#target().target, 'https://example.com/README.md')
  let g:gfex_url = 'error'
endfunction

function! s:suite.G08_japanese_filename_link_opens() abort
  call s:write('資料/設計メモ-第1版.md', ['x'])
  call s:host(['- [設計メモ](./資料/設計メモ-第1版.md)'])
  call cursor(1, 4)
  call s:gf()
  call s:assert.equals(s:opened(), resolve(s:dir . '/資料/設計メモ-第1版.md'))
endfunction

function! s:suite.G09_custom_isfname_does_not_shift_the_decision() abort
  call s:write('調査/設計メモ.md', ['x'])
  call s:host(['- [設計メモ](./調査/設計メモ.md)'])
  set isfname=@,48-57,/,.,-,_
  try
    call cursor(1, 4)
    call s:gf()
    call s:assert.equals(s:opened(), resolve(s:dir . '/調査/設計メモ.md'))
  finally
    let &isfname = '@,48-57,/,.,-,_,+,,,#,$,%,~,='
  endtry
endfunction

function! s:suite.G10_existing_user_mapping_is_not_overwritten() abort
  call s:host(['x'])
  nnoremap <buffer> <C-w>f :echo 'mine'<CR>
  call gfex#map_buffer()
  call s:assert.match(maparg('<C-w>f', 'n'), "echo 'mine'")
  call s:assert.match(maparg('gf', 'n'), '(gfex-edit)')
  call s:assert.match(maparg('gF', 'n'), '(gfex-line)')
  call s:assert.match(maparg('<C-w>gf', 'n'), '(gfex-tab)')
  call s:assert.not_match(b:undo_ftplugin, 'nunmap <buffer> <C-w>f')

  " unmap_buffer() must remove only what gfex owns.
  call gfex#unmap_buffer()
  call s:assert.match(maparg('<C-w>f', 'n'), "echo 'mine'")
  call s:assert.equals(maparg('gf', 'n'), '')
  silent! nunmap <buffer> <C-w>f
endfunction

function! s:suite.G11_count_is_delegated_for_every_key() abort
  call s:write('d1/dup.md', ['one'])
  call s:write('d2/dup.md', ['two'])
  let &path = '.,,' . s:dir . '/d1,' . s:dir . '/d2'
  for l:plug in ["\<Plug>(gfex-edit)", "\<Plug>(gfex-line)",
        \ "\<Plug>(gfex-split)", "\<Plug>(gfex-tab)"]
    call s:host(['use dup.md now'])
    call cursor(1, 5)
    execute 'normal 2' . l:plug
    call s:assert.equals(s:opened(), resolve(s:dir . '/d2/dup.md'))
    if winnr('$') > 1
      close
    endif
    if tabpagenr('$') > 1
      tabclose
    endif
  endfor
endfunction

function! s:suite.G12_no_firing_inside_a_code_fence() abort
  call s:write('src/main.vim', ['decoy'])
  call s:host(['```json', '  "path": "src/main.vim",', '```'])
  call cursor(2, 3)
  call s:assert.equals(gfex#target().kind, 'no_opinion')
  call s:assert.equals(gfex#markdown#in_fence(2), 1)
endfunction

function! s:suite.G13_fence_free_line_still_fires() abort
  call s:write('src/main.vim', ['real'])
  call s:host(['"path": "src/main.vim",'])
  call cursor(1, 3)
  call s:gf()
  call s:assert.equals(s:opened(), resolve(s:dir . '/src/main.vim'))
endfunction

function! s:suite.G14_a_global_mapping_does_not_block_the_buffer_local_one() abort
  " The user's own .vimrc still owns a global `gf` until it is removed.
  " maparg() sees global mappings too, so treating one as "already taken"
  " left gfex silently half-mapped: gF/<C-w>f were bound, gf was not.
  call s:host(['x'])
  nnoremap <silent> gf :echo 'global gf'<CR>
  try
    call gfex#map_buffer()
    call s:assert.match(maparg('gf', 'n'), '(gfex-edit)')
    call s:assert.equals(get(maparg('gf', 'n', 0, 1), 'buffer', 0), 1)
    call s:assert.match(maparg('gF', 'n'), '(gfex-line)')
    call s:assert.match(maparg('<C-w>f', 'n'), '(gfex-split)')
    call s:assert.match(maparg('<C-w>gf', 'n'), '(gfex-tab)')
    call gfex#unmap_buffer()
    " The global mapping is only shadowed, never removed.
    call s:assert.match(maparg('gf', 'n'), "echo 'global gf'")
  finally
    silent! nunmap gf
  endtry
endfunction

function! s:suite.G15_undo_ftplugin_works_when_it_was_unset() abort
  " A filetype with no stock ftplugin leaves b:undo_ftplugin unset.  A leading
  " '|' in the value is executed as :print and aborts the undo with E749,
  " which used to leave the mappings behind.
  call s:host(['x'])
  unlet! b:undo_ftplugin
  call gfex#map_buffer()
  call s:assert.match(maparg('gf', 'n'), '(gfex-edit)')
  call s:assert.not_match(b:undo_ftplugin, '^|')

  let l:err = ''
  try
    execute b:undo_ftplugin
  catch
    let l:err = v:exception
  endtry
  call s:assert.equals(l:err, '')
  call s:assert.equals(maparg('gf', 'n'), '')
  call s:assert.equals(maparg('<C-w>gf', 'n'), '')
endfunction

function! s:suite.G16_shell_script_extension_is_not_a_hostname() abort
  " '.sh' had been added to the TLD blacklist, which killed build.sh.
  for l:name in ['build.sh', 'deploy.sh', 'scripts/build.sh']
    call s:assert.equals([l:name, gfex#path#candidate(l:name)], [l:name, l:name])
    call s:assert.equals([l:name, gfex#path#explicit_cfile(l:name)], [l:name, l:name])
  endfor
  " ... while real host names stay excluded.
  for l:host in ['example.com', 'example.dev', 'example.org']
    call s:assert.equals([l:host, gfex#path#candidate(l:host)], [l:host, ''])
  endfor
endfunction

function! s:suite.G16b_bare_shell_script_opens_from_a_line_scan() abort
  call s:write('build.sh', ['#!/bin/sh'])
  call s:host(['ビルドは build.sh を実行する'])
  call cursor(1, 1)
  call s:gf()
  call s:assert.equals(s:opened(), resolve(s:dir . '/build.sh'))
endfunction

function! s:suite.G17_gF_picks_the_occurrence_at_the_cursor() abort
  call s:write('t.md', ['L1', 'L2', 'L3', 'L4', 'L5', 'L6', 'L7'])
  call s:host(['see t.md:2 and t.md:6 here'])
  call cursor(1, 17)
  execute 'normal ' . "\<Plug>(gfex-line)"
  call s:assert.equals(s:opened(), resolve(s:dir . '/t.md'))
  call s:assert.equals(line('.'), 6)
endfunction

function! s:suite.G18_expand_never_runs_a_shell_command() abort
  " expand() performs backtick expansion through the shell, and every tier
  " that resolves a ~/ or $VAR/ target reaches it - tier5 even resolves each
  " candidate token on the line while merely deciding, so the cursor does not
  " have to be on the payload.
  let l:proof = s:dir . '/pwned'
  let l:payloads = [
        \ 'Some ordinary prose here ~/`touch>' . l:proof . '` and more prose.',
        \ 'See [the docs](~/`touch>' . l:proof . '`) for details.',
        \ 'Config: ~/`touch>' . l:proof . '`',
        \ 'prose $HOME/`touch>' . l:proof . '` prose',
        \ ]
  for l:line in l:payloads
    call s:host([l:line])
    call cursor(1, 1)
    call s:gf()
    call s:assert.equals([l:line, filereadable(l:proof)], [l:line, 0])
    if expand('%:t') !=# 'host.md'
      silent! bwipeout!
    endif
  endfor
endfunction

function! s:suite.G18b_resolve_refuses_shell_and_glob_metacharacters() abort
  for l:t in ['~/`id`', '$HOME/`id`/a.md', '~/*', '~/*.md', '$HOME/?.md', '~/a{1}.md']
    let l:r = gfex#resolve#abs(l:t, s:dir)
    call s:assert.equals([l:t, l:r.path, l:r.found], [l:t, '', 0])
  endfor
  " ${VAR}/... must still work: the rewrite runs before the check.
  let $GFEX_G18_ROOT = s:dir
  try
    call s:write('env/E.md', ['x'])
    let l:ok = gfex#resolve#abs('${GFEX_G18_ROOT}/env/E.md', s:dir)
    call s:assert.equals(l:ok.found, 1)
  finally
    let $GFEX_G18_ROOT = ''
  endtry
endfunction

function! s:suite.G19_no_firing_inside_a_fence_in_a_blockquote() abort
  " Quoting a code block is how a review or a design note shows one, and the
  " fence marker then sits behind '> '.  Same decoy as G12.
  call s:write('src/main.vim', ['decoy'])
  call s:host(['prose', '> ```json', '>   "path": "src/main.vim",', '> ```', 'after'])
  call cursor(3, 5)
  call s:assert.equals(gfex#markdown#in_fence(3), 1)
  call s:assert.equals(gfex#target().kind, 'no_opinion')
  call s:gf()
  call s:assert.equals(s:opened(), resolve(s:dir . '/host.md'))
endfunction

function! s:suite.G20_numeric_ratio_does_not_create_a_phantom_buffer() abort
  " 2.30/5.0 passed candidate() and tier3 opened <dir>/2.30/5.0 for it.
  for l:line in ['- おすすめ度: 2.30/5.0', '- 期間: 2026.08/2026.09']
    call s:host([l:line])
    call cursor(1, 1)
    call s:assert.equals([l:line, gfex#target().kind], [l:line, 'no_opinion'])
    call s:gf()
    call s:assert.equals([l:line, s:opened()], [l:line, resolve(s:dir . '/host.md')])
  endfor
endfunction

function! s:suite.G21_nomagic_does_not_break_fence_detection() abort
  " MT1: search() honours 'magic' where the match() family does not, and the
  " fence pattern's \~ then means "the last substitute string" - E33 on every
  " gf, with no previous :s in the session.
  let l:magic = &magic
  set nomagic
  try
    call s:write('src/main.vim', ['decoy'])
    call s:host(['prose', '~~~json', '  "path": "src/main.vim",', '~~~', 'after'])
    call cursor(3, 5)
    call s:assert.equals(gfex#markdown#in_fence(3), 1)
    call s:assert.equals(gfex#target().kind, 'no_opinion')
    call cursor(5, 1)
    call s:assert.equals(gfex#markdown#in_fence(5), 0)
  finally
    let &magic = l:magic
  endtry
endfunction

function! s:suite.G22_a_bare_url_under_the_cursor_never_becomes_a_buffer() abort
  " MT2: the builtin edits any name containing '://' without consulting
  " 'path', so delegating here opened a buffer named after the URL.
  call s:write('README.md', ['local decoy'])
  call s:host(['https://example.com/README.md'])
  call cursor(1, 12)
  let l:d = gfex#target()
  call s:assert.equals([l:d.kind, l:d.target],
        \ ['recognized', 'https://example.com/README.md'])

  let l:out = ''
  redir => l:out
  call s:gf()
  redir END
  call s:assert.match(l:out, 'g:gfex_url')
  call s:assert.equals(s:opened(), resolve(s:dir . '/host.md'))
  call s:assert.not_match(bufname('%'), 'https\?://')
endfunction

function! s:suite.G23_gF_past_the_end_of_the_file_stops_at_the_last_line() abort
  " MT4: the builtin gF clamps to the last line; ":9999" only clamps too
  " while Vim is in Normal mode.  Called from a script in Ex mode - a batch
  " run, a headless CI job - the same range means :print and raises E16 after
  " the file is already open.
  " Neither this case nor G25 can go red on that error: a sourced function
  " under "vim -e -s" does raise E16, but themis' runner reaches the test
  " bodies in Normal mode, and there ":9999" clamps on its own.  Both tests
  " therefore pin the contract; removing the min() is a mutation the suite
  " cannot catch (verified by running the suite against a patched copy).
  call s:write('target.md', ['L1', 'L2', 'L3'])
  call s:host(['see target.md:9999 here'])
  call cursor(1, 5)
  let l:err = ''
  let v:errmsg = ''
  try
    execute 'normal ' . "\<Plug>(gfex-line)"
  catch
    let l:err = v:exception
  endtry
  call s:assert.equals([l:err, v:errmsg], ['', ''])
  call s:assert.equals(s:opened(), resolve(s:dir . '/target.md'))
  call s:assert.equals(line('.'), 3)
endfunction

function! s:suite.G24_url_after_a_label_does_not_swallow_the_rest_of_the_line() abort
  " MT3: with g:gfex_url = 'edit' the prose behind the URL would end up in
  " the name of the buffer that gets opened.
  call s:host(['参考: https://example.com/a.md ほか `touch pwned`'])
  call cursor(1, 1)
  call s:assert.equals(gfex#target().target, 'https://example.com/a.md')
endfunction

function! s:suite.G25_open_edit_clamps_a_line_number_past_the_end() abort
  " MT4 at the layer itself: G23 only reaches gfex#open#edit() through the
  " mapping, so this pins what the function promises on its own.  See G23 for
  " why neither test can go red on the E16 that motivated the clamp.
  let l:target = s:write('deep.md', ['L1', 'L2', 'L3'])
  let l:err = ''
  try
    call gfex#open#edit('gF', l:target, 9999)
  catch
    let l:err = v:exception
  endtry
  call s:assert.equals(l:err, '')
  call s:assert.equals(s:opened(), resolve(l:target))
  call s:assert.equals([line('.'), line('$')], [3, 3])
endfunction
