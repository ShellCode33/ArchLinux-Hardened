# Firefox

Firefox has been hardened both security and privacy wise thanks to [arkenfox/user.js](https://github.com/arkenfox/user.js).

Its configuration is being updated automatically every time you start Firefox thanks to [this wrapper script](https://github.com/ShellCode33/ArchLinux-Hardened/blob/master/rootfs/usr/local/bin/firefox).

If you're not happy with its current behavior, edit the Configuration overrides which are available in my dotfiles repo [there](https://github.com/ShellCode33/.dotfiles/blob/master/.mozilla/firefox/user-overrides.js).

As always, a line has to be drawn between security and usability. If you want a truly privacy respecting browser, use the TOR browser.

## Remember cookies after a restart

Perform `CTRL + i` on the website you want to stay logged into after a restart of Firefox.

Then look for "Set cookies" and untick "Use Default". Make sure the radio button is set to "Allow".
