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

type operand = {
	kind: string,
	offset: number | boolean,
	value: number | string,

	import: boolean | nil,
	name: string | nil
}

local config = require('../../Config')

local function get_symbol(n: operand, symbols: {{symbol}}, sections: {{section}}): number
	local is_import = n.import

	-- symbols are forced to 16bit bc im lazy to resolve all the resizing
	
	if is_import then
		local name = n.name
		
		return 0
	else
		local resolved = nil

		for i, v in symbols do
			if v.name == n.name then
				resolved = v
			end
		end
		
		if not resolved then
			error(`invalid symbol {n.name}, did you mean to import it?`)
		end

		local section = resolved.section
		local offset = resolved.offset
		local base = 0

		if section == 'undefined' then
			warn(`got undefined section for symbol {n.name}, undefined behavior may occur`)
		else
			local did = false
			for i, v in sections do
				if v.name == section then
					did = true
					base = v.base
					break
				end
			end

			if not did then
				error(`no section named {section}`) -- ????? how ?????
			end
		end

		local final = base + offset
		
		return final
	end
end

return function(name: string, addr_mode: number, max_operands: number, operands: {operand}, symbols: {{symbol}}, sections: {{section}}, raw: string)
	local data = 0
	local bytes = {}
	local is_redef = {false, false}
	
	if addr_mode == 0 then
		local n = operands[1]
		local val = 0
		
		if not n and max_operands == 0 then
			-- it okie
		elseif not n and max_operands > 0 then
			error(`expected operand in instruction [{raw or name}]`)
		elseif n.kind == 'SYMBOL' then
			get_symbol(n, symbols, sections) -- check
			val = n.offset or 0
			
			data = bit32.bor(1, n.deref and 2 or 0)
			table.insert(bytes, bit32.band(val, 0xFF))
			table.insert(bytes, bit32.rshift(val, 8))
			
			is_redef[2] = true
		elseif n.kind == 'NUM' then
			local v = n.value
			
			table.insert(bytes, bit32.band(v, 0xFF))
			
			if v > 0xFF then
				data = 1
				table.insert(bytes, bit32.rshift(v, 8))
			end
		elseif n.kind == 'MEM' then
			local v = n.value
			
			table.insert(bytes, bit32.band(v, 0xFF))
			
			if v > 0xFF then
				data = 3 -- 2 ^ 1
				table.insert(bytes, bit32.rshift(v, 8))
			else
				data = 2
			end
		end
	elseif addr_mode == 1 then -- 1 = REG, LOWER 3 BITS OF DATA IS THE INDEX ex JMP A, IF BIT 3 (8) IS SET, DEREF A
		local n = operands[1]
		
		local reg_idx = config.REG_INDICES[n.value]
		local deref = n.reg_deref
		
		if not reg_idx then
			error(`invalid register {n.value}`)
		end
		
		data = bit32.bor(reg_idx, (deref and 8 or 0))
	elseif addr_mode == 2 then -- 2 = (REG / REG DEREF) -> (REG / REG DEREF) (SRC REG IN HIGH 3 BITS, DEST REG IN LOW 3 BITS), BIT 3 INDICATES IF SRC REG IS DEREFFED, BIT 4 INDICATES IF DEST REG IS DEREFFED
		local b, a = operands[1], operands[2]
		
		local dest_idx, src_idx = config.REG_INDICES[b.value], config.REG_INDICES[a.value]
		local dest_deref, src_deref = b.reg_deref, a.reg_deref
		
		if not dest_idx or not src_idx then
			error(`invalid register {not dest_idx and b.value or src_idx and a.value}`)
		end
		
		data = bit32.bor(bit32.lshift(src_idx, 5), dest_idx, (src_deref and 8 or 0), (dest_deref and 16 or 0))
	elseif addr_mode == 3 then -- 3 = (IMM / IMM DEREF) -> (REG / REG DEREF) (DEST REG IN LOW 3 BITS), BIT 3 IS SIZE, BIT 4 IS DEREF, BIT 5 IS DEST REG DEREF
		local b, a = operands[1], operands[2]
		
		local dest_idx = config.REG_INDICES[b.value]
		
		if not dest_idx then
			error(`invalid register {b.value}`)
		end
		
		local a_val
		
		if a.kind ~= 'SYMBOL' then
			a_val = a.value
		else
			get_symbol(a, symbols, sections)
			a_val = a.offset or 0
			is_redef = {true, false}
		end
		
		data = bit32.bor(
			dest_idx,
			((a_val > 0xFF or a.kind == 'SYMBOL') and 8 or 0),
			((a.kind == 'MEM' or a.deref) and 16 or 0),
			(b.reg_deref and 32 or 0)
		)

		table.insert(bytes, bit32.band(a_val, 0xFF))

		if a_val > 0xFF or a.kind == 'SYMBOL' then
			table.insert(bytes, bit32.rshift(a_val, 8))
		end
	elseif addr_mode == 4 then -- 4 = (REG OFFSET / OFFSET DEREF), LOW 3 BITS IS REGISTER, EXTRA BYTE AFTER INSTRUCTION, SIGNED, IS OFFSET OF REGISTER, BIT 3 INDICATES IF THIS IS A DEREF, IF BIT 4 IS SET, IT BECOMES REG -> (OFFSET / OFFSET DEREF), AND BITS 5, 6, 7 ARE THE SRC IDX
		local b, a = operands[1], operands[2]

		local reg_idx = config.REG_INDICES[b.value]
		local offset = b.offset
		local deref = b.reg_deref
		
		if a then
			data = bit32.bor(
				data,
				a.reg_deref and 8 or 0,
				16,
				bit32.lshift(config.REG_INDICES[a.value], 5),
				reg_idx
			)
		else
			data = bit32.bor(data, reg_idx, deref and 8 or 0)
		end
		
		table.insert(bytes, offset)
	elseif addr_mode == 5 then
		-- 	5 = (REG OFFSET / OFFSET DEREF) -> (REG / REG DEREF), LOW 3 BITS IS REGISTER, BIT 3 (8) IS SET IF SRC REG IS DEREFED, BIT 4 (16) IS SET IF DEST IS A DEREFERENCED REGISTER, HIGH 3 BITS DEST REGISTER
		local b, a = operands[1], operands[2]
		
		local dest_idx, dest_deref = config.REG_INDICES[b.value], b.reg_deref
		local src_idx, src_deref = config.REG_INDICES[a.value], a.reg_deref
		local offset = a.offset
		
		data = bit32.bor(
			src_idx,
			src_deref and 8 or 0,
			dest_deref and 16 or 0,
			bit32.lshift(dest_idx, 5)
		)
		
		table.insert(bytes, offset)
	elseif addr_mode == 6 then
		 -- 6 = (IMM / IMM DEREF / REG / REG DERF) -> MEM, BIT 0 IS IMM SIZE, BIT 1 IS IMM DEREF, BIT 2 IS ADDR SIZE, IF BIT 3 IS SET, REG IS TOP 3 BITS, BIT 2 IS REG DEREF
		
		local b, a = operands[1], operands[2]
		
		local a_val
		local b_val
		
		local a_deref = (a.reg_deref or a.kind == 'MEM' or a.deref)
		local a_reg = false
		
		if a.kind == 'SYMBOL' then
			get_symbol(a, symbols, sections)
			is_redef[1] = true
			data = bit32.bor(1, a_deref and 2 or 0)
			a_val = a.offset or 0
		elseif a.kind == 'NUM' or (a.kind == 'MEM' and not a.reg_deref) then
			a_val = a.value
			data = bit32.bor(a_val > 0xFF and 1 or 0, a_deref and 2 or 0)
		elseif a.kind == 'REG' or a.reg_deref then
			a_reg = true
			a_val = config.REG_INDICES[a.value]
		end
		
		if b.kind == 'SYMBOL' then
			get_symbol(b, symbols, sections)
			data = bit32.bor(data, 4)
			b_val = b.offset or 0
			is_redef[2] = true
		elseif b.kind == 'MEM' then
			data = bit32.bor(b.value > 0xFF and 4 or 0)
			b_val = b.value
		end
		
		if a_reg then
			data = bit32.bor(data, 8, bit32.lshift(a_val, 5))
		else
			table.insert(bytes, bit32.band(a_val, 0xFF))
			
			if bit32.btest(data, 1) then
				table.insert(bytes, bit32.rshift(a_val, 8))
			end
		end
		
		table.insert(bytes, bit32.band(b_val, 0xFF))
		
		if bit32.btest(data, 4) then
			table.insert(bytes, bit32.rshift(b_val, 8))
		end
	elseif addr_mode == 7 then
		--[[
			(REG OFFSET / REG OFFSET DEREF / MEM / IMM) -> (MEM OR REG OFFSET DEREF), BITS 0 AND 1 INDICATE THE TYPE, BIT 2 SET IF MEM NOT SET IF REG OFFSET DEREF
			IF TYPE == REG OFFSET OR DEREF OFFSET, EXTRA BYTE FOR OFFSET, HIGH 3 BITS IS THE REGISTER INDEX
			IF TYPE == MEM OR IMM, BIT 3 IS THE SIZE INDICATOR, 1 FOR 2 BYTES, 0 FOR 1 BYTE

			IF BIT 2 IS SET, DESTINATION IS MEMORY ADDRESS, BIT 4 IS SET FOR SIZE OF ADDRESS
			IF BIT 2 IS NOT SET, DEST IS A REG OFFSET DEREFERENCE. 2 BYTES ARE ADDED, ONE IS THE DESTINATION REGISTER INDEX, AND THE NEXT IS THE OFFSET
		]]
		
		local type = 0
		
		local b, a = operands[1], operands[2]
		
		local b_is_reg = b.kind == 'REG' or b.reg_deref or false
		local a_is_reg = a.kind == 'REG' or a.reg_deref or false
		
		local a_offset = a.offset
		local b_offset = b.offset
		
		local a_val
		local b_val
		
		local a_size, b_size = false, false
		
		if a.kind == 'SYMBOL' then
			get_symbol(a, symbols, sections)
			a_val = a.offset or 0
			a_size = true
			is_redef[1] = true
		elseif (a.kind == 'MEM' and not a_is_reg) or a.kind == 'NUM' then
			a_val = a.value
			a_size = a_val > 0xFF
		end
		
		if b.kind == 'SYMBOL' then
			get_symbol(b, symbols, sections)
			b_val = b.offset or 0
			b_size = true
			is_redef[2] = true
		elseif b.kind == 'MEM' and not b_is_reg then
			b_val = b.value
			b_size = b_val > 0xFF
		end
		
		if a_is_reg then
			data = bit32.bor(data, a.kind == 'REG' and 0 or 1, bit32.lshift(config.REG_INDICES[a.value], 5))
			table.insert(bytes, a_offset)
		else
			data = bit32.bor(data, ((a.kind == 'SYMBOL' and a.deref) or a.kind == 'MEM') and 2 or 3, a_size and 8 or 0)
			
			table.insert(bytes, bit32.band(a_val, 0xFF))
			
			if a_size then
				table.insert(bytes, bit32.rshift(a_val, 8))
			end
		end
		
		if b_is_reg then
			table.insert(bytes, config.REG_INDICES[b.value])
			table.insert(bytes, b.offset)
		else
			data = bit32.bor(data, 4, b_size and 16 or 0)
			table.insert(bytes, bit32.band(b_val, 0xFF))
			
			if b_size then
				table.insert(bytes, bit32.rshift(b_val, 8))
			end
		end
	end
	
	return data, bytes, is_redef
end
