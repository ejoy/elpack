#include <lua.h>
#include <lauxlib.h>
#include <stdio.h>
#include <stdlib.h>
#include <stdint.h>
#include <string.h>
#include <assert.h>
#include "siphash.h"

/*
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
*/

#define HEADER_SIZE 24
#define INFO_SIZE 20
#define HASH_SIZE 8

#define SALT_OFFSET 0xffffffff
#define PATCH_OFFSET 0xfffffffe

struct elp_file {
	uint8_t hash[HASH_SIZE];
	uint32_t offset;
	uint32_t csize;
};

struct elp_package {
	FILE *f;
	int n;
	struct elp_file * ef;
};

static uint32_t
read_dword(FILE *f) {
	uint8_t v[4] = { 0,0,0,0 };
	fread(v,1,4,f);
	return v[0] | v[1] << 8 | v[2] << 16 | v[3] << 24;
}

static int
elp_close(lua_State *L) {
	struct elp_package *elp = luaL_checkudata(L, 1, "elpack");
	if (elp->f == NULL)
		return 0;
	fclose(elp->f);
	elp->f = NULL;
	free(elp->ef);
	elp->ef = NULL;
	return 0;
}

static uint32_t
u8tole32(const char *ptr) {
	const uint8_t * p = (const uint8_t *)ptr;
	return p[0] | p[1] << 8 | p[2] << 16 | p[3] << 24;
}

static int
elp_init(lua_State *L) {
	struct elp_package *elp = luaL_checkudata(L, 1, "elpack");
	if (elp->f == NULL || elp->ef != NULL) {
		return luaL_error(L, "Init failed");
	}
	size_t sz = 0;
	const char * header = luaL_checklstring(L, 2, &sz);
	if (sz != elp->n * INFO_SIZE) {
		return luaL_error(L, "Invalid header");
	}
	int i;
	elp->ef = malloc(elp->n * sizeof(struct elp_file));
	for (i=0;i<elp->n;i++) {
		memcpy(elp->ef[i].hash, header, HASH_SIZE);
		if (i>0) {
			if (memcmp(elp->ef[i].hash, elp->ef[i-1].hash, HASH_SIZE) <= 0) {
				free(elp->ef);
				elp->ef = NULL;
				return luaL_error(L, "The hash in header is not ascending");
			}
		}
		elp->ef[i].offset = u8tole32(header + HASH_SIZE);
		elp->ef[i].csize = u8tole32(header + HASH_SIZE + 4);
		if (elp->ef[i].offset == SALT_OFFSET && elp->ef[i].csize == 0) {
			elp->ef[i].offset = PATCH_OFFSET;
			elp->ef[i].csize = u8tole32(header + HASH_SIZE + 8);
		}
		header += INFO_SIZE;
	}
	return 0;
}

static struct elp_file *
lookup_hash(struct elp_package *elp, uint8_t hash[HASH_SIZE]) {
	int begin = 0;
	int end = elp->n;
	while (begin < end) {
		int middle = (end + begin) / 2;
		struct elp_file * ef = &elp->ef[middle];
		int c = memcmp(hash, ef->hash, HASH_SIZE);
		if (c == 0) {
			return ef;
		}
		if (c > 0) {
			begin = middle + 1;
		} else {
			end = middle;
		}
	}
	return NULL;
}

static int
elp_load(lua_State *L) {
	struct elp_package *elp = luaL_checkudata(L, 1, "elpack");
	if (elp->f == NULL || elp->ef == NULL) {
		return luaL_error(L, "Init first");
	}
	size_t sz = 0;
	const char * name = luaL_checklstring(L, 2, &sz);
	struct elp_file *ef = NULL;
	if (lua_type(L, 3) == LUA_TNUMBER) {
		int index = lua_tointeger(L, 3);
		if (index < 0 || index >= elp->n) {
			return luaL_error(L, "Invalid index %d", index);
		}
		ef = &elp->ef[index];
	} else {
		uint8_t hash[HASH_SIZE];
		uint8_t k[16];
		memset(k, 0, 16);
		siphash(hash, (const uint8_t *)name, sz, k);
		struct elp_file * ef = lookup_hash(elp, hash);
		if (ef == NULL)
			return 0;
		if (ef->offset == SALT_OFFSET) {
			// try again, add salt.
			uint8_t salt[4];
			salt[0] = ef->csize & 0xff;
			salt[1] = (ef->csize >> 8) & 0xff;
			salt[2] = (ef->csize >> 16) & 0xff;
			salt[3] = (ef->csize >> 24) & 0xff;
			siphashsalt(k, (const char *)salt, 4);
			siphash(hash, (const uint8_t *)name, sz, k);
			ef = lookup_hash(elp, hash);
			if (ef == NULL) {
				return 0;
			}
			if (ef->offset == SALT_OFFSET) {
				return 0;
			}
		}
	}
	if (ef->offset == PATCH_OFFSET) {
		lua_pushinteger(L, ef->csize);
		return 1;
	}
	if (fseek(elp->f, ef->offset + HEADER_SIZE, SEEK_SET) != 0) {
		return luaL_error(L, "Can't seek %s", name);
	}
	luaL_Buffer buff;
	char * tmp = luaL_buffinitsize(L, &buff, ef->csize);
	int n = fread(tmp, 1, ef->csize, elp->f);
	if (n != ef->csize) {
		return luaL_error(L, "Can't read %s", name);
	}
	luaL_addsize(&buff, ef->csize);
	luaL_pushresult(&buff);
	return 1;
}

static int
elp_open(lua_State *L) {
	const char * filename = luaL_checkstring(L,1);	// filename
	FILE *f = fopen(filename, "rb");
	if (f == NULL)
		return luaL_error(L, "Can't open %s", filename);
	uint8_t tag[4] = { 0,0,0,0 };
	fread(tag, 1, 4, f);
	if (memcmp(tag, "ELP1",4) != 0)
		return luaL_error(L, "Invalid elp file %s", filename);
	uint32_t v1 = read_dword(f);
	uint32_t v2 = read_dword(f);
	uint32_t header_size = read_dword(f);
	uint32_t header_n = read_dword(f);
	uint32_t body_size = read_dword(f);

	if (fseek(f, body_size + HEADER_SIZE, SEEK_SET) != 0) {
		return luaL_error(L, "Damaged file %s", filename);
	}

	luaL_Buffer buff;
	char *tmp = luaL_buffinitsize(L, &buff, header_size);
	int n = fread(tmp, 1, header_size, f);
	if (n != header_size) {
		fclose(f);
		return luaL_error(L, "Damaged file header %s", filename);
	}
	luaL_addsize(&buff, header_size);
	luaL_pushresult(&buff);

	struct elp_package *elp = lua_newuserdata(L, sizeof(*elp));

	elp->f = f;
	elp->n = header_n;
	elp->ef = NULL;
	if (luaL_newmetatable(L, "elpack")) {
		lua_pushcfunction(L, elp_close);
		lua_setfield(L, -2, "__gc");
		luaL_Reg l[] = {
			{ "close", elp_close },
			{ "init", elp_init },
			{ "load", elp_load },
			{ NULL, NULL },
		};
		luaL_newlib(L, l);
		lua_setfield(L, -2, "__index");
	}
	lua_setmetatable(L, -2);

	lua_insert(L, -2);

	lua_pushinteger(L, v1);
	lua_pushinteger(L, v2);
	
	return 4;
}

void
lua_reader(lua_State *L) {
	luaL_Reg l[] = {
		{ "open", elp_open },
		{ NULL, NULL },
	};
	luaL_setfuncs(L, l, 0);
}

