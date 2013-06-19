
local codegen = require 'codegen'
local exp_to_stat = require 'exp_to_stat'

local input_langs = {}

local err_id = {}

local function parse_lang_priv(parser, istream, srcname)
	if type(istream)=='string' then
		istream = istream:gmatch('.')
	end
	srcname = srcname or "<string>"
	local ls = {
		line = 1,
		exp_to_stat = exp_to_stat,
	}
	local nextid = 0
	function ls.new_tmp_var()
		nextid = nextid + 1
		return "___tmp_"..nextid
	end
	function ls.err(message, cont, line)
		error {
			err_id,
			msg = message,
			cont = cont and true or false,
			line = line or ls.line,
		}
	end
	local prev_cr = false
	function ls.getch()
		local c = istream()
		if prev_cr and c=='\n' then
			prev_cr = false
			c = istream()
			if c == '\r' then
				c = '\n'
			end
		elseif c=='\r' then
			prev_cr = true
			c = '\n'
		end
		if c=='\n' then
			ls.line = ls.line + 1
		end
		ls.c = c
		return c
	end
	local success, result = pcall(parser.parse, ls)
	if not success then
		if type(result)~='table' or result[1]~=err_id then
			error(result)
		end
		return nil, ('%s:%s: %s'):format(srcname, result.line or '?', result.msg), result
	end
	return result
end

local function compile_lang_priv(parser, istream, srcname, ostream)
	local ast, msg, err = parse_lang_priv(parser, istream, srcname)
	if not ast then
		return nil, msg, err
	end
	codegen(ast, ostream)
	return true
end

local function load_lang_priv(parser, istream, srcname, env)
	local t, i = {}, 1
	local function ostream(s)
		t[i], i = s, i+1
	end
	local success, msg, err = compile_lang_priv(parser, istream, srcname, ostream)
	if not success then
		return nil, msg, err
	end
	local src = table.concat(t)
	if setfenv then
		local chunk, errmsg = loadstring(src, srcname)
		if not chunk then return nil, errmsg end
		if env then setfenv(chunk, env) end
		return chunk
	else
		if env then
			return load(src, srcname, 't', env)
		end
		return load(src, srcname, 't')
	end
end

local function add_lang(parser)
	local l = {
		fullname = parser.fullname,
		name = parser.name,
		filesuffix = parser.filesuffix,
		parser = parser,
		parse = function (...) return parse_lang_priv(parser, ...) end,
		compile = function (...) return compile_lang_priv(parser, ...) end,
		load = function (...) return load_lang_priv(parser, ...) end,
	}
	input_langs[l.name] = l
	return l
end

local function get_lang(name)
	return input_langs[name]
end

local function load_lang(lang, istream, srcname, env)
	return input_langs[lang].load(istream, srcname, env)
end

local function loadfile_lang(file, srcname, env, lang)
	if not lang then
		local suffix = file:match('%.([%w]+)$')
		if not suffix then
			return nil, 'cannot get language type by file suffix'
		end
		for k, v in pairs(input_langs) do
			if suffix == v.filesuffix then
				lang = v
				break
			end
		end
		if not lang then
			return nil, 'cannot get language type by file suffix'
		end
	else
		lang = input_langs[lang]
	end
	local f = io.open(file)
	local function istream()
		return f:read(1)
	end
	local chunk, err, errtbl lang.load(istream, srcname, env)
	f:close()
	return chunk, err, errtbl
end

return {
	add_lang = add_lang,
	get_lang = get_lang,
	load = load_lang,
	loadfile = loadfile_lang,
}

