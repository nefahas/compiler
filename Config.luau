local config
config = {
	REG_INDICES = {
		A = 0,
		B = 1,
		C = 2,
		D = 3,
		E = 4,
		BP = 5,
		SP = 6,
		PC = 7
	},
	
	REG_KEYWORDS =  {
		'A',
		'B',
		'C',
		'D',
		'E',
		'BP',
		'SP',
		'PC',
	},
	
	OPCODE_MAP = {
		NOP = 0,

		MOV = 1,
		MOVW = 2,
		JMP = 3,
		JC = 4,
		
		ADD = 5,
		ADC = 6,
		SUB = 7,
		SBB = 8,
		
		CMP = 9,
		CMPW = 10,
		
		SF = 11,
		PUSH = 12,
		POP = 13,
		CALL = 14,
		RET = 15,
		
		MUL = 16,
		IRET = 17,
		SIRQ = 18,
		
		AND = 19,
		OR = 20,
		XOR = 21,
		NOT = 22,
		
		SHL = 23,
		SLR = 24,
		SAR = 25,
		
		CMPS = 26,
		CMPSW = 27,
		SXB = 28,
		
		BRKPT = 31
	},

	OPERAND_COUNT = {
		NOP = 0,
		MOV = 2,
		MOVW = 2,
		JMP = 1,
		JC = 1,
		
		ADD = 2,
		ADC = 2,
		SUB = 2,
		SBB = 2,
		
		CMP = 2,
		CMPW = 2,
		
		SF = 0,
		
		PUSH = 1,
		POP = 1,
		
		CALL = 1,
		RET = 0,
		IRET = 0,
		SIRQ = 0,
		
		MUL = 2,
		
		AND = 2,
		OR = 2,
		XOR = 2,
		NOT = 1,
		
		SHL = 2,
		SLR = 2,
		SAR = 2,
		
		CMPS = 2,
		CMPSW = 2,
		
		SXB = 1,
		
		BRKPT = 0
	},
	
	INSTR_MODES = {
		[0] = {0},
		[1] = {2, 3, 4, 5, 6, 7},
		[2] = {2, 3, 4, 5, 6, 7},
		[3] = {0, 1, 4},
		[4] = {0, 1, 4},
		
		[5] = {2, 3, 5, 6, 7},
		[6] = {2, 3, 5, 6, 7},
		[7] = {2, 3, 5, 6, 7},
		[8] = {2, 3, 5, 6, 7},
		
		[9] = {2, 3, 5, 6, 7},
		[10] = {2, 3, 5, 6, 7},
		[11] = {0},
		[12] = {0, 1, 4},
		[13] = {0, 1, 4},
		[14] = {0, 1, 4},
		[15] = {0},
		
		[16] = {2, 3, 5, 6, 7},
		[17] = {0},
		[18] = {0, 1},
		
		[19] = {2, 3, 5, 6, 7},
		[20] = {2, 3, 5, 6, 7},
		[21] = {2, 3, 5, 6, 7},
		[22] = {0, 1, 4},
		
		[23] = {3},
		[24] = {3},
		[25] = {3},
		[26] = {2, 3, 5, 6, 7},
		[27] = {2, 3, 5, 6, 7},
		[28] = {1},
		
		[31] = {0}
	},
	
	INSTR_KEYWORDS = {
		'NOP',
		'MOV',
		'MOVW',
		'JMP',
		
		'ADD',
		'ADC',
		'SUB',
		'SBB',
		
		'CMP',
		'CMPW',
		
		'PUSH',
		'POP',
		'CALL',
		'RET',
		'IRET', 
		'SIRQ',
		
		'MUL',
		
		'AND',
		'OR',
		'XOR',
		'NOT',
		
		'SHL',
		'SLR',
		'SAR',
		
		'CMPS',
		'CMPSW',
		
		'SXB'
	},
	
	CONDITIONAL_JMP_KEYWORDS = {
		'JZ',
		'JC',
		'JS',
		'JGT',
		'JLT',
		'JEQ',
		'JLE',
		'JGE',
		
		'JNZ',
		'JNC',
		'JNS',
		'JNE',
	},
	
	FLAG_SET_INSTRUCTS = {
		'SCF', 'CCF',
		'SOF', 'COF',
		'SZF', 'CZF',
		'SIF', 'CIF',
	},
	
	FLAG_SET_INSTRUCT_DATA = {
		SCF = {set = true, data = 0},
		CCF = {set = false, data = 0},
		SOF = {set = true, data = 1},
		COF = {set = false, data = 1},
		SZF = {set = true, data = 2},
		CZF = {set = false, data = 2},
		SIF = {set = true, data = 4},
		CIF = {set = false, data = 4},
	},
	-- data is the high 3 bits of the instruction being set for the jmp type
	-- opp indicates the opposite, if the keyword is an opposite, bit 4 is set
	CONDITIONAL_JMP_DATA = {
		JZ = {data = 0, opp = 'JNZ'},
		JC = {data = 1, opp = 'JNC'},
		JS = {data = 2, opp = 'JNS'},
		JEQ = {data = 3, opp = 'JNE'},
		
		JGT = {data = 4},
		JLT = {data = 5},
		JLE = {data = 6},
		JGE = {data = 7},
	},
	
	COND_JMP_FLAG_IDXS = {
		[0] = {2}, -- jz
		[1] = {0}, -- jc
		[2] = {3}, -- js
		[3] = {0}, -- jeq
		[4] = {1}, -- jgt
		[5] = {3}, -- jlt
		[6] = {3, 0}, -- jle
		[7] = {1, 0}, -- jge
	},
	
	FLAG_INDICES = {
		[0] = 'CF / EQ',
		[1] = 'OF / GT',
		[2] = 'ZF',
		[3] = 'SF / LT',
		[4] = 'IF',
	},
	
	get_addr_mode = function(operands: {})
		--[[
			instructions are A -> B
			we do dest, src syntax tho
		]]
		
		if #operands == 0 then
			return 0
		elseif #operands == 1 then
			local a = operands[1]

			if a.kind == 'REG' then
				if a.offset then
					return 4
				end

				return 1
			elseif a.kind == 'NUM' or a.kind == 'MEM' or a.kind == 'SYMBOL' then
				if a.kind == 'MEM' and a.offset and a.reg_deref then
					return 4
				elseif a.kind == 'MEM' and a.reg_deref then
					return 1
				end

				return 0
			end
		elseif #operands == 2 then 
			local b, a = operands[1], operands[2]

			if b.kind == 'REG' then
				if a.kind == 'REG' or (a.kind == 'MEM' and a.reg_deref and not a.offset) then
					if a.kind == 'REG' and a.offset then
						return 5
					end

					return 2
				elseif ((a.kind == 'NUM' or a.kind == 'SYMBOL') or (a.kind == 'MEM' and not a.offset)) then
					return 3
				elseif a.kind == 'MEM' and a.offset and a.reg_deref then
					return 5
				end
			elseif b.kind == 'MEM' or (b.kind == 'SYMBOL' and b.deref) then
				if b.offset and b.reg_deref and ((a.kind == 'REG' or a.reg_deref) and not a.offset) then
					return 4
				end

				if (b.reg_deref and b.offset) or tonumber(b.value) then
					if
						(a.kind == 'REG' and a.offset) or
						(a.kind == 'MEM' and a.offset and a.reg_deref) or
						(a.kind == 'MEM' and tonumber(a.value)) or
						(a.kind == 'SYMBOL') or
						(a.kind == 'NUM')
					then
						return 7
					end
				end
				
				if b.reg_deref and ((a.kind == 'MEM' and a.reg_deref and a.offset) or (a.kind == 'REG' and a.offset)) then
					return 5
				end

				if b.reg_deref and (a.kind == 'REG' or (a.kind == 'MEM' and a.reg_deref)) then
					return 2
				elseif b.reg_deref and (a.kind == 'MEM' and not a.reg_deref) then
					return 3
				elseif b.reg_deref and (a.kind == 'NUM' or a.kind == 'SYMBOL') then
					return 3
				elseif (a.kind == 'MEM' and tonumber(a.value)) or (a.kind == 'NUM' or a.kind == 'SYMBOL') then
					return 6
				elseif a.kind == 'REG' or (a.kind == 'MEM' and a.reg_deref) then
					return 6
				end
			end
		end
	end,
	
	-- trash but idrccccccccc
	get_instruction_size_bytes = function(instr: string, operands: {kind: string, value: string | number})
		local size = 2
		
		local opcode = config.OPCODE_MAP[instr]
		
		if not opcode then
			return 0
		end
		
		local addr_mode = config.get_addr_mode(operands)
		
		if not addr_mode then
			return 0
		end
		
		if addr_mode == 0 then
			local num = operands[1]
			
			if not num then
				return size
			end
			
			size += 1
			
			if num.kind == 'SYMBOL' or (num.force_16 or num.value > 0xFF) then
				size += 1
			end
		elseif addr_mode == 3 then
			local a = operands[2]
			
			size += 1

			if a.kind == 'SYMBOL' or (a.force_16 or a.value > 0xFF) then
				size += 1
			end
		elseif addr_mode == 4 then
			size += 1
		elseif addr_mode == 5 then
			size += 1
		elseif addr_mode == 6 then -- 6 = (IMM / IMM DEREF / REG / REG DERF) -> MEM, BIT 1 IS IMM SIZE, BIT 2 IS IMM DEREF, BIT 3 IS ADDR SIZE, IF BIT 4 IS SET, REG IS TOP 3 BITS, BIT 2 IS REG DEREF
			local b, a = operands[1], operands[2]
			
			size += 1 -- 1 byte addr
			
			if b.kind == 'SYMBOL' or (b.force_16 or b.value > 0xFF) then
				size += 1 -- 1 more byte addr
			end
			
			if a.kind ~= 'REG' and not a.reg_deref then
				size += 1 -- 1 byte imm

				if a.kind == 'SYMBOL' or (a.force_16 or a.value > 0xFF) then
					size += 1 -- another byte imm
				end
			end
		elseif addr_mode == 7 then
			local b, a = operands[1], operands[2]

			local b_is_offset = b.offset and b.reg_deref
			local a_is_offset = a.offset and (a.reg_deref or a.kind == 'REG')
			
			if a_is_offset then
				size += 1
			else
				size += 1
				
				if a.kind == 'SYMBOL' or (a.force_16 or a.value > 0xFF) then
					size += 1
				end
			end
			
			if not b_is_offset then
				size += 1
				
				if b.kind == 'SYMBOL' or (b.force_16 or b.value > 0xFF) then
					size += 1
				end
			else
				size += 2
			end
		end
		
		return size
	end,
}

return config
