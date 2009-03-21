BINARIES=mddiff

all: $(BINARIES)

%: %.c
	gcc -Wall -Wextra -g $< -o $@ \
		`pkg-config --cflags --libs glib-2.0 openssl`

clean: 
	rm -rf $(BINARIES) s2c c2s target
