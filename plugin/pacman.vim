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
    let s:pacman_bufnr = bufnr('%')

    let s:save_updatetime = &updatetime
    set updatetime=50
    augroup pacman
        autocmd!
        autocmd CursorHold <buffer> silent call feedkeys("g\<Esc>", "n")
        autocmd CursorHold <buffer> call s:main_loop()
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
    let s:save_updatetime = -1
endfunction

let s:pacman = 0
function! s:main_loop()
    redraw
    let s:pacman += 1
    echom 'pacman...' . s:pacman
endfunction


command! -bar -bang Pacman call s:start()


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
