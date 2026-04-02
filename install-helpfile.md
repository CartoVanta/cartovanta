# cartovanta installer

Install `cartovanta` command-line tool and a starter-pack of subcommands.

## Usage

- `install.pl [--help]`
- `install.pl [--systemwide] [--fakeroot DIR] [--bindir DIR] [--cartovanta-bindir DIR]`

## Options

- `--bindir DIR` — Set the installation directory for ordinary command-line executables.
- `--cartovanta-bindir DIR` — Set the installation directory for CartoVanta subcommand executables and static-resource directories.
- `--systemwide` — Install using systemwide defaults rather than per-user defaults.
- `--fakeroot DIR` — Perform a systemwide-style installation under `DIR`. Paths such as `/usr/local/bin` are installed beneath that directory instead of on the live system.
- `--help` — Show this help.

## Description

This program installs the core `cartovanta` command-line tool as well as a small starter pack of subcommands.

By default, installation is intended for a single user.
If `--systemwide` is specified, the installer uses systemwide installation behavior instead.

Any pathname supplied for an option must be absolute unless that option explicitly says otherwise.

## Known Dependencies.

This package needs `perl` -- as its core, its installers (including glue code), and several subcommands are written in `perl`.

This package requires ImageMagick as a number of subcommands, some directly some indirectly, make use of it.

This package _temporarily_ needs `swift` for the `textdeck` subcommand -
though that subcommand has been deprecated and probably won't work outside the Mac environment anyway. So really, you won't need `swift` unless you want to support a deprecated subcommand that only works on one platform anyway.

## Notes

If `--systemwide` is used, the installer must be run with effective root privileges.
