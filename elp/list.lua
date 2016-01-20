local lfs = require "lfs"
local elp  = require "elp.core"

local sep = string.match (package.config, "[^\n]+")

local function lookup_dir(dir, realname, files)
	local len = #dir
	for k,v in pairs(files) do
		if v == true and #k > len then
			local path = k:sub(1, len)
			if path == dir then
				return true
			end
		end
	end
	print(realname .. "\\")
end

local function untracked(path,cpath,files)
	for name in lfs.dir(cpath) do
		if name:sub(1,1) ~= '.' then
			local fullname = path .. name:lower()
			local realname = cpath .. sep .. name
			local mode = lfs.attributes(realname, "mode")
			if mode == "file" then
				if files[fullname] == nil then
					print(realname)
				end
			elseif mode == "directory" then
				if lookup_dir(fullname .. "/", realname, files) then
					untracked(fullname .. "/", realname, files)
				end
			end
		end
	end
end

local function main()
	local path = elp.current_dir()
	local f = elp.file "list"
	local files = {}
	local pattern = "^" .. path
	local missing = {}
	print(" [INCLUDE]")
	for v in f:lines() do
		local from, to = v:find(pattern)
		if to then
			v = v:sub(to+1)
			table.insert(files, v)
			files[v] = true
			if lfs.attributes(v, "mode") ~= "file" then
				table.insert(missing, v)
			else
				print(v)
			end
		end
	end
	f:close()
	print(" [MISSING]")
	for _,v in ipairs(missing) do
		print(v)
	end
	print(" [UNTRACKED]")
	untracked("",".",files)
end

return main