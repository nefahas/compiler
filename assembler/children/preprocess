--!native
--!optimize 2

local config = require('../Config')

local function get_lines(src: buffer, len: number)
	local lines = {}
	local idx = 0
	local last = 0
	
	while idx < len do
		local ch = buffer.readu8(src, idx)
		
		if ch == 10 then --newl
			table.insert(lines, buffer.readstring(src, last, idx - last))
			last = idx + 1
		end
		
		idx += 1
	end
	
	if #lines == 0 then
		table.insert(lines, buffer.readstring(src, 0, len))
	end
	
	return lines
end

local function remove_whitespace(str: string)
	return str:gsub('%s+', '')
end

local function to_new_str(lines: {{string}})
	local len = 0
	
	for i, v in lines do
		if v == nil or #v == 0 then
			continue
		end
		
		lines[i] = v .. '\n'
		len += #v + 1 -- newline
	end
	
	local new = buffer.create(len + 1)
	
	local offs = 0
	
	for i, v in lines do
		if v == nil or #v == 0 then
			continue
		end
		
		buffer.writestring(new, offs, v)
		offs += #v
	end
	
	buffer.writeu8(new, len, 255)
	
	return new
end

local function trim(str: string)
	return str:match('^%s*(.-)%s*$')
end

local function remove_all_comments(lines: {{string}})
	for i, v in lines do
		if remove_whitespace(v):sub(1, 1) == ';' then
			table.remove(lines, i)
			return remove_all_comments(lines)
		else
			local idx = v:find(';')
			
			if idx then
				lines[i] = v:sub(1, idx - 1)
			end
		end
	end
end

local function file_sys_parser(cur: Instance, path: string)
	for part in string.gmatch(path, '[^/]+') do
		if part == ".." then
			cur = cur.Parent
		elseif part ~= "." then
			cur = cur:FindFirstChild(part)
		end

		if not cur then
			return nil
		end
	end

	return cur
end

local function prehandle_includes(inst: ModuleScript, included: {Instance})
	local src
	
	if typeof(inst) == 'Instance' then
		if included[inst] then
			return {}
		end
		
		if not inst:IsA('ModuleScript') then
			error(`invalid file {inst:GetFullName()}`)
		end
		
		src = require(inst)
		
		if type(src) ~= 'buffer' then
			error(`invalid file {inst:GetFullName()} (did not return a buffer for src)`)
		end
	else
		src = inst
	end
	
	table.insert(included, inst)
	
	local lines = get_lines(src, buffer.len(src))
	local output = {}
	
	remove_all_comments(lines)
	
	for i, v in lines do
		v = trim(v)
		
		local include = v:match('^#include%s+(%S+)$')
		
		if include then
			local file = file_sys_parser(inst, include)
			
			if not file then
				error(`unable to resolve include {include}`)
			end
			
			local ret = prehandle_includes(file, included)
			
			for _, l in ret do
				table.insert(output, l)
			end

			ret[file] = true
		else
			table.insert(output, v)
		end
	end
	
	return output
end

local function handle_defs_and_macros(lines: {string}, defs: {[string]: number}, macros: {})
	local output = {}
	
	for i, v in lines do
		if v == nil then
			continue
		end
		
		v = trim(v)

		if v:match('^#def%s+(%S+)%s+(%w+)$') then
			local split = string.split(v, ' ')
			lines[i] = nil
			
			if split[3]:sub(1, 2) == '0x' then
				local num = split[3]:sub(3)
				defs[split[2]] = tonumber(num, 16)
			elseif split[3]:sub(1, 2) == '0b' then
				local num = split[3]:sub(3)
				defs[split[2]] = tonumber(num, 2)
			elseif tonumber(split[3]) then
				defs[split[2]] = tonumber(split[3])
			elseif config.REG_INDICES[string.upper(split[3])] then
				defs[split[2]] = string.upper(split[3])
			else
				error(`invalid definition (not a number or register) {split[3]} at line {i}`)
			end
		elseif v:match('^#macro%s+(%S+)') then
			local split = string.split(v, ' ')
			local name = split[2]

			if macros[name] then
				error(`redefinition of macro {name} at line {i}`)
			end
			
			lines[i] = nil
			macros[name] = {}

			local start = i + 1

			for a = start, #lines do
				local nl = lines[a]
				lines[a] = nil
				
				if nl == '#endmacro' then
					break
				else
					table.insert(macros[name], nl)
				end
			end
		else
			table.insert(output, v)
		end
	end
	
	return output
end

local function finish_preprocess(lines: {string}, defs, macros)
	local output = {}
	
	for i, v in lines do
		if not v then
			continue
		end
		
		if macros[v] then
			for _, l in macros[v] do
				table.insert(output, l)
			end
			
			continue
		end
		
		for k, b in defs do
			v = string.gsub(v, k, b)
		end
		
		table.insert(output, v)
	end
	
	-- macro defs dont get resolved until this point
	for i, v in output do
		for k, b in defs do
			output[i] = string.gsub(v, k, b)
		end
	end
	
	return output
end

return function(file: ModuleScript | buffer)
	local defs, macros = {}, {}
	
	local lines = prehandle_includes(file, {})
	local done_defs = handle_defs_and_macros(lines, defs, macros)
	local finished = finish_preprocess(lines, defs, macros)
	
	return to_new_str(finished)
end
