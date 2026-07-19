# salyut-config

The host policy, operator access, mail forwarding, login privacy, welcome
message, and system manual for
[salyut.one](https://salyut.one), an all-purpose, small, tilde-adjacent pubnix
running Fedora 44.

This repository replaces the former `salyut-selinux`, `salyut-manpage`,
`salyut-cockpit`, `salyut-mail`, and `salyut-session-privacy` repositories. It
owns:

- the SELinux domains for `salyut-site` and `salyut-bbsd`;
- the `salyut(7)` manual and login MOTD;
- Cockpit's `wheel`-only PAM service;
- PostSRSd, its hardened service, and Postfix socketmap configuration; and
- the PAM module that keeps SSH client addresses out of public session data.

## Check, build, and install

The portable checks stage every configuration file, lint the manual when a
renderer is available, validate the SELinux sources, and exercise the session
privacy module with stub PAM headers:

```sh
make check
```

A complete Fedora build additionally requires:

```sh
sudo dnf install cmake gcc make curl check-devel libconfuse-devel \
  libseccomp-devel pam-devel selinux-policy-devel
make build
make check
```

`make build` compiles the SELinux module, PostSRSd 2.3.0, and the PAM module.
The PostSRSd source archive is pinned by SHA-256.

Install everything as root:

```sh
sudo make install
```

Component targets are available when changing one area:

```text
build-selinux             install-selinux
build-mail                install-mail
build-session-privacy     install-session-privacy
                          install-manpage
                          install-cockpit
                          install-config
```

`install-config` is build-free and suitable for staged packaging checks. Set
`DESTDIR` to suppress live-host side effects:

```sh
make install-config DESTDIR="$PWD/pkgroot"
```

## Host activation

Installation deliberately stops short of operations that could lock out SSH
or restart public services. After reviewing the staged files, activate them:

```sh
sudo semodule -i /usr/share/selinux/packages/salyut_services.pp
sudo systemctl daemon-reload
sudo restorecon -RFv \
  /usr/local/bin/salyut-site \
  /usr/local/bin/salyut-bbsd \
  /var/lib/salyut-bbs /run/salyut-bbs /srv/user_profiles \
  /usr/lib64/security/pam_salyut_session_privacy.so
sudo systemctl enable --now postsrsd.service
sudo systemctl reload postfix.service
sudo systemctl restart salyut-site.service salyut-bbsd.service
```

Add this line to `/etc/pam.d/sshd` immediately before the stack calls
`pam_systemd.so`:

```text
session required pam_salyut_session_privacy.so
```

Keep an existing root session open while testing a second SSH login. The
installer does not edit the SSH PAM stack because a mistake there can prevent
new logins.

## SELinux policy

The site and BBS daemon run in separate domains. The site may execute
`/usr/bin/pinky` and connect to the BBS Unix socket for read-only web views,
but it cannot read BBS SQLite state or user homes. Public profile data remains
labelled under `/srv/user_profiles` without being exposed to either service.

The service drop-in disables `NoNewPrivileges` and `RestrictSUIDSGID` because
either setting prevents the SELinux process transition and leaves the service
in `init_t`. The units' remaining capability, namespace, device, and
filesystem restrictions stay in force. Production must contain no permissive
declaration or `semanage permissive` override.

The `salyut-bbs` repository continues to own
`/etc/tmpfiles.d/salyut-bbs.conf`; this repository does not overwrite it.
The policy reuses Fedora's existing label for the site's loopback HTTP port
rather than relabelling a shared global port type.

## Login welcome and manual

Interactive SSH sessions display a short MOTD directing users to
`man salyut`. Service notices remain on the BBS instead of running during
every login.

Confirm that the SSH PAM stack displays `/etc/motd` and `/etc/motd.d`
fragments, then check that only an interactive login receives the welcome:

```sh
ssh salyut.one
ssh salyut.one true
scp ./README.md salyut.one:
sftp salyut.one
```

Remote commands, SCP, and SFTP must remain free of banner text on standard
output.

## Cockpit access

Cockpit authentication is restricted to Unix accounts in `wheel`. Root
remains denied through `/etc/cockpit/disallowed-users`. The installer does not
delete the obsolete `/etc/cockpit/allowed-users` file because that file is
administrator-managed.

PAM reads the service for each new authentication, so Cockpit does not need a
restart. To verify the installed account policy with one operator and one
ordinary account:

```sh
sudo dnf install pamtester
sudo sh tests/smoke-cockpit.sh wheel_user ordinary_user
```

## Mail forwarding

Postfix's local delivery agent reads `~/.forward`. PostSRSd rewrites foreign
envelope senders when mail is forwarded externally, while addresses
originating at `salyut.one` and `mail.salyut.one` remain unchanged.
Postfix's standard command and file destinations in `~/.forward` remain
enabled.

On a live install, `make install-mail` creates the `postsrsd` system account,
generates `/etc/postsrsd.secret` only when it is absent, and configures
Postfix's sender and recipient canonical maps. It does not start or reload
PostSRSd or Postfix. Preserve the SRS secret across upgrades and migrations;
losing it prevents delayed bounces from being reversed.

After activation, the privileged smoke test verifies redirect-only delivery,
retaining a local copy, and a forward-and-reverse SRS lookup:

```sh
sudo sh tests/smoke-mail.sh
```

## Session privacy

`pam_salyut_session_privacy.so` clears `PAM_RHOST` immediately before
`pam_systemd.so` opens an SSH session. Ordinary users therefore cannot obtain
another user's remote IP address through `loginctl` or systemd-backed
implementations of `who`; SSH retains the address in its privileged journal
and audit records.

The module propagates errors from `pam_set_item`. Keep it configured as
`required` so a session fails instead of publishing its remote address when
the field cannot be cleared.

## Repository migration

The five former repositories and this repository must not coexist under
`/usr/local/src`: `salyut-admin update` discovers every Git repository with a
Makefile and would install the same paths from multiple owners.

Clone and validate `salyut-config`, install it once, then archive or remove
these old host checkouts before the next all-repository update:

```text
salyut-selinux
salyut-manpage
salyut-cockpit
salyut-mail
salyut-session-privacy
```
