CC ?= cc
INSTALL ?= install
OPENDKIM ?= opendkim
SEMODULE ?= semodule
SYSTEMCTL ?= systemctl
PREFIX ?= /usr/local
SYSCONFDIR ?= /etc
MANDIR ?= $(PREFIX)/share/man
CADDY_DIR ?= $(SYSCONFDIR)/caddy
MOTDDIR ?= $(SYSCONFDIR)/motd.d
PAM_DIR ?= $(SYSCONFDIR)/pam.d
PAM_MODULE_DIR ?= /usr/lib64/security
SYSTEMD_UNIT_DIR ?= $(SYSCONFDIR)/systemd/system
SYSUSERS_DIR ?= $(SYSCONFDIR)/sysusers.d
SELINUX_DEVEL_MAKEFILE ?= /usr/share/selinux/devel/Makefile
SELINUX_PACKAGE_DIR ?= /usr/share/selinux/packages

SELINUX_MODULE = salyut_services
SELINUX_PACKAGE = selinux/$(SELINUX_MODULE).pp
SERVICES = salyut-site salyut-bbsd salyut-bbs-forward-map

PAM_MODULE = pam_salyut_session_privacy.so
PAM_TARGET = build/$(PAM_MODULE)
CFLAGS ?= -O2
PAM_CFLAGS = -D_GNU_SOURCE -fPIC -fstack-protector-strong \
	-Wall -Wextra -Werror -Wformat -Wformat-security
PAM_LDFLAGS = -shared -Wl,-z,relro,-z,now -Wl,-z,defs

POSTSRSD_VERSION = 2.3.0
POSTSRSD_ARCHIVE = dist/postsrsd-$(POSTSRSD_VERSION).tar.gz
POSTSRSD_URL = https://github.com/roehling/postsrsd/archive/refs/tags/$(POSTSRSD_VERSION).tar.gz
POSTSRSD_SHA256 = f908254a6413112059b4fbf117ca5c65821b121065eff1add3485893bfd09c43
POSTSRSD_SOURCE = build/postsrsd-$(POSTSRSD_VERSION)
POSTSRSD_BUILD = build/postsrsd-cmake

.PHONY: all build build-selinux build-mail build-session-privacy \
	test check install install-config install-manpage install-cockpit \
	install-caddy install-selinux-dropins install-selinux install-mail-config install-mail \
	install-session-privacy clean

all: build

build: build-selinux build-mail build-session-privacy

build-selinux:
	test -f "$(SELINUX_DEVEL_MAKEFILE)"
	$(MAKE) -C selinux -f "$(SELINUX_DEVEL_MAKEFILE)" "$(SELINUX_MODULE).pp"

$(POSTSRSD_ARCHIVE):
	mkdir -p dist
	curl -L --fail --output "$@" "$(POSTSRSD_URL)"

$(POSTSRSD_SOURCE)/CMakeLists.txt: $(POSTSRSD_ARCHIVE)
	printf '%s  %s\n' "$(POSTSRSD_SHA256)" "$(POSTSRSD_ARCHIVE)" | \
		sha256sum -c -
	rm -rf "$(POSTSRSD_SOURCE)"
	mkdir -p "$(POSTSRSD_SOURCE)"
	tar -xzf "$(POSTSRSD_ARCHIVE)" --strip-components=1 \
		-C "$(POSTSRSD_SOURCE)"

build-mail: $(POSTSRSD_SOURCE)/CMakeLists.txt
	cmake -S "$(POSTSRSD_SOURCE)" -B "$(POSTSRSD_BUILD)" \
		-DCMAKE_BUILD_TYPE=Release \
		-DCMAKE_INSTALL_PREFIX="$(PREFIX)" \
		-DBUILD_TESTING=ON \
		-DFETCHCONTENT_FULLY_DISCONNECTED=ON \
		-DFETCHCONTENT_TRY_FIND_PACKAGE_MODE=ALWAYS \
		-DGENERATE_SRS_SECRET=OFF \
		-DINSTALL_SYSTEMD_SERVICE=OFF \
		-DINSTALL_SYSTEMD_SYSUSERS=OFF \
		-DPOSTSRSD_CHROOTDIR=/var/lib/postsrsd \
		-DPOSTSRSD_CONFIGDIR="$(SYSCONFDIR)" \
		-DPOSTSRSD_DATADIR=/var/lib/postsrsd \
		-DPOSTSRSD_USER=postsrsd \
		-DWITH_SECCOMP=ON
	cmake --build "$(POSTSRSD_BUILD)"

$(PAM_TARGET): pam/pam_salyut_session_privacy.c
	mkdir -p build
	$(CC) $(CFLAGS) $(PAM_CFLAGS) $(PAM_LDFLAGS) \
		-o "$@" "$<" -lpam

build-session-privacy: $(PAM_TARGET)

test:
	sh tests/check.sh

check: test
	@if [ -f "$(SELINUX_DEVEL_MAKEFILE)" ]; then \
		$(MAKE) build-selinux; \
	else \
		echo "SELinux development Makefile not found; source checks only"; \
	fi
	@if [ -f "$(POSTSRSD_BUILD)/CTestTestfile.cmake" ]; then \
		ctest --test-dir "$(POSTSRSD_BUILD)" --output-on-failure; \
	else \
		echo "PostSRSd is not built; source checks only"; \
	fi

install-config: install-manpage install-cockpit install-selinux-dropins \
	install-caddy install-mail-config

install-manpage:
	$(INSTALL) -d "$(DESTDIR)$(MANDIR)/man7"
	$(INSTALL) -m 0644 man/man7/salyut.7 \
		"$(DESTDIR)$(MANDIR)/man7/salyut.7"
	$(INSTALL) -d "$(DESTDIR)$(MOTDDIR)"
	$(INSTALL) -m 0644 etc/motd.d/50-salyut \
		"$(DESTDIR)$(MOTDDIR)/50-salyut"
	@if [ -z "$(DESTDIR)" ] && command -v mandb >/dev/null 2>&1; then \
		mandb -q; \
	fi

install-cockpit:
	$(INSTALL) -d "$(DESTDIR)$(PAM_DIR)"
	$(INSTALL) -m 0644 etc/pam.d/cockpit \
		"$(DESTDIR)$(PAM_DIR)/cockpit"

install-caddy:
	$(INSTALL) -d "$(DESTDIR)$(CADDY_DIR)"
	$(INSTALL) -m 0644 etc/caddy/Caddyfile \
		"$(DESTDIR)$(CADDY_DIR)/Caddyfile"

install-selinux-dropins:
	@for service in $(SERVICES); do \
		directory="$(DESTDIR)$(SYSTEMD_UNIT_DIR)/$$service.service.d"; \
		$(INSTALL) -d "$$directory"; \
		$(INSTALL) -m 0644 systemd/30-selinux-domain.conf \
			"$$directory/30-selinux-domain.conf"; \
	done

install-selinux: build-selinux install-selinux-dropins
	$(INSTALL) -d "$(DESTDIR)$(SELINUX_PACKAGE_DIR)"
	$(INSTALL) -m 0644 "$(SELINUX_PACKAGE)" \
		"$(DESTDIR)$(SELINUX_PACKAGE_DIR)/$(SELINUX_MODULE).pp"
	@if [ -z "$(DESTDIR)" ]; then \
		$(SEMODULE) -i "$(SELINUX_PACKAGE_DIR)/$(SELINUX_MODULE).pp"; \
	fi

install-mail-config:
	$(INSTALL) -d "$(DESTDIR)$(SYSCONFDIR)"
	$(INSTALL) -m 0644 etc/postsrsd.conf \
		"$(DESTDIR)$(SYSCONFDIR)/postsrsd.conf"
	$(INSTALL) -m 0644 etc/opendkim.conf \
		"$(DESTDIR)$(SYSCONFDIR)/opendkim.conf"
	$(INSTALL) -d "$(DESTDIR)$(SYSTEMD_UNIT_DIR)"
	$(INSTALL) -m 0644 etc/systemd/system/postsrsd.service \
		"$(DESTDIR)$(SYSTEMD_UNIT_DIR)/postsrsd.service"
	$(INSTALL) -d "$(DESTDIR)$(SYSUSERS_DIR)"
	$(INSTALL) -m 0644 etc/sysusers.d/postsrsd.conf \
		"$(DESTDIR)$(SYSUSERS_DIR)/postsrsd.conf"

install-mail: build-mail install-mail-config
	DESTDIR="$(DESTDIR)" cmake --install "$(POSTSRSD_BUILD)"
	@if [ -z "$(DESTDIR)" ]; then \
		systemd-sysusers "$(SYSUSERS_DIR)/postsrsd.conf"; \
		$(INSTALL) -d -m 0750 -o postsrsd -g postsrsd /var/lib/postsrsd; \
		if [ ! -f "$(SYSCONFDIR)/postsrsd.secret" ]; then \
			umask 077; \
			openssl rand -base64 32 >"$(SYSCONFDIR)/postsrsd.secret"; \
		fi; \
		postconf -e \
			'sender_canonical_maps = socketmap:unix:private/srs:forward'; \
		postconf -e \
			'sender_canonical_classes = envelope_sender'; \
		postconf -e \
			'recipient_canonical_maps = socketmap:unix:private/srs:reverse'; \
		postconf -e \
			'recipient_canonical_classes = envelope_recipient, header_recipient'; \
		$(OPENDKIM) -n -x "$(SYSCONFDIR)/opendkim.conf"; \
		$(SYSTEMCTL) restart opendkim.service; \
		postfix check; \
	fi

install-session-privacy: build-session-privacy
	$(INSTALL) -d "$(DESTDIR)$(PAM_MODULE_DIR)"
	$(INSTALL) -m 0755 "$(PAM_TARGET)" \
		"$(DESTDIR)$(PAM_MODULE_DIR)/$(PAM_MODULE)"

install: install-config install-selinux install-mail install-session-privacy

clean:
	rm -rf build
	rm -f selinux/$(SELINUX_MODULE).cil selinux/$(SELINUX_MODULE).mod \
		selinux/$(SELINUX_MODULE).pp
	rm -rf selinux/tmp
