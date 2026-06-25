local preprocessor = require('@self/preprocess')
local lexer = require('@self/lexer')
local parser = require('@self/parser')
local builder = require('@self/build')

local assembler = {}
assembler.__index = assembler

-- "files" (modules) must return a buffer.fromstring[[]] of the src
-- outputs a non linked output file

-- assembles a file and all its includes into one object file
function assembler.assemble(file: ModuleScript | buffer)
	local processed = preprocessor(file)
	
	-- [file:GetFullName()]: {parser output}
	local lex_tokens = lexer(processed)
	local instructions, data, globals, imports, symbols, sections = parser(lex_tokens)
	
	local binary, redef_table = builder(instructions, data, typeof(file) == 'Instance' and file:GetFullName() or '=hi', symbols, sections)
	
	-- build obj file with section data, global data, and imports first two bytes of the file would be the total size of binary img in bytes
	-- the first two bytes of each data section in here is the size of the section, to facilitate skipping over it
	-- after that is section data, a table indicating each section's base (if given), a size, then a name null terminated
		-- each entry is:
		-- 2 bytes for the size of the section
		-- 2 bytes for base of section
		-- then a null terminated name of this section
	-- after that size is a table of symbols exposed globally, with first 2 bytes indicating the count of symbols, each entry:
		-- symbol name (null terminated)
		-- null terminated section name
		-- two bytes indicating the offset from that section
	-- then finally a symbol table, indicating which instructions have symbols that must be imported / redefined; ONLY. those.
		-- symbol name, null terminated, 1 byte indicating if this is an imported symbol, then 2 bytes indicating the size of the table of symbols
			-- 3 byte entries:
				-- first 2 bytes indicating the actual binary object offset for the instruction
				-- 1 extra byte indicating which operand needs redefinition:
					-- bit 0 = a
					-- bit 1 = b
					-- both can be set at the same time
	-- the linker will take this entire object file, and resolve each symbols final address, importing the necessary modules as needed, and building a final binary
	
	local binary_size = buffer.len(binary)
	local section_tbl_size = 2
	local global_tbl_size = 2
	local import_tbl_size = 2
	
	-- sizing
	for i, v in sections do
		local name = v.name
		local name_len = #name
		section_tbl_size += 4 + name_len + 1
	end
	
	for i, v in globals do
		local name = v.name
		local name_len = #name
		local section = v.section
		local sec_len = #section
		
		global_tbl_size += 4 + name_len + sec_len
	end
	
	local sym_offsets = {}
	
	for name, data in redef_table do
		local is_import = false
		
		for i, v in imports do
			if v.name == name then
				is_import = true
				break
			end
		end
		
		if not is_import then
			for i, v in symbols do
				if v.name == name then
					sym_offsets[name] = v.offset
					break
				end
			end
		end
		
		local name_len = #name
		local sec_len = 0
		local count = 0
		
		for i, v in symbols do
			if v.name == name then
				sec_len = #v.section
				break
			end
		end
		
		for i, v in data do
			count += 1
		end
		
		import_tbl_size += name_len + 6 + (3 * count) + sec_len + 1
	end
	
	-- now write them out
	local obj = buffer.create(8 + binary_size + section_tbl_size + global_tbl_size + import_tbl_size)
	local tail = 0
	buffer.writeu16(obj, tail, binary_size)
	tail += 2
	buffer.writeu16(obj, tail, section_tbl_size)
	tail += 2
	buffer.writeu16(obj, tail, global_tbl_size)
	tail += 2
	buffer.writeu16(obj, tail, import_tbl_size)
	tail += 2
	
	-- binary
	buffer.copy(obj, tail, binary, 0, binary_size)
	tail += binary_size
	
	-- sec
	buffer.writeu16(obj, tail, #sections)
	tail += 2
	
	for i, v in sections do
		local name = v.name
		local name_len = #name
		
		buffer.writeu16(obj, tail, v.size)
		tail += 2
		buffer.writeu16(obj, tail, v.base)
		tail += 2
		buffer.writestring(obj, tail, name)
		tail += name_len + 1
	end
	
	-- global
	buffer.writeu16(obj, tail, #globals)
	tail += 2
	
	for i, v in globals do
		local name, sec_name = v.name, v.section
		local name_len, sec_len = #name, #sec_name
		
		buffer.writestring(obj, tail, name)
		tail += name_len + 1
		buffer.writestring(obj, tail, sec_name)
		tail += sec_len + 1
		buffer.writeu16(obj, tail, v.offset)
		tail += 2
	end
	
	local count = 0
	for i, v in redef_table do
		count += 1
	end
	
	buffer.writeu16(obj, tail,  count)
	tail += 2
	
	for name, data in redef_table do
		local name_len = #name
		local is_import = false
		local count = 0
		
		local section: string
		
		for i, v in symbols do
			if v.name == name then
				section = v.section
				break
			end
		end
		
		local sec_len = section and #section or 0
		
		for i, v in imports do
			if v.name == name then
				is_import = true
				break
			end
		end
	
		for i, v in data do
			count += 1
		end
		
		buffer.writestring(obj, tail, name)
		tail += name_len + 1
		buffer.writestring(obj, tail, section or '')
		tail += sec_len + 1
		buffer.writeu8(obj, tail, is_import and 1 or 0)
		tail += 1
		buffer.writeu16(obj, tail, count)
		tail += 2
		
		if not is_import then
			buffer.writeu16(obj, tail, sym_offsets[name])
		end
		
		tail += 2
		
		for i, v in data do
			local a, b = v.a, v.b
			
			buffer.writeu16(obj, tail, i)
			tail += 2
			buffer.writeu8(obj, tail, bit32.bor(a and 1 or 0, b and 2 or 0))
			tail += 1
		end
	end
	
	warn(`ASSEMBLER: created object file; {buffer.len(obj)} bytes`)
	return obj
end

function assembler.assemble_folder(folder: Folder)
	local main = folder:FindFirstChild('main')
	
	if not main then
		error(`no main file inside of {folder:GetFullName()}`)
	end
	
	return assembler.assemble(main)
end

function assembler.assemble_buffer(buf: buffer)
	return assembler.assemble(buf)
end

function assembler.export(b: buffer)
	local len = buffer.len(b)
	local str = ''
	
	for i = 0, len - 1 do
		str ..= string.char(buffer.readu8(b, i))
	end
	
	game:GetService('HttpService'):PostAsync('http://127.0.0.1:3000', str, Enum.HttpContentType.TextPlain, false)
end

function assembler.serialize(obj: buffer)
	local len = buffer.len(obj)
	
	local str = 'return (function(t)b=buffer.create(#t)for i,v in t do buffer.writeu8(b,i-1,v)end return b end){'
	--local str = 'function f(t)b=buffer.create(#t)for i,v in t do buffer.writeu8(b,i-1,v)end return b end return f{'
	
	for i = 0, len - 1 do
		local char = buffer.readu8(obj, i)
		
		str ..= tostring(char)
		
		if i ~= len - 1 then
			str ..= ','
		end
	end
	
	str ..= '}'
	
	local new_file = Instance.new('ModuleScript')
	new_file.Source = str
	
	return new_file
end

return assembler
