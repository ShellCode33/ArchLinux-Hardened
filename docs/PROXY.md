# Local Forwarding Proxy

As mentioned in [NETWORKING.md](NETWORKING.md), this setup uses a local forwarding
proxy to manually choose which applications are allowed to reach the internet.

This document shows you some examples on how to configure your
applications to allow them to reach the internet through the HTTP proxy.

Note that using an HTTP proxy doesn't mean you have to use HTTP as underlying protocol.
This is a bit counter intuitive but what it means is that to initiate the connection,
you have to use the CONNECT HTTP method. Then the proxy will make the connection on your
behalf and forward the TCP stream to you.

[Glider](https://github.com/nadoo/glider) is the forwarding proxy I choose.
It is being run as a systemd service which is configured [here](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/etc/systemd/system/local-forwarding-proxy.service).

## Temporary access from the CLI

This section shows you how to give temporary internet access to any program you want.

Mature enough programs will provide ways for you to route their traffic through a proxy.
For example curl has a `-x` parameter. But it would be very cumbersome to look for a
specific CLI flag for each application. This is why there's a "standard" way of doing this,
by using the `HTTP_PROXY` and `HTTPS_PROXY` environment variables.

For example the commands that follow are equivalent:

```
$ curl -x http://127.0.0.1:8080 https://remote-server
$ HTTPS_PROXY=http://127.0.0.1:8080 curl https://remote-server
```

To simplify things, a [wrapper script called proxify](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/usr/local/bin/proxify) has been written.

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

If the program you want to give internet access to doesn't provide a way to be run
through a proxy. You can use sudo to run it within the `allow-internet` group.
This completely bypasses the proxy, therefore it should be used as a last resort if no other method is available:

```
$ sudo -g allow-internet curl ifconfig.me
```

## Persistent access

There are some applications that you always want to allow reaching the internet.
The configuration is application specific, here are a few examples.

### Firefox

You can setup the proxy from the GUI by going to the settings and searching for "proxy".

Tick the "Manual proxy configuration" and use `127.0.0.1` for the host, and `8080` for the port.

Don't forget to tick `Also use this proxy for HTTPS`.

Alternatively, if you don't want to use the GUI, you can customize your Firefox profile
by creating a custom `user.js` file. Personally I use [arkenfox/user.js](https://github.com/arkenfox/user.js) and [here's my
config](https://github.com/ShellCode33/.dotfiles/blob/master/.mozilla/firefox/user-overrides.js).

### SSH

To reach your SSH machines simply add the following to your `~/.ssh/config` :

```
Host *
    ProxyCommand=socat STDIO PROXY:127.0.0.1:%h:%p,proxyport=8080
```

The idea is to use socat to perform the HTTP CONNECT method for us.
The TCP stream is then forwarded to `ssh`.
See `man 5 ssh_config` to know more about `ProxyCommand`.

## The Docker daemon

The Docker daemon must be able to reach the internet to pull images.

This is already configured for you in [/etc/docker/daemon.json](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/etc/docker/daemon.json)
Note that this setting only applies to the daemon, not containers !

## Systemd services

You simply have to add `Group=allow-internet` to the `[Service]` section of the service configuration file.

If you didn't create the service yourself and want to allow a third party service
to reach the internet, you can create an override for it using `sudo systemctl edit service-name` and add the following content:

```
[Service]
Group=allow-internet
```
