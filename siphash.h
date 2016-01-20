#ifndef sip_hash_h
#define sip_hash_h

#include <stdint.h>

int siphash(uint8_t *out, const uint8_t *in, uint64_t inlen, const uint8_t *k);
void siphashsalt(uint8_t salt[16], const char * keystr , size_t keysz);

#endif
