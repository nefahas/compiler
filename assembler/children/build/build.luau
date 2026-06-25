type operand = {
	kind: string,
	offset: number | boolean,
	value: number | string,
	
	import: boolean | nil,
	name: string | nil
}

type instruction = {
	name: string,
	offset: number,
	operands: {operand},
	section: string
}

type data_entry = {
	bytes: {number},
	offset: number,
	section: string,
	size: number,
	
	name: string | nil -- symbol
}

type symbol = {
	name: string,
	section: string,
	offset: number
}

type section = {
	base: number,
	name: string,
	size: number
}

local config = require('../Config')
local data_solver = require('@self/data_solver')

local builder = {}
builder.__index = builder

local function new_section_data(name: string)
	return {
		name = name,
		size = 256,
		tail = 0,
		buff = buffer.create(256)
	}
end

function builder:emit_byte(section: string, byte: number)
	local sec_data = self.section_data[section]

	if not sec_data then
		sec_data = new_section_data(section)
		self.section_data[section] = sec_data
	end

	local sec_tail, sec_size, sec_buff = sec_data.tail, sec_data.size, sec_data.buff

	if sec_tail >= sec_size then
		sec_size *= 2
		
		local n_buff = buffer.create(sec_size)
		buffer.copy(n_buff, 0, sec_buff, 0)
		sec_data.size = sec_size
		sec_data.buff = n_buff
		sec_buff = n_buff
	end
	
	buffer.writeu8(sec_buff, sec_tail, byte)
	sec_tail += 1
	self.idx += 1
	
	sec_data.tail = sec_tail
end

function builder:emit_instr(section: string, opcode: number, addr_mode: number, data: number, extra_bytes: {number} | nil)
	local instr = bit32.bor(bit32.lshift(opcode, 11), bit32.lshift(data, 3), addr_mode)
	
	self:emit_byte(section, bit32.band(instr, 0xFF))
	self:emit_byte(section, bit32.rshift(instr, 8))
	
	for i, v in extra_bytes do
		self:emit_byte(section, v)
	end
end

function builder:get_tail(section: string)
	local data = self.section_data[section]
	
	return data and data.tail or 0
end

function builder:build()
	local need_redef = {} -- imports only, [import_name]: {}
	
	-- section: {} offset sorted
	
	local sorted_list = {}
	local sorted_sections = {}
	
	for i, v in self.instructions do
		local sec_tbl = sorted_list[v.section]
		
		if not sec_tbl then
			sec_tbl = {}
			sorted_list[v.section] = sec_tbl
		end
		
		local operands = v.operands
		local size = config.get_instruction_size_bytes(v.name, operands)
		
		v.instruction = true
		table.insert(sec_tbl, v)
		
		for i = 1, size - 1 do
			table.insert(sec_tbl, {padding = true, offset = v.offset + i})
		end
	end
	
	for i, v in self.data do
		local sec_tbl = sorted_list[v.section]

		if not sec_tbl then
			sec_tbl = {}
			sorted_list[v.section] = sec_tbl
		end

		v.data = true
		table.insert(sec_tbl, v)
		for i = 1, v.size - 1 do
			table.insert(sec_tbl, {padding = true, offset = v.offset + i})
		end
	end
	
	for i, v in sorted_list do
		table.sort(v, function(a, b) return a.offset < b.offset end)
	end
	
	for aa, bb in self.sections do
		local section = bb.name
		local list = sorted_list[section]
		
		if not list then
			continue
		end
		
		for i, v in list do
			if v.instruction then
				local name = v.name
				local operands = v.operands

				local addr_mode = config.get_addr_mode(operands)
				local max_operands = config.OPERAND_COUNT[name]
				local opcode = config.OPCODE_MAP[name]

				local valid = table.find(config.INSTR_MODES[opcode], addr_mode)

				if not valid then
					error(`invalid mode {addr_mode} for {name}, expected {table.concat(config.INSTR_MODES[opcode], ', ')}`)
				end
				
				local data, bytes, ops_redef = data_solver(name, addr_mode, max_operands, operands, self.symbols, self.sections, v.raw)
				-- returns a redef table which defines which operand needs to be redefined
				-- {a, b}, true / false

				local a_r, b_r = ops_redef[1], ops_redef[2]
				
				if name == 'SF' then
					local info = config.FLAG_SET_INSTRUCT_DATA[v.raw]
					local set, idx = info.set, info.data
					
					data = bit32.bor(data, bit32.lshift(idx, 5), set and 16 or 0)
				elseif name == 'JC' then
					local info = config.CONDITIONAL_JMP_DATA[v.raw]
					local opp = false
					
					-- is an opposite one
					if not info then
						for a, b in config.CONDITIONAL_JMP_DATA do
							if b.opp == v.raw then
								info = b
								opp = true
								break
							end
						end
					end
					
					if not info then
						error(`invalid instruction {v.raw} at instruction i`)
					end
					
					data = bit32.bor(data, bit32.lshift(info.data, 5), opp and 16 or 0)
				end
				
				if a_r or b_r then
					local tail = self.idx

					local a_name = a_r and operands[2].name
					local b_name = b_r and operands[1].name

					if a_name then
						if not need_redef[a_name] then
							need_redef[a_name] = {}
						end

						if need_redef[a_name][tail] then
							need_redef[a_name][tail].a = true
						else
							need_redef[a_name][tail] = {a = true}
						end
					end

					if b_name then
						if not need_redef[b_name] then
							need_redef[b_name] = {}
						end

						if need_redef[b_name][tail] then
							need_redef[b_name][tail].b = true
						else
							need_redef[b_name][tail] = {b = true}
						end
					end
				end

				self:emit_instr(section, opcode, addr_mode, data, bytes)
			elseif v.data then
				for i, v in v.bytes do
					self:emit_byte(section, v)
				end
			end
		end
	end
	
	self.redef_table = need_redef
end

function builder:finalize()
	local final_size = 0
	
	for i, v in self.section_data do
		final_size += v.tail
	end
	
	local final_buff = buffer.create(final_size)
	local cur_tail = 0
	
	for i, v in self.sections do
		local sec_data = self.section_data[v.name]
		
		if not sec_data then
			warn(`no sec data for .{v.name}? (empty)`)
			continue
		end
		

		buffer.copy(final_buff, cur_tail, sec_data.buff, 0, sec_data.tail)
		cur_tail += sec_data.tail
	end
	
	return final_buff
end

function builder:init()
	self.section_data = {
		-- {name: string, tail: number, size: number, buff: buffer}
	}
end

return function (instructions: {instruction}, data: {data_entry}, file_name: string, symbols: {{symbol}}, sections: {{section}})
	local self = setmetatable({
		instructions = instructions,
		data = data,
		file_name = file_name,
		
		symbols = symbols,
		sections = sections,
		
		idx = 0,
	}, builder)
	
	self:init()
	self:build()
	
	local final_buffer = self:finalize()
	
	return final_buffer, self.redef_table
end
