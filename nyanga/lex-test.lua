local band = bit.band

local ASCII_0, ASCII_9 = 48, 57
local ASCII_a, ASCII_z = 97, 122
local ASCII_A, ASCII_Z = 65, 90

local tricky_string = 'ciao \x6aason \106ack \t\r\n\v'
local hex_num = 0xffee
local dec_num = 1.23e-12
local img_num = 3 + 4i
local ll, ull = 12LL, 12ULL

local END_OF_STREAM = -1

local ReservedKeyword = {['and'] = 1, ['break'] = 2, ['do'] = 3, ['else'] = 4, ['elseif'] = 5, ['end'] = 6, ['false'] = 7, ['for'] = 8, ['function'] = 9, ['goto'] = 10, ['if'] = 11, ['in'] = 12, ['local'] = 13, ['nil'] = 14, ['not'] = 15, ['or'] = 16, ['repeat'] = 17, ['return'] = 18, ['then'] = 19, ['true'] = 20, ['until'] = 21, ['while'] = 22 }

local function foo(...)
    return select('#', ...)
end

local some_x = .5

local raw_string = [[C:\temp\somefile.dat]]
local long_string = [[
   Some very long
   string
   here! "I mean"
]]

--[[
   A very long comment
   HERE!
]]

setmetatable(_G, {
    __index = function(t, x) error('undefined global ' .. x) end,
    __newindex = function(t, k, v) error('undefined global ' .. k) end
    }
)

local function char_isident(c)
    if type(c) == 'string' then
        -- print('char:'.. c .. '.')
        local b = string.byte(c)
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