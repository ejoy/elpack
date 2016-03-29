local elpack = require "elpack"
local elp = require "elp.core"
local lfs = require "lfs"

--[[
	TAG:
	DWORD ELP1
	DWORD baseversion
	DWORD lastversion / HEADER_ADLER32
	DWORD HEADER_CSIZE
	DWORD HEADER_N
	DWORD BODY_SIZE

	FILE(s):

	FILEINFO(s):
	BYTE[8] NAMEHASH
	DWORD OFFSET	, FFFFFFFF(add SALT)
	DWORD CSIZE		, SALT32 (0 means REMOVE)
	DWORD ADLER32

]]

local sep = string.match (package.config, "[^\n]+")

local function conflict(names, hash_name, salt_id)
	local salt = string.pack("<4I", salt_id)
	local tmp = {}
	for _, v in ipairs(names) do
		local hash = elpack.hash64(v,salt)
		if tmp[hash] or hash_name[hash] then
			return conflict(names, hash_name, salt_id + 1)
		else
			tmp[hash] = v
		end
	end
	for hash, name in pairs(tmp) do
		hash_name[hash] = name
	end
	return string.unpack("<I4",salt)
end

local function namehash(names)
	print("Calculating hashs")
	local hash_name = {}	--> hash(integer) -> name
	local conflict_hash = {}
	for _, v in ipairs(names) do
		local hash = elpack.hash64(v)
		if conflict_hash[hash] then
			table.insert(conflict_hash[hash], v)
		elseif hash_name[hash] then
			conflict_hash[hash] = { hash_name[hash], v }
			hash_name[hash] = true
		else
			hash_name[hash] = v
		end
	end
	local hash_conflict = {}
	if next(conflict_hash) then
		print("Processing conflict")
		for hash, v in pairs(conflict_hash) do
			for i, cf in ipairs(v) do
				print(i,cf)
			end
			hash_conflict[hash] = conflict(v, hash_name, 0x12345678)
		end
	end
	return hash_name, hash_conflict
end

local function find_path(cache, path)
	if lfs.attributes(path, "mode") == "directory" then
		cache[path] = path
		return path
	else
		local upath, name = path:match("(.+)/([^/]+)$")
		if not upath then
			upath = "."
			name = path
		else
			upath = find_path(cache, upath)
			if upath == nil then
				return
			end
		end
		for v in lfs.dir(upath) do
			if v:lower() == name then
				local fullpath = upath .. sep .. v
				if lfs.attributes(fullpath , "mode") == "directory" then
					cache[path] = fullpath
				else
					return
				end
			end
		end
	end
end

local function find_file(cache, fullname)
	local path, name = fullname:match("(.+)/([^/]+)$")
	if path then
		path = find_path(cache, path)
		if path == nil then
			return
		end
	end
	for v in lfs.dir(path) do
		if v:lower() == name then
			local fullpath = path .. sep .. v
			if lfs.attributes(fullpath, "mode") ~= "file" then
				return
			end
			return fullpath
		end
	end
end

local function lookup_files(files)
	local realfiles = {}
	for _, v in ipairs(files) do
		local mode = lfs.attributes(v, "mode")
		if mode == "directory" then
			error(v .. " is directory")
		elseif mode == "file" then
			files[v] = v
		else
			local realname = find_file(realfiles, v)
			if not realname then
				error("Missing " .. v)
			end
			files[v] = realname
		end
	end
end

local function compress_body(hash_name, hash_conflict, realname)
	local header = {}
	for hash in pairs(hash_name) do
		table.insert(header, hash)
	end
	table.sort(header)
	for k,v in ipairs(header) do
		header[k] = { hash = v , filename = hash_name[v], salt = hash_conflict[v] }
		if header[k].filename == true then
			header[k].filename = nil
		end
	end
	local iter = coroutine.wrap(function()
		for _, f in ipairs(header) do
			if f.filename then
				print("Adding", f.filename)
				local fd = assert(io.open(realname[f.filename],"rb"))
				local data, adler32 = elpack.compress(fd:read "a")
				fd:close()
				f.adler32 = adler32
				f.csize = #data
				coroutine.yield(f, data)
			end
		end
	end)

	return header, iter
end

local function pack(output, name, files)
	lookup_files(files)
	local hash_name, hash_conflict = namehash(files)
	output:seek("set",24)	-- skip head tag
	local header, iter = compress_body(hash_name, hash_conflict,files)
	local offset = 0
	for f , data in iter do
		f.offset = offset
		offset = offset + #data
		output:write(data)
	end
	-- output header (at the end of file)
	local header_block = {}
	for _,f in ipairs(header) do
		local info = string.pack(
			"<c8I4I4I4",
			f.hash,
			f.offset or 0xffffffff,
			f.csize or f.salt,
			f.adler32 or 0
		)
		table.insert(header_block, info)
	end
	local header_compressed , adler32 = elpack.compress(table.concat(header_block))
	output:write(header_compressed)
	-- write head tag
	output:seek("set",0)
	local tag = string.pack(
		"<c4I4I4I4I4I4",
		"ELP1",	-- tag
		0,	-- baseversion : 0
		adler32,
		#header_compressed,
		#header,
		offset
	)
	output:write(tag)
end

local function main()
	local f = elp.file "version"
	local version = assert(f:read "n" , "Invalid .elp/version, Init first")
	f:close()
	f = elp.file "name"
	local name = assert(f:read "l", "Invalid .elp/name, Init first")
	f:close()
	local packname = name .. "." .. version .. ".elp"
	print("Packing", packname)
	local files = {}
	f = elp.file "list"
	for name in f:lines() do
		table.insert(files, name)
	end
	f:close()
	f = elp.file(packname,"wb")
	local ok, err = pcall(pack, f, packname, files)
	f:close()
	if not ok then
		print("Remove", packname)
		os.remove(packname)
		error(err)
	end
	print("Done", packname)
	f = elp.file("version", "w")
	f:write(version+1)
	f:close()
end

return main
