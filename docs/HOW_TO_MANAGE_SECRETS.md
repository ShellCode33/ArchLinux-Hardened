# Secrets Management

I think everyone agrees that typing passwords is annoying, especially when you have long and complex passphrases.
This tutorial aims to show you how to securely manage different kinds of secrets, so that you have to type only one password: [KeePassXC](https://keepassxc.org)'s.

## SSH Keys

Prerequisit: being able to SSH into your server using your SSH keypair.

Under the hood, KeePassXC uses ssh-agent to store SSH secrets.

To make sure ssh-agent is up and running, you should add the following to your login shell profile file:

```
eval $(ssh-agent) > /dev/null
```

The login shell is the shell assigned to your user in `/etc/passwd`. The line above should be added to `~/.bash_profile` if your login shell is bash, or to `~/.profile` if your login shell is sh or dash.

The eval statement will set the `SSH_AUTH_SOCK` environment variable for all the programs you run. You must logout for these changes to propagate.

Now we must enable the SSH Agent integration in KeePassXC. Head over to the settings section and click on _"SSH Agent"_.

You have nothing else to do but to tick _"Enable SSH Agent integration"_, you should see a green dialog telling you that the connection with ssh-agent is working properly.

Now let's create a new entry in KeePassXC which contains the password of your SSH private key, while creating the entry, you should see a _"SSH Agent"_ tab, click on it, make sure the following is ticked:

- Add key to agent when database is opened/unlocked
- Remove key from agent when database is closed/unlocked

Under the _"Private key"_ section, choose the _"External file"_ radio button, click on _"Browse..."_ and pick your private key (the one that **doesn't** end with `.pub.`).

You are now good to go, ssh won't ask for your password anymore as long as KeePassXC's database is open.

## GPG Keys

Prerequisit: having a pair of GPG keys generated already.

KeePassXC doesn't support GPG out of the box, but there's a workaround: the libsecret integration.

Unlock your database and create a new group/folder that will contain all your GPG keys.

Head over to the settings section and click on _"Secret Service Integration"_ and tick _"Enable KeePassXC Freedesktop.org Secret Service integration"_.

Under the _"Exposed database groups"_ you should see that an entry is there already but the _"Group"_ field is set to _"none"_. Click on the edit button on the right of this row. A new settings dialog will open, head over to the _"Secret Service Integration"_ again, and tick _"Expose entries under this group"_, then choose the previously created group.

The Secret Service integration is now setup properly.

We must now setup our keys so that they are automatically picked up by gpg.

By default gpg will spawn a gpg-agent that will store your passwords for a given period of time so that you don't have to enter your passwords multiple times if you want to use the same key again. Thing is, we want KeePassXC to manage our GPG keys, not gpg-agent. If KeePassXC's database is locked, the gpg keys shouldn't stay in gpg-agent memory.

To prevent gpg-agent from keeping our keys in memory, add the following to `~/.gnupg/gpg-agent.conf`:

```
default-cache-ttl 0
max-cache-ttl 0
```

It will basically disable caching of GPG keys.

When asked for a password, GPG will spawn a "pinentry" program. There are many of them and you can basically use any of them as long as they have libsecret integration. I personnally use `pinentry-curses` which doesn't spawn any GUI and asks for a password within the terminal.

To make sure the pinentry program you use has support for libsecret, you can run the following command (replace `pinentry-curses` by the pinentry you're planning to use):

```
ldd "$(command -v pinentry-curses)" | grep libsecret
```

If you see something like this in the ouput, then libsecret should be supported:

```
libsecret-1.so.0 => /usr/lib/libsecret-1.so.0 (0x00006a1d0397b000)
```

To change the pinentry program of gpg-agent, you can add the following to `~/.gnupg/gpg-agent.conf`:

```
pinentry-program /usr/bin/pinentry-curses
```

At this point everything is ready, you must kill any already running gpg-agent instance so that your config modifications are applied:

```
killall gpg-agent
```

There's one last thing to be aware of. Currently the pinentry of gpg-agent has no clue about what password entry to use in our KeePassXC database. We will now see how to link a GPG key to an entry in our KeePassXC database.

Run the following command:

```
gpg --list-secret-keys --with-keygrip
```

If you have generated only one GPG keypair, your output should be similar to this:

```
/home/shellcode/.gnupg/pubring.kbx
----------------------------------
sec   rsa4096 2023-07-20 [SC]
      XXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXXX
      Keygrip = YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
uid           [ultimate] YourName <your@e.mail>
ssb   rsa4096 2023-07-20 [E]
      Keygrip = ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ
```

We can see in this output that we have two keys, YYY and ZZZ.

Note: a keygrip is basically a unique identifier of your keys. The pinentry programs will use this keygrip to query password to the libsecret provider (in our case KeePassXC).

We must now head over to KeePassXC and create a new entry for our GPG key. This new entry must be in the previously created group. Add your GPG key password to this entry and name it whatever you like.

Then click on the _"Advanced"_ tab, there's a _"Additional attributes"_ section.

In this section create an entry called `xdg:schema` and set its value to `org.gnupg.Passphrase`.

Then create a second entry called `keygrip` which must contain the keygrip of your key prefixed with `n/`.
With the output above it should be:

```
n/YYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYYY
```

And you're done ! The pinentry program won't ask for your password anymore, as long as your KeePassXC database is unlocked.

You can test this by running:

```
killall gpg-agent
echo test | gpg --armor --sign
```

I invite you to make sure it's working properly by trying to lock/unlock your KeePassXC database to make sure the behavior is as expected.

Clone your existing GPG key entry in KeepassXC, and do the same for `n/ZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZZ` so that you wont be prompted when trying to decrypt stuff.

## Automatically lock your database when you lock your computer

If an attacker robs your PC while your KeePassXC database is unlocked, the passwords/keys remain in memory and could be extracted without having to unlock the computer (see [DMA attack](https://en.wikipedia.org/wiki/DMA_attack)).

In this chapter we will harden our setup to automatically lock KeePassXC's database when we lock our PC so that secrets don't stay in memory.

Head over to KeePassXC settings, under the _"Security"_ tab, make sure _"Lock databases when session is locked or lid is closed"_ is ticked.

On some desktop environments it will work out of the box (check it), on others, it wont. In my experience, it mostly doesn't work out of the box.

If it doesn't work for you, the following command must be run before the lock program is being run:

```
dbus-send --print-reply --dest=org.keepassxc.KeePassXC.MainWindow /keepassxc org.keepassxc.KeePassXC.MainWindow.lockAllDatabases
```

Therefore you must identify how your session is being locked (which program, and who's reponsible for starting this program).
