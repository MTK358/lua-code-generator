Library to generate Lua code from a syntax tree. 

Example Language
----------------

	# comment

	# local localiables
	local a, b = 1, 2

	# function calls have no ()
	print a, "example", b

	# ! is a call with no args
	local input = tonumber io.read!

	# everything is an expression
	print if input>5: "greater than 5" else "less than or equal to 5"

	# two options for block syntax

	if cond
		print "test"
	end

	if cond: print "test"

	# string interpolation with $ in double-quoted strings
	print "$a + $b = $(a + b)"

	# loops evaluate to a list
	local list = for i = 1, 5: i
	for k, v in ipairs list: print k, v

	# table constructors don't need commas before newlines
	local tbl = {
		# key->value syntax
		456 -> "asdf"
		# sugar for literal strings
		thing: 123
		tbl: {'a', 'b'}
	}

	# table deconstruction
	local {thing:thing, tbl:{a, b}} = tbl
	print thing, a, b

	# "in" syntax sugar for multiple comparisons with the same value
	print 'bar' in ('foo', 'bar')
	print 5 in (4, 7)
	print 4 in (4, 7)
	print 4 in (4<=>7) # range (inclusive)
	print 4 in (4<>7) # range (exclusive)
	print 4 in (4<=->7) # range (includes only lower limit)
	print 4 in (4<-=>7) # range (includes only upper limit)
	print 50 in (4<=>7, 10<=>20, 50) # ranges and choices can be combined
	print 'bar' in ('a'<=>'c') # ranges work with any comparable values

	local cls = {}
	cls.__index = cls

	cls.new = fn val
		local self = {v: val}
		return self
	end

	# @ is short for self.
	cls.foo = fn self, n
		return @v + n
	end

	# calling an @name automatically uses self as the first arg
	cls.bar = fn self
		@v = @foo 5
	end

	# \ is a method call
	local i = cls.new 3
	print cls\foo 3
	cls\bar!
	print cls\foo 3

AST reference
-------------

Each node is a table with `[1]` containing the type of the node as a string, plus other info.

Each node is also either a _statement_ or an _expression_. Many nodes only accept either one or the other as child node in certain cases.

* `{'seq', ...}` (statement)

A sequence of statements run in order.

* `{'while', cond, body}` (statement)

A `while` loop. `cond` is an expression, and `body` is a statement.

* `{'repeat', body, cond}` (statement)

A `repeat` loop. `cond` is an expression, and `body` is a statement.

* `{'for_num', var, istart, iend, istep, body}` (statement)

A numeric `for` loop. `var` is a string, `istart`, `iend`, and `istep` are expressions (but `istep` can be `false` to omit it), and `body` is a statement.

* `{'for_iter', var_list, iter, body}` (statement)

An iterator `for` loop. `var_list` is a list of strings, `iter` is the iterator (`explist` is allowed for multiple values), and `body` is a statement.

* `{'do', body}` (statement)

Creates a new scope for the `body` statement to run in.

* `{'goto', label}` (statement)

Jump to the label named by te `label` string. If this is used the resulting code will not be Lua 5.1 compatible.

* `{'label', label}` (statement)

Create a goto label named by the `label` string. If this is used the resulting code will not be Lua 5.1 compatible.

* `{'break'}` (statement)

Break out of the innermost loop.

* `{'return', exp}` (statement)

Return the value `exp` from the current function. `exp` can be an `explist` node for multiple values.

* `{'assign', lhs, rhs}` (statement)

Assignment operator. For multiple values on either side, use an `explist` node.

* `{'local', lhs, rhs}` (statement)

Create local variables. `lhs` is either a `name` node or `explist` of `name` nodes, and `rhs` is an optional value to assign to the variables (`explist` is allowed).

* `{'if', cond, true_body, elseif_cond, elseif_body, else_body}` (statement)

An `if` statement. The `else_body` is optional, and the `elseif_cond` and `elseif_body` can be repeated 0 or more times. The conditions are expected to be expressions, and the bodies should be statements.

* `{'name', str}` (expression)

A variable name.

* `{'number', str}` (expression)

A literal number. `str` is a string representation of the number, in a format that can be inserted directly into a Lua script file.

* `{'string', str}` (expression)

A literal string. `str` is the contents of the string.

* `{'true'}` (expression)

A boolean `true` value.

* `{'false'}` (expression)

A boolean `false` value.

* `{'nil'}` (expression)

A `nil` value.

* `{'binop', op, lhs, rhs}` (expression)

A binary operator expression. `op` is a string containing a valid Lua binary operator, and `lhs` and `rhs` are the sub-expressions.

* `{'unop', op, sub}` (expression)

A unary operator expression. `op` is a string containing a valid Lua unary operator, and `sub` is the sub-expression.

* `{'gettable', tbl, key}` (expression)

Get the value at `key` from `tbl`.

* `{'call', fn, arg}` (any)

Calls `fn` with `arg` as the argument. `arg` can be an `explist` node for multiple args.

* `{'method_call', tbl, name, arg}` (any)

Calls `tbl.name` with `tbl, arg` as the arguments. Translates to the `:` operator in Lua. Note that `name` is a string, not an expression that results in a string.

* `{'table', key1, val1, key2, val2, ...}` (expression)

A table constructor. For array items, the key can be `false`.

* `{'function', {...}, body}` (expression)

A function expression. `...` is a list of arg name string, `body` is the statement inside the function.

* `{'vararg'}` (expression)

Creates a `...` in the resulting code.

* `{'explist', ...}` (expression, but only usable where a comma-separated list is acceptable in Lua)

A comma-separated list of expressions. Often used as the arg expression for function calls, or the `return` statement.

* `{'quote', node}` (expression)

Put a table constructor that creates a table equivalent to `node` in the resulting code. Used to implement macros.

* `{'dequote', node}` (any)

Run the statement `node` during te code-generation process, and replace the `dequote` node with the node that it returns. Used to implement macros.

Converting expressions to statements
------------------------------------

The `expr_to_stat` function takes an AST which ignores the distinction between statements and expressions, and changes it so that it represents a valid Lua program while retaining its original meaning.

Some important nodes about how the conversion is done:

`if` statements evaluate to the contents of the branch that was chosen, or `nil` of none of the branches match and there is no `else`:

	f(if x then y else z end)

	---

	local tmp1
	if x then
		tmp1 = y
	else
		tmp1 = z
	end
	f(tmp1)

Any loop evaluates to a list of the values returned on each iteration:

	x = for i = 1, 10 do i end

	---

	local tmp1, tmp2 = 1, {}
	for i = 1, 10 do
		tmp2[tmp1] = i
		tmp1 = tmp1 + 1
	end
	x = tmp2

When an expression not usable as a statement in Lua doesn't have its result used, it's wrapped in a dummy statement:

	a + b

	---

	if a + b then end

Assignment (either with the `assign` or `local` node) results in the varaible's new value, or a list of values if there are multiple variables:

	f(a, b = thing())

	---

	local tmp1, tmp2 = thing()
	a, b = tmp1, tmp2
	f(tmp1, tmp2)

