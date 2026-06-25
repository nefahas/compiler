-- move to preproc
-- did
function remove_backslash_newlines(src: buffer): nil
	local len = buffer.len(src)

	for i = 0, len - 1 do
		local ch = buffer.readu8(src, i)

		if ch == 92 and i < len - 1 then -- \
			local nxt = buffer.readu8(src, i + 1)

			if nxt == 10 then
				buffer.writeu8(src, i, 32)
				buffer.writeu8(src, i + 1, 32)
			end
		end
	end
end

local function trim(s: string)
	return string.gsub(s, '^%s*(.-)%s*$', '%1')
end

function remove_comments(src: buffer)
	local len = buffer.len(src) - 1
	
	local function find_next_newl(idx: number)
		local i = idx
		
		while i < len do
			local ch = buffer.readu8(src, i)
			
			if ch == 10 then
				return i
			end
			
			i += 1
		end
		
		return len
	end
	
	local function find_ending_block(idx: number)
		local i = idx
		
		while i < len - 1 do
			local ch1, ch2 = buffer.readu8(src, i), buffer.readu8(src, i + 1)
			
			if ch1 == 42 and ch2 == 47 then -- '*/'
				return i + 2
			end
			
			i += 1
		end
		
		error(`no ending for block comment at {idx}`)
	end
	
	for i = 0, len do
		local ch = buffer.readu8(src, i)
		
		if ch == 47 and i < len - 1 then
			local nxt = buffer.readu8(src, i + 1)
			
			if nxt == 47 then -- '//'
				local nl = find_next_newl(i)
				
				-- i dont feel like managing buffer size and reallocating a new one for every single replacement
				-- so we can just trim spaces after this
				for a = i, nl - 1 do
					buffer.writeu8(src, a, 32)
				end
			elseif nxt == 42 then -- '/*'
				local f = find_ending_block(i)
				
				for a = i, f do
					buffer.writeu8(src, a, 32)
				end
			end
		end
	end
end

local function get_lines(src: buffer): nil
	local lines = {}
	local start = 0
	
	for i = 0, buffer.len(src) - 1 do
		local ch = buffer.readu8(src, i)
		
		if ch == 10 then
			table.insert(lines, buffer.readstring(src, start, i - start))
			start = i + 1
		end
	end
	
	if #lines == 0 and buffer.len(src) > 0 then
		table.insert(lines, buffer.tostring(src))
	end
	
	for i, v in lines do
		lines[i] = trim(v)
	end
	
	return lines
end

local function get_defines(lines: {string})
	local defs = {}
	local newl = {}
	
	for i, v in lines do
		if string.match(v, '^#define%s+(%S+)%s+(%S+)') then
			local split = string.split(v, ' ')

			assert(#split >= 3, `invalid #define {v}, line {i}`)
			
			local name, val = split[2], split[3]
			local is_hex, is_bin = string.sub(val, 1, 2) == '0x', string.sub(val, 1, 2) == '0b'
			local is_num = tonumber(val)
			local is_string = string.sub(val, 1, 1) == '"'
			
			if is_hex or is_bin or is_num then
				local v = (is_hex or is_bin and string.sub(val, 2)) or val
				
				if is_bin then
					v = string.gsub(v, '_', '')
				end
				
				local num = (is_hex and tonumber(v, 16)) or (is_bin and tonumber(v, 2)) or tonumber(v, 10)
				
				if defs[name] then
					error(`redefinition of {name}, line {i}, already defined at line {defs[name].line}`)
				end
				
				defs[name] = {kind = 'int', val = num, line = i}
			elseif is_string then
				table.remove(split, 1)
				table.remove(split, 1)
				local str = table.concat(split, ' ')
				
				if string.sub(str, -1) ~= '"' then
					error(`invalid string {str} at line {i}, expected "`)
				end
				
				str = string.sub(str, 2, -2)
				
				defs[name] = {kind = 'str', val = str, line = i}
			else
				error(`invalid #definition of {name} at line {i}, {val} is not a valid value`)
			end
		else
			table.insert(newl, v)
		end
	end
	
	return newl, defs
end

local function remove_empty_lines(lines: {string})
	local nl = {}
	
	for i, v in lines do
		local trimmed = trim(v)
		
		if #trimmed == 0 then
			continue
		else
			table.insert(nl, v)
		end
	end
	
	return nl
end

local function get_includes(lines: {string})
	local includes = {}
	local newl = {}
	
	for i, v in lines do
		if string.match(v, '^#include%s+(%S+)') then
			local split = string.split(v, ' ')
			local path = split[2]
			
			if not path then
				error(`invalid include at line {i}`)
			end
			
			for a, b in includes do
				if b.path == path then
					error(`line {i}: {path} already included at line {b.oline}`)
				end
			end
			
			table.insert(includes, {path = path, line = #newl + 1, oline = i})
		else
			table.insert(newl, v)
		end
	end
	
	return newl, includes
end

local function file_sys_parser(cur: Instance, path: string): Instance | nil
	for part in string.gmatch(path, '[^/]+') do
		if part == '..' then
			cur = cur.Parent
		elseif part ~= '.' then
			cur = cur:FindFirstChild(part)
		end

		if not cur then
			return nil
		end
	end

	return cur
end

local function handle_includes(lines: {string}, includes: {[string]: {line: number, path: string}}, root: Instance)
	for a, b in includes do
		local inst = file_sys_parser(root, b.path)
		
		if not inst then
			error(`invalid include {b.path}, could not find file`)
		end
		
		local src = inst:IsA('ModuleScript') and require(inst)
		
		if type(src) ~= 'buffer' then
			error(`invalid include {b.path}, invalid file`)
		end
		
		remove_backslash_newlines(src)
		remove_comments(src)
		local new_lines = get_lines(src, src)
		local cur_l = b.line
		
		for i, v in new_lines do
			table.insert(lines, cur_l, v)
			cur_l += 1
		end
	end
end

local function handle_defs(lines: {string}, defs: {[string]: {kind: string, val: any, line: number}})
	for i, v in lines do
		for a, b in defs do
			if string.match(v, a) then
				local nv = b.val
				
				if b.kind == 'str' then
					nv = `"{nv}"`
				end
				
				lines[i] = string.gsub(v, a, nv)
			end
		end
	end
end

local function to_new_str(lines: {string})
	local len = 1
	
	for i, v in lines do
		len += #v + 1
	end
	
	local new = buffer.create(len)
	local o = 0
	
	for i, v in lines do
		local l = #v
		buffer.writestring(new, o, v, l)
		buffer.writeu8(new, o + l, 10)
		o += l + 1
	end
	
	buffer.writeu8(new, len - 1, 0xFF)
	return new
end

local function handle_int_constants(lines: {string})
	for i, v in lines do
		v = string.gsub(v, '0[xX]([%da-fA-F]+)', function(h: string)
			return tostring(tonumber(h, 16))
		end)
		
		lines[i] = string.gsub(v, '0[bB]([01]+)', function(b: string)
			return tonumber(tonumber(b, 2))
		end)
	end
end

function preproc(b: buffer, root: Instance)
	remove_backslash_newlines(b)
	remove_comments(b)
	
	local lines = get_lines(b)
	handle_int_constants(lines)
	local includes; lines, includes = get_includes(lines)
	
	if root then
		handle_includes(lines, includes, root)
	else
		local has_includes = false
		
		for i, v in includes do
			has_includes = true
			break
		end
		
		if has_includes then
			error(`cannot include from a compiled string`)
		end
	end
	
	lines = remove_empty_lines(lines)
	
	local defs; lines, defs = get_defines(lines)
	handle_defs(lines, defs)
	
	return to_new_str(lines)
end

return preproc
