
local pairs = pairs
local ipairs = ipairs
local tostring = tostring
local type = type
local strfmt = string.format

local codegen_functions

local function loadwrapper(src, name, env)
	if setfenv then
		local chunk, err = loadstring(src, name)
		if chunk and env then setfenv(chunk, env) end
		return chunk, err
	else
		return load(src, name, "bt", env)
	end
end

local function codegen(state, node, ostream)
	if node.line then
		while node.line > state.line do
			ostream'\n'
			state.line = state.line + 1
		end
	end
	local f = codegen_functions[node[1]]
	if not f then
		error("invalid ast node: "..node[1])
	end
	return f(state, node, ostream)
end

codegen_functions = {
	["if"] = function (state, node, o)
		o" if "
		codegen(state, node[2], o)
		o" then "
		codegen(state, node[3], o)
		local i = 4
		while node[i+1] do
			o" elseif "
			codegen(state, node[i], o)
			o" then "
			codegen(state, node[i+1], o)
			i=i+2
		end
		if node[i] then
			o" else "
			codegen(state, node[i], o)
		end
		o" end "
	end,

	["while"] = function (state, node, o)
		o" while "
		codegen(state, node[2], o)
		o" do "
		codegen(state, node[3], o)
		o" end "
	end,

	["repeat"] = function (state, node, o)
		o" repeat "
		codegen(state, node[2], o)
		o" until "
		codegen(state, node[3], o)
	end,

	["for_num"] = function (state, node, o)
		o" for "
		o(node[2])
		o"="
		codegen(state, node[3], o)
		o","
		codegen(state, node[4], o)
		if node[5] then
			o","
			codegen(state, node[5], o)
		end
		o" do "
		codegen(state, node[6], o)
		o" end "
	end,

	["for_iter"] = function (state, node, o)
		o" for "
		codegen(state, node[2], o)
		o" in "
		codegen(state, node[3], o)
		o" do "
		codegen(state, node[4], o)
		o" end "
	end,

	["do"] = function (state, node, o)
		o" do "
		codegen(state, node[2], o)
		o" end "
	end,

	["function"] = function (state, node, o)
		o" function("
		for i, v in ipairs(node[2]) do
			if i ~= 1 then o"," end
			o(v)
		end
		o")"
		codegen(state, node[3], o)
		o" end "
	end,

	["binop"] = function (state, node, o)
		o"("
		codegen(state, node[3], o)
		o(node[2])
		codegen(state, node[4], o)
		o")"
	end,

	["unop"] = function (state, node, o)
		o"("
		o(node[2])
		codegen(state, node[3], o)
		o")"
	end,

	["gettable"] = function (state, node, o)
		codegen(state, node[2], o)
		o"["
		codegen(state, node[3], o)
		o"]"
	end,

	["call"] = function (state, node, o)
		codegen(state, node[2], o)
		o"("
		codegen(state, node[3], o)
		o")"
	end,

	["method_call"] = function (state, node, o)
		codegen(state, node[2], o)
		o":"
		o(node[3])
		o"("
		codegen(state, node[4], o)
		o")"
	end,

	["assign"] = function (state, node, o)
		codegen(state, node[2], o)
		o"="
		codegen(state, node[3], o)
	end,

	["local"] = function (state, node, o)
		o" local "
		codegen(state, node[2], o)
		if node[3] then
			o"="
			codegen(state, node[3], o)
		end
	end,

	["goto"] = function (state, node, o)
		o" goto "
		o(node[2])
	end,

	["label"] = function (state, node, o)
		o"::"
		o(node[2])
		o"::"
	end,

	["break"] = function (state, node, o)
		o" break "
	end,

	["return"] = function (state, node, o)
		o" return "
		codegen(state, node[2], o)
	end,

	["seq"] = function (state, node, o)
		for i = 2, #node do
			if i ~= 2 and node[i][1]~='seq' then o";" end
			codegen(state, node[i], o)
		end
	end,

	["nil"] = function (state, node, o)
		o'nil'
	end,

	["true"] = function (state, node, o)
		o'true'
	end,
	["false"] = function (state, node, o)
		o'false'
	end,

	["number"] = function (state, node, o)
		o(node[2])
	end,

	["string"] = function (state, node, o)
		o(strfmt("%q", node[2]))
	end,

	["literal"] = function (state, node, o)
		local v = node[2]
		local t = type(v)
		o"("
		if t == "number" then
			o(tostring(v))
		elseif t == "string" then
			o(strfmt("%q", v))
		elseif t == "boolean" then
			o(v and "true" or "false")
		elseif t == "nil" then
			o"nil"
		end
		o")"
	end,

	["table"] = function (state, node, o)
		o"({"
		local hash = node.hash
		if hash then
			for k, v in pairs(hash) do
				o"["
				codegen(state, k, o)
				o"]="
				codegen(state, v, o)
				o","
			end
		end
		for i = 2, #node do
			codegen(state, node[i], o)
			o","
		end
		o"})"
	end,

	["explist"] = function (state, node, o)
		for i = 2, #node do
			if i ~= 2 then
				o","
			end
			codegen(state, node[i], o)
		end
	end,

	["name"] = function (state, node, o)
		o(node[2])
	end,

	["quote"] = function (state, node, o)
		local level = state.dequote_level + 1
		state.dequote_level = level
		local function quote_rec(node)
			o"{"
			for i, v in ipairs(node) do
				if i ~= 1 then
					o","
				end
				local t = type(v)
				if t == "string" then
					o(strfmt("%q", v))
				elseif t == "booelan" then
					o(v and "true" or "false")
				elseif t == "nil" then
					o"nil"
				elseif t == "number" then
					o(tostring(v))
				else
					quote_rec(v)
				end
			end
			o"}"
		end
		quote_rec(node[2])
		state.dequote_level = level - 1
	end,

	["dequote"] = function (state, node, o)
		local level = state.dequote_level + 1
		state.dequote_level = level
		if state.safemode then
			error("running code at compile-time is not allowed")
		end
		local i, t = 1, {}
		local function ostream(str)
			i, t[i] = i+1, str
		end
		codegen(state, node[2], ostream)
		local env = state.dequote_envs[level]
		if not env then
			env = setmetatable({}, {__index=_G})
			state.dequote_envs[level] = env
		end
		local chunk, err = loadwrapper(table.concat(t), "(dequoted block)", env)
		if not chunk then
			error("error loading dequoted block: "..err)
		end
		local success, result = pcall(chunk)
		if not success then
			error("error running dequoted block: "..tostring(err))
		end
		if type(result) ~= 'table' then
			result = {'literal', result}
		end
		codegen(state, result, o)
		state.dequote_level = level - 1
	end,
}

return function (ast, ostream)
	local state = {
		safemode = false,
		dequote_level = 0,
		dequote_envs = {},
		line = 1,
	}
	codegen(state, ast, ostream)
	ostream"\n"
end

