local gen = {}
gen.__index = gen

local type_sizes = {
	PTR = 2,
	CHAR = 1,
	--WORD = 2,
	
	INT = 2,
}

type func_arg = {depth: number, name: string, type: string}

function gen:emit_ln(ln: string): nil
	local len = #ln
	
	if self.tail >= self.size or len + self.tail + 1 >= self.size then
		local n_size = self.size * 2
		local n_buf = buffer.create(n_size)
		
		buffer.copy(n_buf, 0, self.buf, 0, self.tail)
		
		self.buf = n_buf
		self.size = n_size
	end
	
	buffer.writestring(self.buf, self.tail, ln, len)
	buffer.writeu8(self.buf, self.tail + len, 10) -- newl
	self.tail += len + 1
end

local extra_scopes = {
	'IF',
	'WHILE'
}

local function is_within_scope(var_loc_data: {scope: number, max_scope: number | nil}, cur_scope: number)
	local scope, max = var_loc_data.scope or 0, var_loc_data.max_scope
	
	if cur_scope < scope or (max and cur_scope > max) then
		return false
	end
	
	return true
end

function gen:get_local_label()
	local c = self.local_label_count
	
	if not c then
		self.local_label_count = 1
		return '_LL0'
	end
	
	self.local_label_count += 1
	
	return `_LL{c}`
end

function gen:free_local_label() -- dec by 1
	if not self.local_label_count or self.local_label_count == 0 then
		return
	end
	
	self.local_label_count -= 1
end

function gen:get_func_var_decls(block: {}, cur_scope: number)
	local decl = {}
	
	cur_scope = cur_scope or 0
	local next_scope = cur_scope + 1
	
	for i, v in block do
		if v.kind == 'VAR_DECL' then
			v.scope = cur_scope
			table.insert(decl, v)
		elseif table.find(extra_scopes, v.kind) then
			local r_decl = self:get_func_var_decls(v.body, next_scope)
			
			local highest_scope_allowed = 0
			
			for a, b in r_decl do
				if b.scope > next_scope then
					next_scope = b.scope + 1
					highest_scope_allowed = b.scope
				end
			end
			
			-- since every other scope will be highest + 1, we can make it so scopes >= var.scope but <= highest_scope can access,
			-- wherease any higher or lower cannot access the variable
			
			if highest_scope_allowed > next_scope then
				for a, b in r_decl do
					b.max_scope = highest_scope_allowed
				end
			end
			
			table.move(r_decl, 1, #r_decl, #decl + 1, decl)
		end
	end

	return decl
end

function gen:store_var(dest_var: string, src: {any}, var_locations: {}, scope: number, depth: number)
	local dest_loc = var_locations[dest_var]
	
	assert(dest_loc, `variable {dest_var} is not defined`)
	
	if not is_within_scope(dest_loc, scope) then
		error(`variable {dest_var} is out of scope {scope}, {dest_var} at {dest_loc.scope}`)
	end
	
	local size = type_sizes[dest_loc.type]
	local dest_loc_str = `{dest_loc.reg}{dest_loc.offset == 0 and '' or (dest_loc.offset > 0 and '+' or '-')}{dest_loc.offset == 0 and '' or math.abs(dest_loc.offset)}`
	local deref_dest_loc_str = `[{dest_loc_str}]`
	
	if depth and depth > 0 then
		self:emit_ln(`movw a {deref_dest_loc_str}`)
		
		for i = 1, depth - 1 do
			self:emit_ln(`movw a [a]`)
		end
		
		dest_loc_str = `a`
		deref_dest_loc_str = `[a]`
	end
	
	if src[1] == 'REG' then
		self:emit_ln(`{size > 1 and 'movw' or 'mov'} {deref_dest_loc_str} {src[2]}`)
	elseif src[1] == 'VAR' then
		local name = src[2]
		local src_depth = src[3]
		local amp = src[4]
		
		local src_loc = var_locations[name]
		
		assert(src_loc, `variable {name} is not defined`)
		
		if not is_within_scope(src_loc, scope) then
			error(`variable {name} is out of scope {scope}, {name} at {src_loc.scope}`)
		end
		
		local src_loc_str
		if src_loc.offset ~= 0 then
			src_loc_str = `{src_loc.reg}{src_loc.offset == 0 and '' or (src_loc.offset > 0 and '+' or '-')}{src_loc.offset == 0 and '' or math.abs(src_loc.offset)}`
		else
			src_loc_str = `{src_loc.reg}`
		end
		
		local deref_src_loc_str = `[{src_loc_str}]`
		local src_size = type_sizes[src_loc.type]

		if amp and src_depth and src_depth > 0 then
			src_depth -= 1
		elseif amp and (not src_depth or src_depth <= 0) then
			deref_src_loc_str = src_loc_str
		end
		
		if src_depth and src_depth > 0 then
			self:emit_ln(`push c`)
			self:emit_ln(`{src_size > 1 and 'movw' or 'mov'} c {deref_src_loc_str}`)
			
			for i = 1, src_depth - 1 do
				self:emit_ln(`movw c [c]`)
			end
			
			src_loc_str = 'c'
			deref_src_loc_str = '[c]'
		end
		
		if (src_size == size or size < src_size) or (src_size < size and depth > 0) then
			self:emit_ln(`{(depth > 0 and (src_size > 1 and 'movw' or 'mov')) or (size > 1 and 'movw' or 'mov')} {deref_dest_loc_str} {deref_src_loc_str}`)
		elseif src_size < size then -- so far only exists with 1 < 2 so
			self:emit_ln(`push b`)
			self:emit_ln(`mov b {deref_src_loc_str}`)
			self:emit_ln(`sxb b`)
			self:emit_ln(`movw {deref_dest_loc_str} b`)
			self:emit_ln(`pop b`)
		else
			error()
		end
		
		if src_loc_str == 'c' then
			self:emit_ln('pop c')
		end
	elseif src[1] == 'LIT' then
		local lit_depth = src[3] or 0
		
		if lit_depth > 0 then
			self:emit_ln(`push b`)
			
			for i = 1, lit_depth - 1 do
				self:emit_ln(`mov a [a]`)
			end
			
			self:emit_ln(`{size > 1 and 'movw' or 'mov'} {deref_dest_loc_str} [b]`)
			self:emit_ln(`pop b`)
		else
			self:emit_ln(`{size > 1 and 'movw' or 'mov'} {deref_dest_loc_str} {src[2]}`)
		end
	end
end

function gen:store_reg(dest: string, src: {any}, var_locations: {}, scope: number, depth: number | nil)
	if src[1] == 'LIT' then
		if depth == 0 then
			self:emit_ln(`mov {dest} {src[2]}`)
		else
			self:emit_ln(`movw a [{src[2]}]`)
			
			for i = 1, depth - 1 do
				self:emit_ln(`movw a [a]`)
			end
			
			self:emit_ln(`movw {dest} a`)
		end
	end
end

function gen:load_var(dest: {string}, var: string, var_locations: {}, scope: number, depth: number | nil): number
	local loc = var_locations[var]
	
	assert(loc, `variable {var} is not defined`)
	
	if not is_within_scope(loc, scope) then
		error(`variable {var} is out of scope {scope}, {var} at {loc.scope}`)
	end
	
	local size = type_sizes[loc.type]
	
	local load_var_str
	
	if loc.offset ~= 0 then
		load_var_str = `[{loc.reg}{loc.offset == 0 and '' or (loc.offset > 0 and '+' or '-')}{loc.offset == 0 and '' or math.abs(loc.offset)}]`
	else
		load_var_str = `[{loc.reg}]`
	end
	
	local dest_type = dest[1]
	local dest_val = dest[2]
	
	if dest_type == 'REG' then
		if not depth or depth == 0 then
			self:emit_ln(`{size > 1 and 'movw' or 'mov'} {dest_val} {load_var_str}`)
		elseif depth and depth > 0 then
			self:emit_ln(`{size > 1 and 'movw' or 'mov'} {dest_val} {load_var_str}`)
			
			for i = 1, depth do
				self:emit_ln(`movw {dest_val} [{dest_val}]`)
			end
		end
	elseif dest_type == 'VAR' then
		local dest_var = var_locations[dest_val]
		
		assert(dest_var, `variable {dest_val} is not defined`)
		assert(is_within_scope(dest_var, scope), `variable {dest_val} is out of scope {scope}, {dest_val} at {dest_var.scope}`)
		
		local dest_var_str
		
		if dest_var.offset ~= 0 then
			dest_var_str = `[{dest_var.reg}{dest_var.offset == 0 and '' or (dest_var.offset > 0 and '+' or '0')}{dest_var.offset == 0 and '' or math.abs(dest_var.offset)}]`
		else
			dest_var_str = `[{dest_var.reg}]`
		end
		
		local dest_size = type_sizes[dest_var.type]
		
		if size < dest_size then
			if depth == 0 then
				self:emit_ln(`mov a {load_var_str}`)
				self:emit_ln('sxb a')
				self:emit_ln(`movw {dest_var_str} a`)
			elseif depth and depth > 0 then
				self:emit_ln(`mov a {load_var_str}`)
				self:emit_ln('sxb a')
				
				for i = 1, depth do
					self:emit_ln(`movw {dest_var_str} [a]`)
				end
				
				self:emit_ln(`movw {dest_var_str} a`)
			end
		elseif size > dest_size then
			if depth == 0 then
				self:emit_ln(`mov {dest_var_str} {load_var_str}`)
			elseif depth and depth > 0 then
				self:emit_ln(`movw a {load_var_str}`)
				
				for i = 1, depth do
					self:emit_ln(`movw a [a]`)
				end
				
				self:emit_ln(`mov {dest_var_str} a`)
			end
		elseif size == dest_size then
			self:emit_ln(`{size > 1 and 'movw' or 'mov'} {dest_var_str} {load_var_str}`)
		else
			error()
		end
	end
	
	return type_sizes[loc.type]
end

function gen:emit_arith(lhs_reg: string, rhs_reg: string, lhs: {}, rhs: {}, mid: string, var_locations: {}, scope: number)
	local lhs_in_reg = false
	local rhs_in_reg = false
	
	if rhs and rhs_reg then
		if rhs.name then
			self:load_var({'REG', rhs_reg:lower()}, rhs.name, var_locations, scope, rhs.depth)

			rhs_in_reg = true
		elseif rhs.val then
			--self:store_reg(rhs_reg:lower(), {'LIT', rhs.val}, var_locations, scope, rhs.depth)
			--rhs_in_reg = true
		elseif rhs.arith then
			self:emit_arith(rhs_reg, lhs_reg, rhs.lhs, rhs.rhs, rhs.mid, var_locations, scope)

			rhs_in_reg = true
		end
	end
	
	if lhs and lhs_reg then
		if lhs.name then
			self:load_var({'REG', lhs_reg:lower()}, lhs.name, var_locations, scope, lhs.depth)
		elseif lhs.val then
			self:store_reg(lhs_reg:lower(), {'LIT', lhs.val}, var_locations, scope, lhs.depth)
		elseif lhs.arith then
			self:emit_arith(lhs_reg, rhs_reg, lhs.lhs, lhs.rhs, lhs.mid, var_locations, scope)
		end
		
		lhs_in_reg = true
	end
	
	local arith_func_name = ''
	
	if mid == 'TOK_PLUS' then
		arith_func_name = 'add'
	elseif mid == 'TOK_MINUS' then
		arith_func_name = 'sub'
	elseif mid == 'TOK_STAR' then
		arith_func_name = 'mul'
	elseif mid == 'TOK_SLASH' then
		arith_func_name = 'div'
		
		error()
	end
	
	if lhs_in_reg and rhs_in_reg then
		self:emit_ln(`{arith_func_name} {lhs_reg} {rhs_reg}`)
	elseif lhs_in_reg and not rhs_in_reg then
		if rhs.val then
			self:emit_ln(`{arith_func_name} {lhs_reg} {rhs.val}`)
		else
			error()
		end
	elseif not lhs_in_reg and not rhs_in_reg then
		error('invalid arithmetic')
	end
end

function gen:emit_block(block: {}, var_locations: {}, func_name: string, ret_type: string, scope: number, do_ret: boolean)
	local did_ret = false
	
	local next_scope = scope + 1
	
	for i, v in block do
		if v.kind == 'FUNC_CALL' then
			local func = self.func_declarations[v.name]

			if not func then
				error(`invalid function {v.name}`)
			end
			
			-- flag2
			self:emit_func_call(func, v.args, var_locations, scope)
		elseif v.kind == 'WHILE' then
			local cond, body = v.cond, v.body
			
			local loop_label = self:get_local_label()
			local finish_label = self:get_local_label()
			
			local do_body = true
			
			self:emit_ln(`{loop_label}:`)
			
			if cond.comp then
				local lhs, mid, rhs = cond.lhs, cond.mid, cond.rhs

				local lhs_lit, lhs_var = lhs.val, lhs.name
				local rhs_lit, rhs_var = rhs.val, rhs.name
				
				if lhs_lit and rhs_lit then
					if mid == 'TOK_EQUALS' then
						do_body = lhs_lit == rhs_lit
					elseif mid == 'TOK_NEQ' then
						do_body = lhs_lit ~= rhs_lit
					elseif mid == 'TOK_LT' then
						do_body = lhs_lit < rhs_lit
					elseif mid == 'TOK_GT' then
						do_body = lhs_lit > rhs_lit
					elseif mid == 'TOK_LTE' then
						do_body = lhs_lit <= rhs_lit
					elseif mid == 'TOK_GTE' then
						do_body = lhs_lit >= rhs_lit
					end
				else
					local lhs_in_a = false
					local rhs_in_b = false
					
					if lhs_var then
						lhs_in_a = true
						self:load_var({'REG', 'a'}, lhs_var, var_locations, scope)
					end
					
					if rhs_var then
						rhs_in_b = true
						self:load_var({'REG', 'b'}, rhs_var, var_locations, scope)
					end
					
					if lhs_in_a and rhs_in_b then
						local lhs_size = type_sizes[var_locations[lhs_var].type]
						local rhs_size = type_sizes[var_locations[rhs_var].type]

						if lhs_size > rhs_size then
							self:emit_ln('sxb b')
							rhs_size = lhs_size
						elseif rhs_size > lhs_size then
							self:emit_ln('sxb a')
							lhs_size = rhs_size
						end

						self:emit_ln(`{lhs_size > 1 and 'cmpsw' or 'cmps'} a b`)
					elseif lhs_in_a then
						local size = type_sizes[var_locations[lhs_var].type]

						self:emit_ln(`{size > 1 and 'cmpsw' or 'cmps'} a {rhs_lit}`)
					elseif rhs_in_b then
						local size = type_sizes[var_locations[rhs_var].type]
						
						self:emit_ln(`{size > 1 and 'cmpsw' or 'cmps'} {lhs_lit} b`)
					end
					
					if mid == 'TOK_EQUALS' then
						self:emit_ln(`jne {finish_label}`)
					elseif mid == 'TOK_NEQ' then
						self:emit_ln(`jeq {finish_label}`)
					elseif mid == 'TOK_LT' then
						self:emit_ln(`jge {finish_label}`)
					elseif mid == 'TOK_GT' then
						self:emit_ln(`jle {finish_label}`)
					elseif mid == 'TOK_LTE' then
						self:emit_ln(`jgt {finish_label}`)
					elseif mid == 'TOK_GTE' then
						self:emit_ln(`jlt {finish_label}`)
					end
				end
			else
				local lit, var = cond.val, cond.name
				
				local is_opp = v.cond.opp
				
				if var then
					local size = self:load_var('a', var, var_locations, scope)
					
					self:emit_ln(`{size > 1 and 'cmpsw' or 'cmps'} a 0`)
					self:emit_ln(`{is_opp and 'jne' or 'jeq'} {finish_label}`)
				elseif lit then
					if lit == 0 and not is_opp then
						do_body = false
					elseif lit ~= 0 and is_opp then
						do_body = false
					end
				end
			end
			
			if do_body then
				self.break_loop = finish_label
				local did, n_scope = self:emit_block(body, var_locations, func_name, ret_type, next_scope, true)
				self:emit_ln(`jmp {loop_label}`)
				self:emit_ln(`{finish_label}:`)
			
				if n_scope > next_scope then
					next_scope = n_scope
				end
				
				self.break_loop = nil
				
				if did then
					did_ret = did
				end
			else
				self:free_local_label()
				self:free_local_label()
			end
		elseif v.kind == 'BREAK' then
			assert(self.break_loop, `put break outside of a loop`)
			
			self:emit_ln(`jmp {self.break_loop}`)
		elseif v.kind == 'IF' then
			local cond = v.cond
			local body = v.body
			
			if #body == 0 then -- no body, no point generating
				continue
			end
			
			local fail_label = self:get_local_label()
			
			local do_body = true
			local do_label = true
			
			if cond.comp then -- comparison
				local lhs, mid, rhs = cond.lhs, cond.mid, cond.rhs
				
				local lhs_lit, lhs_var = lhs.val, lhs.name
				local rhs_lit, rhs_var = rhs.val, rhs.name
				
				if lhs_lit and rhs_lit then
					if mid == 'TOK_EQUALS' then -- lhs == rhs
						if lhs_lit ~= rhs_lit then
							do_label = false -- op out
							do_body = false
						else
							do_label = false
						end
					elseif mid == 'TOK_NEQ' then
						if lhs_lit == rhs_lit then -- lhs != rhs
							do_label = false
							do_body = false
						else
							do_label = false
						end
					elseif mid == 'TOK_LT' then -- lhs < rhs then
						if lhs_lit >= rhs_lit then
							do_label = false
							do_body = false
						else
							do_label = false
						end
					elseif mid == 'TOK_GT' then -- lhs > rhs
						if lhs_lit <= rhs_lit then
							do_label = false
							do_body = false
						else
							do_label = false
						end
					elseif mid == 'TOK_LTE' then -- lhs <= rhs
						if lhs_lit > rhs_lit then
							do_label = false
							do_body = false
						else
							do_label = false
						end
					elseif mid == 'TOK_GTE' then -- lhs >= rhs
						if lhs_lit < rhs_lit then
							do_label = false
							do_body = false
						else
							do_label = false
						end
					end
				else
					local lhs_in_a = false
					local rhs_in_b = false
					
					if lhs_var then
						self:load_var({'REG', 'a'}, lhs_var, var_locations, scope, lhs.depth)
						lhs_in_a = true
					end
					
					if rhs_var then
						self:load_var({'REG', 'b'}, rhs_var, var_locations, scope, rhs.depth)
						rhs_in_b = true
					end
					
					if lhs_in_a and rhs_in_b then
						local lhs_size = type_sizes[var_locations[lhs_var].type]
						local rhs_size = type_sizes[var_locations[rhs_var].type]
						
						if lhs_size > rhs_size then
							self:emit_ln('sxb b')
							rhs_size = lhs_size
						elseif rhs_size > lhs_size then
							self:emit_ln('sxb a')
							lhs_size = rhs_size
						end
						
						self:emit_ln(`{lhs_size > 1 and 'cmpsw' or 'cmps'} a b`)
					elseif lhs_in_a then
						local size = type_sizes[var_locations[lhs_var].type]
						
						self:emit_ln(`{size > 1 and 'cmpsw' or 'cmps'} a {rhs_lit}`)
					elseif rhs_in_b then
						local size = type_sizes[var_locations[rhs_var].type]
						
						self:emit_ln(`{size > 1 and 'cmpsw' or 'cmps'} {lhs_lit} b`)
					end
					
					if mid == 'TOK_EQUALS' then
						self:emit_ln(`jne {fail_label}`)
					elseif mid == 'TOK_NEQ' then
						self:emit_ln(`jeq {fail_label}`)
					elseif mid == 'TOK_LT' then
						self:emit_ln(`jge {fail_label}`)
					elseif mid == 'TOK_GT' then
						self:emit_ln(`jle {fail_label}`)
					elseif mid == 'TOK_LTE' then
						self:emit_ln(`jgt {fail_label}`)
					elseif mid == 'TOK_GTE' then
						self:emit_ln(`jlt {fail_label}`)
					end
				end
			else -- nonzero check
				local lit = cond.val
				local var = cond.name
				
				local is_opp = v.cond.opp
				
				if var then
					self:load_var({'REG', 'a'}, var, var_locations, scope, cond.depth)
					local size = type_sizes[var_locations[var].type]
					
					self:emit_ln(`{size > 1 and 'cmpsw' or 'cmps'} a 0`)
					self:emit_ln(`{is_opp and 'jne' or 'jeq'} {fail_label}`)
				elseif lit then
					if lit == 0 and not is_opp then
						self:emit_ln(`jmp {fail_label}`)
						do_body = false
					elseif lit ~= 0 and is_opp then
						self:emit_ln(`jmp {fail_label}`)
						do_body = false
					else
						do_label = false
					end
				else
					error(`error in if statement generation`)
				end
			end
			
			if do_body then
				local did, n_scope = self:emit_block(body, var_locations, func_name, ret_type, next_scope, true)
				
				if n_scope > next_scope then
					next_scope = n_scope
				end
				
				if do_label then
					self:emit_ln(fail_label .. ':')
				else
					self:free_local_label()
				end
				
				if did then
					did_ret = did
				end
			else
				self:free_local_label()
			end
		elseif v.kind == 'RETURN' then
			local val = v.val

			local to_ret = {}

			if val and ret_type == 'VOID' then
				error(`returning value in void function {func_name}`)
			end
			
			if not val and ret_type ~= 'VOID' then
				error(`expected return of type {ret_type}, got no return value`)
			end
			
			if val then
				if val.val then
					if val.val > 0xFF and ret_type == 'CHAR' then
						warn(`return value too large for char in function {func_name}, return may be unexpected values`)
					end

					table.insert(to_ret, `mov a {val.val}`)
				elseif val.name then
					self:load_var({'REG', 'a'}, val.name, var_locations, scope, val.depth)
					local var_loc = var_locations[val.name]

					if var_loc.type ~= ret_type then
						error(`invalid return type in function {func_name}`)
					end
				elseif val.arith then
					local lhs = val.lhs
					local rhs = val.rhs
					local mid = val.mid
					
					self:emit_arith('a', 'b', lhs, rhs, mid, var_locations, scope)
				end
			end
			
			for i, v in to_ret do
				self:emit_ln(v)
			end

			self:emit_ln(`mov sp bp`)
			self:emit_ln(`pop bp`)
			self:emit_ln(`ret`)
			
			did_ret = true
		elseif v.kind == 'VAR_ASSIGN_RETVAL' then
			local func_name = v.func
			local args = v.args
			local depth = v.depth

			local var_name = v.name
			local var_loc = var_locations[var_name]

			assert(var_loc, `invalid variable {var_name}`)

			local func = self.func_declarations[func_name]

			assert(func, `invalid function {func_name}`)

			if func.ret == 'VOID' then
				error(`trying to set value to a void functions ({func_name}) return value`)
			elseif func.ret ~= var_loc.type then
				error(`type mismatch on func call var assignment {var_name} = {func_name}`)
			end
			
			self:emit_func_call(func, args, var_locations, scope)
			
			self:store_var(var_name, {'REG', 'a'}, var_locations, scope)
			--self:emit_ln(`{type_sizes[var_loc.type] > 1 and 'movw' or 'mov'} [{var_loc.reg}{var_loc.offset > 0 and '+' or '-'}{math.abs(var_loc.offset)}] a`)
		elseif v.kind == 'VAR_ASSIGN' then
			local var_name = v.name
			local var_val = v.val

			local depth = v.depth
			
			if var_val.val then
				self:store_var(var_name, {'LIT', var_val.val, var_val.depth}, var_locations, scope, depth)
			elseif var_val.name then
				self:store_var(var_name, {'VAR', var_val.name, var_val.depth}, var_locations, scope, depth)
			elseif var_val.arith then
				local lhs, rhs, mid = var_val.lhs, var_val.rhs, var_val.mid

				self:emit_arith('d', 'e', lhs, rhs, mid, var_locations, scope)
				self:store_var(var_name, {'REG', 'd'}, var_locations, scope, depth)
			end
		elseif v.kind == 'ASM' then
			local str = v.val

			str = string.gsub(str, '%(([^)]+)%)', function(n)
				local var_loc = var_locations[n]

				if not var_loc then
					error(`invalid variable inside of inlined assembly {str}`)
				end

				assert(is_within_scope(var_loc, scope), `variable {n} out of scope {scope}, var at {var_loc.scope}`)
				
				return `[{var_loc.reg}{var_loc.offset == 0 and '' or (var_loc.offset > 0 and '+' or '-')}{var_loc.offset == 0 and '' or math.abs(var_loc.offset)}]`
			end)

			self:emit_ln(str)
		elseif v.kind == 'VAR_DECL' then
			if v.initialized then
				continue
			end
			
			local var_val = v.val
			local var_name = v.name
			local var_depth = v.depth
			local var_type = v.type
			
			if var_val then
				if var_val.kind == 'FUNC_CALL' then
					local func_name = var_val.func
					local args = var_val.args
					local depth = var_val.depth

					local var_loc = var_locations[var_name]

					assert(var_loc, `invalid variable {var_name}`)

					local func = self.func_declarations[func_name]

					assert(func, `invalid function {func_name}`)

					if func.ret == 'VOID' then
						error(`trying to set value to a void functions ({func_name}) return value`)
					elseif func.ret ~= var_loc.type then
						error(`type mismatch on func call var assignment {var_name} = {func_name}`)
					end

					self:emit_func_call(func, args, var_locations, scope)

					self:store_var(var_name, {'REG', 'a'}, var_locations, scope)
					
					continue
				end
				
				if var_val.val then -- literal
					self:store_var(var_name, {'LIT', var_val.val, var_val.depth}, var_locations, v.scope, var_depth)
				elseif var_val.name then
					self:store_var(var_name, {'VAR', var_val.name, var_val.depth, var_val.amp}, var_locations, v.scope, var_depth)
				elseif var_val.arith then -- expression
					self:emit_arith('d', 'e', var_val.lhs, var_val.rhs, var_val.mid, var_locations, scope)
					
					self:store_var(var_name, {'REG', 'd'}, var_locations, scope, var_depth)
				end
			end
		end
	end
	
	if not did_ret and scope == 0 then
		assert(ret_type == 'VOID', `did not return value in function {ret_type} {func_name}`)
		
		self:emit_ln(`mov sp bp`)
		self:emit_ln(`pop bp`)
		self:emit_ln(`ret`)
	end
	
	return did_ret, next_scope
end

function gen:emit_func(func: {depth: number, ret: string, name: string}, is_lib: boolean)
	-- if is_lib == true, #global before the function name
	
	local args: {func_arg} = func.args
	local body: {{depth: number, kind: string, name: string, type: string, val: any}} = func.body
	
	if not body or #body == 0 then
		return
	end
	
	-- entry
	self:emit_ln('#global')
	self:emit_ln(`_{func.name}:`)
	self:emit_ln(`push bp`)
	self:emit_ln(`mov bp sp`)
	
	-- +4 is any pushed args
	-- +2 ret address
	
	local var_locations = {}
	local bp_offset = 6
	local stack_frame = 2
	
	for i, v in self.global_variables do
		var_locations[v.name] = {reg = 'data', offset = v.offset, type = v.type, depth = v.depth, scope = v.scope}
	end
	
	for i, v in args do
		var_locations[v.name] = {reg = 'bp', offset = bp_offset, type = v.type, depth = v.depth}
		bp_offset += 2
	end
	
	local var_decls = self:get_func_var_decls(body, 0)
	
	self:emit_ln(`sub sp {2 + (#var_decls * 2)}`)
	
	--self:emit_ln(`push a`)
	--self:emit_ln(`push b`)
	
	for i, v in var_decls do
		local var_name = v.name
		local var_type = v.type
		local var_depth = v.depth
		local var_val = v.val
		local o_sf = stack_frame

		var_locations[var_name] = {reg = 'bp', offset = -o_sf, type = var_type, depth = var_depth, scope = v.scope, max_scope = v.max_scope}
		stack_frame += 2
	end

	--self:emit_ln(`pop b`)
	--self:emit_ln(`pop a`)
	
	return self:emit_block(body, var_locations, func.name, func.ret, 0)
end

function gen:emit_func_call(func: {}, args: {func_arg}, var_locs, scope: number)
	local expected_args = func.args
	
	for i, v in args do
		if v.type == 'VAR' then
			local var_name = v.name
			local loc = var_locs[var_name]
			
			if not loc then
				error(`variable {var_name} being passed into func call {func.name} is not defined`)
			end
			
			assert(is_within_scope(loc, scope), `{var_name} out of scope of function call {func.name}`)
			
			local r, o, t, d = loc.reg, loc.offset, loc.type, loc.depth
			
			v.type = t
			v.reg = r
			v.offset = o
			v.ptr = v.amp
		elseif v.arith then
			local tpe
			
			local function recurse_types(t)
				if tpe then
					return
				end
				
				if t.val then
					if not tpe then
						tpe = 'INT'
					end
				elseif t.arith then
					recurse_types(t.lhs)
					
					if t.rhs then
						recurse_types(t.rhs)
					end
				elseif t.name then
					local var = var_locs[t.name]
					
					assert(var, `undefined variable {t.name}`)
					
					assert(is_within_scope(var, scope), `{t.name} out of scope of function call {func.name}`)
					
					if not tpe then
						tpe = var.type
						return
					end
				end
			end
			
			recurse_types(v)
			
			v.type = tpe
		end
	end
	
	for i, v in expected_args do
		if not args[i] or args[i].type ~= v.type then
			if args[i] and args[i].type == 'INT' and v.type == 'CHAR' then
				continue
			end
			
			error(`invalid argument #{i} to {func.name} (expected {v.type}, got {args[i] and args[i].type or 'none'})`)
		end
	end
	
	for i, v in args do
		if not expected_args[i] then
			error(`invalid argument #{i} to {func.name} (expected none, got {v.type})`)
		end
	end
	
	local total_stack_offset = #args * 2
	
	for i = #args, 1, -1 do
		local v: func_arg = args[i]
		local e_arg = expected_args[i]
		local depth = v.depth
		
		if v.reg then
			-- var offset!
			
			-- push [reg+offset]
			
			if v.ptr then
				if v.offset ~= 0 then
					self:emit_ln(`push {v.reg}{v.offset < 0 and '-' or '+'}{math.abs(v.offset)}`)
				else
					self:emit_ln(`push {v.reg}`)
				end
			else
				if v.offset ~= 0 then
					self:emit_ln(`push [{v.reg}{v.offset < 0 and '-' or '+'}{math.abs(v.offset)}]`)
				else
					self:emit_ln(`push [{v.reg}]`)
				end
			end
		elseif not v.arith then
			-- push var
			self:emit_ln(`push {v.val}`)
		else
			local lhs, mid, rhs = v.lhs, v.mid, v.rhs
			
			-- both int literals
			if lhs.val and rhs.val then
				local val = lhs.val
				
				if mid == 'TOK_PLUS' then
					val += rhs.val
				elseif mid == 'TOK_MINUS' then
					val -= rhs.val
				elseif mid == 'TOK_STAR' then
					val *= rhs.val
				else
					error()
				end
				
				self:emit_ln(`push {val}`)
			else
				self:emit_arith('a', 'b', lhs, rhs, mid, var_locs, scope)
				self:emit_ln('push a')
			end
		end
	end
	
	self:emit_ln(`call _{func.name}`)
	
	if total_stack_offset > 0 then
		self:emit_ln(`add sp {total_stack_offset}`)
	end
end

local function recursive_search_ast_for_strlits(ast)
	local ret = {}
	
	for i, v in ast do
		if v.kind == 'VAR_DECL' and v.val and v.val.strlit then
			if not table.find(ret, v.val.str) then
				table.insert(ret, {str = v.val.str, decl_ref = v})
			end
		elseif v.kind == 'FUNC_DECL' and v.body then
			local r = recursive_search_ast_for_strlits(v.body)
			
			for a, b in r do
				for _, e in ret do
					if e.str == b.str then
						continue
					end
					
					table.insert(ret, e)
				end
			end
		end
	end
	
	return ret
end

function gen:gen()
	--[[
		super simple unoptimized assembly
	]]
	
	local main_func
	
	local data_sec_size = 0
	self.func_declarations = {}
	self.global_variables = {}
	
	local str_lits = recursive_search_ast_for_strlits(self.ast)

	self.string_tbl_size = 0
	self.strings = {}
	
	if #str_lits > 0 then
		for i, b in str_lits do
			local data = {
				offset = self.string_tbl_size,
				str = b.str
			}

			self.string_tbl_size += #b.str + 1

			table.insert(self.strings, data)
		end
	end
	
	for i, v in self.ast do
		if v.kind == 'FUNC_DECL' then
			if v.name == 'main' then
				main_func = v
			end
			
			if self.func_declarations[v.name] then
				error(`redefinition of function {v.name}`)
			end
			
			self.func_declarations[v.name] = v
		elseif v.kind == 'VAR_DECL' then
			v.scope = 0
			v.offset = data_sec_size
			
			if v.val and v.val.strlit then
				for a, b in self.strings do
					if b.str == v.val.str then
						v.val = {
							val = b.offset,
							
							do_real_val = `strings+{b.offset} .`,
							
							depth = 1,
						}
					end
				end
			end
			
			data_sec_size += type_sizes[v.type]
			
			self.global_variables[v.name] = v
			--table.insert(self.global_variables, v)
		elseif v.kind == 'ASM' then
			self:emit_ln(v.val)
		end
	end
	
	self:emit_ln('#sec text')
	self:emit_ln('#import _END_OF_BINARY')
	self:emit_ln('#import _START_OF_BINARY')
	self:emit_ln('#import _SECT_text')
	
	if #str_lits > 0 then
		self:emit_ln('#import _SECT_text')
	end
	
	self:emit_ln('#import _SECT_data')
	for i, v in self.func_declarations do
		if not v.body or #v.body == 0 then
			self:emit_ln(`#import _{v.name}`)
		end
	end

	if not self.flags.lib then
		self:emit_ln(`_entry:`)
		
		for i, v in self.global_variables do
			if not v.strlit then
				local val = v.val
				
				if val and not val.do_real_val then
					v.reg = 'data'
					if val.val then
						self:store_var(v.name, {'LIT', val.val, val.depth}, self.global_variables, 0, v.depth)
					elseif val.name then
						self:store_var(v.name, {'VAR', val.name, val.depth}, self.global_variables, 0, v.depth)
					end
				end
			end
		end
		
		assert(main_func, `no main function defined`)
		self:emit_func_call(main_func, {}, {})
	end
	
	for i, v in self.func_declarations do
		if v.body and #v.body > 0 then
			self:emit_func(v, self.flags.lib)
		end
	end

	if #str_lits > 0 then
		self:emit_ln(`#sec strings`)
		self:emit_ln(`strings:`)

		for i, v in self.strings do
			self:emit_ln(`#byte "{v.str}" 0 .`)
		end
	end
	
	self:emit_ln(`#sec data`)
	self:emit_ln('data:')
	
	for i, v in self.global_variables do
		local defined_value = v.val
		
		local val = defined_value and defined_value.val or 0
		local cmd = `#{type_sizes[v.type] == 1 and 'byte' or 'word'}`
		
		if not v.strlit then
			if v.val and not v.val.do_real_val then
				self:emit_ln(`{cmd} {val}{cmd == '#byte' and ' .' or ''} ; {v.name}`)
			elseif v.val and v.val.do_real_val then
				self:emit_ln(`{cmd} {v.val.do_real_val}{cmd == '#byte' and ' .' or ''}`)
			end
		end
	end
	
	self:emit_ln(`#def DATA_SIZE {data_sec_size}`) -- replace with size for undefined variables!
end

function gen:finalize()
	local real_len = 0
	
	while true do
		if buffer.readu8(self.buf, real_len) == 0 then
			break
		end
		
		real_len += 1
	end
	
	local copy = buffer.create(real_len + 1)
	
	buffer.copy(copy, 0, self.buf, 0, real_len + 1)
	
	warn(buffer.tostring(copy))
	
	return copy
end

function gen:init()
	self.buf = buffer.create(256)
	self.tail = 0
	self.size = 256
end

return function(ast, flags)
	local self = setmetatable({ast = ast, flags = flags}, gen)
	
	self:init()
	self:gen()
	
	return self:finalize()
end
