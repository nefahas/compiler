local preprocessor = require('@self/preprocessor')
local lexer = require('@self/lexer')
local parser = require('@self/parser')
local codegen = require('@self/gen')

local assembler = require('@game/ReplicatedStorage/Modules/Assembler')
local linker = require('@game/ReplicatedStorage/Modules/Linker')

local cc = {}

local function parse_flags(flags: string): {[string]: any}
	if type(flags) ~= 'string' then
		return {}
	end

	local split = string.split(flags, ' ')
	local parsed = {}
	
	for i, v in split do
		if v == '-B' then -- pass base address to linker, default 0x400
			local base = split[i+1]
			
			if not tonumber(base) then
				error(`invalid base: {base}`)
			end
			
			parsed.base = tonumber(base)
		elseif v == '-lib' then -- tells codegen to ignore call to main and entry point
			parsed.lib = true
		elseif v == '-obj' then -- ignore linking and generate as an object file, should be used with -lib, as libraries in linking must be object files
			parsed.obj = true
		elseif v == '-nasm' then -- no assemble, just return the string source
			parsed.no_assemble = true
		end
	end
	
	if not parsed.base then
		parsed.base = 0x400
	end
	
	return parsed
end

function cc.cmpl(b: buffer, root_inst: Instance, flags: string, libs: {buffer})
	flags = parse_flags(flags)
	b = preprocessor(b, root_inst)
	
	local tokens = lexer(b)
	local ast = parser(tokens)
	local asm = codegen(ast, flags)
	
	
	if not flags.no_assemble then
		local obj_file = assembler.assemble_buffer(asm)
		local binary
	
		if not flags.obj then
			binary = linker(obj_file, libs or {}, `-B {flags.base}`)
		end
		
		return binary or obj_file
	else
		return asm
	end
end

function cc.compile_str(str: string, flags: string, libs: {})
	if type(str) ~= 'string' then
		error(`invalid type passed to .compile_str: expected string, got {type(str)}`)
	end
	
	libs = libs or {}

	for i, v in libs do
		if typeof(v) == 'Instance' then
			assert(v.ClassName == 'ModuleScript', `invalid instance passed into libs, {v.name}`)

			local obj = require(v)

			assert(type(obj) == 'buffer', `invalid return value from library {v.name}`)

			libs[i] = obj
		elseif type(v) ~= 'buffer' then
			error(`invalid library at index {i}`)
		end
	end
	
	return cc.cmpl(buffer.fromstring(str), nil, flags, libs)
end

function cc.compile(str: buffer, root_inst: Instance, flags: string, libs: {})
	if type(str) ~= 'buffer' then
		error(`invalid type passed to .compile: expected buffer, got {type(str)}`)
	end
	
	libs = libs or {}
	
	for i, v in libs do
		if typeof(v) == 'Instance' then
			assert(v.ClassName == 'ModuleScript', `invalid instance passed into libs, {v.name}`)
			
			local obj = require(v)
			
			assert(type(obj) == 'buffer', `invalid return value from library {v.name}`)
			
			libs[i] = obj
		elseif type(v) ~= 'buffer' then
			error(`invalid library at index {i}`)
		end
	end
	
	local l = buffer.len(str)
	
	return cc.cmpl(str, root_inst, flags, libs)
end

return cc
