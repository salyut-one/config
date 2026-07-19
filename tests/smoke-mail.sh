#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run this smoke test as root on the mail server" >&2
	exit 1
fi

for command in postmap sendmail systemctl useradd userdel; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "missing required command: $command" >&2
		exit 1
	fi
done

systemctl is-active --quiet postfix
systemctl is-active --quiet postsrsd

suffix=$$
source_user=slytfwdsrc$suffix
target_user=slytfwddst$suffix
source_home=/home/$source_user
target_home=/home/$target_user
token=salyut-forward-smoke-$suffix

cleanup()
{
	userdel -r "$source_user" >/dev/null 2>&1 || :
	userdel -r "$target_user" >/dev/null 2>&1 || :
}

trap cleanup EXIT HUP INT TERM
useradd -m -s /usr/sbin/nologin "$source_user"
useradd -m -s /usr/sbin/nologin "$target_user"

wait_for_mail()
{
	home=$1
	count=0
	while [ "$count" -lt 20 ]; do
		if find "$home/Maildir" -type f -exec grep -l "$token" {} + \
			2>/dev/null | grep . >/dev/null
		then
			return 0
		fi
		count=$((count + 1))
		sleep 1
	done
	return 1
}

printf '%s\n' "$target_user" >"$source_home/.forward"
chown "$source_user:$source_user" "$source_home/.forward"
chmod 600 "$source_home/.forward"
printf 'Subject: %s redirect\n\n%s\n' "$token" "$token" |
	sendmail -f smoke@example.net "$source_user@salyut.one"
wait_for_mail "$target_home"
if find "$source_home/Maildir" -type f 2>/dev/null | grep . >/dev/null; then
	echo "redirect unexpectedly retained a local copy" >&2
	exit 1
fi

rm -rf "$source_home/Maildir" "$target_home/Maildir"
printf '\\%s, %s\n' "$source_user" "$target_user" \
	>"$source_home/.forward"
chown "$source_user:$source_user" "$source_home/.forward"
chmod 600 "$source_home/.forward"
printf 'Subject: %s copy\n\n%s\n' "$token" "$token" |
	sendmail -f smoke@example.net "$source_user@salyut.one"
wait_for_mail "$source_home"
wait_for_mail "$target_home"

rewritten=$(postmap -q smoke@example.net \
	'socketmap:unix:/var/spool/postfix/private/srs:forward')
case "$rewritten" in
	SRS0*@salyut.one) ;;
	*)
		echo "unexpected SRS address: $rewritten" >&2
		exit 1
		;;
esac

reversed=$(postmap -q "$rewritten" \
	'socketmap:unix:/var/spool/postfix/private/srs:reverse')
if [ "$reversed" != "smoke@example.net" ]; then
	echo "SRS reverse lookup returned: $reversed" >&2
	exit 1
fi

echo "redirect, retained-copy, and SRS round-trip checks passed"
