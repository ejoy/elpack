#include <lua.h>
#include <lauxlib.h>

#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <ctype.h>

#include "siphash.h"

void
siphashsalt(uint8_t key[16], const char * keystr , size_t keysz) {
	if (keysz <= 0) {
		memset(key, 0, 16);
	} else {
		int i;
		for (i=0;i<16;i++) {
			key[i] = (uint8_t)keystr[i%keysz] ^ i;
		}
	}
}

static int
lsiphash(lua_State *L) {
	uint8_t out[8];
	uint8_t key[16];
	size_t sz = 0;
	const char * str = luaL_checklstring(L, 1, &sz);
	uint8_t lower[sz];
	int i;
	for (i=0;i<sz;i++) {
		lower[i] = tolower(str[i]);
	}
	size_t keysz = 0;
	const char * keystr = lua_tolstring(L, 2, &keysz);
	siphashsalt(key, keystr, keysz);
	siphash(out, lower, sz, key);
	lua_pushlstring(L, (const char *)out, 8);
	return 1;
}

void
lua_hash(lua_State *L) {
	luaL_Reg l[] = {
		{ "hash64", lsiphash },
		{ NULL, NULL },
	};
	luaL_setfuncs(L, l, 0);
}
