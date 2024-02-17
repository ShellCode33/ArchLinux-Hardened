# Firejail

This tool is a bit controversial because it is a setuid binary.

I ended up choosing it anyway for its ease of configuration and balanced defaults.
Firejail's default profiles are more permissive than good AppArmor profiles (such as the ones from [apparmor.d](https://github.com/roddhjav/apparmor.d))
but the thing with AppArmor on ArchLinux is that it is almost unusable for most applications (that don't provide an AppArmor profile themselves).
ArchLinux is a rolling release therefore programs are updated very regularly.
It means that AppArmor profiles become outdated very fast, and things break frequently.

Regarding the setuid controversy, I was quite sold by a point made by the creator of Firejail [in that thread](https://github.com/netblue30/firejail/issues/3046):

> Once inside a sandbox - firejail, bubblewrap, or any other seccomp sandbox - you can not exploit any SUID executable present in the system. It has to do with the way seccomp is handled by the kernel. The attack surface of the program that configured seccomp becomes irrelevant. In other words, if you get control of a firefox running in a sandbox, the kernel wouldn't let you exploit the program that started the sandbox.

(Also, I don't really care if an attacker is able to privesc on my machine, see my [threat model](THREAT_MODEL.md))

In addition to that, Firejail has an AppArmor profile which is in use as well.
