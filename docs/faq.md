# FAQ

### Is antitheft an antivirus?

No. An antivirus tries to recognize malware. antitheft doesn't need to: it guards the files malware goes for, your
wallets, saved passwords, browser logins and messenger sessions, and lets only their own apps in. Something brand new
that no antivirus has seen yet is still not your wallet app. Keep your antivirus; antitheft works next to it.

### What happens when something reaches for my wallet?

On Windows and macOS the program is stopped. On Linux, with kernel protection on, it is refused before the file opens.
Either way you get an alert: which program it was, which app started it, and what it reached for. From the alert you
can look closer, end the program, or mark it as not a threat.

### Something I trust was stopped. What now?

Mark it as not a threat from the alert. Some programs are trusted by design, and the rules differ per app and per
system. If antitheft keeps getting one of your apps wrong, [tell us](https://github.com/kinnector/antitheft/issues/new?template=false-alert.yml)
so we can fix it.

### Does it work without a subscription?

Yes, in **watching only** mode: it shows everything that reaches for your vaults, and stops nothing. A subscription is
$10 per computer, a year, with 14 days money back.

### Does it slow down my computer?

It doesn't scan your disk. It acts only when a program reaches for one of the files it guards.

### Why does Windows warn about the installer?

SmartScreen warns about installers it hasn't seen many times yet. Choose **More info**, then **Run anyway**. You can
check the file first: [verify.md](verify.md).

### Does antitheft send my files anywhere?

It does its work on your computer and doesn't upload your files. It talks to our server to sign you in, check your
subscription and fetch the list of apps it knows, and to GitHub (or our mirror) for updates. Reports about alerts are
sent only if you turn on **Help improve antitheft**. The details are in the [Privacy policy](https://antitheft.pro/privacy/).

### Why do I need to sign in?

Your subscription is on your account, and it follows you: every computer you sign in to with that account is covered,
up to the number of computers you pay for.

### Is the source code available?

Not publicly. This repository holds antitheft's releases, documentation and issue tracker. You may examine antitheft
itself on computers you own (decompile it, debug it, watch its network traffic): see [SECURITY.md](../SECURITY.md).

### Can I use it at work?

The plans on the website are for individuals and their household. For a business licence, write to
[business@antitheft.pro](mailto:business@antitheft.pro).

### How do I uninstall it?

See [install.md](install.md#uninstall).
