local EOF = string.char(255)

local compiler_config = require('./config')

local lexer = {}
lexer.__index = lexer

function lexer:peek(): string
	return string.char(buffer.readu8(self.src, self.idx))
end

function lexer:lookahead(n: number)
	return string.char(buffer.readu8(self.src, self.idx + n))
end

function lexer:peek_amt(n: number): string
	if type(n) ~= 'number' or n <= 1 then
		return self:peek()
	end
	
	local rebuilt = ''
	
	for i = 0, n - 1 do
		rebuilt ..= string.char(buffer.readu8(self.src, self.idx + i))
	end
	
	return rebuilt
end

function lexer:advance(): string
	local c = self:peek()
	self.idx += 1
	return c
end

function lexer:advance_amt(n: number): string
	local c = self:peek_amt(n)
	self.idx += n
	return c
end

function lexer:adv_until(str: string): string | boolean
	local len = string.len(str)
	local rebuilt = ''
	
	rebuilt ..= self:peek(len)
	
	if rebuilt == str then
		return self:advance_amt(len), len
	end
	
	local start = self.idx
	while self.idx < self.len do
		if self.idx + len >= self.len then
			break
		end
		
		rebuilt = self:advance_amt(len)
		
		if rebuilt == str then
			return rebuilt, self.idx - start
		end
	end
	
	return false
end

function lexer:read_str(o: number, l: number)
	return buffer.readstring(self.src, o, l)
end

function lexer:emit(kind: string, val: any)
	return table.insert(self.tokens, {kind = 'TOK_' .. kind, val = val})
end

function lexer:lex()
	while self.idx < self.len do
		local c = self:peek()
		
		if c == EOF then
			break
		end
		
		if string.match(c, '%s') then
			self:advance()
			continue
		end
		
		local dbl = self:peek_amt(2)
		
		if dbl == '0x' or dbl == '0b' then
			self:advance_amt(2)
			
			if dbl == '0x' then
				local str = ''
				
				while tonumber(self:peek(), 16) do
					str ..= self:advance()
				end
				
				self:emit('NUM', tonumber(str, 16))
			elseif dbl == '0b' then
				local str = ''
				
				while tonumber(self:peek(), 2) do
					str ..= self:advance()
				end
				
				self:emit('NUM', tonumber(str, 2))
			end
		end
		
		if compiler_config.syntax_tokens[dbl] then
			self:advance_amt(2)
			self:emit(compiler_config.syntax_tokens[dbl], dbl)
			continue
		elseif compiler_config.syntax_tokens[c] then
			if c == '"' then
				self:advance()
				local start = self.idx
				local _, len = self:adv_until('"')
				
				local str = self:read_str(start, len - 1)
				
				self:emit('STRLIT', str)
			else
				self:advance()
				self:emit(compiler_config.syntax_tokens[c], c)
			end
			
			continue
		end
		
		local start = self.idx
		local fin
		self:advance()
		
		while self.idx < self.len do
			local c = self:peek()
			
			if not string.match(c, '%w') and c ~= '_' then
				fin = self.idx
				break
			end
			
			self:advance()
		end
		
		if fin then
			local str = self:read_str(start, fin - start)
			
			if compiler_config.keywords[str] then
				self:emit(compiler_config.keywords[str], str)
			else
				local is_num = tonumber(str)
				
				if is_num then
					self:emit('NUM', is_num)
				else
					self:emit('IDENT', str)
				end
			end
		end
	end
	
	return self.tokens
end

return function(src: buffer)
	local self = setmetatable({
		src = src,
		idx = 0,
		len = buffer.len(src),
		tokens = {},
	}, lexer)
	
	return self:lex()
end
