
local nextid = 1

local function tmpvarname()
	local n = "___exp2stat_tmp_"..nextid
	nextid = nextid + 1
	return n
end

local exp2stat_funcs

local function exp2stat(exp, node, parent, index, laststat_parent, laststat_index)
	--print(debug.traceback())
	--print(node[1])
	local f = exp2stat_funcs[node[1]]
	f(exp, node, parent, index, laststat_parent, laststat_index)
end

local stat_nodes = {
	['if'] = true,
	['while'] = true,
	['repeat'] = true,
	['for_num'] = true,
	['for_iter'] = true,
	['do'] = true,
	['seq'] = true,
	['assign'] = true,
	['local'] = true,
}

exp2stat_funcs = {
	["seq"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			laststat_parent[laststat_index] = {'seq',
				node,
				laststat_parent[laststat_index],
			}
			local count = #node
			for i = 2, count-1 do
				exp2stat(false, node[i], node, i, node, i)
			end
			if count >= 2 then
				parent[index] = node[count]
				node[count] = nil
				exp2stat(true, parent[index], parent, index, laststat_parent[laststat_index], 3)
			else
				parent[index] = {'nil'}
			end
		else
			for i = 2, #node do
				exp2stat(false, node[i], node, i, node, i)
			end
		end
	end,
	["do"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			if node[2][1] == 'seq' and not node[2][2] then
				parent[index] = {'nil'}
			else
				if node[2][1] ~= 'seq' then
					node[2][1] = {'seq', node[2][1]}
				end
				local v = {'name', tmpvarname()}
				laststat_parent[laststat_index] = {'seq',
					{'local', v},
					node,
					laststat_parent[laststat_index],
				}
				local seq = node[2]
				local count = #seq
				for i = 2, count-1 do
					exp2stat(false, seq[i], seq, i, seq, i)
				end
				seq[count] = {'assign', v, seq[count]}
				exp2stat(true, seq[count][3], seq[count], 3, seq, count)
				parent[index] = v
			end
		else
			exp2stat(false, seq[2], seq, 2, seq, 2)
		end
	end,
	["if"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if node[5] then
			local start = #node%2==0 and #node-2 or #node-1
			for i = start, 4, -2 do
				node[i],node[i+1],node[i+2] = {'if', node[i], node[i+1], node[i+2]}
			end
		end
		if exp then
			local v = {'name', tmpvarname()}
			laststat_parent[laststat_index] = {'seq',
				{'local', v},
				node,
				laststat_parent[laststat_index],
			}
			exp2stat(true, node[2], node, 2, laststat_parent, laststat_index)
			for i = 3, #node do
				node[i] = {'assign', v, node[i]}
				exp2stat(true, node[i][3], node[i], 3, node, i)
			end
			parent[index] = v
		else
			exp2stat(true, node[2], node, 2, laststat_parent, laststat_index)
			for i = 3, #node do
				exp2stat(false, node[i], node, i, node, i)
			end
		end
	end,
	["while"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			local vt = {'name', tmpvarname()}
			local vi = {'name', tmpvarname()}
			laststat_parent[laststat_index] = {'seq',
				{'local', {'explist', vt, vi}, {'explist', {'table'}, {'number', 1}}},
				node,
				laststat_parent[laststat_index],
			}
			exp2stat(true, node[2], node, 2, laststat_parent, laststat_index)
			node[3] = {'seq', 
				{'assign', {'gettable', vt, vi}, node[3]},
				{'assign', vi, {'binop', '+', vi, {'number', 1}}},
			}
			exp2stat(true, node[3][2][3], node[3][2], 3, node[3], 2)
			parent[index] = vt
		else
			exp2stat(true, node[2], node, 2, parent, index)
			exp2stat(false, node[3], node, 3, node, 3)
		end
	end,
	["for_num"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			local vt = {'name', tmpvarname()}
			local vi = {'name', tmpvarname()}
			laststat_parent[laststat_index] = {'seq',
				{'local', {'explist', vt, vi}, {'explist', {'table'}, {'number', 1}}},
				node,
				laststat_parent[laststat_index],
			}
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
			exp2stat(true, node[4], node, 4, laststat_parent, laststat_index)
			if node[5] then
				exp2stat(true, node[5], node, 5, laststat_parent, laststat_index)
			end
			node[6] = {'seq', 
				{'assign', {'gettable', vt, vi}, node[6]},
				{'assign', vi, {'binop', '+', vi, {'number', 1}}},
			}
			exp2stat(true, node[6][2][3], node[6][2], 3, node[6], 2)
			parent[index] = vt
		else
			exp2stat(true, node[3], node, 3, parent, index)
			exp2stat(true, node[4], node, 4, parent, index)
			if node[5] then
				exp2stat(true, node[5], node, 5, parent, index)
			end
			exp2stat(false, node[6], node, 6, node, 6)
		end
	end,
	["for_iter"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			local vt = {'name', tmpvarname()}
			local vi = {'name', tmpvarname()}
			laststat_parent[laststat_index] = {'seq',
				{'local', {'explist', vt, vi}, {'explist', {'table'}, {'number', 1}}},
				node,
				laststat_parent[laststat_index],
			}
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
			node[4] = {'seq', 
				{'assign', {'gettable', vt, vi}, node[4]},
				{'assign', vi, {'binop', '+', vi, {'number', 1}}},
			}
			exp2stat(true, node[4][2][3], node[4][2], 3, node[4], 2)
			parent[index] = vt
		else
			exp2stat(true, node[3], node, 3, parent, index)
			exp2stat(false, node[4], node, 4, node, 4)
		end
	end,
	["repeat"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			local vt = {'name', tmpvarname()}
			local vi = {'name', tmpvarname()}
			laststat_parent[laststat_index] = {'seq',
				{'local', {'explist', vt, vi}, {'explist', {'table'}, {'number', 1}}},
				node,
				laststat_parent[laststat_index],
			}
			node[2] = {'seq', 
				{'assign', {'gettable', vt, vi}, node[3]},
				{'assign', vi, {'binop', '+', vi, {'number', 1}}},
			}
			exp2stat(true, node[2][2][3], node[2][2], 3, node[2], 2)
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
			parent[index] = vt
		else
			exp2stat(true, node[3], node, 3, parent, index)
			exp2stat(false, node[2], node, 2, node, 2)
		end
	end,
	["name"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if not exp then
			parent[index] = {"if", node, {"seq"}}
		end
	end,
	["assign"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			local tmpvars = {'explist'}
			if node[2][1] == 'explist' then
				for i = 2, #node[2] do
					tmpvars[i] = {'name', tmpvarname()}
				end
			else
				tmpvars[2] = {'name', tmpvarname()}
			end
			local tmpvar_node = {'local', tmpvars, node[3]}
			laststat_parent[laststat_index] = {'seq',
				tmpvar_node,
				{'assign', node[2], tmpvars},
				laststat_parent[laststat_index],
			}
			parent[index] = tmpvars
			exp2stat(true, tmpvar_node[3], tmpvar_node, 3, laststat_parent, laststat_index)
		else
			exp2stat(true, node[3], node, 3, parent, index)
		end
	end,
	["local"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			local lhs = node[2]
			laststat_parent[laststat_index] = {'seq',
				node,
				laststat_parent[laststat_index],
			}
			parent[index] = lhs
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
		else
			exp2stat(true, node[3], node, 3, parent, index)
		end
	end,
	["call"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			for i = 2, #node do
				exp2stat(true, node[i], node, i, laststat_parent, laststat_index)
			end
		else
			for i = 2, #node do
				exp2stat(true, node[i], node, i, parent, index)
			end
		end
	end,
	["method_call"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			exp2stat(true, node[2], node, 2, laststat_parent, laststat_index)
			exp2stat(true, node[4], node, 4, laststat_parent, laststat_index)
		else
			exp2stat(true, node[2], node, 2, parent, index)
			exp2stat(true, node[4], node, 4, parent, index)
		end
	end,
	["binop"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if stat_nodes[node[3][1]] or stat_nodes[node[4][1]] then
			local lhs = {'name', tmpvarname()}
			local rhs = {'name', tmpvarname()}
			local alhs = {'local', lhs, node[3]}
			local arhs = {'local', rhs, node[4]}
			node[3] = lhs
			node[4] = rhs
			laststat_parent[laststat_index] = {'seq',
				alhs,
				arhs,
				laststat_parent[laststat_index],
			}
			exp2stat(true, alhs[3], alhs, 3, laststat_parent[laststat_index], 2)
			exp2stat(true, arhs[3], arhs, 3, laststat_parent[laststat_index], 3)
			--parent[index] = node
		else
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
			exp2stat(true, node[4], node, 4, laststat_parent, laststat_index)
		end
		if not exp then
			parent[index] = {"if", node, {"seq"}}
		end
	end,
	["unop"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if stat_nodes[node[3][1]] then
			local sub = {'name', tmpvarname()}
			local asub = {'local', sub, node[3]}
			node[3] = sub
			laststat_parent[laststat_index] = {'seq',
				asub,
				laststat_parent[laststat_index],
			}
			exp2stat(true, asub[3], asub, 3, laststat_parent[laststat_index], 2)
			--parent[index] = node
		else
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
		end
		if not exp then
			parent[index] = {"if", node, {"seq"}}
		end
	end,
	["gettable"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if stat_nodes[node[2][1]] or stat_nodes[node[3][1]] then
			local lhs = {'name', tmpvarname()}
			local rhs = {'name', tmpvarname()}
			local alhs = {'local', lhs, node[2]}
			local arhs = {'local', rhs, node[3]}
			node[3] = lhs
			node[4] = rhs
			laststat_parent[laststat_index] = {'seq',
				alhs,
				arhs,
				laststat_parent[laststat_index],
			}
			exp2stat(true, alhs[3], alhs, 3, laststat_parent[laststat_index], 2)
			exp2stat(true, arhs[3], arhs, 3, laststat_parent[laststat_index], 3)
			--parent[index] = node
		else
			exp2stat(true, node[2], node, 2, laststat_parent, laststat_index)
			exp2stat(true, node[3], node, 3, laststat_parent, laststat_index)
		end
		if not exp then
			parent[index] = {"if", node, {"seq"}}
		end
	end,
	["function"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		exp2stat(false, node[3], node, 3, node, 3)
	end,
	["return"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			laststat_parent[laststat_index] = {'do', {'seq',
				node,
				laststat_parent[laststat_index],
			}}
			parent[index] = {'nil'}
			exp2stat(true, node[2], node, 2, laststat_parent, laststat_index)
		else
			parent[index] = {'do', node}
			exp2stat(true, node[2], node, 2, parent[index], 2)
		end
	end,
	["table"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		local lsp, lsi = laststat_parent, laststat_index
		if not exp then
			parent[index] = {"if", node, {"seq"}}
		end
		for i = 2, #node do
			local n = node[i]
			if n then
				exp2stat(true, node[i], node, i, lsp, lsi)
			end
		end
	end,
	["explist"] = function (exp, node, parent, index, laststat_parent, laststat_index)
		if exp then
			for i = 2, #node do
				exp2stat(true, node[i], node, i, laststat_parent, laststat_index)
			end
		else
			for i = 2, #node do
				exp2stat(false, node[i], node, i, parent, index)
			end
		end
	end,
	["vararg"] = function () end,
	["nil"] = function () end,
	["true"] = function () end,
	["false"] = function () end,
	["number"] = function () end,
	["string"] = function () end,
	["literal"] = function () end,
}

local function exp_to_stat(node, implicit_return)
	nextid = 1
	node = {'seq', node}
	exp2stat(false, node[2], node, 2, node, 2)
	return node
end

return exp_to_stat

