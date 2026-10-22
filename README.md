<p align="center"><img src="docs/greenhorn.gif" alt="Sentinel Greenhorn title screen: fireworks, THE SENTINEL / GREENHORN / WSL INSTALLER HAS LANDED!" width="958"></p>

<p align="center"><i>A small batch file, with an enormous inside!</i></p>

<p align="center">
  <img alt="Windows 10 | 11" src="https://img.shields.io/badge/Windows-10%20%7C%2011-00a4ef?style=for-the-badge&logo=windows11&logoColor=white">
  <img alt="WSL 2" src="https://img.shields.io/badge/WSL-2-ff87ff?style=for-the-badge&logo=linux&logoColor=white">
  <img alt="One file" src="https://img.shields.io/badge/one%20file-.bat-ffaf00?style=for-the-badge">
  <img alt="Fireworks: yes" src="https://img.shields.io/badge/fireworks-yes-5fffff?style=for-the-badge">
  <img alt="Chiptune: included" src="https://img.shields.io/badge/chiptune-included-af87ff?style=for-the-badge">
</p>

<p align="center"><b>The WSL installer for dummies. With fireworks. And a chiptune. Obviously.</b></p>

Installing WSL (Windows Subsystem for Linux) should not need a computer science degree.
Sentinel Greenhorn is a single `.bat` file you double-click. It throws a fireworks show,
plays a retro synth tune, and then walks you through the whole thing, one friendly step at a
time, cheering you on when it works and calmly fixing it with you when it doesn't.

<h2 align="center"><img src="docs/readme/h-how.svg" alt="How to use it"></h2>

<p align="center">
  <a href="https://github.com/sentinelarmory/greenhorn/releases/latest/download/Sentinel-Greenhorn.bat"><img src="docs/readme/download.svg" alt="Download Sentinel-Greenhorn.bat"></a>
</p>

1. Download **`Sentinel-Greenhorn.bat`** (the button above, or the [latest release](../../releases/latest)).
2. Double-click it.
3. Windows may say *"Windows protected your PC"* because the file came from the internet.
   Click **More info → Run anyway**.
4. Enjoy the show, press **1**, and say **Yes** when Windows asks for administrator rights.

That's it. Mr. Greenhorn takes it from there, restarts included: if the PC has to reboot (or
visit the BIOS), the installer pops up again by itself after you log in and carries on where
it left off.

> **Want a sneak peek first?** Run it with `--dry-run`. It shows everything it *would* do and
> changes nothing: `.\Sentinel-Greenhorn.bat --dry-run`

<h2 align="center"><img src="docs/readme/h-steps.svg" alt="What happens, step by step"></h2>

<p align="center"><img src="docs/readme/steps.svg" alt="The ten steps of the installer, each followed by a cheer" width="958"></p>

<details>
<summary><b>The ten steps in detail</b></summary>

1. **Saying hello to your PC**: checks the Windows version, free disk space, memory and that
   virtualization is on. If it's off in the BIOS, it finds out who made your PC, tells you
   exactly which menu to look in, and restarts straight into the BIOS for you.
2. **The WSL engine**: switches on the right Windows features, with a plan B (DISM) if the
   normal way fails.
3. **Picking a Linux**: installs Ubuntu, and explains the username and password prompt in
   plain words.
4. **Fixed IP address**: sniffs out your router and home network, picks a private network for
   WSL that clashes with nothing (LAN, VPN, Hyper-V), checks the addresses are free, and gives
   Linux an IP that never changes. Or mirrored networking, if you prefer.
5. **Speed and memory**: a sensible `.wslconfig` (memory limit, swap, memory reclaim, sparse disk).
6. **Setting up the fixed IP** on both sides, plus the name `wsl.local` in the Windows hosts file.
7. **Spring cleaning the disk**: tidies up inside Linux and compacts the virtual disk, so the
   space actually comes back to Windows.
8. **Does Linux work? (the big test)**: Linux answers, runs WSL 2, has systemd and can reach
   the internet.
9. **Next stop: [Tortugarr](https://github.com/tortugarr/tortugarr)**: downloads the server
   installer and the TV/phone apps, checks the checksums, explains how to get the apps onto an
   Android TV and phone, and can even serve them over Wi-Fi with a short address.
10. **Done! Hooray!** A fireworks finale, a list of handy tricks, and the safety net is taken
    down again.

</details>

<h2 align="center"><img src="docs/readme/h-oops.svg" alt="When it goes wrong"></h2>

<p align="center"><img src="docs/readme/oops.svg" alt="An example error: a plain-words explanation, a comforting line and the exact thing to do next" width="958"></p>

Nobody panics. Every error comes with a plain-words explanation and the exact thing to do
next. Restarts and trips to the BIOS are covered by a safety net: a one-shot logon task brings
the installer back after you log in, and is taken down again when everything is done.

<h2 align="center"><img src="docs/readme/h-flags.svg" alt="For the curious"></h2>

| Flag | What it does |
|---|---|
| `--dry-run` | Show everything, change nothing |
| `--fresh` | (with `--dry-run`) pretend WSL isn't installed, to see the whole install path |
| `--oops` | (with `--dry-run`) pretend something fails, to see how errors are handled |
| `--novirt` | (with `--dry-run`) pretend virtualization is off in the BIOS |
| `--resume` | (with `--dry-run`) preview the "welcome back after a restart" screen |
| `--go` | Skip the fireworks and go straight to the guide |
| `--quiet` | No music (or press **M** on the title screen) |

<h2 align="center"><img src="docs/readme/h-changes.svg" alt="What it changes on your PC"></h2>

Being honest about it, so nothing comes as a surprise:

- Windows features: *Windows Subsystem for Linux* and *Virtual Machine Platform* (via `wsl --install`).
- `%USERPROFILE%\.wslconfig` (the old one is backed up as `.wslconfig.bak-<date>`).
- Fixed IP option: a line in `/etc/wsl.conf` inside Linux, a scheduled task
  `Greenhorn-WSL-FixedIP`, a helper script in `C:\ProgramData\GreenhornWSL\`, and a
  `wsl.local` line in the Windows hosts file (backed up as `hosts.bak-greenhorn`).
- During the run only: the safety net (scheduled task `Greenhorn-WSL-Resume`), removed again
  when the guide finishes. The temporary firewall rule for the APK shop is removed when you
  close the shop.
- A log in `%TEMP%\greenhorn-wsl-helper.log`.

<details>
<summary><b>Undo the fixed IP setup</b></summary>

```powershell
Unregister-ScheduledTask -TaskName Greenhorn-WSL-FixedIP -Confirm:$false
Remove-Item C:\ProgramData\GreenhornWSL -Recurse
# then remove the line ending in "# greenhorn-wsl" from C:\Windows\System32\drivers\etc\hosts
```

Inside Linux, remove the two lines starting at `# greenhorn-fixed-ip` from `/etc/wsl.conf`.

</details>

**Requirements:** Windows 11 (or Windows 10 2004 and newer), a CPU with virtualization support
(nearly every PC from the last ten years), an administrator account, and a sense of humour
(optional, but recommended).

<h2 align="center"><img src="docs/readme/h-hood.svg" alt="Under the hood"></h2>

One file, no downloads, no dependencies, no telemetry. The `.bat` is a tiny launcher that hands
itself to Windows PowerShell. The fireworks are drawn with ANSI colours and half-block
characters, and the music is a small chiptune synthesizer written in C# that renders the tune
into memory when the installer starts. The animated images on this page are generated by
[`tools/readme_svgs.py`](tools/readme_svgs.py), and [`docs/index.html`](docs/index.html) is the
full show as a web page, the same animation ported to JavaScript.

<p align="center"><img src="docs/readme/marquee.svg" alt="WINDOWS SUBSYSTEMS FOR LINUX INSTALLER FOR DUMMIES v.0.1" width="958"></p>

<p align="center"><b>Sentinel has got your back.</b></p>
