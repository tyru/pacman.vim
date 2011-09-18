" vim:foldmethod=marker:fen:
scriptencoding utf-8

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



command! -bar -bang Pacman call pacman#start(<bang>0)


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
