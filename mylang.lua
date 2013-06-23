
local new_lang = require 'lua_codegen.new_lang'

local tonumber = tonumber
local strmatch = string.match
local strchar = string.char
local tconcat = table.concat
local tinsert = table.insert

local one_char_tokens = {
	['(']=true, [')']=true, ['[']=true, [']']=true,
	['{']=true, ['}']=true, ['~']=true, ['@']=true,
	[',']=true, ['\\']=true, ['?']=true,
}

local optional_eq_tokens = {
	['+']=true, ['*']=true, ['/']=true,
	['%']=true, ['^']=true, ['>']=true, ['#']=true,
	['!']=true, ['=']=true,
}

local keywords = {
	['if'] = true,
	['else'] = true,
	['elseif'] = true,
	['while'] = true,
	['repeat'] = true,
	['until'] = true,
	['do'] = true,
	['for'] = true,
	['in'] = true,
	['fn'] = true,
	['end'] = true,
	['local'] = true,
	['goto'] = true,
	['return'] = true,
	['and'] = true,
	['or'] = true,
	['not'] = true,

	['function'] = true,
	['then'] = true,
}

local string_backslash_escapes = {
	n = '\n',
	r = '\r',
	t = '\t',
	v = '\v',
	a = '\a',
	['$'] = '$',
}

local function nexttok(ls)
	local c = ls.c
	if not c then
		ls.tok = nil
		return nil
	end
	local b = c:byte()

	if ls.in_dq_str then
		local chars = {}
		if c == '$' then
			c = ls.getch()
			if c == '(' then
				ls.tok = 'dqstr_expr'
				ls.getch()
				return
			else
				chars[1] = c
				repeat
					c = ls.getch()
					if not c then
						ls.err('unfinished double-quoted string', ls.line, true)
					end
				until not c:match('[_%w]')
				ls.tok = 'dqstr_var'
				ls.tokval = tconcat(chars)
				return
			end
		elseif c == '"' then
			ls.getch()
			ls.tok = 'dqstr_end'
			return
		elseif not c then
			ls.err('unfinished double-quoted string', ls.line, true)
		else
			while true do
				if not c or c == '"' or c == '$' then
					break
				elseif c == '\\' then
					c = ls.getch()
					local cc = string_backslash_escapes[c]
					if cc then
						chars[#chars+1] = cc
						c = ls.getch()
					elseif c == '"' then
						chars[#chars+1] = '"'
						c = ls.getch()
					elseif c == 'x' then
						c = ls.getch()
						if not strmatch(c, '%x') then
							ls.err('expected hexadecimal digit after \\x in double-quoted string')
						end
						local cc = tonumber(c, 16)
						c = ls.getch()
						if strmatch(c, '%x') then
							local cc = cc*16 + tonumber(c, 16)
						else
							ls.err('expected 2 hexadecimal digits after \\x in double-quoted string')
						end
						chars[#chars+1] = strchar(cc)
						c = ls.getch()
					else
						if not strmatch(c, '%d') then
							ls.err('invalid double-quoted string escape sequence')
						end
						local cc = tonumber(c)
						c = ls.getch()
						if strmatch(c, '%d') then
							cc = cc*10 + tonumber(c)
							c = ls.getch()
							if strmatch(c, '%d') then
								cc = cc*10 + tonumber(c)
							end
						end
						if cc > 255 then
							ls.err('charater value must be between 0 and 255 (inclusive)')
						end
						chars[#chars+1] = strchar(cc)
					end
				else
					chars[#chars+1] = c
					c = ls.getch()
				end
			end
			ls.tok = 'dqstr_text'
			ls.tokval = tconcat(chars)
			return
		end
	end

	while c==' ' or c=='\t' do
		c = ls.getch()
	end

	if c=='#' then
		repeat
			c = ls.getch()
		until c=='\n' or not c
		return nexttok(ls)
	end

	if not c then
		ls.tok = nil
		return nil
	end

	if one_char_tokens[c] then
		ls.getch()
		ls.tok = c

	elseif optional_eq_tokens[c] then
		local cc = ls.getch()
		if cc=='=' then
			ls.getch()
			ls.tok = c..'='
		else
			ls.tok = c
		end

	elseif c=='.' then
		local cc = ls.getch()
		if cc=='.' then
			local ccc = ls.getch()
			if ccc=='=' then
				ls.getch()
				ls.tok = '..='
			else
				ls.tok = '..'
			end
		else
			ls.tok = '.'
		end

	elseif c==':' then
		c = ls.getch()
		if c==':' then
			ls.getch()
			ls.tok = '::'
		else
			ls.tok = ':'
		end

	elseif c=='-' then
		c = ls.getch()
		if c=='>' then
			ls.getch()
			ls.tok = '->'
		else
			ls.tok = '-'
		end

	elseif c=='<' then
		c = ls.getch()
		if c=='=' then
			c = ls.getch()
			if c=='>' then
				ls.getch()
				ls.tok = '<=>'
			elseif c=='-' then
				c = ls.getch()
				if c == '>' then
					ls.getch()
					ls.tok = '<=->'
				else
					ls.err('invalid token')
				end
			else
				ls.tok = '<='
			end
		elseif c=='-' then
			c = ls.getch()
			if c == '=' then
				c = ls.getch()
				if c == '>' then
					ls.getch()
					ls.tok = '<-=>'
				else
					ls.err('invalid token')
				end
			else
				ls.tok = '<-'
			end
		elseif c=='>' then
			ls.getch()
			ls.tok = '<>'
		else
			ls.tok = '<'
		end

	elseif c=='\n' or c==';' then
		ls.getch()
		ls.tok = ';'

	elseif strmatch(c, '%d') then
		local str = c
		c = ls.getch()
		if str == '0' and c == 'x' then
			c = ls.getch()
			while strmatch(c, '%x') do
				str = str..c
				c = ls.getch()
			end
			str = tostring(tonumber(str, 16))
		elseif c and strmatch(c, '%d') then
			repeat
				str = str..c
				c = ls.getch()
			until not strmatch(c, '%d')
			if c == '.' then
				repeat
					str = str..c
					c = ls.getch()
				until not strmatch(c, '%d')
			end
		end
		ls.tok = 'number'
		ls.tokval = str

	elseif strmatch(c, '[_%a]') then
		local str = ''
		repeat
			str = str..c
			c = ls.getch()
		until not (c and strmatch(c, '[_%w]'))
		if keywords[str] then
			ls.tok = str
		else
			ls.tok = 'name'
			ls.tokval = str
		end

	elseif c == "'" then
		local str = ''
		while true do
			ls.getch()
			if ls.c == "'" then
				ls.getch()
				if ls.c == "'" then
					str = str.."'"
				else
					break
				end
			elseif not ls.c then
				ls.err('unfinished single-quoted string', ls.line, true)
			else
				str = str..ls.c
			end
		end
		ls.tok = "'"
		ls.tokval = str

	elseif c == '"' then
		ls.getch()
		ls.tok = 'dqstr_start'
	
	else
		ls.err('invalid token')
	end
end

-- if this is the next token, there's another expression following
-- this is used for deciding if an expr is a function call: once an expr has
-- been parsed, it checks if the next token is one of these, and if so, it's
-- a function call and the next expr is the first arg
local expr_start_tokens = {
	['name'] = true,
	['number'] = true,
	['true'] = true,
	['false'] = true,
	['nil'] = true,
	['fn'] = true,
	['if'] = true,
	['while'] = true,
	['for'] = true,
	['local'] = true,
	['not'] = true,
	['do'] = true,
	['goto'] = true,
	['return'] = true,
	['repeat'] = true,
	['::'] = true,
	["'"] = true,
	['dqstr_start'] = true,
	['('] = true,
	['['] = true,
	['{'] = true,
	['~'] = true,
	['@'] = true,
}

local function expect(ls, tok)
	if ls.tok ~= tok then
		ls.err("expected token: "..tok, ls.line, ls.tok==nil)
	end
	nexttok(ls)
end

local parse_expr

local function parse_expr_list(ls)
	if expr_start_tokens[ls.tok] then
		local e = {'explist', parse_expr(ls)}
		while ls.tok == ',' do
			nexttok(ls)
			while ls.tok == ';' do
				nexttok(ls)
			end
			e[#e+1] = parse_expr(ls)
		end
		return e
	end
	return {'explist'}
end

local function parse_opt_expr_list(ls)
	if expr_start_tokens[ls.tok] then
		local e = parse_expr(ls)
		if ls.tok == ',' then
			e = {'explist', e}
			while ls.tok == ',' do
				nexttok(ls)
				while ls.tok == ';' do
					nexttok(ls)
				end
				e[#e+1] = parse_expr(ls)
			end
		end
		return e
	end
	return {'explist'}
end

local function parse_stat_list(ls)
	local e = {'seq'}
	while ls.tok == ';' do nexttok(ls) end
	while expr_start_tokens[ls.tok] do
		e[#e+1] = parse_opt_expr_list(ls)
		local count = 0
		while ls.tok == ';' do
			nexttok(ls)
			count = count + 1
		end
		if count==0 then break end
	end
	return e
end

local function parse_opt_stat_list(ls)
	while ls.tok == ';' do nexttok(ls) end
	local i, e = 0, nil
	while expr_start_tokens[ls.tok] do
		i=i+1
		if i == 1 then
			e = parse_opt_expr_list(ls)
		elseif i == 2 then
			e = {'seq', e, parse_opt_expr_list(ls)}
		else
			e[#e+1] = parse_expr_list(ls)
		end
		local count = 0
		while ls.tok == ';' do
			nexttok(ls)
			count = count + 1
		end
		if count==0 then break end
	end
	return e or {'seq'}
end

local parse_start_expr

local function parse_var_list(ls)
	local l = ls.line
	local e = {'explist'}
	local has_tbl = false
	while true do
		if ls.tok == 'name' then
			e[#e+1] = {'name', ls.tokval}
			nexttok(ls)
		elseif ls.tok == '{' then
			e[#e+1] = parse_start_expr(ls)
			has_tbl = true
		else
			ls.err('expected name or table deconstructor')
		end
		if ls.tok == ',' then
			nexttok(ls)
			while ls.tok == ';' do
				nexttok(ls)
			end
		else
			break
		end
	end
	return e, has_tbl
end

local function parse_fnargs(ls)
	if ls.tok == 'name' then
		local e = {ls.tokval}
		nexttok(ls)
		while ls.tok == ',' do
			nexttok(ls)
			while ls.tok == ';' do
				nexttok(ls)
			end
			e[#e+1] = ls.tokval
			expect(ls, 'name')
		end
		return e
	end
	return {}
end

local function parse_block(ls)
	if ls.tok == ':' then
		nexttok(ls)
		return parse_expr(ls)
	elseif ls.tok == ';' then
		local l = ls.line
		nexttok(ls)
		local e = parse_opt_stat_list(ls)
		if ls.tok ~= 'end' then
			ls.err('expected "end" to match block on line '..l, ls.line, ls.tok==nil)
		end
		nexttok(ls)
		return e
	end
	ls.err('expected ":", ";", or newline')
end

local function tbl_node_iter(node)
	local i, nextarrkey = 2, 1
	return function ()
		local k, v = node[i], node[i+1]
		if not v then return end
		i = i + 2
		if not k then
			k = {'number', tostring(nextarrkey)}
			nextarrkey = nextarrkey + 1
		end
		return k, v
	end
end

local function convert_table_deconstruction_2(ls, tblnode, tbltmp, islocal)
	local new_node = {'seq'}
	local tmp_assign_node = nil
	for k, v in tbl_node_iter(tblnode) do
		if v[1] == 'table' then
			if not tmp_assign_node then
				tmp_assign_node = {'local', {'explist'}, {'explist'}}
				new_node[2] = tmp_assign_node
			end
			local tbltmp2 = {'name', ls.new_tmp_var()}
			tinsert(tmp_assign_node[2], tbltmp2)
			tinsert(tmp_assign_node[3], {'gettable', tbltmp, k})
			new_node[#new_node+1] = convert_table_deconstruction_2(ls, v, tbltmp2, islocal)
		end
	end
	local var_assign_node = nil
	for k, v in tbl_node_iter(tblnode) do
		if v[1] ~= 'table' then
			if not islocal and v[1]~='name' and v[1]~='gettable' then
				ls.err('table deconstructor values must be assignable')
			end
			if not var_assign_node then
				var_assign_node = {islocal and 'local' or 'assign', {'explist'}, {'explist'}}
				new_node[#new_node+1] = var_assign_node
			end
			tinsert(var_assign_node[2], v)
			tinsert(var_assign_node[3], {'gettable', tbltmp, k})
		end
	end
	return new_node
end

local function convert_table_deconstruction(ls, node)
	local new_node = {'seq'}
	local islocal = node[1] == 'local'
	if node[2][1] ~= 'explist' then node[2] = {'explist', node[2]} end
	local tmp_assign_node = {'local', {'explist'}, node[3]}
	new_node[2] = tmp_assign_node
	for i = 2, #node[2] do
		if node[2][i][1]=='table' then
			local tbltmp = {'name', ls.new_tmp_var()}
			tinsert(tmp_assign_node[2], tbltmp)
			tinsert(new_node, convert_table_deconstruction_2(ls, node[2][i], tbltmp, islocal))
		elseif not islocal then
			if node[2][i][1]~='name' and node[2][i][1]~='gettable' then
				ls.err('table deconstructor values must be assignable')
			end
			local tmp = {'name', ls.new_tmp_var()}
			tinsert(tmp_assign_node[2], tbltmp)
			tinsert(new_node, {'assign', node[2][i], tmp})
		else
			tinsert(tmp_assign_node[2], node[2][i])
		end
	end
	return new_node
end

parse_start_expr = function(ls)
	local t = ls.tok

	if t == "nil" then
		local l = ls.line
		nexttok(ls)
		return {line=l, "nil"}

	elseif t == "name" then
		local l, n = ls.line, ls.tokval
		nexttok(ls)
		return {line=l, "name", n}

	elseif t == "(" then
		nexttok(ls)
		local e = parse_opt_stat_list(ls)
		if ls.tok ~= ')' then
			ls.err('expected ")" to match "(" in line '..l, ls.line, ls.tok==nil)
		end
		nexttok(ls)
		if e[1]=='seq' and not e[2] then
			return {'nil'}
		end
		return e

	elseif t == "true" then
		local l = ls.line
		nexttok(ls)
		return {line=l, "true"}

	elseif t == "false" then
		local l = ls.line
		nexttok(ls)
		return {line=l, "false"}

	elseif t == "number" then
		local l = ls.line
		nexttok(ls)
		return {line=l, "number", ls.tokval}

	elseif t == "break" then
		local l = ls.line
		nexttok(ls)
		return {line=l, "break"}

	elseif t == "local" then
		local ln = ls.line
		nexttok(ls)
		local l, has_tbl = parse_var_list(ls)
		if ls.tok == '=' then
			nexttok(ls)
			local e = {line=ln, 'local', l, parse_opt_expr_list(ls)}
			if has_tbl then
				e = convert_table_deconstruction(ls, e)
			end
			return e
		else
			if has_tbl then
				ls.err('local variable declaration with a table deconstructor cannot omit the assignment')
			end
			return {line=ln, 'local', l}
		end

	elseif t == "::" then
		nexttok(ls)
		local l = ls.line
		local name = ls.tokval
		expect(ls, 'name')
		expect(ls, '::')
		return {line=l, "label", name}

	elseif t == "goto" then
		local l = ls.line
		nexttok(ls)
		local name = ls.tokval
		expect(ls, "name")
		return {line=l, "goto", name}

	elseif t == "do" then
		local l = ls.line
		nexttok(ls)
		local block = parse_opt_stat_list(ls)
		expect(ls, "end")
		return {line=l, "do", block}

	elseif t == "while" then
		local l = ls.line
		nexttok(ls)
		local cond = parse_expr(ls)
		local body = parse_block(ls)
		return {line=l, "while", cond, body}

	elseif t == "repeat" then
		local l = ls.line
		nexttok(ls)
		local block = parse_opt_stat_list(ls)
		if ls.tok ~= 'until' then
			ls.err('expected "until" to match "repeat" on line '..l, ls.line, ls.tok==nil)
		end
		nexttok(ls)
		local cond = parse_exp(ls)
		return {line=l, "repeat", block, cond}

	elseif t == "if" then
		local l = ls.line
		nexttok(ls)
		local cond = parse_expr(ls)
		if ls.tok == ':' then
			nexttok(ls)
			local true_branch = parse_expr(ls)
			local node = {line=l, "if", cond, true_branch}
			if ls.tok == "else" then
				nexttok(ls)
				node[4] = parse_expr(ls)
			end
			return node
		else
			expect(ls, ';')
			local true_branch = parse_opt_stat_list(ls)
			local node = {line=l, "if", cond, true_branch}
			while ls.tok == "elseif" do
				nexttok(ls)
				node[#node+1] = parse_expr(ls)
				expect(ls, ';')
				node[#node+1] = parse_opt_stat_list(ls)
			end
			if ls.tok == "else" then
				nexttok(ls)
				node[#node+1] = parse_opt_stat_list(ls)
			end
			if ls.tok ~= 'end' then
				ls.err('expected "end" to match "if" on line '..l, ls.line, ls.tok==nil)
			end
			nexttok(ls)
			return node
		end

	elseif t == "for" then
		local l = ls.line
		nexttok(ls)
		if ls.tok == ":" or ls.tok == ';' then
			local body = parse_block(ls)
			return {line=l, 'repeat', body, {'false'}}
		else
			local itervars = parse_var_list(ls)
			if ls.tok == "in" then
				nexttok(ls)
				local iterexp = parse_opt_expr_list(ls)
				local block = parse_block(ls)
				return {line=l, "for_iter", itervars, iterexp, block}
			else
				if itervars[3] or itervars[2][1] ~= 'name' then
					ls.err("numeric for loop can only have one variable")
				end
				expect(ls, "=")
				local istart = parse_expr(ls);
				expect(ls, ",")
				local iend = parse_expr(ls);
				local istep = false
				if ls.tok == "," then
					nexttok(ls)
					istep = parse_expr(ls);
				end
				local block = parse_block(ls)
				return {line=l, "for_num", itervars[2][2], istart, iend, istep, block}
			end
		end

	elseif t == "fn" then
		local l = ls.line
		nexttok(ls)
		local args = parse_fnargs(ls)
		local ret = ls.tok == ':'
		local body = parse_block(ls)
		if ret then
			return {line=l, "function", args, {'return', body}}
		end
		return {line=l, "function", args, body}

	elseif t == "@" then
		local l = ls.line
		nexttok(ls)
		local name = ls.tokval
		expect(ls, "name")
		if ls.tok == '!' then
			nexttok(ls)
			return {line=l, 'method_call', {"name", "self"}, name, {'explist'}}
		elseif expr_start_tokens[ls.tok] then
			return {line=l, 'method_call', {"name", "self"}, name, parse_expr_list(ls)}
		else
			return {line=l, "gettable", {"name", "self"}, {"string", name}}
		end

	elseif t == "{" then
		local l = ls.line
		nexttok(ls)
		while ls.tok==';' or ls.tok==',' do
			nexttok(ls)
		end
		local node = {line=l, "table"}
		local first = true
		while true do
			if first then
				first = false
			else
				local count = 0
				while ls.tok==';' or ls.tok==',' do
					count = count + 1
					nexttok(ls)
				end
				if count == 0 and ls.tok ~= '}' then
					ls.err('expected "}"')
				end
			end
			if ls.tok == "}" then
				nexttok(ls)
				break
				--[[
			elseif ls.tok == "[" then
				nexttok(ls)
				local key = parse_expr(ls)
				expect(ls, "]")
				expect(ls, ":")
				local val = parse_expr(ls)
				node.hash[key] = val
				]]
			else
				local key = parse_expr(ls)
				if key[1] == "name" and ls.tok == ':' then
					nexttok(ls)
					local val = parse_expr(ls)
					key[1] = "string"
					node[#node+1] = key
					node[#node+1] = val
				elseif ls.tok == '->' then
					nexttok(ls)
					local val = parse_expr(ls)
					node[#node+1] = key
					node[#node+1] = val
				else
					node[#node+1] = false
					node[#node+1] = key
				end
			end
			local count = 0
		end
		return node

	elseif t == "'" then
		local l = ls.line
		local str = ls.tokval
		nexttok(ls)
		return {line=l, "string", str}

	elseif t == 'dqstr_start' then
		local l = ls.line
		ls.in_dq_str = true
		nexttok(ls)
		local node = nil
		while true do
			local newnode
			if ls.tok == "dqstr_text" then
				newnode = {line=l, "string", ls.tokval}
				nexttok(ls)
			elseif ls.tok == "dqstr_expr" then
				ls.in_dq_str = false
				nexttok(ls)
				if ls.tok == ')' then
					newnode = {line=l, 'nil'}
				else
					newnode = parse_expr(ls)
					if ls.tok ~= ')' then
						ls.err('expected matching ) for expression in double-quoted string')
					end
				end
				ls.in_dq_str = true
				nexttok(ls)
			elseif ls.tok == "dqstr_var" then
				newnode = {line=l, 'name', ls.tokval}
				nexttok(ls)
			elseif ls.tok == 'dqstr_end' then
				ls.in_dq_str = false
				nexttok(ls)
				break
			else
				ls.err("unexpected token in double-quoted string")
			end
			if node then
				node = {"binop", "..", node, newnode}
			else
				node = newnode
			end
		end
		return node or {line=l, "string", ""}

	elseif t == "[" then
		local l = ls.line
		nexttok(ls)
		local quotetype
		if ls.tok == ">" then
			quotetype = "quote"
		elseif ls.tok == "<" then
			quotetype = "dequote"
		else
			ls.err("expected < or > after [")
		end
		nexttok(ls)
		local node = {line=l, quotetype, parse_opt_stat_list(ls)}
		if quotetype == 'dequote' then
			node[3] = {'return', node[3]}
		end
		if ls.tok ~= ']' then
			ls.err('expected "]" to match "[" in line '..l, ls.line, ls.tok==nil)
		end
		nexttok(ls)
		return node

	elseif t == "return" then
		nexttok(ls)
		return {'return', parse_opt_expr_list(ls)}

	end

	ls.err("expected expression", ls.line, ls.tok==nil)
end

local cmp_op_tokens = {
	['=='] = true, ['!='] = true,
	['>'] = true, ['<'] = true,
	['>='] = true, ['<='] = true,
}

local function parse_atom_expr(ls)
	if ls.tok == '~' then
		nexttok(ls)
		return {'unop', '-', parse_atom_expr(ls)}
	end
	local e = parse_start_expr(ls)

	while true do
		if ls.tok == "!" then
			nexttok(ls)
			e = {line=e.line, "call", e, {'explist'}}

		elseif ls.tok == "." then
			nexttok(ls)
			if ls.tok == '?' then
				nexttok(ls)
				local name = ls.tokval
				expect(ls, "name")
				local tmpname = {'name', ls.new_tmp_var()}
				e = {line=e.line, "if", {'binop', '~=', {'local', tmpname, e}, {'nil'}},
				                        {"gettable", tmpname, {'string', name}}}
			else
				local name = ls.tokval
				expect(ls, "name")
				e = {line=e.line, "gettable", e, {'string', name}}
			end

		elseif ls.tok == "\\" then
			nexttok(ls)
			local name = ls.tokval
			expect(ls, "name")
			if ls.tok == '!' then
				nexttok(ls)
				e = {line=e.line, "method_call", e, name, {'explist'}}
			elseif expr_start_tokens[ls.tok] then
				e = {line=e.line, "method_call", e, name, parse_expr_list(ls)}
			else
				local tmpname = {'name', ls.new_tmp_var()}
				e = {line=e.line, 'do', {'seq',
					{'local', tmpname, e},
					{'function', {'...'}, {'return',
						{'method_call', tmpname, name, {'vararg'}},
					}},
				}}
			end

		elseif ls.tok == "[" then
			nexttok(ls)
			if ls.tok == '?' then
				nexttok(ls)
				local key = parse_expr(ls)
				expect(ls, "]")
				local tmpname = {'name', ls.new_tmp_var()}
				e = {line=e.line, "if", {'binop', '~=', {'local', tmpname, e}, {'nil'}},
				                        {"gettable", tmpname, key}}
			else
				local key = parse_expr(ls)
				expect(ls, "]")
				e = {line=e.line, "gettable", e, key}
			end

		elseif ls.tok == "in" then
			local l = ls.line
			nexttok(ls)
			if not ls.tok == '(' then
				ls.err('expected "(" after "in"')
			end
			nexttok(ls)
			local cmp
			local tmpname = {'name', ls.new_tmp_var()}
			while true do
				local choice = parse_expr(ls)
				if ls.tok == '<>' then
					nexttok(ls)
					choice = {'binop', 'and',
						{'binop', '>', tmpname, choice},
						{'binop', '<', tmpname, parse_expr(ls)},
					}
				elseif ls.tok == '<=>' then
					nexttok(ls)
					choice = {'binop', 'and',
						{'binop', '>=', tmpname, choice},
						{'binop', '<=', tmpname, parse_expr(ls)},
					}
				elseif ls.tok == '<=->' then
					nexttok(ls)
					choice = {'binop', 'and',
						{'binop', '>=', tmpname, choice},
						{'binop', '<', tmpname, parse_expr(ls)},
					}
				elseif ls.tok == '<-=>' then
					nexttok(ls)
					choice = {'binop', 'and',
						{'binop', '>', tmpname, choice},
						{'binop', '<=', tmpname, parse_expr(ls)},
					}
				else
					choice = {'binop', '==', tmpname, choice}
				end
				cmp = cmp and {'binop', 'or', cmp, choice} or choice
				if ls.tok == ',' then
					nexttok(ls)
					while ls.tok == ';' do nexttok(ls) end
				else
					break
				end
			end
			expect(ls, ')')
			e = {line=l, 'do', {'seq', {'local', tmpname, e}, cmp}}

		elseif expr_start_tokens[ls.tok] then
			e = {line=e.line, "call", e, parse_expr_list(ls)}

		else
			break
		end
	end

	return e
end

local ops = {
	["or"] = {10, "l"},
	["and"] = {20, "l"},
	["=="] = {23, "l"},
	["!="] = {23, "l"},
	[">"] = {27, "l"},
	["<"] = {27, "l"},
	[">="] = {27, "l"},
	["<="] = {27, "l"},
	[".."] = {30, "l"},
	["+"] = {40, "l"},
	["-"] = {40, "l"},
	["*"] = {50, "l"},
	["/"] = {50, "l"},
	["%"] = {50, "l"},
	["^"] = {60, "r"},
}

local function parse_binop_expr(ls, min_prec)
	local e = parse_atom_expr(ls)
	while true do
		local optok = ls.tok
		local op = ops[optok]
		if not op or op[1]<min_prec then break end
		nexttok(ls)
		while ls.tok == ';' do
			nexttok(ls)
		end
		if op[2]=="l" then
			next_min_prec = op[1] + 1
		else
			next_min_prec = op[1]
		end
		local rhs = parse_binop_expr(ls, next_min_prec)
		e = {"binop", optok, e, rhs}
	end
	return e
end

local binop_assign_tokens = {
	['+=']='+', ['-=']='-', ['*=']='*', ['/=']='/',
	['%=']='%', ['^=']='^', ['..=']='..',
}

parse_expr = function(ls)
	local e
	if ls.tok == "not" then
		nexttok(ls)
		e = {"unop", "not", parse_binop_expr(ls, 0)}
	else
		e = parse_binop_expr(ls, 0)
	end

	while true do
		if ls.tok == "=" then
			if e[1]~='name' and e[1]~='gettable' and e[1]~='table' then
				if e[1]=='explist' then
					for i = 2, #e do
						if e[1]~='name' and e[1]~='gettable' and e[1]~='table' then
							ls.err('expression on left side of = is not an assignable value')
						end
					end
				else
					ls.err('expression on left side of = is not an assignable value')
				end
			end
			local istbl = e[1] == 'table'
			if not istbl and e[1] == 'explist' then
				for i = 2, #e do
					if e[i][1] == 'table' then
						istbl = true
						break
					end
				end
			end
			nexttok(ls)
			local rhs = parse_opt_expr_list(ls)
			e = {"assign", e, rhs}
			if istbl then
				e = convert_table_deconstruction(ls, e)
			end
		else
			local op = binop_assign_tokens[ls.tok]
			if op then
				nexttok(ls)
				e = {"assign", e, {'binop', op, e, parse_expr(ls)}}
			else
				break
			end
		end
	end

	return e
end

local function parse(ls, implicit_return)
	ls.getch()
	nexttok(ls)
	local node = parse_stat_list(ls)
	if implicit_return then
		node = {'return', node}
	end
	if ls.tok then
		ls.err('expected end of file')
	end
	node = ls.exp_to_stat(node, implicit_return)
	return node
end

return new_lang {
	fullname = "mylang",
	name = "mylang",
	file_extensions = {"mylang"},
	parse = parse,
}

