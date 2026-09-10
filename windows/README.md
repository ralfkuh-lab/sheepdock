# sheepdock for Windows

The same idea as the macOS launcher, ported to Windows: herdr opens in its own
[Alacritty](https://alacritty.org) window with its own taskbar icon - one
button, the ram's head, and no terminal icon next to it.

![herdr running, as the rightmost button in the Windows 11 taskbar](docs/taskbar.png)

Rightmost: herdr, launched by sheepdock, while running. No Alacritty or
Windows Terminal button appears next to it.

No admin rights are needed. Everything is installed per user.

## Why

Windows groups taskbar buttons by *AppUserModelID*. Programs that do not set
one explicitly get an ID derived from their executable path, and the taskbar
draws whatever icon that executable carries.

That rules out Windows Terminal: it stamps its own fixed ID onto every window,
so a herdr launcher always ends up with a second button wearing the Windows
Terminal icon - or, if you force the same ID onto the shortcut, all your other
Windows Terminal windows get pulled under the ram's head as well.

Alacritty sets no ID of its own. So a *copy* of the Alacritty executable at its
own path is, as far as the taskbar is concerned, a separate application. Embed
the herdr icon into that copy and the window, Alt-Tab and taskbar all show the
sheep, while an Alacritty you install yourself is never touched. It is the
Windows counterpart of the copied kitty launcher binary inside `herdr.app`.

## What you get

`%LOCALAPPDATA%\Programs\sheepdock\`, about 7 MB:

- `herdr-terminal.exe` - Alacritty's portable build with the herdr icon and
  `FileDescription = herdr` embedded, so Task Manager says herdr too
- `herdr.ico` - built from herdr.dev's logo in all sizes the shell asks for
- `herdr-launch.ps1` - starts herdr from a shell (see below)
- `herdr.lnk` - the shortcut you pin; a copy goes to the Start Menu
- `tools\rcedit-x64.exe` - used to embed the icon

`%APPDATA%\sheepdock\alacritty.toml` holds the Alacritty profile for this
window only.

## Requirements

- Windows 10 or 11, PowerShell 5.1 or PowerShell 7
- [herdr](https://herdr.dev) installed (`irm https://herdr.dev/install.ps1 | iex`)
- Python 3 with Pillow for the icon (`python -m pip install --user pillow`),
  or [uv](https://docs.astral.sh/uv/) which fetches Pillow on the fly. Without
  either, the 32 px favicon from herdr.dev is used and looks soft in the taskbar.

Alacritty itself is **not** a requirement. The installer downloads the portable
build straight from the Alacritty GitHub release.

## Install

```powershell
git clone https://github.com/ralfkuh-lab/sheepdock.git
cd sheepdock\windows
.\install.ps1
```

Then start herdr from the Start Menu. To pin it, right-click the **Start Menu
entry** and choose "Pin to taskbar".

Pin the Start Menu entry, not a running window. A pin taken from a running
window keeps only the executable and drops the `--config-file` argument, so the
next click would open a plain Alacritty with your default shell instead of herdr.

Options:

| Parameter | Meaning |
| --- | --- |
| `-Prefix DIR` | install somewhere other than `%LOCALAPPDATA%\Programs\sheepdock` |
| `-ConfigDir DIR` | put the Alacritty profile somewhere other than `%APPDATA%\sheepdock` |
| `-Icon SRC` | use a different logo (URL or local image) |
| `-AlacrittyVersion X.Y.Z` | download a different Alacritty release (default 0.17.0) |
| `-Force` | replace an existing `alacritty.toml` in the config directory |
| `-NoStartMenu` | skip the Start Menu entry |

If PowerShell refuses to run the script, start it with
`powershell -ExecutionPolicy Bypass -File .\install.ps1`.

## How it works

The shortcut runs

```
herdr-terminal.exe --config-file "%APPDATA%\sheepdock\alacritty.toml"
```

and the profile makes herdr the window's shell:

```toml
[terminal.shell]
program = "C:/Users/you/AppData/Local/Programs/Herdr/bin/herdr.exe"
```

Closing herdr closes the window; there is no prompt to fall through to. herdr
sets the window title to the active workspace, which the profile allows.

Three details worth knowing:

**herdr refuses to run nested.** Started from inside a herdr pane the process
inherits that pane's `HERDR_*` variables and herdr aborts with *"nested herdr is
disabled by default"*. `herdr-launch.ps1` drops them before starting the
window. From the taskbar there is nothing to drop.

**The exe is a plain copy of Alacritty.** Alacritty's own config lookup on
Windows only knows `%APPDATA%\alacritty\alacritty.toml`, which is why the
profile is passed explicitly with `--config-file`. If you have an Alacritty
config of your own there, the profile imports it, so colours and key bindings
carry over.

**Fonts go by their DirectWrite family name.** The installer picks
JetBrainsMono Nerd Font Mono if it is installed, else Cascadia Mono, else
Consolas, at 11 pt. Nerd Fonts must be named by their short family name in
`alacritty.toml` (`"JetBrainsMono NFM"`, not `"JetBrainsMono Nerd Font Mono"`);
the long name is not found. Ctrl+V is bound to paste, as in Windows Terminal.

**Updating Alacritty means re-running `install.ps1`.** The portable build is a
single file, and the icon lives inside that file, so a newer Alacritty is
simply downloaded and branded again. Your `alacritty.toml` is kept unless you
pass `-Force`.

## Starting from a shell

`herdr-launch.ps1` takes the same arguments as herdr and opens them in a new
window:

```powershell
& "$env:LOCALAPPDATA\Programs\sheepdock\herdr-launch.ps1" --session scratch
```

From Git Bash:

```sh
pwsh -File "$LOCALAPPDATA/Programs/sheepdock/herdr-launch.ps1"
```

## What it does not touch

Windows Terminal keeps working as before, including any herdr you start there.
herdr itself is not modified; the launcher only points at its executable. An
Alacritty you installed yourself is neither required nor changed.

## Caveats

The portable Alacritty build is downloaded without a signature check; the
installer prints its SHA-256 so you can compare it against the release.

herdr's pane shells are unaffected by all of this. If you use Git Bash as the
pane shell, that stays Git Bash.

## Uninstall

```powershell
.\uninstall.ps1          # removes the exe, icon, launcher and shortcuts
.\uninstall.ps1 -Purge   # also removes %APPDATA%\sheepdock
```

A taskbar pin becomes dead after uninstalling; right-click it and unpin.
