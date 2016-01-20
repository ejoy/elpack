local lfs = require "lfs"

local function last_version(mod)
	mod = mod .. "."
	local len = #mod
	local max = 0
	for name in lfs.dir ".elp" do
		if name:sub(1, len) == mod then
			local ext = name:sub(len+1)
			local v = ext:match("(%d+)%.elp")
			if v then
				v = tonumber(v)
				if v and v >= max then
					max = v + 1
				end
			end
		end
	end
	return max
end

local function main(name)
	lfs.mkdir(".elp")
	assert(io.open(".elp/list","a")):close()
	name = name or lfs.currentdir():lower():match("([^/\\]+)$")
	local f = assert(io.open(".elp/name","wb"))
	f:write(name)
	f:close()

	local version = last_version(name)

	f = assert(io.open(".elp/version", "wb"))
	f:write(version)
	f:close()

	print(string.format("Name = %s , Version = %d", name, version))
end

return main
