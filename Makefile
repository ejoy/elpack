ZLIB_DIR = zlib/

ZLIB_SRC = $(addprefix $(ZLIB_DIR), \
 adler32.c\
 compress.c\
 crc32.c\
 deflate.c\
 gzclose.c\
 gzlib.c\
 gzread.c\
 gzwrite.c\
 infback.c\
 inffast.c\
 inflate.c\
 inftrees.c\
 trees.c\
 uncompr.c\
 zutil.c\
)


CFLAGS = -g -Wall

all : elpack.dll lfs.dll

elpack.dll : elp.c lzip.c siphash24.c lsiphash.c elpreader.c $(ZLIB_SRC)
	gcc $(CFLAGS) --shared -o $@ $^ -I$(ZLIB_DIR) -I/usr/local/include -L/usr/local/bin -llua53

lfs.dll : lfs/lfs.c
	gcc $(CFLAGS) --shared -o $@ $^ -Ilfs -I/usr/local/include -L/usr/local/bin -llua53

foobar.elp :
	cd foobar && lua ../elp.lua init && lua ../elp.lua add hello.lua && lua ../elp.lua pack
	
clean :
	rm elpack.dll lfs.dll
