#!/bin/sh
set -eu

repo=$(CDPATH= cd -- "$(dirname -- "$0")/.." && pwd)
tmp=${TMPDIR:-/tmp}/salyut-config-check.$$

cleanup()
{
	rm -rf "$tmp"
}

trap cleanup EXIT HUP INT TERM
mkdir -p "$tmp"

make -C "$repo" install-config DESTDIR="$tmp"

manual="$tmp/usr/local/share/man/man7/salyut.7"
motd="$tmp/etc/motd.d/50-salyut"
test -f "$manual"
test -f "$motd"
grep -F 'Run man salyut.' "$motd" >/dev/null
grep -F '.TH SALYUT 7' "$manual" >/dev/null
grep -F 'pinky -lb username' "$manual" >/dev/null
grep -F 'https://salyut.one/bbs' "$manual" >/dev/null
grep -F '.I ~/.forward' "$manual" >/dev/null
grep -F '\\username, you@example.net' "$manual" >/dev/null

if command -v mandoc >/dev/null 2>&1; then
	mandoc -T lint "$repo/man/man7/salyut.7"
	mandoc "$repo/man/man7/salyut.7" >/dev/null
elif command -v groff >/dev/null 2>&1; then
	groff -T utf8 -man "$repo/man/man7/salyut.7" >/dev/null
fi

caddyfile="$tmp/etc/caddy/Caddyfile"
test -f "$caddyfile"
grep -F 'reverse_proxy 127.0.0.1:8082' "$caddyfile" >/dev/null
grep -F 'redir https://salyut.one/bbs{uri} permanent' "$caddyfile" >/dev/null
grep -F 'redir https://salyut.one/now{uri} permanent' "$caddyfile" >/dev/null
if command -v caddy >/dev/null 2>&1; then
	caddy validate --config "$caddyfile" --adapter caddyfile
fi

pam_file="$tmp/etc/pam.d/cockpit"
test -f "$pam_file"
test "$(stat -c '%a' "$pam_file" 2>/dev/null || stat -f '%Lp' "$pam_file")" = 644
deny_line=$(grep -nF \
	'pam_listfile.so item=user sense=deny file=/etc/cockpit/disallowed-users' \
	"$pam_file" | cut -d: -f1)
wheel_line=$(grep -nF \
	'pam_succeed_if.so quiet user ingroup wheel' \
	"$pam_file" | cut -d: -f1)
test "$deny_line" -lt "$wheel_line"
test "$(grep -Fc 'pam_succeed_if.so quiet user ingroup wheel' "$pam_file")" -eq 1
if grep -F 'file=/etc/cockpit/allowed-users' "$pam_file" >/dev/null; then
	echo "the obsolete per-user Cockpit allowlist is still referenced" >&2
	exit 1
fi

config="$tmp/etc/postsrsd.conf"
unit="$tmp/etc/systemd/system/postsrsd.service"
sysusers="$tmp/etc/sysusers.d/postsrsd.conf"
test -f "$config"
test -f "$unit"
test -f "$sysusers"
grep -F 'domains = { "salyut.one", "mail.salyut.one" }' "$config" >/dev/null
grep -F 'srs-domain = "salyut.one"' "$config" >/dev/null
grep -F 'socketmap = unix:/var/spool/postfix/private/srs' "$config" >/dev/null
grep -F 'secrets-file = "/etc/postsrsd.secret"' "$config" >/dev/null
grep -F 'ExecStart=/usr/local/sbin/postsrsd -C /etc/postsrsd.conf' "$unit" >/dev/null
grep -F 'NoNewPrivileges=yes' "$unit" >/dev/null
grep -F \
	'ReadWritePaths=/var/spool/postfix/private /var/lib/postsrsd' \
	"$unit" >/dev/null
grep -F 'u postsrsd ' "$sysusers" >/dev/null
if find "$repo" -type f -name '*.secret' | grep . >/dev/null; then
	echo "PostSRSd secret committed to the repository" >&2
	exit 1
fi

policy="$repo/selinux/salyut_services.te"
contexts="$repo/selinux/salyut_services.fc"
grep -F 'policy_module(salyut_services,' "$policy" >/dev/null
for domain in salyut_site salyut_bbsd
do
	grep -F "init_daemon_domain(${domain}_t, ${domain}_exec_t)" \
		"$policy" >/dev/null
done
for executable in salyut-site salyut-bbsd
do
	grep -F "/usr/local/bin/$executable" "$contexts" >/dev/null
done
grep -F '/srv/user_profiles(/.*)?' "$contexts" >/dev/null
grep -F 'userdom_search_user_home_dirs(salyut_site_t)' "$policy" >/dev/null
grep -F 'userdom_read_user_home_content_symlinks(salyut_site_t)' "$policy" >/dev/null
grep -F \
	'read_files_pattern(salyut_site_t, salyut_now_profile_t, salyut_now_profile_t)' "$policy" >/dev/null
grep -F \
	'allow postfix_cleanup_t unconfined_service_t:unix_stream_socket connectto;' "$policy" >/dev/null
if grep -Eiq '(^|[[:space:]])permissive([[:space:]]|$)' "$policy"; then
	echo "policy must not contain a permissive declaration" >&2
	exit 1
fi
if grep -F '/home' "$policy" "$contexts" >/dev/null; then
	echo "policy must not label or grant access to user homes" >&2
	exit 1
fi
for service in salyut-site salyut-bbsd
do
	dropin="$tmp/etc/systemd/system/$service.service.d/30-selinux-domain.conf"
	grep -Fx 'NoNewPrivileges=false' "$dropin" >/dev/null
	grep -Fx 'RestrictSUIDSGID=false' "$dropin" >/dev/null
done

"${CC:-cc}" -std=c11 -Wall -Wextra -Werror \
	-I"$repo/tests/include" \
	"$repo/pam/pam_salyut_session_privacy.c" \
	"$repo/tests/test_session_privacy.c" \
	-o "$tmp/test_session_privacy"
"$tmp/test_session_privacy"
grep -F 'return pam_set_item(pamh, PAM_RHOST, NULL);' \
	"$repo/pam/pam_salyut_session_privacy.c" >/dev/null
