local elp = require "elpack"

local loader = {}

local register_mod = {}

function loader.load(mod,elpfile)
	if type(elpfile) == "table" then
		local last = 0
		local tmp = {}
		local n = #elpfile
		for _, filename in ipairs(elpfile) do
			local e, header, v1, v2 = elp.open(filename)
			if v1 ~= last then
				error("Invalid patch file version ".. filename)
			end
			last = v2
			local header, v = elp.decompress(header)
			e:init(header)
			tmp[n] = e
			n = n - 1
		end
		register_mod[mod] = tmp
	else
		local e, header, v1, v2 = elp.open(elpfile)
		if v1 ~= 0 then
			error(elpfile .. " is a patch file")
		end
		local header, v = elp.decompress(header)
		e:init(header)
		register_mod[mod] = e
	end
end

local function elp_loader(data)
	return elp.load(data[1], data[2])
end

local function load_file(m, name)
	if type(m) == "table" then
		local index = nil
		for i = 1, #m do
			index = m[i]:load(name, index)
			if index == nil then
				return
			end
			if type(index) == "string" then
				return index
			end
		end
	else
		return m:load(name)
	end
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
	local block = load_file(m, name .. ".lua")
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
