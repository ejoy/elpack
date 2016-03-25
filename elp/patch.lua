local elpack = require "elpack"
local elp = require "elp.core"

local HEADER_SIZE = 24
local INFO_SIZE = 20	-- see elpreader.c

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
	BYTES[8] NAMEHASH
	DWORD OFFSET	, FFFFFFFF(add SALT)
	DWORD CSIZE		, SALT32 , 0 (patch)
	DWORD ADLER32	, (patch index)
]]

local function mod_path()
	local f = elp.file "name"
	local mod_name = assert(f:read "l", "Invalid .elp/name, Init first")
	f:close()
	return elp.config_path() ..  mod_name
end

mod_path = mod_path()

local function load_pack(p)
	local e, header, v1, v2 = elpack.open(mod_path .. "." .. p .. ".elp")
	e:close()
	assert(v1 == 0, "Don't support patch file now")
	header,v1 = elpack.decompress(header)
	assert(v1 == v2)
	local n = #header // INFO_SIZE
	local ret = { adler32 = v1 }
	for i = 1, n do
		local hash, offset, size, adler32 = string.unpack("c8<I4I4I4", header, (i-1)*INFO_SIZE + 1)
		table.insert(ret, { hash = hash, offset = offset, size = size, adler32 = adler32 })
	end

	return ret
end

local function dump(p)
	for i=1,#p do
		local f = p[i]
		print(i, "hash = ", string.unpack("<I8", f.hash), "offset =", f.offset, "size = ", f.size, "adler32=", f.adler32)
	end
end

local function make_index(t, key)
	for k,v in ipairs(t) do
		v.index = k
		t[v[key]] = v
	end
end

local function find_in_package(from, v)
	local vfrom = from[v.hash]
	if vfrom and vfrom.size == v.size and vfrom.adler32 == v.adler32 then
		return vfrom.index
	end
	for index, vfrom in ipairs(from) do
		if vfrom.adler32 == v.adler32 and vfrom.size == v.size then
			return index
		end
	end
end

local function pack_header(header)
	local tmp = {}
	for _,v in ipairs(header) do
		table.insert(tmp,string.pack(
			"<c8I4I4I4",
			v.hash,
			v.offset,
			v.size,
			v.adler32
		))
	end
	return elpack.compress(table.concat(tmp))
end

local function main(from, to)
	assert(from and to)
	local filename = string.format("%s.%d.%d.elp", mod_path, from, to)
	local to_filename = string.format("%s.%d.elp", mod_path, to)
	from = load_pack(from)
	to = load_pack(to)
	if from.adler32 == to.adler32 then
		print("package may be the same")
		return
	end
	make_index(from, "hash")
	local shift = {}
	local shift_offset = 0
	for _,v in ipairs(to) do
		if v.offset ~= 0xffffffff then
			local index = find_in_package(from, v)	-- todo: compare contant
			if index then
				v.offset = 0xffffffff
				v.size = 0
				v.adler32 = index - 1	-- base 0
			else
				table.insert(shift, { from = v.offset, size = v.size })
				v.offset = shift_offset
				shift_offset = shift_offset + v.size
			end
		end
	end

	local header = pack_header(to)
	local f = assert(io.open(filename, "wb"))
	local tag = string.pack(
		"<c4I4I4I4I4I4",
		"ELP1",	-- tag
		from.adler32,
		to.adler32,
		#header,
		#to,
		shift_offset
	)
	assert(#tag == HEADER_SIZE)
	f:write(tag)
	local to_f = assert(io.open(to_filename,"rb"))
	for _, v in ipairs(shift) do
		to_f:seek("set", HEADER_SIZE + v.from)
		local data = to_f:read(v.size)
		f:write(data)
	end
	to_f:close()
	f:write(header)
	f:close()
	print("Done", filename)
end

return main
