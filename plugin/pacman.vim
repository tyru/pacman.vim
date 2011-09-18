" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Change Log: {{{
" }}}
" Document {{{
"
" Name: pacman
" Version: 0.0.0
" Author:  tyru <tyru.exe@gmail.com>
" Last Change: 2011-09-19.
" License: Distributable under the same terms as Vim itself (see :help license)
"
" Description:
"   NO DESCRIPTION YET
"
" Usage: {{{
"   Commands: {{{
"   }}}
"   Mappings: {{{
"   }}}
"   Global Variables: {{{
"   }}}
" }}}
" }}}

" Load Once {{{
if (exists('g:loaded_pacman') && g:loaded_pacman) || &cp
    finish
endif
let g:loaded_pacman = 1
" }}}
" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


let s:caller_bufnr = -1
let s:pacman_bufnr = -1
let s:save_updatetime = -1
let s:save_lazyredraw = -1

function! s:playing()
    return s:caller_bufnr isnot -1
endfunction

function! s:start()
    if s:playing()
        execute s:caller_bufnr 'buffer'
        return
    endif

    let s:caller_bufnr = bufnr('%')
    enew
    setlocal buftype=nowrite
    setlocal noswapfile
    let s:pacman_bufnr = bufnr('%')

    let s:save_updatetime = &updatetime
    set updatetime=100
    let s:save_lazyredraw = &lazyredraw
    set lazyredraw
    augroup pacman
        autocmd!
        autocmd CursorHold <buffer> silent call feedkeys("g\<Esc>", "n")
        autocmd CursorHold <buffer> call s:state_table[s:state].func()
        autocmd BufLeave,BufDelete <buffer> call s:stop()
    augroup END
endfunction

function! s:stop()
    if !s:playing()
        echohl WarningMsg
        echomsg 'No pacman progress.'
        echohl None
        return
    endif

    execute s:caller_bufnr 'buffer'
    execute s:pacman_bufnr 'bwipeout'
    let s:caller_bufnr = -1
    let s:pacman_bufnr = -1
    let &updatetime = s:save_updatetime
    let s:save_updatetime = -1
    let &lazyredraw = s:save_lazyredraw
    let s:save_lazyredraw = -1
endfunction




let s:state = 'loading'
let s:state_table = {}

" --------- loading ---------
let s:state_table.loading = {
\   'count': 0,
\   'graph': map(['|', '/', '-', '\'], '"loading....." . v:val'),
\}
function! s:state_table.loading.func()
    if self.count is 10
        let s:state = 'setup'
        call setline(1, 'load what? :p')
        redraw
        sleep 1
        return
    endif
    let self.count += 1
    call setline(1, self.graph[self.count % len(self.graph)])
endfunction
" --------- loading end ---------

" --------- setup ---------
let s:state_table.setup = {
\   'board': [
\       '---------------------------',
\       '|                         |',
\       '|                         |',
\       '|                         |',
\       '|                         |',
\       '|                         |',
\       '|                         |',
\       '|                         |',
\       '|                         |',
\       '---------------------------',
\   ],
\}
function! s:state_table.setup.func()
    %delete _
    let i = 0
    while i < len(self.board)
        call setline(i ==# 0 ? 1 : line('$') + 1, self.board[i])
        redraw
        sleep 200m
        let i += 1
    endwhile
    let s:state = 'main'
endfunction
" --------- setup end ---------

" --------- main ---------
let s:state_table.main = {
\   'count': 0,
\}
function! s:state_table.main.func()
    let self.count += 1
    call setline(1, 'hoge'.self.count)
endfunction
" --------- main end ---------


command! -bar -bang Pacman call s:start()


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
