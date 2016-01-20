local elp = require "elp.core"
local lfs = require "lfs"

local sep = string.match (package.config, "[^\n]+")

local function remove_dotdot(path, name)
	if name:find("^.[/\\]") then
		return remove_dotdot(path, name:sub(3))
	end
	if name:find("^..[/\\]") then
		local from,to = path:find("[^/]+/$")
		if from == nil then
			error(name .. " is outside")
		end
		return remove_dotdot(path:sub(1, from-1), name:sub(4))
	end
	-- todo: .. may contains in the path like ../foo/../bar
	return path,name
end

local function add_filename(oname, name, files)
	if files[name] then
		print("Exist:", oname, name)
	else
		files[name] = true
		table.insert(files,name)
		print("Add:", oname, name)
	end
end

local function add_file(path, name, files)
	if name:find "^[/\\]" then
		error("Don't support abs path :", name)
	end
	local oname = name
	path, name = remove_dotdot(path, name)
	name = name:lower()
	name = path ..name:gsub("\\","/")
	add_filename(oname, name, files)
end

local function add_dir_files(real_dir, dir, files)
	for name in lfs.dir(real_dir) do
		if name:sub(1,1) ~= '.' then
			--todo: skip other patterns
			local pathname = real_dir .. sep .. name
			local fullname = dir .. "/" .. name:lower()
			if lfs.attributes(pathname, "mode") == "directory" then
				add_dir_files(pathname, fullname, files)
			else
				add_filename(pathname, fullname, files)
			end
		end
	end
end

local function add_dir(path, dir, files)
	if dir:find "^[/\\]" then
		error("Don't support abs path :", name)
	end
	local odir = dir
	path, dir = remove_dotdot(path, dir)
	dir = dir:lower()
	dir = path .. dir:gsub("\\","/")
	add_dir_files(odir, dir, files)
end

local function main(...)
	local f = elp.file "list"
	local files = {}
	for v in f:lines() do
		table.insert(files, v)
		files[v] = true
	end
	local addfiles = { ... }
	local path = elp.current_dir()
	for _, v in ipairs(addfiles) do
		local mode = lfs.attributes(v,"mode")
		if mode == "file" then
			add_file(path, v, files)
		elseif mode == "directory" then
			add_dir(path, v, files)
		else
			error(v .. " is not a file or directory")
		end
	end
	table.sort(files)
	f:close()
	f = elp.file("list","wb")
	for _, v in ipairs(files) do
		f:write(v)
		f:write("\n")
	end
	f:close()
end

return main
