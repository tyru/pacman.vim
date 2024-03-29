" vim:foldmethod=marker:fen:
scriptencoding utf-8

" Saving 'cpoptions' {{{
let s:save_cpo = &cpo
set cpo&vim
" }}}


" Delay rewriting feed character to free space character.
if !exists('g:pacman#eat_effect')
    let g:pacman#eat_effect = 1
endif


function! s:playing()
    return exists('b:pacman')
endfunction

function! pacman#start(skip_loading)
    if s:playing()
        execute b:pacman.caller_bufnr 'buffer'
        return
    endif

    " Create buffer.
    call s:create_buffer()

    " a:skip_loading for debug.
    call s:set_state(a:skip_loading ? 'fast_setup' : 'loading')
endfunction
function! s:create_buffer()
    let caller_bufnr = bufnr('%')
    enew
    let b:pacman = {}
    let b:pacman.pausing = 0
    let b:pacman.caller_bufnr = caller_bufnr

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
    let b:pacman.save_updatetime = &updatetime
    set updatetime=100
    let b:pacman.save_lazyredraw = &lazyredraw
    set lazyredraw
    let b:pacman.save_virtualedit = &virtualedit
    set virtualedit=
    let b:pacman.save_insertmode = &insertmode
    set noinsertmode

    " TODO: Implement Konami command.
    for key in ['j', 'k', 'h', 'l']
        execute 'nnoremap <buffer><expr>' key
        \   'b:pacman.current_table.on_key('.string(key).')'
    endfor
    for key in [
    \   '0', '^', '$',
    \   'i', 'a', 'A',
    \   '/', '?',
    \   's', 'S', 'c', 'C', 'd', 'D',
    \]
        execute 'nnoremap <buffer>' key '<Nop>'
    endfor
    " Deep-Copy of `s:state_table[s:state]`.
    " `s:state_table[s:state]` and its keys/values DOES NOT change.
    " `b:pacman.current_table` does change.
    let b:pacman.current_table = {}

    augroup pacman
        autocmd!
        call s:register_polling_autocmd()
        " Inhibit insert-mode.
        autocmd InsertEnter <buffer> stopinsert
        " Pause on BufLeave, BufEnter.
        autocmd BufLeave <buffer> call s:pause()
        autocmd BufEnter <buffer> call s:restart()
        " Clean up all thingies about pacman.
        autocmd BufDelete <buffer> call s:clean_up()
    augroup END
endfunction

function! s:register_polling_autocmd()
    autocmd pacman CursorHold <buffer> silent call feedkeys("g\<Esc>", "n")
    autocmd pacman CursorHold <buffer> call s:main_loop()
    let b:pacman.pausing = 0
endfunction

function! s:unregister_polling_autocmd()
    autocmd! pacman CursorHold <buffer>
    let b:pacman.pausing = 1
endfunction

function! s:pausing()
    return b:pacman.pausing
endfunction

function! s:pause()
    if !s:playing() || s:pausing()
        return
    endif
    call s:unregister_polling_autocmd()
endfunction

function! s:restart()
    if !s:playing() || !s:pausing()
        return
    endif
    call s:register_polling_autocmd()
endfunction

function! s:clean_up()
    if !s:playing()
        return
    endif

    let &updatetime = b:pacman.save_updatetime
    let b:pacman.save_updatetime = -1
    let &lazyredraw = b:pacman.save_lazyredraw
    let b:pacman.save_lazyredraw = -1
    let &virtualedit = b:pacman.save_virtualedit
    let b:pacman.save_virtualedit = ''
    let &insertmode = b:pacman.save_insertmode
    let b:pacman.save_insertmode = ''

    execute b:pacman.caller_bufnr 'buffer'
endfunction




" TODO: Implement field auto-generation.
let s:field = {'map': [], 'feed_num': -1}
let s:FIELDS = []

let s:CHAR_START_POINT = '+'
let s:CHAR_FREE_SPACE = ' '
let s:CHAR_FEED = '$'

let s:DIR_DOWN = 'j'
let s:DIR_UP = 'k'
let s:DIR_LEFT = 'h'
let s:DIR_RIGHT = 'l'
let s:DIR = {
\   s:DIR_DOWN  : {'dx':  0, 'dy': +1},
\   s:DIR_UP    : {'dx':  0, 'dy': -1},
\   s:DIR_LEFT  : {'dx': -1, 'dy': 0},
\   s:DIR_RIGHT : {'dx': +1, 'dy': 0},
\}

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
                if start_point_coord.x isnot -1
                \   && start_point_coord.y isnot -1
                    call s:echomsg('WarningMsg', 'warning: '
                    \   . 'there must be start point only one '
                    \   . 'in a field. ignoring...')
                    continue
                endif
                let start_point_coord.x = x
                let start_point_coord.y = y
            elseif s:field.map[y][x] ==# s:CHAR_FEED
                let s:field.feed_num += 1
            endif
        endfor
    endfor
    if start_point_coord.x is -1
    \   || start_point_coord.y is -1
        throw 'No start point found in a field.'
    else
        call s:move_to_start_point(start_point_coord.x, start_point_coord.y)
    endif
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



function! s:main_loop()
    let b:pacman.previous_changedtick =
    \   get(b:pacman, 'previous_changedtick', b:changedtick)
    if b:changedtick isnot b:pacman.previous_changedtick
        undo
    endif
    call b:pacman.current_table.func()
    let b:pacman.previous_changedtick = b:changedtick
endfunction

function! s:set_state(state)
    let s:state = a:state
    let b:pacman.current_table = deepcopy(s:state_table[s:state])
    unlockvar! b:pacman.current_table
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


" TODO: Implement main menu scene.
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
\   'moving_to_next_stage': 0,
\   'pressing_keys': {
\       s:DIR_DOWN  : 0,
\       s:DIR_UP    : 0,
\       s:DIR_LEFT  : 0,
\       s:DIR_RIGHT : 0,
\   },
\})
function! s:state_table.main.func()
    if self.moving_to_next_stage
        " Draw current field before moving to next stage.
        " Because the last `s:CHAR_FEED` remains in a buffer.
        call self.draw_field()
        redraw
        sleep 1
        call s:set_state('next_stage')
        return
    endif

    " Time is over!!
    if self.left_time is 0
        call s:set_state('gameover')
        return
    endif
    let self.left_time -= 1

    " Move current position.
    call self.move()

    " Draw a field.
    call self.draw_field()
endfunction
function! s:state_table.main.move()
    let [lnum, col] = [line('.'), col('.')]

    if self.pressing_keys[s:DIR_DOWN]
        let lnum += 1
        let self.pressing_keys[s:DIR_DOWN] = 0
    endif

    if self.pressing_keys[s:DIR_LEFT]
        let col -= 1
        let self.pressing_keys[s:DIR_LEFT] = 0
    endif

    if self.pressing_keys[s:DIR_RIGHT]
        let col += 1
        let self.pressing_keys[s:DIR_RIGHT] = 0
    endif

    if self.pressing_keys[s:DIR_UP]
        let lnum -= 1
        let self.pressing_keys[s:DIR_UP] = 0
    endif

    call cursor(lnum, col)
endfunction
function! s:state_table.main.draw_field()
    " TODO: Draw only changed point(s)
    call setline(1, s:field_get_map() + [
    \   '',
    \   'Left Time: ' . self.left_time,
    \])
endfunction
function! s:state_table.main.on_key(key)
    if !has_key(s:DIR, a:key)
        return
    endif
    let dx = s:DIR[a:key].dx
    let dy = s:DIR[a:key].dy

    " Do `let self.left_time -= 1` once per 5 times.
    if self.move_count is 5
        let self.left_time -= 1
        let self.move_count = 0
    endif
    let self.move_count += 1

    let coord = {'x': col('.') - 1 + dx, 'y': line('.') - 1 + dy}
    let line = getline(coord.y + 1)
    if coord.x <# 0 || coord.x >=# len(line)
        " Out of text! (virtualedit is "")
        return ''
    endif

    let mark_type = s:get_mark_type(line[coord.x])
    if mark_type ==# s:MARK_FREE_SPACE
        " Set the flag of a:key
        if has_key(self.pressing_keys, a:key)
            let self.pressing_keys[a:key] = 1
        endif
        return ''
    elseif mark_type ==# s:MARK_FEED
        " Ate it. Mark here as a free space...
        call s:field_set_char(s:CHAR_FREE_SPACE, coord.x, coord.y)
        " Decrement the number of feeds in this field.map.
        call s:field_dec_feed_num()
        if s:field_get_feed_num() <=# 0
            " You have eaten all feeds!! Go to next stage...
            let self.moving_to_next_stage = 1
        endif
        return a:key . (g:pacman#eat_effect ? '' : 'r ')
    else " s:MARK_WALL, and others
        return ''
    endif
endfunction
" --------- main end ---------

" --------- next_stage ---------
let s:state_table.next_stage = s:create_table()
function! s:state_table.next_stage.func()
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




function! s:echomsg(hl, msg)
    try
        execute 'echohl' a:hl
        echomsg a:msg
    finally
        echohl None
    endtry
endfunction
function! s:rand(n)
    let match_end = matchend(reltimestr(reltime()), '\d\+\.') + 1
    return reltimestr(reltime())[match_end : ] % a:n
endfunction


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
