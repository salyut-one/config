#!/bin/sh
set -eu

if [ "$(id -u)" -ne 0 ]; then
	echo "run this smoke test as root on the Cockpit host" >&2
	exit 1
fi

if [ "$#" -ne 2 ]; then
	echo "usage: $0 WHEEL_USER NON_WHEEL_USER" >&2
	exit 1
fi

wheel_user=$1
non_wheel_user=$2

for command in id pamtester; do
	if ! command -v "$command" >/dev/null 2>&1; then
		echo "missing required command: $command" >&2
		exit 1
	fi
done

if ! id -nG "$wheel_user" | tr ' ' '\n' | grep -Fx wheel >/dev/null; then
	echo "$wheel_user is not a member of wheel" >&2
	exit 1
fi

if id -nG "$non_wheel_user" | tr ' ' '\n' | grep -Fx wheel >/dev/null; then
	echo "$non_wheel_user is unexpectedly a member of wheel" >&2
	exit 1
fi

pamtester cockpit "$wheel_user" acct_mgmt

if pamtester cockpit "$non_wheel_user" acct_mgmt; then
	echo "Cockpit account check unexpectedly allowed $non_wheel_user" >&2
	exit 1
fi

if pamtester cockpit root acct_mgmt; then
	echo "Cockpit account check unexpectedly allowed root" >&2
	exit 1
fi

echo "wheel member allowed; ordinary user and root denied"
