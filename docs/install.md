# Install antitheft

antitheft has two parts: a protection service that runs in the background with full system rights, and the antitheft
app, where you see your vaults, alerts and activity. Both install together.

By installing antitheft you agree to its [Terms](https://antitheft.pro/terms/).

- [Windows](#windows)
- [macOS](#macos)
- [Linux](#linux)
- [After installing](#after-installing)
- [Uninstall](#uninstall)

## Windows

Windows 10 or 11, 64-bit.

**With the installer:**

1. Download `antitheft-<version>-windows-x86_64-setup.exe` from the
   [latest release](https://github.com/kinnector/antitheft/releases/latest).
2. Run it and allow it to make changes (the protection service needs administrator rights).
3. Open **Antitheft** from the Start menu.

Windows may show **"Windows protected your PC"** (SmartScreen) while the installer is new. Choose **More info**, check
that it names the file you downloaded, then **Run anyway**. You can check the file first: see [verify.md](verify.md).

The app uses the Microsoft Edge WebView2 Runtime, which comes with Windows 11 and with Edge on Windows 10. The
installer tells you if it is missing.

**From PowerShell** (downloads, checks the SHA-256 and installs; Windows asks for permission):

```powershell
iwr https://antitheft.pro/antitheft.ps1 -useb | iex
```

Running the installer again over an existing install updates it in place.

## macOS

Open Terminal and run:

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | bash
```

It asks for your password to install the protection service. macOS ships with its file auditing turned off, and
antitheft needs it to see which programs open your vaults, so the script asks whether to turn it on and then offers to
restart. If you say no, the app asks again later. Then it opens the app.

## Linux

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | bash
```

It installs the protection service (systemd) and the app, and asks for your password through `sudo`.

On Linux antitheft refuses a program before the file opens, using a security feature of the Linux kernel (BPF LSM).
Many distributions ship with it turned off. If yours does, the app shows **Turn on**: it changes your boot settings
once and asks you to restart.

## After installing

1. Open the app and sign in with your email or Google.
2. With a subscription on your account, this computer is protected. Without one, antitheft runs in **watching only**
   mode: it shows everything that reaches for your vaults, and stops nothing.
3. Look at **Vaults**: every app antitheft found on this computer and what it guards for it.

## Uninstall

Remove antitheft with its own uninstaller, never by deleting its files or ending its service. Its records on the
computer (alerts, activity, your decisions) stay unless you ask the uninstaller to delete them.

**Windows:** Settings > Apps > Installed apps > **Antitheft** > Uninstall. To also delete its records, run in
PowerShell opened as administrator:

```powershell
powershell -ExecutionPolicy Bypass -File "C:\Program Files\Antitheft\uninstall.ps1" -Purge
```

**macOS:** in the app, Settings > General > Uninstall antitheft. Or in Terminal:

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | bash -s uninstall
```

Add `--purge` to also delete its records, and `--disable-auditing` to turn macOS auditing back off.

**Linux:**

```sh
curl -fsSL https://antitheft.pro/antitheft.sh | bash -s uninstall
```

Add `--purge` to also delete its records.

More: [antitheft.pro/uninstall](https://antitheft.pro/uninstall/).
