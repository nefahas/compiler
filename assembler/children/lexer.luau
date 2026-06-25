--!native
--!optimize 2

local config = require('../Config')

local SYNTAX_TOKENS = {
	['['] = 'LBRACK',
	[']'] = 'RBRACK',
	[':'] = 'COLON',
	[';'] = 'SEMICOLON',
	['#'] = 'HASH',
	['\''] = 'APOSTROPHE',
	['"'] = 'QUOTE',
	['.'] = 'PERIOD',

	['+'] = 'PLUS',
	['-'] = 'MINUS',
}

local INSTR_KEYWORDS = config.INSTR_KEYWORDS
local REG_KEYWORDS = config.REG_KEYWORDS
local SIZE_KEYWORDS = config.SIZE_KEYWORDS
local CJMP_KEYWORDS = config.CONDITIONAL_JMP_KEYWORDS
local FLAG_INSTRUCTS = config.FLAG_SET_INSTRUCTS

local lexer = {}
lexer.__index = lexer

function lexer:peek()
	return string.char(buffer.readu8(self.src, self.idx))
end

function lexer:advance()
	local c = self:peek()
	self.idx += 1
	return c
end

function lexer:emit_token(kind: string, val: string, raw: any)
	return table.insert(self.tokens, {kind = kind, value = val, raw = raw})
end

function lexer:lex()
	while self.idx < self.len do
		local cur = self:peek()

		if cur:match('%s') then
			self:advance()
			continue
		end

		local len = 0
		local start = self.idx

		while true do
			if self.idx >= self.len then
				break
			end

			local new = self:peek()

			if new:match('%s') or (not new:match('%w') and new ~= '_') then
				break
			end

			self:advance()
			len += 1
		end

		if len == 0 then
			if SYNTAX_TOKENS[cur] then
				if cur == '"' then
					self:advance()
					local start = self.idx
					local end_quote_pos

					while self:advance() ~= '"' do
						end_quote_pos = self.idx
					end

					if not end_quote_pos then
						end_quote_pos = start
					end

					local str = buffer.readstring(self.src, start, end_quote_pos - start)

					str = str:gsub('\\n', '\n')
						:gsub('\\t', '\t')
						:gsub('\\r', '\r')


					self:emit_token('TOK_ESCSTR', str)

					continue
				elseif cur == '\'' then
					self:advance()

					local char = self:advance()

					if self:advance() ~= '\'' then
						error(`invalid character at {self.idx} (no escape apostrophe)`)
					end

					self:emit_token('TOK_CHAR', char:byte())

					continue
				elseif cur == ';' then
					self:advance()

					while self.idx < self.len do
						local nxt = self:peek()

						if nxt == '\n' or nxt == ';' then
							self:advance()
							break
						end

						self:advance()
					end

					continue
				end

				self:emit_token(string.format('TOK_%s', SYNTAX_TOKENS[cur]), cur)
			end

			self:advance()

			continue
		end

		local word = buffer.readstring(self.src, start, len)
		
		if table.find(INSTR_KEYWORDS, word:upper()) then
			self:emit_token('TOK_INSTR', word:upper())
		elseif table.find(CJMP_KEYWORDS, word:upper()) then
			self:emit_token('TOK_INSTR', 'JC', word:upper())
		elseif table.find(REG_KEYWORDS, word:upper()) then
			self:emit_token('TOK_REG', word:upper())
		elseif table.find(FLAG_INSTRUCTS, word:upper()) then
			self:emit_token('TOK_INSTR', 'SF', word:upper())
		else
			if tonumber(word) then
				self:emit_token('TOK_NUM', tonumber(word), word:sub(1, 2) == '0x' and word or nil)
			elseif #word > 2 and tonumber(word:sub(3)) then -- this is redundant for hex numbers, but binary numbers prefixed 0b dont work in tonumber
				local prefix = word:sub(1, 2)
				
				if prefix == '0b' then
					local n = tonumber(word:sub(3), 2)

					if not n then
						error(`ASSEMBLER: invalid binary number at {start}`)
					end

					self:emit_token('TOK_NUM', n, word)
				elseif prefix == '0x' then -- redundant
					local n = tonumber(word:sub(3), 16)

					if not n then
						error(`ASSEMBLER: invalid hex number at {start}`)
					end

					self:emit_token('TOK_NUM', n, word)
				end
			elseif #word > 2 and word:sub(1, 2) == '0b' then
				word = word:gsub('_', '')
				
				local n = tonumber(word:sub(3), 2)
				
				if not n then
					error(`ASSEMBLER: invalid binary number at {start}`)
				end
				
				self:emit_token('TOK_NUM', n, word)
			else
				self:emit_token('TOK_STR', word)
			end
		end
	end
	
	table.insert(self.tokens, {kind = 'TOK_EOF', value = nil})
	
	return self.tokens
end

return function(src: buffer)
	local lex = setmetatable({
		src = src,
		idx = 0,
		len = buffer.len(src),
		tokens = {}
	}, lexer)

	return lex:lex()
end
