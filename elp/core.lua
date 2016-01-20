local lfs = require "lfs"

local sep = string.match (package.config, "[^\n]+")

local elp = {}

local function is_root(path)
	return lfs.attributes(path .. ".elp", "mode") == "directory"
end

function elp.root()
	local level = 0
	local root = ""
	repeat
		level = level + 1
		if is_root(root) then
			return root, level
		end
		root = ".." .. sep .. root
	until lfs.attributes(root:sub(1,-2), "mode") ~= "directory"
	error "init first"
end

function elp.current_dir()
	local path = lfs.currentdir()
	local _, level = elp.root()
	local cpath = ""
	for i = 1 , level-1 do
		local from,to,n = path:find("[/\\]?([^/\\]+)$")
		cpath = n .. "/" .. cpath
		path = path:sub(1,from-1)
	end
	return cpath
end

function elp.file(name, mode)
	return assert(io.open(elp.root() .. ".elp" .. sep .. name,mode or "r"))
end

function elp.remove(name)
	os.remove(elp.root() .. ".elp" .. sep .. name)
end

return elp

