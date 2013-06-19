
Library to generate Lua code from a syntax tree. 

Example language usage:

	# comment

	# local variables
	var a, b = 1, 2

	# function calls have no ()
	print a, "example", b

	# ! is a call with no args
	var input = tonumber io.read!

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
	var list = for i = 1, 5: i
	for k, v in ipairs list: print k, v

	# table constructors use : instead of = , and don't need commas after newlines
	var tbl = {
		thing: 123
		[456]: "asdf"
		tbl: {'a', 'b'}
	}

	# table deconstruction
	var {thing:thing, tbl:{a, b}} = tbl
	print thing, a, b

