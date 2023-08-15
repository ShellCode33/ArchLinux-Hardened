# Networking

The networking configuration of this ArchLinux setup follows the usual security principal which states that "what is not explicitly allowed is forbidden".

## What

All [firewalling policies](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/etc/nftables.conf) are set to `drop` by default. But wait for it, there's a plot twist ;)

While both the `input` and `forward` chains can easily be set to `drop` without breaking much, the `output` chain is another kettle of fish.

I obviously want a usable setup, and being able to reach the internet is kind of mandatory. But then how do I manage to conciliate security and usability in that matter ? By using a local proxy !

## How

The idea is that by default nothing has access to the internet (thanks to the output `drop` policy), but any application routing its traffic through the local proxy will. This is achieved by matching the `skuid` nftables metadata. The `skuid` matches the `http` user, which is an ArchLinux default.

In order for you to instruct applications to route their traffic through the proxy, a [wrapper script called proxify](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/usr/local/bin/proxify) has been written.

Anytime you want to reach the internet you just have to prepend it to the command you want to run, for example:

```
$ proxify curl ifconfig.me
WW.XX.YY.ZZ
```

Otherwise you would get:

```
$ curl ifconfig.me
curl: (7) Failed to connect to ifconfig.me port 80: Couldn't connect to server
```

Obviously there are some applications we don't want to bother with, for example Firefox. It wouldn't make sense to start it every time from the command line using the `proxify` script. So instead of doing so, you can just change its proxy configuration to use the proxy by default (if you're feeling curious you can have a look at [my user-overrides.js](https://github.com/ShellCode33/.dotfiles/blob/master/.mozilla/firefox/user-overrides.js) and my [firefox wrapper](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/usr/local/bin/firefox)).

You can also have a look at [glider](https://github.com/nadoo/glider) which is the forwarding proxy I chose for [my setup](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/etc/systemd/system/local-forwarding-proxy.service). I configured glider to listen to `127.0.0.1:8080`.

## Why

There might be some informed users reading this that might be thinking "But why? What's the point? It doesn't add anything security-wise". And you would be kind of right. A determined attacker would just have to look for running proxies or look for `HTTP_PROXY` environment variables to be able to bypass this measure.

But let me try to convince you of the usefulness of this:

1. It would still prevent poorly written malware from exfiltrating data (script kiddies are all over the place).
2. It prevents "well-behaved" applications from reaching the internet without you noticing. Many times in the past it has happened that dependencies of legitimate programs have been backdoored. Blocking access to the internet might prevent those apps from self-updating and potentially pulling malicious code. First program that comes to my mind is neovim.
3. This local proxy allows you to monitor what's going on (i.e. which apps are using the network). It can be useful for statistics purposes or to look for something fishy. Being able to monitor what's going on on a system is also a big component of systems security.

This is both defense in depth and a great privacy tool. (Privacy in the sense that it prevents apps from reaching the internet, your IP will obviously still be the same).
