local elp = require "elpack"

local loader = {}

local register_mod = {}

function loader.load(mod,elpfile)
	local e, header, v1, v2 = elp.open(elpfile)
	local header, v = elp.decompress(header)
	e:init(header)
	register_mod[mod] = e
end

local function elp_loader(data)
	return elp.load(data[1], data[2])
end

local function elp_searcher(mod)
	local pack, name = mod:match("^([^.]+)%.(.+)")
	if pack == nil then
		return
	end
	local m = register_mod[pack]
	if not m then
		return "\n\tno elp '" .. pack .. "'"
	end

	name = name.gsub("%.", "/")
	local block = m:load(name .. ".lua")
	if not block then
		return string.format("\n\tno file '%s' in elp '%s'", name, pack)
	end

	return elp_loader, { block, string.format("@[%s]%d.lua", mod, name) }
end

local function main()
	table.insert(package.searchers, elp_searcher)
end

main()

return loader
