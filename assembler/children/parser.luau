local config = require('../Config')

local parser = {}
parser.__index = parser

function parser:peek()
	if self.idx > self.len then
		error(`out of bounds on parser {debug.info(2, 'n') == 'advance' and 'advance' or 'peek'}\nidx: {self.idx}, len: {self.len}`)
	end
	
	return self.tokens[self.idx]
end

function parser:advance()
	local token = self:peek()
	
	self.idx += 1
	
	return token
end

function parser:expect(kind: string)
	local token = self:advance()
	
	if token.kind ~= kind then
		error(`expected {kind}, got {token.kind} at {token.raw}\n{token.raw}`)
	end
	
	return token
end

function parser:get_offset()
	local c = self:advance()
	local offset = self:expect('TOK_NUM').value
	
	if c.kind == 'TOK_MINUS' then
		offset = -offset
	else
		offset = offset
	end
	
	if offset < -128 or offset > 127 then
		error(`invalid offset {offset} at {self.idx}, expected [-128 - 127]`)
	end
	
	return offset
end

function parser:has_offset()
	local c = self:peek()
	
	return c.kind == 'TOK_MINUS' or c.kind == 'TOK_PLUS'
end

function parser:is_imported(name: string)
	for i, v in self.imports do
		if v.name == name and v.external then
			return true
		end
	end
	
	return false
end

function parser:get_operands(max: number)
	local operands = {}
	
	for i = 1, max do
		local c = self:peek()
		
		if c.kind == 'TOK_NUM' then
			table.insert(operands, {
				kind = 'NUM',
				value = self:expect('TOK_NUM').value,
			})
		elseif c.kind == 'TOK_REG' then
			local reg = self:expect('TOK_REG').value
			local offset: number
			
			if self:has_offset() then
				offset = self:get_offset()
			end
			
			table.insert(operands, {
				kind = 'REG',
				value = reg,
				offset = offset
			})
		elseif c.kind == 'TOK_STR' then
			local name = self:expect('TOK_STR').value
			local is_imported = self:is_imported(name)
			
			local offset = (self:has_offset() and self:get_offset()) or nil
			
			table.insert(operands, {
				kind = 'SYMBOL',
				name = name,
				value = 0,
				import = is_imported,
				offset = offset
			})
		elseif c.kind == 'TOK_LBRACK' then
			self:advance()
			c = self:advance()
			
			if c.kind == 'TOK_NUM' then
				table.insert(operands, {
					kind = 'MEM',
					value = c.value,
				})
			elseif c.kind == 'TOK_REG' then
				local offset = self:has_offset() and self:get_offset()

				table.insert(operands, {
					kind = 'MEM',
					value = c.value,
					offset = offset,
					reg_deref = true,
				})
			elseif c.kind == 'TOK_STR' then
				local name = c.value
				local is_imported = self:is_imported(name)

				local offset = (self:has_offset() and self:get_offset()) or nil
				
				table.insert(operands, {
					kind = 'SYMBOL',
					name = name,
					value = 0,
					import = is_imported,
					deref = true,
					offset = offset
				})
			else
				error(`unexpected token {c.kind}`)
			end
			
			self:expect('TOK_RBRACK')
		end
	end
	
	return operands
end

function parser:parse()
	local instructions = {}
	local data = {}
	
	while self.idx <= self.len do
		local tok = self:advance()
		
		if tok.kind == 'TOK_EOF' then
			break
		end
		
		if tok.kind == 'TOK_HASH' then
			local cmd = self:expect('TOK_STR').value
			
			if cmd == 'global' then
				self.next_lbl_global = true
			elseif cmd == 'import' then
				local name = self:expect('TOK_STR')
				
				table.insert(self.imports, {name = name.value, external = true})
			elseif cmd == 'sec' or cmd == 'section' then
				local name = self:expect('TOK_STR')
				
				if self.section_map[name.value] then
					error(`section {name.value} is already defined`)
				end
				
				local nxt = self:peek()
				
				local cur_section = self.current_section
				
				if cur_section ~= 'undefined' then
					for i, v in self.sections do
						if v.name == cur_section then
							v.size = self.section_offset
							break
						end
					end
				end
				
				self.loc_counter += self.section_offset
				self.section_map[name.value] = true
				table.insert(self.sections, {name = name.value, base = self.loc_counter, size = 0})
				self.section_offset = 0
				self.current_section = name.value
			elseif cmd == 'word' then
				local nxt = self:advance()
				local val: number
				
				if nxt.kind == 'TOK_STR' then
					local str = nxt.value
					
					local is_section = self.section_map[str]
					
					if is_section then
						local nxt = self:advance()
						local base
						
						for i, v in self.sections do
							if v.name == str then
								base = v.base
								break
							end
						end
						
						if nxt.kind == 'TOK_PERIOD' then
							val = base
						elseif nxt.kind == 'TOK_PLUS' then
							val = base + self:expect('TOK_NUM').value
							self:expect('TOK_PERIOD')
						elseif nxt.kind == 'TOK_MINUS' then
							val = base - self:expect('TOK_NUM').value
							self:expect('TOK_PERIOD')
						else
							error(`unexpected token {nxt.kind}`)
						end
					end
				elseif nxt.kind == 'TOK_NUM' then
					val = nxt.value
				end
				
				local bytes = {bit32.band(val, 0xFF), bit32.rshift(val, 8)}
				
				table.insert(data, {section = self.current_section, offset = self.section_offset, bytes = bytes, size = 2})
				self.section_offset += 2
			elseif cmd == 'db' or cmd == 'byte' then
				local name
				
				if cmd == 'db' then
					name = self:expect('TOK_STR')
				
					if self.symbols[name.value] then
						error(`symbol {name.value} is already defined; being overwritten at [{self.current_section}+{self.section_offset}]`)
					end
				end
				
				local bytes = {}
				
				while self:peek().kind ~= 'TOK_PERIOD' do
					local v = self:advance()
					
					if v.kind == 'TOK_ESCSTR' then
						local b = {string.byte(v.value, 1, #v.value)}
						
						table.move(b, 1, #b, #bytes + 1, bytes)
					elseif v.kind == 'TOK_CHAR' then
						table.insert(bytes, v.value)
					elseif v.kind == 'TOK_NUM' then
						if v.value > 0xFF then
							local byte_count = (math.log(v.value, 2) // 8) + 1
							
							for i = 0, byte_count - 1 do
								table.insert(bytes, bit32.band(bit32.rshift(v.value, i * 8), 0xFF))
							end
						else
							table.insert(bytes, v.value)
						end
					else
						error(`unexpected token {v.kind} [{v.value}] in #db {name}`)
					end
				end
				
				self:expect('TOK_PERIOD')
				
				local offset = self.section_offset
				local section = self.current_section
				
				if name then
					local is_glbl = self.next_lbl_global
					self.next_lbl_global = false
					self.symbols[name.value] = {section = self.current_section, offset = self.section_offset}
					
					local sym_tbl = {
						name = name.value,
						offset = offset,
						section = section
					}
					
					self.section_offset += #bytes
					
					table.insert(self.symbol_list, sym_tbl)
					
					if is_glbl then
						table.insert(self.globals, sym_tbl)
					end
				end
				
				table.insert(data, {section = section, offset = offset, bytes = bytes, size = #bytes})
			elseif cmd == 'dblock' then
				local name = self:expect('TOK_STR').value
				local size = self:expect('TOK_NUM').value
				
				self:expect('TOK_PERIOD')
				
				local is_glbl = self.next_lbl_global
				self.next_lbl_global = false
				
				self.symbols[name] = {section = self.current_section, offset = self.section_offset}
				
				local sym_tbl = {
					name = name.value,
					offset = self.section_offset,
					section = self.current_section
				}
				
				self.section_offset += size
				
				table.insert(self.symbol_list, sym_tbl)
				
				if is_glbl then
					table.insert(self.globals, sym_tbl)
				end
				
				table.insert(data, {section = sym_tbl.section, offset = sym_tbl.offset, bytes = table.create(size, 0), size = size})
			end
		elseif tok.kind == 'TOK_STR' then
			local is_label = self:peek().kind == 'TOK_COLON' and self:advance() and tok.value or false
			
			if is_label then
				if self.symbols[tok.value] then
					error(`symbol {tok.value} is already defined; being overwritten at [{self.current_section}+{self.section_offset}]`)
				end
				
				local is_glbl = self.next_lbl_global
				self.next_lbl_global = false
				
				local symbol_tbl = {
					name = tok.value,
					offset = self.section_offset,
					section = self.current_section
				}
				
				self.symbols[tok.value] = {section = self.current_section, offset = self.section_offset}
				table.insert(self.symbol_list, symbol_tbl)
				
				if is_glbl then
					table.insert(self.globals, symbol_tbl)
				end
			else
				error(`unexpected [TOK_STR] at {self.idx}: {tok.value}`)
			end
		elseif tok.kind == 'TOK_INSTR' then
			local name = tok.value
			local max_operands = config.OPERAND_COUNT[name]
			
			if not max_operands then
				error(`invalid instruction {name} at [.{self.current_section}+{self.section_offset}]`)
			end
			
			local operands = self:get_operands(max_operands)
			
			table.insert(instructions, {name = name, raw = tok.raw, operands = operands, section = self.current_section, offset = self.section_offset})
			
			local size = config.get_instruction_size_bytes(name, operands)
			local cur_section = self.current_section
			
			self.section_offset += size
			
			if cur_section ~= 'undefined' then
				for i, v in self.sections do
					if v.name == cur_section then
						v.size = self.section_offset
						break
					end
				end
			end
		end
	end
	
	return instructions, data, self.globals, self.imports, self.symbol_list, self.sections
end

return function(tokens: {{kind: string, value: string | number, raw: string}})
	local self = setmetatable({
		tokens = tokens,
		idx = 1,
		len = #tokens,
		
		section_offset = 0,
		loc_counter = 0,
		current_section = 'undefined',
		
		parsed = {},
		data = {},
		org_sets = {},
		
		symbol_list = {},
		section_map = {},
		
		sections = {},
		symbols = {},
		globals = {},
		imports = {},
		relocs = {},
	}, parser)
	
	return self:parse()
end
