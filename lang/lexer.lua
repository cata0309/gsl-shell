local ffi = require('ffi')

local band = bit.band
local strsub, strbyte, strchar = string.sub, string.byte, string.char

local ASCII_0, ASCII_9 = 48, 57
local ASCII_a, ASCII_z = 97, 122
local ASCII_A, ASCII_Z = 65, 90

local END_OF_STREAM = -1

local ReservedKeyword = {['and'] = 1, ['break'] = 2, ['do'] = 3, ['else'] = 4, ['elseif'] = 5, ['end'] = 6, ['false'] = 7, ['for'] = 8, ['function'] = 9, ['goto'] = 10, ['if'] = 11, ['in'] = 12, ['local'] = 13, ['nil'] = 14, ['not'] = 15, ['or'] = 16, ['repeat'] = 17, ['return'] = 18, ['then'] = 19, ['true'] = 20, ['until'] = 21, ['while'] = 22 }

local uint64, int64 = ffi.typeof('uint64_t'), ffi.typeof('int64_t')
local complex = ffi.typeof('complex')

local TokenSymbol = { TK_ge = '>=', TK_le = '<=' , TK_concat = '..', TK_eq = '==', TK_ne = '~=', TK_eof = '<eof>' }

local function token2str(tok)
    if string.match(tok, "^TK_") then
        return TokenSymbol[tok] or string.sub(tok, 4)
    else
        return tok
    end
end

local function error_lex(chunkname, tok, line, em, ...)
    local emfmt = string.format(em, ...)
    local msg = string.format("%s:%d: %s", chunkname, line, emfmt)
    if tok then
        msg = string.format("%s near '%s'", msg, tok)
    end
    error("LLT-ERROR" .. msg, 0)
end

local function lex_error(ls, token, em, ...)
    local tok
    if token == 'TK_name' or token == 'TK_string' or token == 'TK_number' then
        tok = ls.save_buf
    elseif token then
        tok = token2str(token)
    end
    error_lex(ls.chunkname, tok, ls.linenumber, em, ...)
end

local function char_isident(c)
    if type(c) == 'string' then
        local b = strbyte(c)
        if b >= ASCII_0 and b <= ASCII_9 then
            return true
        elseif b >= ASCII_a and b <= ASCII_z then
            return true
        elseif b >= ASCII_A and b <= ASCII_Z then
            return true
        else
            return (c == '_')
        end
    end
    return false
end

local function char_isdigit(c)
    if type(c) == 'string' then
        local b = strbyte(c)
        return b >= ASCII_0 and b <= ASCII_9
    end
    return false
end

local function char_isspace(c)
    local b = strbyte(c)
    return b >= 9 and b <= 13 or b == 32
end

local function byte(ls, n)
    local k = ls.p + n
    return strsub(ls.data, k, k)
end

local function skip(ls, n)
    ls.n = ls.n - n
    ls.p = ls.p + n
end

local function pop(ls)
    local k = ls.p
    local c = strsub(ls.data, k, k)
    ls.p = k + 1
    ls.n = ls.n - 1
    return c
end

local function fillbuf(ls)
    local data = ls:read_func()
    if not data then
        return END_OF_STREAM
    end
    ls.data, ls.n, ls.p = data, #data, 1
    return pop(ls)
end

local function nextchar(ls)
    local c = ls.n > 0 and pop(ls) or fillbuf(ls)
    ls.current = c
    return c
end

local function curr_is_newline(ls)
    local c = ls.current
    return (c == '\n' or c == '\r')
end

local function resetbuf(ls)
    ls.save_buf = ''
end

local function save(ls, c)
    ls.save_buf = ls.save_buf .. c
end

local function save_and_next(ls)
    ls.save_buf = ls.save_buf .. ls.current
    nextchar(ls)
end

local function get_string(ls, init_skip, end_skip)
    return strsub(ls.save_buf, init_skip + 1, - (end_skip + 1))
end

local function inclinenumber(ls)
    local old = ls.current
    nextchar(ls) -- skip `\n' or `\r'
    if curr_is_newline(ls) and ls.current ~= old then
        nextchar(ls) -- skip `\n\r' or `\r\n'
    end
    ls.linenumber = ls.linenumber + 1
end

local function skip_sep(ls)
    local count = 0
    local s = ls.current
    assert(s == '[' or s == ']')
    save_and_next(ls)
    while ls.current == '=' do
        save_and_next(ls)
        count = count + 1
    end
    return ls.current == s and count or (-count - 1)
end

local function build_64int(str)
    local u = str[#str - 2]
    local x = (u == 117 and uint64(0) or int64(0))
    local i = 1
    while str[i] <= ASCII_9 do
        x = 10 * x + (str[i] - ASCII_0)
        i = i + 1
    end
    return x
end

local function strnumdump(str)
    local t = {}
    for i = 1, #str do
        local c = strsub(str, i, i)
        if char_isident(c) then
            t[i] = strbyte(c)
        else
            return nil
        end
    end
    return t
end

local function lex_number(ls)
    local lower = string.lower
    local xp = 'e'
    local c = ls.current
    if c == '0' then
        save_and_next(ls)
        local xc = ls.current
        if xc == 'x' or xc == 'X' then xp = 'p' end
    end
    while char_isident(ls.current) or ls.current == '.' or
        ((ls.current == '-' or ls.current == '+') and lower(c) == xp) do
        c = lower(ls.current)
        save(ls, c)
        nextchar(ls)
    end
    local str = ls.save_buf
    local x
    if strsub(str, -1, -1) == 'i' then
        local img = tonumber(strsub(str, 1, -2))
        if img then x = complex(0, img) end
    elseif strsub(str, -2, -1) == 'll' then
        local t = strnumdump(str)
        if t then x = build_64int(t) end
    else
        x = tonumber(str)
    end
    if x then
        return x
    else
        lex_error(ls, 'TK_number', "malformed number")
    end
end

local function read_long_string(ls, sep, ret_value)
    save_and_next(ls) -- skip 2nd `['
    if curr_is_newline(ls) then -- string starts with a newline?
        inclinenumber(ls) -- skip it
    end
    while true do
        local c = ls.current
        if c == END_OF_STREAM then
            lex_error(ls, 'TK_eof', ret_value and "unfinished long string" or "unfinished long comment")
        elseif c == ']' then
            if skip_sep(ls) == sep then
                save_and_next(ls) -- skip 2nd `['
                break
            end
        elseif c == '\n' or c == '\r' then
            save(ls, '\n')
            inclinenumber(ls)
            if not ret_value then
                resetbuf(ls) -- avoid wasting space
            end
        else
            if ret_value then save_and_next(ls)
            else nextchar(ls) end
        end
    end
    if ret_value then
        return get_string(ls, 2 + sep, 2 + sep)
    end
end

local Escapes = {
    a = '\a', b = '\b', f = '\f', n = '\n', r = '\r', t = '\t',
    v = '\v',
}

local function hex_char(c)
    if string.match(c, '^%x') then
        local b = band(strbyte(c), 15)
        if not char_isdigit(c) then b = b + 9 end
        return b
    end
end

local function read_string(ls, delim)
    save_and_next(ls)
    while ls.current ~= delim do
        local c = ls.current
        if c == END_OF_STREAM then
            lex_error(ls, 'TK_eof', "unfinished string")
        elseif c == '\n' or c == '\r' then
            lex_error(ls, 'TK_string', "unfinished string")
        elseif c == '\\' then
            c = nextchar(ls) -- Skip the '\\'.
            local esc = Escapes[c]
            if esc then
                c = esc
            elseif c == 'x' then -- Hexadecimal escape '\xXX'.
                local ch1 = hex_char(nextchar(ls))
                c = nil
                if ch1 then
                    local ch2 = hex_char(nextchar(ls))
                    if ch2 then
                        c = strchar(ch1 * 16 + ch2)
                    end
                end
                if not c then
                    lex_error(ls, 'TK_string', "invalid escape sequence")
                end
            elseif c == 'z' then -- Skip whitespace.
                nextchar(ls)
                while char_isspace(ls.current) do
                    if curr_is_newline(ls) then inclinenumber(ls) else nextchar(ls) end
                end
            elseif c == '\n' or c == '\r' then
                save(ls, '\n')
                inclinenumber(ls)
            elseif c == '\\' or c == '\"' or c == '\''  or c == END_OF_STREAM then
            else
                if not char_isdigit(c) then
                    lex_error(ls, 'TK_string', "invalid escape sequence")
                end
                local bc = band(strbyte(c), 15) -- Decimal escape '\ddd'.
                if char_isdigit(nextchar(ls)) then
                    bc = bc * 10 + band(strbyte(ls.current), 15)
                    if char_isdigit(nextchar(ls)) then
                        bc = bc * 10 + band(strbyte(ls.current), 15)
                        if bc > 255 then
                            lex_error(ls, 'TK_string', "invalid escape sequence")
                        end
                    end
                end
                c = strchar(bc)
            end
            save(ls, c)
            nextchar(ls)
        else
            save_and_next(ls)
        end
    end
    save_and_next(ls) -- skip delimiter
    return get_string(ls, 1, 1)
end

local function llex(ls)
    resetbuf(ls)
    while true do
        local current = ls.current
        if char_isident(current) then
            if char_isdigit(current) then -- Numeric literal.
                return 'TK_number', lex_number(ls)
            end
            repeat
                save_and_next(ls)
            until not char_isident(ls.current)
            local s = get_string(ls, 0, 0)
            local reserved = ReservedKeyword[s]
            if reserved then
                return 'TK_' .. s
            else
                return 'TK_name', s
            end
        end
        if current == '\n' or current == '\r' then
            inclinenumber(ls)
        elseif current == ' ' or current == '\t' or current == '\b' or current == '\f' then
            nextchar(ls)
        elseif current == '-' then
            nextchar(ls)
            if ls.current ~= '-' then return '-' end
            -- else is a comment
            nextchar(ls)
            if ls.current == '[' then
                local sep = skip_sep(ls)
                resetbuf(ls) -- `skip_sep' may dirty the buffer
                if sep >= 0 then
                    read_long_string(ls, sep, false) -- long comment
                    resetbuf(ls)
                end
            end
            while not curr_is_newline(ls) and ls.current ~= END_OF_STREAM do
                nextchar(ls)
            end
        elseif current == '[' then
            local sep = skip_sep(ls)
            if sep >= 0 then
                local str = read_long_string(ls, sep, true)
                return 'TK_string', str
            elseif sep == -1 then
                return '['
            else
                lex_error(ls, 'TK_string', "delimiter error")
            end
        elseif current == '=' then
            nextchar(ls)
            if ls.current ~= '=' then return '=' else nextchar(ls); return 'TK_eq' end
        elseif current == '<' then
            nextchar(ls)
            if ls.current ~= '=' then return '<' else nextchar(ls); return 'TK_le' end
        elseif current == '>' then
            nextchar(ls)
            if ls.current ~= '=' then return '>' else nextchar(ls); return 'TK_ge' end
        elseif current == '~' then
            nextchar(ls)
            if ls.current ~= '=' then return '~' else nextchar(ls); return 'TK_ne' end
        elseif current == ':' then
            nextchar(ls)
            if ls.current ~= ':' then return ':' else nextchar(ls); return 'TK_label' end
        elseif current == '"' then
            local str = read_string(ls, current)
            return 'TK_string', str
        elseif current == '.' then
            save_and_next(ls)
            if ls.current == '.' then
                nextchar(ls)
                if ls.current == '.' then
                    nextchar(ls)
                    return 'TK_dots' -- ...
                end
                return 'TK_concat' -- ..
            elseif not char_isdigit(ls.current) then
                return '.'
            else
                return 'TK_number', lex_number(ls)
            end
        elseif current == END_OF_STREAM then
            return 'TK_eof'
        else
            nextchar(ls)
            return current -- Single-char tokens (+ - / ...).
        end
    end
end

local Lexer = {
    token2str = token2str,
    error = lex_error,
}

function Lexer.next(ls)
    ls.lastline = ls.linenumber
    if ls.tklookahead == 'TK_eof' then -- No lookahead token?
        ls.token, ls.tokenval = llex(ls) -- Get nextchar token.
    else
        ls.token, ls.tokenval = ls.tklookahead, ls.tklookaheadval
        ls.tklookahead = 'TK_eof'
    end
end

function Lexer.lookahead(ls)
    assert(ls.tklookahead == 'TK_eof')
    ls.tklookahead, ls.tklookaheadval = llex(ls)
    return ls.tklookahead
end

local LexerClass = { __index = Lexer }

local function lex_setup(read_func, chunkname)
    local header = false
    local ls = {
        n = 0,
        tklookahead = 'TK_eof', -- No look-ahead token.
        linenumber = 1,
        lastline = 1,
        read_func = read_func,
        chunkname = chunkname,
    }
    nextchar(ls)
    if ls.current == '\xef' and ls.n >= 2 and
        byte(ls, 0) == '\xbb' and byte(ls, 1) == '\xbf' then -- Skip UTF-8 BOM (if buffered).
        ls.n = ls.n - 2
        ls.p = ls.p + 2
        nextchar(ls)
        header = true
    end
    if ls.current == '#' then
        repeat
            nextchar(ls)
            if ls.current == END_OF_STREAM then return ls end
        until curr_is_newline(ls)
        inclinenumber(ls)
        header = true
    end
    return setmetatable(ls, LexerClass)
end

return lex_setup
