" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


function! s:playing()
    return exists('b:caller_bufnr')
endfunction

function! pacman#start(skip_loading)
    if s:playing()
        execute b:caller_bufnr 'buffer'
        return
    endif

    " Create buffer.
    let b:caller_bufnr = bufnr('%')
    call s:create_buffer()

    " a:skip_loading for debug.
    call s:set_state(a:skip_loading ? 'fast_setup' : 'loading')
endfunction
function! s:create_buffer()
    enew

    " Local options.
    setlocal buftype=nowrite
    setlocal noswapfile
    setlocal bufhidden=wipe
    setlocal buftype=nofile
    setlocal nonumber
    setlocal nowrap
    setlocal nocursorline
    setlocal nocursorcolumn

    " Global options.
    let b:save_updatetime = &updatetime
    set updatetime=100
    let b:save_lazyredraw = &lazyredraw
    set lazyredraw
    let b:save_virtualedit = &virtualedit
    set virtualedit=
    let b:save_insertmode = &insertmode
    set noinsertmode

    " TODO: Implement Konami command.
    for key in ['j', 'k', 'h', 'l']
        execute 'nnoremap <buffer><expr>' key 'b:pacman_current_table.on_key('.string(key).')'
    endfor
    for key in ['0', '^', '$', 'i', 'a', 'A', '/', '?']
        execute 'nnoremap <buffer>' key '<Nop>'
    endfor
    " Deep-Copy of `s:state_table[s:state]`.
    " `s:state_table[s:state]` and its keys/values DOES NOT change.
    " `b:pacman_current_table` does change.
    let b:pacman_current_table = {}

    augroup pacman
        autocmd!
        autocmd CursorHold <buffer> silent call feedkeys("g\<Esc>", "n")
        autocmd CursorHold <buffer> call b:pacman_current_table.func()
        autocmd InsertEnter <buffer> stopinsert
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

    let &updatetime = b:save_updatetime
    let b:save_updatetime = -1
    let &lazyredraw = b:save_lazyredraw
    let b:save_lazyredraw = -1
    let &virtualedit = b:save_virtualedit
    let b:save_virtualedit = ''
    let &insertmode = s:insertmode
    let b:save_insertmode = ''

    execute b:caller_bufnr 'buffer'
endfunction




" TODO: Implement field auto-generation.
let s:field = {'map': [], 'feed_num': -1}
let s:FIELDS = []

let s:CHAR_START_POINT = '+'
let s:CHAR_FREE_SPACE = ' '
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
\   s:CHAR_FEED       : s:MARK_FEED,
\}

function! s:get_mark_type(c)
    return get(s:CHAR_TO_MARK_TYPE_TABLE, a:c, s:MARK_WALL)
endfunction

function! s:rand(n)
    let match_end = matchend(reltimestr(reltime()), '\d\+\.') + 1
    return reltimestr(reltime())[match_end : ] % a:n
endfunction
function! s:choose_field()
    if empty(s:FIELDS)
        for map_file in split(
        \   globpath(&rtp, 'macros/pacman-fields/*', 1),
        \   '\n'
        \)
            try   | call add(s:FIELDS, readfile(map_file))
            catch | endtry
        endfor
    endif
    let s:field.map = deepcopy(s:FIELDS[s:rand(len(s:FIELDS))])
endfunction
function! s:initialize_field()
    let start_point_coord = {'x': -1, 'y': -1}
    let s:field.feed_num = 0
    " Scan field.
    for y in range(len(s:field.map))
        for x in range(len(s:field.map[y]))
            if s:field.map[y][x] ==# s:CHAR_START_POINT
                let start_point_coord.x = x
                let start_point_coord.y = y
            elseif s:field.map[y][x] ==# s:CHAR_FEED
                let s:field.feed_num += 1
            endif
        endfor
    endfor
    call s:move_to_start_point(start_point_coord.x, start_point_coord.y)
endfunction
function! s:move_to_start_point(x, y)
    " Rewrite s:CHAR_START_POINT to s:CHAR_FREE_SPACE.
    call s:field_set_char(s:CHAR_FREE_SPACE, a:x, a:y)
    " Move cursor to free space. (not wall)
    call cursor(a:y + 1, a:x + 1)
endfunction

" Vim does not support assignment to a character of String...
"let s:field.map[a:y][a:x]  = s:CHAR_START_POINT
function! s:field_set_char(char, x, y)
    if a:y <# 0 || a:y >=# len(s:field.map)
    \   || a:x <# 0 || a:x >=# len(s:field.map[a:y])
    \   || strlen(a:char) !=# 1
        return
    endif
    let line = s:field.map[a:y]
    let middle_left = (a:x ==# 0 ? '' : line[: a:x - 1])
    let middle_right = (a:x ==# len(line) - 1 ? '' : line[a:x + 1 :])
    let s:field.map[a:y] = middle_left . a:char . middle_right
endfunction
function! s:field_get_feed_num()
    return s:field.feed_num
endfunction
function! s:field_dec_feed_num()
    let s:field.feed_num -= 1
endfunction
function! s:field_get_map()
    return s:field.map
endfunction




function! s:set_state(state)
    let s:state = a:state
    let b:pacman_current_table = deepcopy(s:state_table[s:state])
    unlockvar! b:pacman_current_table
endfunction
" Return empty string for 'on_key()'
function! s:nop(...)
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
    let map = s:field_get_map()
    for i in range(len(map))
        call setline(i ==# 0 ? 1 : line('$') + 1, map[i])
        redraw
        sleep 200m
    endfor
    call s:initialize_field()

    call s:set_state('main')
endfunction
" --------- setup end ---------

" --------- fast_setup ---------
let s:state_table.fast_setup = s:create_table()
function! s:state_table.fast_setup.func()
    call s:choose_field()
    %delete _
    call setline(1, s:field_get_map())
    call s:initialize_field()

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
    " Time is over!!
    if self.left_time is 0
        call s:set_state('gameover')
        return
    endif
    let self.left_time -= 1

    " TODO: Draw only changed point(s)
    call setline(1, s:field_get_map() + [
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
        " Move cursor.
        return a:key
    elseif mark_type ==# s:MARK_FEED
        " Decrement the number of feeds in this field.map.
        call s:field_dec_feed_num()
        if s:field_get_feed_num() <=# 0
            " You have eaten all feeds!! Go to next stage...
            call s:set_state('next_stage')
        else
            " Ate it. Set a free space here...
            call s:field_set_char(s:CHAR_FREE_SPACE, coord.x, coord.y)
        endif
        " Move cursor.
        return a:key.'r '
    else " s:MARK_WALL, and others
        return ''
    endif
endfunction
" --------- main end ---------

" --------- next_stage ---------
let s:state_table.next_stage = s:create_table({'firstcall': 1})
function! s:state_table.next_stage.func()
    if self.firstcall
        sleep 1
    endif
    let self.firstcall = 0

    " Delete the last line.
    $delete _
    redraw
    " All lines were deleted.
    if line('$') is 1 && getline(1) ==# ''
        call s:set_state('setup')
    endif
endfunction
" --------- next_stage end ---------

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

lockvar! s:state_table


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
