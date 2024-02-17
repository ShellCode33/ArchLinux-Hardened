# Networking

The networking configuration of this ArchLinux setup follows the usual security principal which states that "what is not explicitly allowed is forbidden".

## Firewall Policies

All the [firewall policies](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/etc/nftables.conf) are set to `drop` by default, which means nothing can come in or out unless stated otherwise.

While both the `input` and `forward` chains can easily be set to `drop` without breaking much, the `output` chain is another kettle of fish.

I obviously want a usable setup, and being able to reach the internet is a requirement.
But then how do I manage to conciliate security and usability in that matter ?
By using a local proxy !

## The Local Proxy

The idea is that by default nothing has access to the internet
(thanks to the output `drop` policy),
but any application routing its traffic through the local proxy will.

This is achieved by matching the `skgid` nftables metadata.
The `skgid` matches the `allow-internet` group, any program using that group
will be allowed to reach the internet.
The proxy is run using that group.

You can read more on how to use the proxy in the [PROXY.md](PROXY.md) documentation.

Some informed users reading this that might be thinking "But why? What's the point?
It doesn't add anything security-wise".
And you would be kind of right. A determined attacker would just have to look for
running proxies or look for the `HTTPS_PROXY` environment variables to be able to
bypass this measure.

But let me try to convince you of the usefulness of this:

1. It would still prevent poorly written malware from exfiltrating data and reverse connecting to a C&C (script kiddies are all over the place).
2. It prevents "well-behaved" applications from reaching the internet without you noticing. Many applications fetch content from remote servers (especially Google Cloud and Amazon AWS).
3. It can help prevent supply chain attacks. Many times in the past it has happened that dependencies of legitimate programs have been backdoored. Blocking access to the internet might prevent those legitimate apps from self-updating and potentially pulling malicious code. First program that comes to my mind is neovim and its npm dependencies.
4. This local proxy allows you to monitor what's going on (i.e. which apps are using the network). It can be useful for statistics purposes or to look for something fishy. Being able to monitor what's going on on a system is also a big component of systems security.

This is both defense in depth and a great privacy tool. (Privacy in the sense that it prevents apps from reaching the internet, your IP will obviously still be the same).

## Kernel hardening

The `linux-hardened` kernel of ArchLinux has various defaults which harden the network configuration as well.

Here's a non exhaustive list:

- Enable syn flood protection: `net.ipv4.tcp_syncookies`
- Ignore source-routed packets: `net.ipv4.conf.all.accept_source_route`
- Ignore source-routed packets: `net.ipv4.conf.default.accept_source_route`
- Ignore ICMP redirects: `net.ipv4.conf.all.accept_redirects`
- Ignore ICMP redirects: `net.ipv4.conf.default.accept_redirects`
- Ignore ICMP redirects from non-GW hosts: `net.ipv4.conf.all.secure_redirects`
- Ignore ICMP redirects from non-GW hosts: `net.ipv4.conf.default.secure_redirects`
- Don't allow traffic between networks or act as a router: `net.ipv4.ip_forward`
- Don't allow traffic between networks or act as a router: `net.ipv4.conf.all.send_redirects`
- Don't allow traffic between networks or act as a router: `net.ipv4.conf.default.send_redirects`
- Reverse path filtering - IP spoofing protection: `net.ipv4.conf.all.rp_filter`
- Reverse path filtering - IP spoofing protection: `net.ipv4.conf.default.rp_filter`
- Ignore ICMP broadcasts to avoid participating in Smurf attacks: `net.ipv4.icmp_echo_ignore_broadcasts`
- Ignore bad ICMP errors: `net.ipv4.icmp_ignore_bogus_error_responses`
- Log spoofed, source-routed, and redirect packets: `net.ipv4.conf.all.log_martians`
- Log spoofed, source-routed, and redirect packets: `net.ipv4.conf.default.log_martians`

You can query their value using the `sysctl` command, for example:

```
$ sysctl net.ipv4.tcp_syncookies
net.ipv4.tcp_syncookies = 1
```
