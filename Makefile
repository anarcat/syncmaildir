# ----------------------------------------------------------------------------
# These variables should not be changed by the regular user, only developers
# should care about them

PROJECTNAME=syncmaildir
VERSION=1.3.0
COPYRIGHT=© 2008-2018 Enrico Tassi <gares@fettunta.org>
BINARIES=mddiff smd-applet
MANPAGES1=mddiff.1 smd-server.1 smd-client.1 \
	 smd-pull.1 smd-push.1 smd-loop.1 smd-applet.1 smd-translate.1 \
	 smd-check-conf.1 smd-restricted-shell.1 smd-uniform-names.1
GSCHEMAS=xdg/glib-2.0/schemas/org.syncmaildir.applet.gschema.xml
GSCHEMAS_COMPILED=xdg/glib-2.0/schemas/gschemas.compiled
MANPAGES5=smd-config.5
HTML=index.html design.html hooks.html
DESTDIR=
TEST_SIZE=100
TEST_MAILBOX=misc/Mail.TEST.tgz
TEST_SUITES=mddiff client-server pull-push migration
BENCH_SIZE=25000
BENCH_MAILBOX=misc/Mail.BENCH.tgz
BENCH_SUITES=benchmarks
PKG_GTK=gtk+-3.0 
SMD_APPLET_C=smd-applet.c 
PKGS_VALA=glib-2.0 $(PKG_GTK) libnotify gee-0.8 gio-2.0
TARGET_GLIB=2.32
PKGCONFIG_CHECK_GLIB_VERSION=--atleast-version=$(TARGET_GLIB) glib-2.0
PKGCONFIG_GLIB_VERSION=--modversion glib-2.0
VALAC=valac-0.30
H=@

# ----------------------------------------------------------------------------
# These variables affect the programs behaviour and their installation;
# they are meant to be overridden if necessary. See the end of this
# file for some templates setting them.

PREFIX=usr/local
SED=sed
XDELTA=xdelta
SSH=ssh
LUAV=5.1
LUA=lua$(LUAV)
CFLAGS=-O2 -Wall -Wextra -Wcast-align -g
PKG_FLAGS=

# ----------------------------------------------------------------------------
# Rules follow...

all: check-build update-smd-config $(BINARIES) $(GSCHEMAS_COMPILED)

update-smd-config:
	$H echo "#define SMD_CONF_PREFIX \"/$(PREFIX)\"" > smd-config.h.new
	$H echo "#define SMD_CONF_VERSION \"$(VERSION)\"" >> smd-config.h.new
	$H echo "#define SMD_CONF_COPYRIGHT \"$(COPYRIGHT)\"" \
		>> smd-config.h.new
	$H if diff -q smd-config.h smd-config.h.new > /dev/null 2>&1; then \
		rm smd-config.h.new; \
	else \
		echo CONFIGURE smd-config.h; \
		mv smd-config.h.new smd-config.h; \
	fi

smd-applet.c: smd-applet.vala smd-config.vapi
	$H if which $(VALAC) >/dev/null; then \
		echo "VALAC $^"; \
		$(VALAC) -C $^ --thread --vapidir=./ \
			--target-glib=$(TARGET_GLIB) \
			--pkg posix $(patsubst %,--pkg %,$(PKGS_VALA)); \
	elif [ -e smd-applet.c ]; then \
		echo "** No $(VALAC), reusing precompiled .c files"; \
		echo "** Changes to the following files will not be"; \
		echo "** taken into account: $^"; \
	else \
		echo "** No $(VALAC) and no precompiled .c files"; \
		echo "** To compile smd-applet you need a vala compiler"; \
		echo "** or the precompiled $@ file"; \
		false; \
	fi
	$H touch $@

mddiff: mddiff.c smd-config.h
	@echo CC $<
	$H $(CC) $(CFLAGS) $< -o $@ \
		`pkg-config $(PKG_FLAGS) --cflags --libs glib-2.0` $(LDFLAGS)

smd-applet: $(SMD_APPLET_C) smd-config.h
	@echo CC $<
	$H $(CC) $(CFLAGS) -w $< -o $@ \
		`pkg-config $(PKG_FLAGS) --cflags --libs $(PKGS_VALA)` \
		$(LDFLAGS)

$(GSCHEMAS_COMPILED): $(GSCHEMAS)
	@echo GLIB-COMPILE-SCHEMAS $(dir $(GSCHEMAS))
	$H glib-compile-schemas $(dir $(GSCHEMAS))
	$H $(foreach p,$(subst :, ,$(XDG_DATA_DIRS)), \
		test -e $(p)/glib-2.0/schemas/$(patsubst xdg/%, \
			%,$(notdir $(GSCHEMAS))) ||) \
		echo WARN: export XDG_DATA_DIRS=\$$XDG_DATA_DIRS:xdg/

check-build: check-w-gcc check-w-$(VALAC) check-w-glib-compile-schemas
	$H pkg-config $(PKGCONFIG_CHECK_GLIB_VERSION) || \
		(echo glib version too old: \
			`pkg-config $(PKGCONFIG_GLIB_VERSION)`; \
		 echo required version: $(TARGET_GLIB); \
		 false)

check-run: check-w-$(LUA) check-w-bash 

check-w-%:
	$H which $* > /dev/null || echo $* not found

test/%: text/all check-run $(TEST_MAILBOX)
	$H tests.d/test.sh $(TEST_MAILBOX) $*

test: text/all check-run $(TEST_MAILBOX)
	$H SUITES="$(TEST_SUITES)" tests.d/test.sh $(TEST_MAILBOX) 

bench: text/all check-run $(BENCH_MAILBOX)
	$H SUITES="$(BENCH_SUITES)" tests.d/test.sh \
		$(BENCH_MAILBOX) $(addprefix $(shell pwd)/,$T)

misc/Mail.%.tgz:
	$(MAKE) check-w-polygen
	rm -rf Mail 
	mkdir -p Mail/cur
	namea=Mail/cur/`date +%s`.$$$$;\
	nameb=`hostname`;\
	date=`date`;\
	for i in `seq $$core $($*_SIZE) $$CORES`; do \
		name=$${namea}_$$i.$$nameb;\
		echo "Subject: foo-subject $$i" >> $$name; \
		echo "Message-Id: $$i" >> $$name; \
		echo "Date: $$date" >> $$name; \
		echo "X-Foo: foo.foo.com" >> $$name; \
		echo >> $$name;\
		polygen -X 10 /usr/share/polygen/eng/manager.grm >> $$name;\
	done
	tar -czf $@ Mail
	rm -rf Mail

%.1:%.1.txt check-w-txt2man
	txt2man -t $* -v "Sync Mail Dir (smd) documentation" -s 1 $< > $@
%.5:%.5.txt check-w-txt2man
	txt2man -t $* -v "Sync Mail Dir (smd) documentation" -s 5 $< > $@

define install-replacing
	cat $(1) |\
		$(SED) 's?@PREFIX@?/$(PREFIX)?' |\
		$(SED) 's?@SED@?$(SED)?'  |\
		$(SED) 's?@XDELTA@?$(XDELTA)?' |\
		$(SED) 's?@SSH@?$(SSH)?' |\
		$(SED) 's?@SMDVERSION@?$(VERSION)?' |\
		$(SED) 's?#! /usr/bin/env lua.*?#! /usr/bin/env $(LUA)?' |\
		cat > $(DESTDIR)/$(PREFIX)/$(2)/$(1)
	if [ $(2) = "bin" ]; then chmod a+rx $(DESTDIR)/$(PREFIX)/$(2)/$(1); fi
endef

define install
	cp $(1) $(DESTDIR)/$(PREFIX)/$(2)/$(notdir $(1))
	if [ $(2) = "bin" ]; then chmod a+rx $(DESTDIR)/$(PREFIX)/$(2)/$(1); fi
endef

define mkdir-p
	mkdir -p $(DESTDIR)/$(PREFIX)/$(1)
endef

install: install-bin install-misc

install-bin: $(BINARIES)
	$(call mkdir-p,bin)
	$(call mkdir-p,share/$(PROJECTNAME))
	$(call mkdir-p,share/$(PROJECTNAME)-applet)
	$(call mkdir-p,share/lua/$(LUAV))
	cp $(BINARIES) $(DESTDIR)/$(PREFIX)/bin
	$(call install-replacing,smd-server,bin)
	$(call install-replacing,smd-client,bin)
	$(call install-replacing,smd-pull,bin)
	$(call install-replacing,smd-push,bin)
	$(call install-replacing,smd-translate,bin)
	$(call install-replacing,smd-check-conf,bin)
	$(call install-replacing,smd-uniform-names,bin)
	$(call install-replacing,smd-restricted-shell,bin)
	$(call install-replacing,smd-loop,bin)
	$(call install-replacing,smd-common,share/$(PROJECTNAME))
	$(call install-replacing,syncmaildir.lua,share/lua/$(LUAV))

install-misc: $(MANPAGES1) $(MANPAGES5)
	$(call mkdir-p,$(DESTDIR)/etc/xdg/autostart)
	$(foreach d,\
	  $(filter-out xdg,$(shell find xdg -type d)),\
	  $(call mkdir-p,share/$(patsubst xdg/%,%,$(d)));)
	$(foreach f,\
	  $(filter-out $(GSCHEMAS_COMPILED),$(shell find xdg -type f)),\
	  $(call install,$(f),share/$(patsubst xdg/%,%,$(dir $(f))));)
	$(call install,smd-applet.ui,share/$(PROJECTNAME)-applet)
	$(call mkdir-p,share/man/man1)
	$(call mkdir-p,share/man/man5)
	cp $(MANPAGES1) $(DESTDIR)/$(PREFIX)/share/man/man1
	cp $(MANPAGES5) $(DESTDIR)/$(PREFIX)/share/man/man5
	$(call mkdir-p,share/doc/syncmaildir)
	cp -r sample-hooks/ $(DESTDIR)/$(PREFIX)/share/doc/syncmaildir
	$(call install,README.md,share/doc/syncmaildir)
	$(call install,misc/strip-header,share/doc/syncmaildir)

clean: 
	$H rm -f $(BINARIES) $(MANPAGES1) $(MANPAGES5)
	$H rm -rf tests.d/run
	$H rm -f $(PROJECTNAME)-$(VERSION).tar.gz
	$H rm -f $(HTML) $(MANPAGES1:=.html) $(MANPAGES5:=.html)
	$H rm -f misc/smd-applet-1.0.0.c

dist $(PROJECTNAME)-$(VERSION).tar.gz: smd-applet.c
	rm -f $(PROJECTNAME)-$(VERSION).tar.gz
	rm -f $(PROJECTNAME)-$(VERSION).tar
	git archive --format=tar \
		--prefix=$(PROJECTNAME)-$(VERSION)/ HEAD \
		> $(PROJECTNAME)-$(VERSION).tar
	tar --transform=s?^?$(PROJECTNAME)-$(VERSION)/? \
		-r smd-applet.c \
		--owner root --group root \
		-f $(PROJECTNAME)-$(VERSION).tar
	gzip -9 -n -f $(PROJECTNAME)-$(VERSION).tar

stats:
	T=`git tag | sort -V | head -n 1`; \
	for V in `git tag | sort -V | tail -n +2`; do \
		echo $$V; \
		git diff $$T $$V | diffstat -s; T=$$V; \
	done;\
	git diff --no-prefix $$V HEAD | diffstat -C

# ----------------------------------------------------------------------------
# These templates collect standard values for known platforms, like osx.
# To use a template run make TEMPLATE/TARGET, for example:
#   make osx/all && make osx/install
# You may also combine templates. For example, to build only text mode
# utilities on osx type:
#   make osx/text/all && make osx/text/install

text/%:
	$H $(MAKE) $* \
		BINARIES="$(subst smd-applet,,$(BINARIES))" \
		MANPAGES1="$(subst smd-applet.1,,$(MANPAGES1))" \
		PREFIX="$(PREFIX)" VALAC=ls H=$H \
		CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)"

static/%:
	$H $(MAKE) $* \
		CFLAGS="$(CFLAGS) -static " \
		PKG_FLAGS="$(PKG_FLAGS) --static " \
		PREFIX="$(PREFIX)" H=$H LDFLAGS="$(LDFLAGS)"

gnome2/%:
	$H gunzip -c misc/smd-applet-1.0.0.c.gz > misc/smd-applet-1.0.0.c
	$H $(MAKE) $* \
		SMD_APPLET_C=misc/smd-applet-1.0.0.c PKG_GTK=gtk+-2.0 \
		CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)" TARGET_GLIB="2.19.1"


osx/%:
	$H $(MAKE) $* SED=sed PREFIX="$(PREFIX)" H=$H \
		CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)"

abspath/%:
	$H $(MAKE) $* SED=/bin/sed \
		XDELTA=/usr/bin/xdelta SSH=/usr/bin/ssh \
		PREFIX="$(PREFIX)" H=$H \
		CFLAGS="$(CFLAGS)" LDFLAGS="$(LDFLAGS)"

.PHONY : update-smd-config
# eof
