-- REAL LUA STRINGS: protobuf + gzip in an isolated Neovim debuggee. F5: next stop.
-- Only counter changes at B, protobuf age at C, gzip age at D; E is unchanged.
local root = vim.fn.fnamemodify(debug.getinfo(1, "S").source:sub(2), ":p:h") .. "/"
local function read(name)
    local file = assert(io.open(root .. name, "rb"))
    local bytes = file:read("*a")
    file:close()
    return setmetatable({ data = bytes }, {
        __tostring = function()
            return "binary buffer"
        end,
    })
end
local function run()
    local unchanged = "Ada"
    local counter = 37
    local protobuf_wire = read("protobuf-37.bin")
    local gzip_wire = read("gzip-37.bin")
    print("A: initial") -- STOP: initial
    counter = 38
    print("B: only counter changed") -- STOP: counter
    protobuf_wire = read("protobuf-38.bin")
    print("C: only protobuf age changed") -- STOP: protobuf
    gzip_wire = read("gzip-38.bin")
    print("D: only gzip age changed") -- STOP: gzip
    print("E: no changes", counter, unchanged) -- STOP: unchanged
end
run()
