# kakikomi

Guidance for anyone, human or agent, changing kakikomi. What kakikomi is and how to use it lives in [README.md](README.md).

[FAMILY.md](FAMILY.md) holds everything kakikomi shares with the rest of the kodougu family, and it is the same in every member. This file holds only what is exclusive to kakikomi, under the same headings as the agent guide of every member. Read both before changing anything; a rule that would serve the other members goes into `FAMILY.md` instead of here.

## Layout

| Path | Holds |
|:-----|:------|
| [`bin/kakikomi`](bin/kakikomi) | The entry point: usage, options, the menu and the write flow |
| [`lib/`](lib) | The modules. [`lib/state.sh`](lib/state.sh) declares every global |
| [`man/kakikomi.1`](man/kakikomi.1) | The man page |
| [`completions/`](completions) | bash, zsh and fish completions |
| [`test/`](test) | The `bats` suite, its helpers, the golden transcripts and their normalizer, the fake `sudo` and the Linux container script |
| [`scripts/`](scripts) | Coverage, the coverage gate, the Linux coverage run and the name check, which `make` runs |
| [`.github/scripts/`](.github/scripts) | The toolset helper and the release version stamp, which only CI and the release run |

## Names

- Globals carry `DISK_`; function-scoped variables carry a per-function `disk_` prefix. kiyome uses the same names, see Domain rules.
- Settings come from `KAKIKOMI_<NAME>`, such as `KAKIKOMI_VERIFY` or `KAKIKOMI_JSON`; test switches are `KAKIKOMI_TERMINAL`, `KAKIKOMI_TEST_SHELLS` and `KAKIKOMI_TEST_RECORD`.
- Output goes through `disk_info`, `disk_say`, `disk_error` and `disk_warning`.

## Behaviour

- kakikomi has several jobs, so a bare `kakikomi` on a terminal opens the menu.
- `kakikomi format` takes the same options as a write, since a format is written and verified the same way.
- `kakikomi release` removes the mount guards an interrupted run left behind.
- `--json` reports the image, its size and SHA-256, and for each target whether it was written and verified. Parallel writes record each target's result in the run's work folder, and the object is printed once every target finished.

## Domain rules

- kiyome is the closest sibling. Both keep the same `disk_` function names in [`lib/`](lib), and a fix to a shared helper, such as the option parser in [`lib/cli.sh`](lib/cli.sh) or the drive fault handling in [`lib/io.sh`](lib/io.sh), lands in both repositories.
- Tests write real file-backed disks attached with `hdiutil` or `losetup`; in the container, `dmsetup` injects I/O errors, so the container runs privileged.
- The bytes a `dd` moved come from its bytes line. BusyBox's `dd` prints only its record counts, so there the count is the whole records out times the block size, and a partial record leaves the move short.
- A transfer past its deadline exits 124 from GNU and uutils `timeout`, and 143 from BusyBox's, which also means a terminate signal. A 143 counts as a deadline only when the transfer ran at least its limit.
- 7-Zip is `7z` from apt's `7zip` and Homebrew's `p7zip`, and `7zz` from Homebrew's `sevenzip`; kakikomi takes whichever it finds, `7z` first.

## Release

- `KAKIKOMI_VERSION` lives in [`lib/core.sh`](lib/core.sh).
- The tap's `Formula/kakikomi.rb` depends on `mtools` and `wimlib`.

## Gaps against FAMILY.md

None (as of 2026-10-30).
