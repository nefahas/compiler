local config = require('./config')

local parser = {}
parser.__index = parser

local function get_tok_is_type(k: string)
	local t = string.sub(k, 5)
	local idx = table.find(config.types, t)
	
	return (idx and config.types[idx]) or nil
end

local function is_comparison_tok(k: string)
	return k == 'TOK_EQUALS' or k == 'TOK_NEQ' or k == 'TOK_LT' or k == 'TOK_GT' or k == 'TOK_GTE' or k == 'TOK_LTE' 
end

local function is_arith_tok(k: string)
	return k == 'TOK_PLUS' or k == 'TOK_STAR' or k == 'TOK_MINUS' or k == 'TOK_SLASH' or k == 'TOK_BOR' or k == 'TOK_BNOT' or k == 'TOK_XOR'
end

function parser:peek()
	return self.tokens[self.idx]
end

function parser:peek_fwd(n: number)
	return self.tokens[self.idx + n]
end

function parser:advance()
	local t = self:peek()
	self.idx += 1
	return t
end

function parser:expect(k: string)
	local t = self:advance()
	
	assert(t.kind == k, `expected {k}, got {t.kind}`)
	
	return t
end

function parser:parse_identifier()
	local cur = self:peek()
	local depth = 0
	
	if cur.kind == 'TOK_IDENT' then
		self:advance()
		return {name = cur.val, depth = depth}
	elseif cur.kind == 'TOK_STAR' then
		local t = self:advance()
		while t.kind == 'TOK_STAR' do
			t = self:advance()
			depth += 1
		end
		
		if t.kind ~= 'TOK_IDENT' then
			error(`invalid identifier {t.kind}`)
		end
		
		return {name = t.val, depth = depth}
	end
end

function parser:parse_func_declaration(ret_type: string, name: string, depth: number)
	self:expect('TOK_LPAR')
	
	local args = {}
	
	while self:peek().kind ~= 'TOK_RPAR' do
		local tpe = get_tok_is_type(self:peek().kind)
		
		if not tpe then
			error(`invalid type {self:peek().kind} {self:peek().val}`)
		end
		
		self:advance()
		
		local ident_val = self:parse_identifier()
		local name = ident_val.name
		local depth = ident_val.depth
		
		table.insert(args, {
			name = name,
			depth = depth,
			type = tpe,
		})
		
		if self:peek().kind == 'TOK_COMMA' then
			self:advance()
			if self:peek().kind == 'TOK_RPAR' then
				error(`invalid args in {ret_type} {name}() declaration`)
			end
		end
	end
	
	--if #args > 5 then
	--	error(`too many arguments in function`)
	--end
	
	self:expect('TOK_RPAR')
	
	return {
		name = name,
		ret = ret_type,
		args = args,
		depth = depth,
		body = {},
	}
end

local PRECEDENCE = {
	TOK_STAR = 20,
	TOK_SLASH = 20,
	TOK_PLUS = 10,
	TOK_MINUS = 10,
	TOK_EQUALS = 5,
	TOK_LT = 5,
	TOK_GT = 5,
	TOK_LTE = 5,
	TOK_GTE = 5,
	TOK_NEQ = 5,
}

function parser:parse_unary(comma: boolean?, ...)
	local node = {
		depth = 0,
		name = nil
	}
	
	local end_tokens = {...}
	
	while true do
		local t = self:peek()
		
		if table.find(end_tokens, t.kind) or t.kind == 'TOK_SEMICOLON' or (comma and (t.kind == 'TOK_COMMA' or t.kind == 'TOK_RPAR')) then
			error(`expected TOK_IDENT or TOK_NUM, unfinished unary`)
		end
		
		if t.kind == 'TOK_STAR' then
			node.depth += 1
			self:advance()
		elseif t.kind == 'TOK_NOT' then
			node.opp = not node.opp
			self:advance()
		elseif t.kind == 'TOK_BNOT' then
			node.bnot = not node.bnot
			self:advance()
		elseif t.kind == 'TOK_AMPER' then
			node.amp = (node.amp and node.amp + 1) or 1
			self:advance()
		elseif t.kind == 'TOK_MINUS' then
			node.neg = not node.neg
			self:advance()
		else
			break
		end
	end
	
	local t = self:peek()
	
	if t.kind == 'TOK_IDENT' then
		node.name = t.val
		self:advance()
	elseif t.kind == 'TOK_NUM' then
		node.val = t.val
		self:advance()
		
		if node.neg then
			node.val = -node.val
			node.neg = nil
		end
	elseif t.kind == 'TOK_STRLIT' then
		node.str = t.val
		node.strlit =true
		self:advance()
	else
		error(`got {t.kind}, expected NUM, IDENT or STR_LIT`)
	end
	
	return node
end

function parser:parse_expression(min_prec: number)
	min_prec = min_prec or 0
	
	local lhs = self:parse_unary(true)
	
	while true do
		local t = self:peek()
		local prec = PRECEDENCE[t.kind]
		
		if not prec or prec < min_prec then
			break
		end
		
		local op = t.kind
		
		self:advance()
		
		local rhs = self:parse_expression(prec + 1)
		
		lhs = {
			lhs = lhs,
			rhs = rhs,
			mid = op,
			arith = is_arith_tok(op),
			comp = is_comparison_tok(op)
		}
	end
	
	return lhs
end

function parser:parse_expr_no_adv(min_prec: number)
	local start = self.idx
	
	local suc, expr = pcall(self.parse_expression, self, min_prec)
	
	self.idx = start
	
	return suc, expr
end

function parser:get_assignment(decl_type: string, depth: number)
	local is_ident = self:peek().kind == 'TOK_IDENT'
	
	if is_ident then
		local s = self.idx
		local ident = self:advance()
		
		local is_func_call = self:peek().kind == 'TOK_LPAR'
		
		if is_func_call then
			self:advance()
			
			local call = {
				kind = 'FUNC_CALL',
				func = ident.val,
				depth = depth,
				args = {},
			}

			while self:peek().kind ~= 'TOK_RPAR' do
				local c = self:parse_expression()

				if c.val then
					c.type = 'INT'
				elseif c.name then
					c.type = 'VAR'
				end

				table.insert(call.args, c)

				if self:peek().kind ~= 'TOK_RPAR' then
					self:expect('TOK_COMMA')
				end
			end

			self:expect('TOK_RPAR')
			self:expect('TOK_SEMICOLON')
			
			return call
		else
			self.idx = s
		end
	end
	
	local expr = self:parse_expression()
	
	return expr
end

function parser:parse_var_decl(decl_type: string, name: string, depth: number)
	local is_assigned = self:peek().kind == 'TOK_ASSIGN'
	
	if is_assigned then
		self:advance()
	end
	
	local t = {
		name = name,
		depth = depth,
		type = decl_type,
		kind = 'VAR_DECL',
		val = is_assigned and self:get_assignment() or nil
	}
	
	return t
end

function parser:parse_struct()
	self:expect('TOK_STRUCT')
	
	local name = self:expect('TOK_IDENT').val
	
	local fields = {}
	
	self:expect('TOK_LCURLY')
	
	while self:peek().kind ~= 'TOK_RCURLY' do
		local tpe = get_tok_is_type(self:peek().kind)
		
		if not tpe then
			error(`expected field type {self:peek().kind}`)
		end
		
		self:advance()
		local ident = self:parse_identifier()
		
		table.insert(fields, {
			name = ident.name,
			depth = ident.depth,
			type = tpe
		})
		
		self:expect('TOK_SEMICOLON')
	end
	
	self:expect('TOK_RCURLY')
	self:expect('TOK_SEMICOLON')
	
	local struct = {
		kind = 'STRUCT_DECL',
		name = name,
		fields = fields,
	}
	
	return struct
end

function parser:parse_block()
	self:expect('TOK_LCURLY')
	
	local len = self.len
	local block = {}
	
	while self.idx <= len do
		local tok = self:peek()
		
		if tok.kind == 'TOK_RCURLY' then
			break
		end
		
		local is_type = get_tok_is_type(tok.kind)
		
		if is_type then
			self:advance()
			local ident = self:parse_identifier()

			if not ident then
				error(`unexpected type declaration {tok.kind}`)
			end

			local is_func_decl = self:peek().kind == 'TOK_LPAR'
			local decl

			if is_func_decl then
				error(`cannot declare function within block`)
				--decl = self:parse_func_declaration(is_type, ident.name, ident.depth)
			else
				decl = self:parse_var_decl(is_type, ident.name, ident.depth)
			end
			
			table.insert(block, decl)
		elseif tok.kind == 'TOK_STRUCT' then
			local strt = self.idx
			self:advance()
			local nxt = self:peek()
			
			if nxt.kind == 'TOK_IDENT' then
				local struct_name = self:advance().val
				
				if self:peek().kind == 'TOK_LCURLY' then
					error(`cannot declare struct within block`)
				end
				
				local var_name = self:expect('TOK_IDENT').val
				
				if not self.structs[struct_name] then
					
				end
			else
				self.idx -= 1
				error(`invalid struct usage inside of a block`)
			end
		elseif tok.kind == 'TOK_RETURN' then
			self:advance()
			
			local fin = self:peek().kind == 'TOK_SEMICOLON'
			
			if fin then
				self:advance()
				table.insert(block, {
					kind = 'RETURN',
					val = nil
				})
			else
				local is_expr, expr = self:parse_expr_no_adv()
				
				if is_expr then
					expr = self:parse_expression()
					
					table.insert(block, {
						kind = 'RETURN',
						val = expr
					})
				else
					error(`invalid return value`)
				end
				
				self:expect('TOK_SEMICOLON')
			end
		elseif tok.kind == 'TOK_IF' then
			self:advance()
			
			self:expect('TOK_LPAR')
			
			local expr = self:parse_expression()
			self:expect('TOK_RPAR')
			
			local if_state = {
				kind = 'IF',
				cond = expr,
				body = self:parse_block()
			}
			
			table.insert(block, if_state)
		elseif tok.kind == 'TOK_BREAK' then
			self:advance()
			
			table.insert(block, {
				kind = 'BREAK'
			})
		elseif tok.kind == 'TOK_WHILE' then
			self:advance()
			
			self:expect('TOK_LPAR')
			
			local expr = self:parse_expression()
			self:expect('TOK_RPAR')
			
			local while_loop = {
				kind = 'WHILE',
				cond = expr,
				body = self:parse_block()
			}
			
			table.insert(block, while_loop)
		elseif tok.kind == 'TOK_IDENT' or tok.kind == 'TOK_STAR' then
			self:advance()
			
			local is_func_call = self:peek().kind == 'TOK_LPAR'
			
			if is_func_call then
				self:advance()
				
				local call = {
					kind = 'FUNC_CALL',
					args = {},
					name = tok.val
				}
				
				while self:peek().kind ~= 'TOK_RPAR' do
					local c = self:parse_expression()
					
					if c.val then
						c.type = 'INT'
					elseif c.name then
						c.type = 'VAR'
					end
					
					table.insert(call.args, c)
					
					if self:peek().kind ~= 'TOK_RPAR' then
						self:expect('TOK_COMMA')
					end
				end
				
				self:expect('TOK_RPAR')
				table.insert(block, call)
			else
				local d = 0
				
				if tok.kind == 'TOK_STAR' then
					while tok.kind == 'TOK_STAR' do
						tok = self:advance()
						d += 1

						if tok.kind == 'TOK_IDENT' then
							self.idx -= 1
							break
						end
					end
					
					self:expect('TOK_IDENT')
				end
				
				local is_assign = self:peek().kind == 'TOK_ASSIGN'
				
				if is_assign then
					local s = self.idx
					
					self:advance()

					local is_expr, expr = self:parse_expr_no_adv()
					
					if is_expr and expr then
						expr = self:parse_expression()
						
						table.insert(block, {
							name = tok.val,
							kind = 'VAR_ASSIGN',
							val = expr,
							depth = d,
						})
					else
						local is_ident = self:peek().kind == 'TOK_IDENT'
						
						if is_ident then
							is_ident = self:advance()
							local is_func_call = self:peek().kind == 'TOK_LPAR'
							
							if is_func_call then
								self:advance()
								
								local call = {
									name = tok.val,
									kind = 'VAR_ASSIGN_RETVAL',
									func = is_ident.val,
									depth = d,
									args = {},
								}
								
								while self:peek().kind ~= 'TOK_RPAR' do
									local c = self:parse_expression()

									if c.val then
										c.type = 'INT'
									elseif c.name then
										c.type = 'VAR'
									end

									table.insert(call.args, c)

									if self:peek().kind ~= 'TOK_RPAR' then
										self:expect('TOK_COMMA')
									end
								end
								
								self:expect('TOK_RPAR')
								self:expect('TOK_SEMICOLON')
								
								table.insert(block, call)
							else
								self.idx -= 1
							end
						end
					end
				else
					error(`unexpected TOK_IDENT {tok.val}`)
				end
			end
		elseif tok.kind == 'TOK_ASM' then
			self:advance()
			local lcurl = self:expect('TOK_LPAR')
			local lit = self:expect('TOK_STRLIT')
			self:expect('TOK_RPAR')
			self:expect('TOK_SEMICOLON')
			
			table.insert(block, {kind = 'ASM', val = lit.val})
		else
			self:advance()
		end
	end
	
	self:expect('TOK_RCURLY')
	
	return block
end


function parser:parse()
	local len = self.len
	
	while self.idx <= len do
		local tok = self:advance()
		
		local is_type = get_tok_is_type(tok.kind)

		if is_type then
			if tok.kind == 'TOK_STRUCT' then
				self.idx -= 1
				
				local decl_struct = self:parse_struct()
				
				warn(decl_struct)
				
				continue
			end
			
			local ident = self:parse_identifier()

			if not ident then
				error(`unexpected type declaration {tok.kind}`)
			end

			local is_func_decl = self:peek().kind == 'TOK_LPAR'
			local decl

			if is_func_decl then
				decl = self:parse_func_declaration(is_type, ident.name, ident.depth)
				
				if self:peek().kind == 'TOK_LCURLY' then
					decl.body = self:parse_block()
				else
					self:expect('TOK_SEMICOLON')
				end
				
				decl.kind = 'FUNC_DECL'
			else
				decl = self:parse_var_decl(is_type, ident.name, ident.depth)
			end
			
			table.insert(self.ast, decl)
		end
	end
end

function parser.new(tokens: {{kind: string, val: any}})
	local self = setmetatable({
		tokens = tokens,
		len = #tokens,
		ast = {},
		structs = {},
		idx = 1,
	}, parser)
	
	self:parse()
	
	return self.ast
end

return parser.new
