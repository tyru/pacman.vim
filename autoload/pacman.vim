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


" ---------------------- Vim Interface for Pacman ---------------------- {{{

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
    \   's', 'S', 'c', 'C', 'd', 'D', 'r', 'R',
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

" ---------------------- Vim Interface for Pacman end ---------------------- }}}


" ---------------------- Utilities ---------------------- {{{

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
" Return empty string for 'on_key()'
function! s:nop(...)
    return ''
endfunction
function! s:SID()
    return matchstr(expand('<sfile>'), '<SNR>\zs\d\+\ze_SID$')
endfunction
function! s:localfunc(name)
    return function('<SNR>'.s:SID().'_'.a:name)
endfunction
function! s:assert(cond, msg)
    if !a:cond
        throw 'assertion failure: '.a:msg
    endif
endfunction

" ---------------------- Utilities end ---------------------- }}}


" ---------------------- Field ---------------------- {{{

" TODO: Implement field auto-generation.
let s:field = {
\   'map': [],
\   '__drawn_map': [],
\   'enemies': [],
\   'start_point_coord': {'x': -1, 'y': -1},
\   'enemy_action_map': [],
\   'feed_num': -1,
\}
let s:FIELDS = []

let s:CHAR_START_POINT = '+'
let s:CHAR_FREE_SPACE = ' '
let s:CHAR_FEED = '$'
let s:CHAR_ENEMY = '*'

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

function! s:enemy_action_turn()
    " TODO
endfunction

let s:ACTION_NOP = 'nop'
let s:ACTION_TURN = 'turn'
let s:ACTION = {
\   s:ACTION_NOP : s:localfunc('nop'),
\   s:ACTION_TURN : s:localfunc('enemy_action_turn'),
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
    call s:initialize_field()
endfunction
function! s:initialize_field()
    " Parse headers.
    let headers = s:parse_field_headers()
    if empty(s:field.map)
        throw 'No map data in map file.'
    endif
    " Generate enemy action map from s:field.map
    " whose headers were removed.
    let s:field.enemy_action_map = repeat(
    \   [repeat([s:ACTION_NOP], len(s:field.map[0]))],
    \   len(s:field.map)
    \)
    " Clear previous data.
    let s:field.start_point_coord.x = -1
    let s:field.start_point_coord.y = -1
    let s:field.__drawn_map = []
    let s:field.feed_num = 0
    let s:field.enemies = []
    " Scan field.
    call s:field_scan(s:field.map, 's:field_get_init_info', {
    \   'headers' : headers,
    \})
endfunction
function! s:parse_field_headers()
    let headers = {}
    let rx = '^\([^[:space:]]\)\s*=\s*\(.\+\)'
    while !empty(s:field.map)
        let h = s:field.map[0]
        let m = matchlist(h, rx)
        if empty(m) | break | endif

        unlet s:field.map[0]
        let [lhs, rhs] = m[1:2]
        let headers[lhs] = s:parse_field_header_rhs(rhs)
        call s:assert(has_key(headers[lhs], 'char'),
        \   'headers[lhs] must have key "char" at least.')
    endwhile
    return headers
endfunction
function! s:parse_field_header_rhs(rhs)
    let rhs = a:rhs
    let result = {}
    " e.g., "$", '*', ...
    let char_in_quotes = ['^\(["'']\)\(.\)\1', 2]
    let actions = ['^\('.join(keys(s:ACTION), '\|').'\)', 1]
    let handlers = {
    \   char_in_quotes[0] : 'char',
    \   actions[0]        : 'action',
    \}
    while 1
        let rhs = substitute(rhs, '^\s\+', '', '')
        let last_match = []
        for [p, idx] in [char_in_quotes, actions]
            let last_match = matchlist(rhs, p)
            if !empty(last_match)
                let rhs = substitute(rhs, p, '', '')
                let result[handlers[p]] = last_match[idx]
                let rhs = substitute(rhs, '^\s\+', '', '')
                if rhs ==# ''
                    return result
                endif
                if rhs[0] !=# '+'
                    throw "parse error: expected '+': "
                    \   . string(rhs)
                endif
                " Found "+". go to next pattern...
                let rhs = substitute(rhs, '^+\s*', '', '')
                break
            endif
        endfor
        if empty(last_match)
            " No match.
            throw 'parse error: unknown token here: '
            \   . string(rhs)
        endif
    endwhile
    throw 'never reach here!'
endfunction
function! s:field_scan(map, func, stash)
    for y in range(len(a:map))
        for x in range(len(a:map[y]))
            call call(a:func, [a:map[y][x], x, y, a:stash])
        endfor
    endfor
endfunction
function! s:field_get_init_info(c, x, y, stash)
    let c = a:c
    let x = a:x
    let y = a:y
    let start_point_coord = s:field.start_point_coord
    let headers = a:stash.headers
    if has_key(headers, c)
        " Expand header (macro).
        call s:field_set_char(headers[c].char, x, y)
        if has_key(headers[c], 'action')
            let s:field.enemy_action_map[y][x] =
            \   s:ACTION[headers[c].action]
        endif
    endif
    if c ==# s:CHAR_START_POINT
        if start_point_coord.x isnot -1
        \   && start_point_coord.y isnot -1
            call s:echomsg('WarningMsg', 'warning: '
            \   . 'there must be start point only one '
            \   . 'in a field. ignoring...')
            continue
        endif
        let start_point_coord.x = x
        let start_point_coord.y = y
    elseif c ==# s:CHAR_FEED
        let s:field.feed_num += 1
    elseif c ==# s:CHAR_ENEMY
        call add(s:field.enemies, s:enemy_new(x, y, 2))
        call s:field_set_char(s:CHAR_FREE_SPACE, x, y)
    endif
endfunction
function! s:move_to_start_point()
    let coord = s:field.start_point_coord
    let x = coord.x
    let y = coord.y
    if y <# 0 || y >=# len(s:field.map)
    \   || x <# 0 || x >=# len(s:field.map[0])
        throw 'No start point found in a field.'
    endif
    " Rewrite s:CHAR_START_POINT to s:CHAR_FREE_SPACE.
    call s:field_set_char(s:CHAR_FREE_SPACE, x, y)
    " Move cursor to free space. (not wall)
    call cursor(y + 1, x + 1)
endfunction

" Vim does not support assignment to a character of String...
"let s:field.map[a:y][a:x]  = s:CHAR_START_POINT
function! s:field_set_char(char, x, y)
    call s:__field_set(s:field.map, a:char, a:x, a:y)
    let s:field.__drawn_map = []
endfunction
function! s:field_drawn_set_char(char, x, y)
    call s:__field_set(s:field.__drawn_map, a:char, a:x, a:y)
endfunction
function! s:__field_set(map, char, x, y)
    if a:y <# 0 || a:y >=# len(a:map)
    \   || a:x <# 0 || a:x >=# len(a:map[a:y])
    \   || strlen(a:char) !=# 1
        return
    endif
    let line = a:map[a:y]
    let middle_left = (a:x ==# 0 ? '' : line[: a:x - 1])
    let middle_right = (a:x ==# len(line) - 1 ? '' : line[a:x + 1 :])
    let a:map[a:y] = middle_left . a:char . middle_right
endfunction
function! s:field_get_feed_num()
    return s:field.feed_num
endfunction
function! s:field_dec_feed_num()
    let s:field.feed_num -= 1
endfunction
function! s:field_get_map()
    if empty(s:field.__drawn_map)
        let s:field.__drawn_map = deepcopy(s:field.map)
        " Place enemies on `s:field.map`.
        for enemy in s:field.enemies
            call s:field_drawn_set_char(s:CHAR_ENEMY, enemy.x, enemy.y)
        endfor
    endif
    return s:field.__drawn_map
endfunction
function! s:field_get_char(x, y)
    return s:field.map[a:y][a:x]
endfunction
function! s:field_update_enemy_coord(enemy)
    let s:field.__drawn_map = []
    let a:enemy.x += s:DIR[a:enemy.move_dir].dx
    let a:enemy.y += s:DIR[a:enemy.move_dir].dy
endfunction
function! s:field_move_all_enemies()
    for enemy in s:field.enemies
        call enemy.move()
    endfor
endfunction
function! s:field_draw_text(lnum, text)
    call setline(a:lnum, a:text)
endfunction
function! s:field_draw_field_delay(ms)
    return s:field_draw_lines_delay(1, s:field_get_map(), a:ms)
endfunction
function! s:field_draw_field()
    call setline(1, s:field_get_map())
endfunction
function! s:field_draw_append(lines)
    call setline(line('$') + 1, a:lines)
endfunction
function! s:field_clear_field()
    %delete _
endfunction
function! s:field_clear_last_line()
    $delete _
endfunction
function! s:field_draw_lines_delay(lnum, lines, ms)
    for i in range(len(a:lines))
        let lnum = a:lnum + (i ==# 0 ? 0 : line('$'))
        call setline(lnum, a:lines[i])
        redraw
        execute 'sleep' a:ms.'m'
    endfor
endfunction
" ---------------------- Field end ---------------------- }}}


" ---------------------- Enemy ---------------------- {{{

let s:enemy = {
\   'x': -1,
\   'y': -1,
\   'speed': -1,
\   'speed_counter': -1,
\   'move_dir': s:DIR_UP,
\}
function! s:enemy_new(x, y, speed)
    if a:x <# 0
        throw 's:enemy_new(): invalid x number: '.a:x
    endif
    if a:y <# 0
        throw 's:enemy_new(): invalid y number: '.a:y
    endif
    if a:speed <# 0
        throw 's:enemy_new(): invalid speed number: '.a:speed
    endif

    let dir = [
    \   s:DIR_UP,
    \   s:DIR_RIGHT,
    \   s:DIR_DOWN,
    \   s:DIR_LEFT
    \][s:rand(4)]
    return extend(deepcopy(s:enemy), {
    \   'x': a:x,
    \   'y': a:y,
    \   'speed': a:speed,
    \   'speed_counter': 0,
    \   'move_dir': dir,
    \}, 'force')
endfunction
function! s:enemy.move()
    let self.speed_counter += 1
    if self.speed_counter <# self.speed
        return
    endif
    " Move!
    let self.speed_counter = 0

    " Choose next direction.
    let dirs = copy(s:DIR)
    while !empty(dirs)
        " Move to `self.move_dir`.
        let dx = s:DIR[self.move_dir].dx
        let dy = s:DIR[self.move_dir].dy
        let x  = self.x + dx
        let y  = self.y + dy
        let mark_type = s:get_mark_type(s:field_get_char(x, y))
        if mark_type is s:MARK_FEED
        \   || mark_type is s:MARK_FREE_SPACE
            " Update enemies' coords.
            call s:field_update_enemy_coord(self)
            return
        else
            " If enemy can't go to next coord,
            " try another directions.
            unlet dirs[self.move_dir]
            let self.move_dir = keys(dirs)[s:rand(len(dirs))]
        endif
    endwhile

    throw "enemy: Can't move to anywhere!"
endfunction

" ---------------------- Enemy end ---------------------- }}}


" ---------------------- Scenes ---------------------- {{{

function! s:main_loop()
    let b:pacman.previous_changedtick =
    \   get(b:pacman, 'previous_changedtick', b:changedtick)
    if b:changedtick isnot b:pacman.previous_changedtick
        undo
    endif
    call b:pacman.current_table.func()
    call s:field_move_all_enemies()
    let b:pacman.previous_changedtick = b:changedtick
endfunction

function! s:set_state(state)
    let s:state = a:state
    let b:pacman.current_table = deepcopy(s:state_table[s:state])
    unlockvar! b:pacman.current_table
endfunction
" DSL for creating table.
function! s:create_table(...)
    return extend(copy(s:BASE_TABLE), a:0 ? copy(a:1) : {}, 'force')
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
        call s:field_draw_text(1, 'load what? :p')
        redraw
        sleep 1
        return
    endif
    let self.count += 1
    call s:field_draw_text(1, self.graph[self.count % len(self.graph)])
endfunction
" --------- loading end ---------

" --------- setup ---------
let s:state_table.setup = s:create_table()
function! s:state_table.setup.func()
    call s:choose_field()
    call s:field_clear_field()
    call s:field_draw_field_delay(200)
    call s:move_to_start_point()

    call s:set_state('main')
endfunction
" --------- setup end ---------

" --------- fast_setup ---------
let s:state_table.fast_setup = s:create_table()
function! s:state_table.fast_setup.func()
    call s:choose_field()
    call s:field_clear_field()
    call s:field_draw_field()
    call s:move_to_start_point()

    call s:set_state('main')
endfunction
" --------- fast_setup end ---------

" --------- main ---------
let s:state_table.main = s:create_table({
\   'moving_to_next_stage': 0,
\   '__start_time': -1,
\})
function! s:state_table.main.func()
    if self.__start_time is -1
        let self.__start_time = localtime() + 999
    endif

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
    if self.get_left_time() <=# 0
        call s:set_state('gameover')
        return
    endif
    " Draw a field.
    call self.draw_field()
endfunction
function! s:state_table.main.draw_field()
    " TODO: Draw only changed point(s)
    let pos = getpos('.')
    try
        call s:field_clear_field()
        call s:field_draw_field()
        call s:field_draw_append([
        \   '',
        \   'Left Time: ' . self.get_left_time(),
        \])
    finally
        call setpos('.', pos)
    endtry
endfunction
function! s:state_table.main.on_key(key)
    if !has_key(s:DIR, a:key)
        return ''
    endif
    " Move enemies.
    call s:field_move_all_enemies()
    " Move player.
    return self.move_player(a:key)
endfunction
function! s:state_table.main.move_player(key)
    let dx = s:DIR[a:key].dx
    let dy = s:DIR[a:key].dy

    let coord = {'x': col('.') - 1 + dx, 'y': line('.') - 1 + dy}
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
function! s:state_table.main.get_left_time()
    return self.__start_time - localtime()
endfunction
" --------- main end ---------

" --------- next_stage ---------
let s:state_table.next_stage = s:create_table()
function! s:state_table.next_stage.func()
    " Delete the last line.
    call s:field_clear_last_line()
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
    call s:field_clear_field()
    call s:field_draw_lines_delay(1, [
    \   '  ####     ##    #    #  ######   ####   #    #  ######  #####',
    \   ' #    #   #  #   ##  ##  #       #    #  #    #  #       #    #',
    \   ' #       #    #  # ## #  #####   #    #  #    #  #####   #    #',
    \   ' #  ###  ######  #    #  #       #    #  #    #  #       #####',
    \   ' #    #  #    #  #    #  #       #    #   #  #   #       #   #',
    \   '  ####   #    #  #    #  ######   ####     ##    ######  #    #',
    \], 200)
    " TODO: Implement "continue?" button.
    call s:pause()
endfunction
" --------- gameover end ---------

lockvar! s:state_table

" ---------------------- Scenes end ---------------------- }}}


" Restore 'cpoptions' {{{
let &cpo = s:save_cpo
" }}}
