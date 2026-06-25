local ReplicatedStorage = game:GetService('ReplicatedStorage')

local compiler = require('@game/ReplicatedStorage/Modules/Compiler')
local vm = require('@game/ReplicatedStorage/Modules/VM')

local uncompiled_prgms = ReplicatedStorage:WaitForChild('uncompiled_prgms')
local libs_folder = ReplicatedStorage:WaitForChild('programs_folder_asm'):WaitForChild('libs')

local base = 0x400

local compiled = compiler.compile(
	require(uncompiled_prgms.test.main),
	uncompiled_prgms.test, `-B {base}`, {}
)


vm:load_binary(base, compiled)
