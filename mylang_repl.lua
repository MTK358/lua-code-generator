
local mylang = require'mylang'

local pack = table.pack or function(...) return {n=select('#',...),...} end
local unpack = table.unpack or unpack

if arg[1] then
	local f = assert(io.open(arg[1]))
	local function stream()
		return f:read(1)
	end
	local chunk, errstr, errtbl = mylang.load(stream, arg[1])
	f:close()
	if chunk then
		local newarg = {}
		for k, v in pairs(arg) do
			newarg[k-1] = v
		end
		arg = newarg
		local success, result = pcall(chunk, unpack(arg))
		if not success then
			io.stdout:write(tostring(result)..'\n')
		end
	else
		io.stdout:write(errstr..'\n')
	end
	return
end

local function readln()
local line = io.stdin:read()
	if not line then
		io.stdout:write('\n')
		os.exit(0)
	end
	return line
end

local srcname = "(repl input)"

while true do
	io.stdout:write('>>> ')
	local line = readln()..'\n'
	local chunk, errstr, errtbl = mylang.load(line, srcname, env, true)
	while not chunk do
		if errtbl.cont then
			io.stdout:write('... ')
			line = line..readln()..'\n'
			chunk, errstr, errtbl = mylang.load(line, srcname, env, true)
		else
			io.stdout:write(errstr..'\n')
			break
		end
	end
	if chunk then
		local result = pack(pcall(chunk))
		if result[1] then
			if result.n >= 2 then
				for i = 2, result.n do
					if i > 2 then
						io.stdout:write'\t'
					end
					io.stdout:write(tostring(result[i]))
				end
				io.stdout:write'\n'
			end
		else
			io.stdout:write(tostring(result[2])..'\n')
		end
	end
end

