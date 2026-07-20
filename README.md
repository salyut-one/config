# salyut-config

Host configuration for https://salyut.one. It owns the SELinux policy, system
manual and login message, Caddy routing, Cockpit access policy, PostSRSd mail
forwarding configuration, and the PAM module that removes SSH client addresses
from public session data.

## Build and test

```sh
make check
make build
```

A complete build requires Fedora's SELinux, PAM, PostSRSd, and C development
dependencies. Portable configuration checks can run without them:

```sh
make install-config DESTDIR="$PWD/pkgroot"
```

A live `make install` activates the installed SELinux module; staged
`DESTDIR` installs do not. Installation does not edit `/etc/pam.d/sshd` or
restart services. Those operations remain explicit because a bad PAM or
SELinux change can prevent new logins.

## Deploying

```sh
salyut-admin update
```

## License
[MIT](./LICENSE)
