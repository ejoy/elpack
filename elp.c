#include <lua.h>
#include <lauxlib.h>
#include "elp.h"

LUAMOD_API int
luaopen_elpack(lua_State *L) {
	luaL_checkversion(L);
	lua_newtable(L);

	lua_zip(L);
	lua_hash(L);
	lua_reader(L);

	return 1;
}
