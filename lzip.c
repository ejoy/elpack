#include "zlib.h"

#include <lua.h>
#include <lauxlib.h>
#include <stdint.h>
#include <string.h>

#define CRYPT_NONE 0
#define CRYPT_IN 1
#define CRYPT_OUT 2

struct filter {
	z_stream *stream;
	int (*end)(z_streamp strm);
	int (*execute)(z_streamp strm, int flags);
	int crypt_type;
	void *crypt_sbox;
};

struct rc4_sbox {
	int i;
	int j;
	uint8_t s[256];
};

static void
rc4_init(struct rc4_sbox *box, const uint8_t key[8]) {
	int i,j;
	for (i=0;i<256;i++) {
		box->s[i] = i;
	}
	j = 0;
	for (i=0;i<256;i++) {
		j = (j + box->s[i] + key[i%8]) & 0xff;
		uint8_t temp = box->s[i];
		box->s[i] = box->s[j];
		box->s[j] = temp;
	}
	box->i = 0;
	box->j = 0;
}

static void
rc4_crypt(struct rc4_sbox *box, const uint8_t *stream_in, uint8_t *stream_out, int sz) {
	int index;
	for (index=0;index<sz;index++) {
		int i = (box->i + 1) & 0xff;
		int j = (box->j + box->s[i]) & 0xff;
		box->i = i;
		box->j = j;
		uint8_t si = box->s[i];
		uint8_t sj = box->s[j];
		box->s[i] = sj;
		box->s[j] = si;
		uint8_t k = box->s[(si + sj) & 0xff];
		*stream_out = *stream_in ^ k;
		++stream_in;
		++stream_out;
	}
}

static void
lz_assert(lua_State *L, int result, struct filter *flt) {
	if ( result == Z_OK || result == Z_STREAM_END || result == Z_BUF_ERROR )
		return;
	z_stream* stream = flt->stream;
	switch ( result ) {
	case Z_NEED_DICT:
		lua_pushfstring(L, "RequiresDictionary: input stream requires a dictionary to be deflated (%s)", stream->msg);
		break;
	case Z_STREAM_ERROR:
		lua_pushfstring(L, "InternalError: inconsistent internal zlib stream (%s)", stream->msg);
		break;
	case Z_DATA_ERROR:
		lua_pushfstring(L, "InvalidInput: input string does not conform to zlib format or checksum failed");
		break;
	case Z_MEM_ERROR:
		lua_pushfstring(L, "OutOfMemory: not enough memory (%s)", stream->msg);
		break;
	case Z_VERSION_ERROR:
		lua_pushfstring(L, "IncompatibleLibrary: built with version %s, but dynamically linked with version %s (%s)",
			ZLIB_VERSION,  zlibVersion(), stream->msg);
		break;
	default:
		lua_pushfstring(L, "ZLibError: unknown code %d (%s)", result, stream->msg);
		break;
	}
	flt->end(stream);
	lua_error(L);
}

#define CHUNK_IN 4096

static int
execute(lua_State *L, struct filter *flt) {
	z_stream *stream = flt->stream;
	size_t avail_in;
	const char * source = lua_tolstring(L, 1, &avail_in);
	uint8_t chunk[CHUNK_IN];
	int flags = Z_NO_FLUSH;
	stream->avail_in = 0;
	stream->avail_out = 0;
	luaL_Buffer buff;
	luaL_buffinit(L, &buff);
	int result;
	do {
		if (stream->avail_in == 0 && flags != Z_FINISH) {
			stream->next_in = (z_const Bytef *)chunk;
			if (avail_in <= CHUNK_IN) {
				flags = Z_FINISH;
				stream->avail_in = avail_in;
			} else {
				stream->avail_in = CHUNK_IN;
			}
			if (flt->crypt_type == CRYPT_IN) {
				rc4_crypt(flt->crypt_sbox, (const uint8_t *)source, chunk, stream->avail_in);
				stream->next_in = (z_const Bytef *)chunk;
			} else {
				stream->next_in = (z_const Bytef *)source;
			}
			source += stream->avail_in;
			avail_in -= stream->avail_in;
		}
		void *buffer = luaL_prepbuffer(&buff);
		stream->next_out  = buffer;
		stream->avail_out = LUAL_BUFFERSIZE;
		result = flt->execute(stream, flags);
		lz_assert(L, result, flt);
		if (flt->crypt_type == CRYPT_OUT) {
			rc4_crypt(flt->crypt_sbox, buffer, buffer, LUAL_BUFFERSIZE - stream->avail_out);
		}
		luaL_addsize(&buff, LUAL_BUFFERSIZE - stream->avail_out);
	} while ( result != Z_STREAM_END );
	luaL_pushresult(&buff);
	lua_pushinteger(L, stream->adler);
	flt->end(stream);
	return 2;
}

static int
lcompress(lua_State *L) {
	z_stream stream;
	stream.zalloc = Z_NULL;
	stream.zfree = Z_NULL;
	stream.opaque = Z_NULL;
	struct filter flt = {
		&stream,
		deflateEnd,
		deflate,
		CRYPT_NONE,
		NULL,
	};
	struct rc4_sbox sbox;
	if (lua_isstring(L, 2)) {
		size_t keysz;
		const char * key = lua_tolstring(L, 2, &keysz);
		if (keysz != 8) {
			return luaL_error(L, "Only support 8 bytes key");
		}
		rc4_init(&sbox, (const uint8_t *)key);
		flt.crypt_type = CRYPT_OUT;
		flt.crypt_sbox = &sbox;
	}
	int result = deflateInit(&stream,Z_DEFAULT_COMPRESSION);
	lz_assert(L, result, &flt);
	return execute(L, &flt);
}

static int
ldecompress(lua_State *L) {
	z_stream stream;
	stream.zalloc = Z_NULL;
	stream.zfree = Z_NULL;
	stream.opaque = Z_NULL;
	struct filter flt = {
		&stream,
		inflateEnd,
		inflate,
		CRYPT_NONE,
		NULL,
	};
	struct rc4_sbox sbox;
	if (lua_isstring(L, 2)) {
		size_t keysz;
		const char * key = lua_tolstring(L, 2, &keysz);
		if (keysz != 8) {
			return luaL_error(L, "Only support 8 bytes key");
		}
		rc4_init(&sbox, (const uint8_t *)key);
		flt.crypt_type = CRYPT_IN;
		flt.crypt_sbox = &sbox;
	}
	int result = inflateInit(&stream);
	lz_assert(L, result, &flt);
	return execute(L, &flt);
}

struct reader {
	z_stream stream;
	const char * source;
	size_t source_sz;
	uint8_t inbuffer[CHUNK_IN];
	uint8_t outbuffer[CHUNK_IN];
	struct rc4_sbox *crypt_sbox;
	int flags;
};

static const char *
zip_reader(lua_State *L, void *data, size_t *size) {
	struct reader *rd = data;
	if (rd->source == NULL)
		return NULL;
	z_stream *stream = &rd->stream;
	if (stream->avail_in == 0 && rd->flags != Z_FINISH) {
		if (rd->source_sz <= CHUNK_IN) {
			rd->flags = Z_FINISH;
			stream->avail_in = rd->source_sz;
		} else {
			stream->avail_in = CHUNK_IN;
		}
		if (rd->crypt_sbox) {
			rc4_crypt(rd->crypt_sbox, (const uint8_t *)rd->source, rd->inbuffer, stream->avail_in);
			stream->next_in = (z_const Bytef *)rd->inbuffer;
		} else {
			stream->next_in = (z_const Bytef *)rd->source;
		}
		rd->source += stream->avail_in;
		rd->source_sz -= stream->avail_in;
	}
	stream->next_out = rd->outbuffer;
	stream->avail_out = CHUNK_IN;
	int result = inflate(stream, rd->flags);
	struct filter flt = { &rd->stream, inflateEnd, NULL, 0, 0 };
	lz_assert(L, result, &flt);
	if (rd->flags == Z_FINISH && stream->avail_out != 0) {
		rd->source = NULL;
	}
	*size = CHUNK_IN - stream->avail_out;
	return (const char *)rd->outbuffer;
}

static int
lload(lua_State *L) {
	struct reader rd;
	rd.source = luaL_checklstring(L,1,&rd.source_sz);
	const char * filename = luaL_checkstring(L, 2);
	struct filter flt = { &rd.stream, inflateEnd, NULL, 0, 0 };
	struct rc4_sbox sbox;
	if (lua_isstring(L, 3)) {
		size_t keysz;
		const char * key = lua_tolstring(L, 3, &keysz);
		if (keysz != 8) {
			return luaL_error(L, "Only support 8 bytes key");
		}
		rc4_init(&sbox, (const uint8_t *)key);
		rd.crypt_sbox = &sbox;
	} else {
		rd.crypt_sbox = NULL;
	}
	rd.flags = Z_NO_FLUSH;
	z_stream *stream = &rd.stream;
	stream->zalloc = Z_NULL;
	stream->zfree = Z_NULL;
	stream->opaque = Z_NULL;
	stream->avail_in = 0;
	stream->avail_out = 0;
	int result = inflateInit(stream);
	lz_assert(L, result, &flt);
	result = lua_load (L, zip_reader, &rd, filename, "bt");
	inflateEnd(stream);
	if (result != LUA_OK) {
		return lua_error(L);
	}
	return 1;
}

void
lua_zip(lua_State *L) {
	luaL_Reg l[] = {
		{ "compress", lcompress },
		{ "decompress", ldecompress },
		{ "load", lload },
		{ NULL, NULL },
	};
	luaL_setfuncs(L, l, 0);
}
