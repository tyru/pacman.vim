" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


let s:caller_bufnr = -1
let s:pacman_bufnr = -1
let s:save_updatetime = -1
let s:save_lazyredraw = -1
let s:save_virtualedit = ''

function! s:playing()
    return s:caller_bufnr isnot -1
endfunction

function! pacman#start(skip_loading)
    if s:playing()
        execute s:caller_bufnr 'buffer'
        return
    endif

    " Create buffer.
    let s:caller_bufnr = bufnr('%')
    call s:create_buffer()
    let s:pacman_bufnr = bufnr('%')

    if a:skip_loading
        call s:set_state('fast_setup')
    endif
endfunction
function! s:create_buffer()
    enew

    setlocal buftype=nowrite
    setlocal noswapfile

    for key in ['j', 'k', 'h', 'l']
        execute 'nnoremap <buffer><expr>' key 'b:pacman_current_table.on_key('.string(key).')'
    endfor
    " Alias for `s:state_table[s:state]`.
    " because <buffer><expr>-mapping `<SID>state_table[<SID>state].on_key()` causes error.
    let b:pacman_current_table = {}

    let s:save_updatetime = &updatetime
    set updatetime=100
    let s:save_lazyredraw = &lazyredraw
    set lazyredraw
    let s:save_virtualedit = &virtualedit
    set virtualedit=
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
    let &virtualedit = s:save_virtualedit
    let s:save_virtualedit = ''
endfunction




let s:field = []
" TODO: Add more fields!
let s:FIELDS = []
call add(s:FIELDS, [
\   '---------------------------',
\   '|         $$$$$$$$$$$$$$$$|',
\   '|  -----  ------  | -----$|',
\   '|      |          |      $|',
\   '|  |   |     + |  -------$|',
\   '|  |   -----   |$$$$$$$$$$|',
\   '|  |       |   |  ------- |',
\   '|  ------  |   |  ------- |',
\   '|                         |',
\   '---------------------------',
\])

let s:CHAR_START_POINT = '+'
let s:CHAR_FREE_SPACE = ' '
let s:CHAR_WALL1 = '|'
let s:CHAR_WALL2 = '-'
let s:CHAR_FEED = '$'

" No `s:MARK_START_POINT` because
" `s:CHAR_START_POINT` is replaced with `s:CHAR_FREE_SPACE`.
" s:MARK_* constants is only needed for detection of
" a mark type of a character.
let [
\   s:MARK_FREE_SPACE,
\   s:MARK_WALL,
\   s:MARK_FEED
\] = range(3)

let s:CHAR_TO_MARK_TYPE_TABLE = {
\   s:CHAR_FREE_SPACE : s:MARK_FREE_SPACE,
\   s:CHAR_WALL1      : s:MARK_WALL,
\   s:CHAR_WALL2      : s:MARK_WALL,
\   s:CHAR_FEED       : s:MARK_FEED,
\}

function! s:get_mark_type(c)
    return s:CHAR_TO_MARK_TYPE_TABLE[a:c]
endfunction

function! s:choose_field()
    " TODO
    "let s:field = deepcopy(s:FIELDS[s:rand(len(s:FIELDS))])
    let s:field = deepcopy(s:FIELDS[0])
endfunction
function! s:move_to_start_point()
    for y in range(len(s:field))
        for x in range(len(s:field[y]))
            if s:field[y][x] ==# s:CHAR_START_POINT
                " Rewrite s:CHAR_START_POINT to s:CHAR_FREE_SPACE.
                call s:field_set_char(s:CHAR_FREE_SPACE, x, y)
                " Move cursor to free space. (not wall)
                call cursor(y + 1, x + 1)
                break
            endif
        endfor
    endfor
endfunction

" Vim does not support assignment to a character of String...
"let s:field[a:y][a:x]  = s:CHAR_START_POINT
function! s:field_set_char(char, x, y)
    if a:y <# 0 || a:y >=# len(s:field)
    \   || a:x <# 0 || a:x >=# len(s:field[a:y])
    \   || strlen(a:char) !=# 1
        return
    endif
    let above = (a:y ==# 0 ? [] : s:field[: a:y - 1])
    let middle_left = (a:x ==# 0 ? '' : s:field[a:y][: a:x - 1])
    let middle_right = (a:x ==# len(s:field[a:y]) - 1 ? '' : s:field[a:y][a:x + 1 :])
    let below = (a:y ==# len(s:field) - 1 ? [] : s:field[a:y + 1 :])
    let s:field = above + [middle_left . a:char . middle_right] + below
endfunction




function! s:set_state(state)
    let s:state = a:state
    let b:pacman_current_table = s:state_table[s:state]
endfunction
" Return empty string for 'on_key()'
function! s:nop()
    return ''
endfunction
function! s:create_table(...)
    return extend(copy(s:BASE_TABLE), a:0 ? copy(a:1) : {}, 'force')
endfunction
function! s:SID()
    return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfunction
function! s:localfunc(name)
    return function('<SNR>'.s:SID().'_'.a:name)
endfunction

let s:BASE_TABLE = {
\   'func': s:localfunc('nop'),
\   'on_key': s:localfunc('nop'),
\}
let s:state = 'loading'
let s:state_table = {}


" --------- loading ---------
let s:state_table.loading = s:create_table({
\   'count': 0,
\   'graph': map(['|', '/', '-', '\'], '"loading....." . v:val'),
\})
function! s:state_table.loading.func()
    if self.count is 10
        call s:set_state('setup')
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
let s:state_table.setup = s:create_table()
function! s:state_table.setup.func()
    call s:choose_field()
    %delete _
    for i in range(len(s:field))
        call setline(i ==# 0 ? 1 : line('$') + 1, s:field[i])
        redraw
        sleep 200m
    endfor
    call s:move_to_start_point()

    call s:set_state('main')
endfunction
" --------- setup end ---------

" --------- fast_setup ---------
let s:state_table.fast_setup = s:create_table()
function! s:state_table.fast_setup.func()
    call s:choose_field()
    %delete _
    call setline(1, s:field)
    call s:move_to_start_point()

    call s:set_state('main')
endfunction
" --------- fast_setup end ---------

" --------- main ---------
let s:state_table.main = s:create_table({
\   'move_count': 0,
\   'left_time': 999,
\   'keys': {
\       'j': {'x':  0, 'y': +1},
\       'k': {'x':  0, 'y': -1},
\       'h': {'x': -1, 'y': 0},
\       'l': {'x': +1, 'y': 0},
\   },
\})
function! s:state_table.main.func()
    let self.left_time -= 1

    " Time is over!!
    if self.left_time is -1
        call s:set_state('gameover')
        return
    endif

    " TODO: Draw only changed point(s)
    call setline(1, s:field + [
    \   '',
    \   'Left Time: ' . self.left_time,
    \])
endfunction
function! s:state_table.main.on_key(key)
    if !has_key(self.keys, a:key)
        return
    endif
    let x = self.keys[a:key].x
    let y = self.keys[a:key].y

    " Do `let self.left_time -= 1` once per 5 times.
    if self.move_count is 5
        let self.left_time -= 1
        let self.move_count = 0
    endif
    let self.move_count += 1

    let coord = {'x': col('.') - 1 + x, 'y': line('.') - 1 + y}
    let line = getline(coord.y + 1)
    if coord.x <# 0 || coord.x >=# len(line)
        " Out of text! (virtualedit is "")
        return ''
    endif

    let mark_type = s:get_mark_type(line[coord.x])
    if mark_type ==# s:MARK_FREE_SPACE
        " Move to h/j/k/l (Simply return h/j/k/l key)
        return a:key
    elseif mark_type ==# s:MARK_FEED
        call s:field_set_char(s:CHAR_FREE_SPACE, coord.x, coord.y)
        return a:key.'r '
    else " s:MARK_WALL, and others
        return ''
    endif
endfunction
" --------- main end ---------

" --------- gameover ---------
let s:state_table.gameover = s:create_table()
function! s:state_table.gameover.func()
    %delete _
    a
  ####     ##    #    #  ######   ####   #    #  ######  #####
 #    #   #  #   ##  ##  #       #    #  #    #  #       #    #
 #       #    #  # ## #  #####   #    #  #    #  #####   #    #
 #  ###  ######  #    #  #       #    #  #    #  #       #####
 #    #  #    #  #    #  #       #    #   #  #   #       #   #
  ####   #    #  #    #  ######   ####     ##    ######  #    #
.
endfunction
" --------- gameover end ---------

" --------- pause ---------
let s:state_table.pause = s:create_table()
" --------- pause end ---------


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
