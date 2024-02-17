# Threat Model

Very good article: https://www.privacyguides.org/en/basics/threat-modeling/

> Balancing security, privacy, and usability is one of the first and most difficult tasks you'll face on your privacy journey. Everything is a trade-off: The more secure something is, the more restricting or inconvenient it generally is, etc. Often, people find that the problem with the tools they see recommended is that they're just too hard to start using!

My setup aims to be single-user, therefore in my threat model I consider that if any malicious actor gets code execution on my machine it's over. Even if that code execution is unprivileged. Most of the "sensitive" stuff I have is under my home directory. This is what I want to protect, not some random configuration files in `/etc`.

![alt authorization](https://imgs.xkcd.com/comics/authorization.png)

Image Credit: https://xkcd.com/1200/

## What do I want to protect?

- My personal data integrity and confidentially (documents, passwords, pictures, etc.)
- My privacy (e.g. eavesdropping, laptops usually have built-in microphones, cameras, etc.)

## Who do I want to protect it from?

- Thieves that could steal my hardware
- Corporations that make money on my back
- Script kiddies, and even more tech savvy hackers
- Slow down state-sponsored hackers as much as possible, but considering how much money and manpower they have, if I'm being targeted I do realize there's nothing I can do

## How likely is it that I will need to protect it?

Not likely.

I would say the most likely to happen is either a supply chain attack or
a Firefox exploit spreading from a random website I visit.
Hopefully the payload wont work with my setup considering I'm running a Linux machine,
most malware campaigns target Windows/Mac machines because of their market share.

## How bad are the consequences if I fail?

Not that bad, I'm not a public figure or anything, just a random person on the internet.

Still, I don't want my passwords, SSH and GPG keys to leak.

It's more a matter of principle that a real need to avoid any consequence.

## How much trouble am I willing to go through to try to prevent potential consequences?

Enough to spend a good portion of my free time writing configuration files and documentation.
But I still want a setup that I can easily use on a daily basis to perform administrative
tasks, programming, and entertain myself on the internet.
