# Working on ArchLinux-Hardened

## Purpose and scope

This repository describes a personal, hardened Arch Linux installation. It serves both as a reinstall recipe and as public configuration for others to adapt. Preserve reproducibility, security, and day-to-day usability together.

The checkout may be on the owner's running workstation. Treat the host as a real machine with valuable data, not as a disposable development environment. Repository files, installed files, and upstream package defaults can differ intentionally; investigate before choosing which to change.

Keep changes focused on the request. Do not create extra files or documentation unless requested; when a requested feature requires new files, keep them minimal. Avoid introducing dependencies, containers, services, abstractions, or test infrastructure when existing tools suffice. Explain material choices and limitations briefly.

## Start with the relevant sources

| Location                           | Responsibility                                                                                                                            |
| ---------------------------------- | ----------------------------------------------------------------------------------------------------------------------------------------- |
| `install.sh`                       | Destructive fresh installation from an Arch environment: storage, packages, boot, users, rootfs deployment, and service enablement.       |
| `packages/regular`, `packages/aur` | Selected install-time packages, one package name per line with optional comments. Hardware-dependent additions also live in `install.sh`. |
| `rootfs/`                          | Overlay for the target filesystem: `rootfs/etc/...` maps to `/etc/...`, and likewise for other paths.                                     |
| `rootfs/usr/local/bin/`            | Maintenance scripts, notifications, and command wrappers; many scripts have no extension.                                                 |
| `rootfs/etc/systemd/`              | System/user services, timers, overrides, and network configuration.                                                                       |
| `sync`                             | Typed, standard-library Python tool for previewing/applying tracked rootfs content and auditing drift.                                    |
| `dev`, `.pre-commit-config.yaml`   | Local lint/format entry point and pinned tools used by CI.                                                                                |
| `.github/workflows/lint.yml`       | Runs the same `./dev lint` command on GitHub.                                                                                             |
| `iso/build`, `iso/start-install`   | Official ISO remastering/release checks and the live-session launcher that clones the latest installer.                                   |
| `.github/workflows/iso.yml`        | Polls Arch releases, builds and boot-tests the customized ISO, and publishes it to GitHub Releases.                                       |
| `docs/`                            | Installation guidance, threat model, networking, and operational notes. Verify older guidance against current code and upstream behavior. |
| `~/.dotfiles`                      | Separate Git repository for user configuration, linked into the home directory by its own installer.                                      |

Before editing:

1. Inspect `git status --short` and the relevant diffs. Preserve existing user work, including untracked files.
2. Read the code/configuration involved and any more specific `AGENTS.md` instructions. Use `rg --hidden` or `git ls-files` when searching dotfiles.
3. For reconciliation work, inspect the live counterpart, symlink target, package owner/default, and relevant service state. Do not assume an installed file matches either Git or the package.
4. If user configuration is involved, inspect `~/.dotfiles` as a separate checkout. Run its checks and commits there. This guide is not automatically discovered by agents working in that sibling repository.

Use non-login shells for automated commands. The user's `.profile` starts the interactive shell or graphical session; do not source it to obtain environment variables. Resolve symlinks before editing `~/.config` or `~/.local/bin`: many point directly into `~/.dotfiles`, and changes can take effect immediately.

## Protect the running installation

- Never execute or source `install.sh` as a test. It unmounts filesystems, overwrites disks, partitions, encrypts, and installs the OS. Use static checks; exercise installation behavior only in an explicitly authorized disposable VM/disk.
- Do not run `~/.dotfiles/install.sh` as a harmless refresh. Its link function removes existing destinations recursively before replacing them with symlinks, and the script performs other setup actions. Make targeted changes instead.
- A repository-edit request does not automatically authorize applying all rootfs changes, upgrading packages, restarting unrelated services, changing boot configuration, or rebooting. For an authorized live fix, inspect the specific change first and apply only the necessary scope. Do not repeatedly request permission already granted; respect tool/sandbox approval requirements.
- Never relax firewall policy, sandboxing, file permissions, or service privileges merely to make a command or check pass. Diagnose the actual access/network requirement.
- Keep credentials, tokens, private keys, account databases, generated diffs containing private data, and personal event details out of Git and command output. Inspect only the data needed for the task; report counts/status rather than secrets.
- Do not remove packages, erase container volumes, overwrite user data, or rewrite unrelated Git history as incidental cleanup.

For reusable rootfs files, retain `username_placeholder` where the installer and `sync` substitute the selected user. Avoid introducing machine-specific usernames, device paths, or home directories without a deliberate reason. If a change affects both fresh installation and an existing system, account for both paths and report which has actually been validated.

## Preserve the sync contract

Read `sync` before changing it. Its existing behavior is intentional:

- `./sync` and `./sync --dry-run` preview only. Apply requires root and `--apply`; `--yes` bypasses its confirmation. Do not use apply mode for validation.
- Selection is restricted to Git-tracked/indexed paths under `rootfs/`; content comes from the working tree, including uncommitted edits and staged additions. Untracked rootfs files are ignored with warnings. It does not sync the dotfiles repository.
- Package differences, removed-but-still-live configurations, and package permission differences are warnings, never automatic repairs. Package audits distinguish explicit installations from dependencies and account for installer-conditional packages.
- For a formerly tracked, package-owned file, the expected fallback is the installed package's default content, checked using its local mtree manifest. Its continued existence alone is not an error. Unowned leftovers are reported separately.
- Unprivileged preview continues past unreadable files, reports the unchecked count, and exits nonzero for an incomplete preview. Do not weaken permissions to avoid this. Apply must finish planning successfully before writing files.
- Diffs are written to a private temporary `.diff` file and its path is logged. Leave viewing to the user; do not restore automatic pager launching.
- Content updates preserve existing ownership, modes, and extended attributes. Retain symlink safeguards, destination-change detection, and atomic replacement of each file. This is not a transaction across all files.
- Keep the implementation standard-library-only, properly typed, and executable as `sync` without a filename extension. Preserve readable `[sync] [LEVEL]` logging and terminal-aware colors.

For changes to these behaviors, use temporary fixtures and mocked filesystem/package responses. Never test apply logic against real `/etc` files. A privileged preview can be appropriate for an authorized system comparison, but an ordinary lint run does not require it.

## Packages, network access, and services

- Add deliberately selected applications to the appropriate package list. Do not copy every installed package or its transitive dependencies into the installer. Use Arch package names, which can differ from commands: `rg` is provided by `ripgrep`.
- Keep hardware-specific packages conditional in the installer. Check the package audit in `sync` when changing how those additions are expressed.
- Prefer existing tools and rootless Podman for isolated applications where practical. A minimal host package is also acceptable when justified by the requested task. Do not create a custom image by default when an existing container or host tool can do the work.
- For read-only package queries, use `/usr/bin/pacman` explicitly. The installed `/usr/local/bin/pacman` wrapper can treat `-S...` queries as installation attempts and prompt. Do not bypass installation safeguards to mutate the host, and do not recommend partial Arch upgrades.
- Outbound networking is restricted intentionally. The local Glider HTTP proxy listens on `127.0.0.1:8080`; use `proxify COMMAND` or command-scoped proxy variables when needed. Keep loopback traffic out of the proxy. Consult `docs/NETWORKING.md`, `docs/PROXY.md`, and the actual nftables/service configuration before changing network behavior.
- Distinguish system and user systemd managers. A user unit cannot order itself after a system service by naming it in `After=`. Use a bounded readiness check for cross-manager dependencies when required; `After=` alone also does not establish application readiness.
- Rootless Quadlets live in `~/.dotfiles/.config/containers/systemd`, linked into the user's config. Edit the source units, not generated services. Preserve first-login activation; a fresh-install chroot does not have a working user service bus.
- Consider proxy access separately for image builds and running containers. Keep localhost-only published services local, preserve user ownership of mounted data, and avoid unnecessary host networking or privileges.
- Rolling images in convenience aliases are intentional. Lint/format tool versions are pinned intentionally. Do not apply one policy indiscriminately to the other.

## Local and CI validation

Run from the repository being changed:

```sh
./dev format path/to/changed-file
./dev lint path/to/changed-file
./dev lint
git diff --check
```

`uv` is the local prerequisite. `dev` requests the pinned Python/pre-commit versions; `.pre-commit-config.yaml` selects tool versions and file coverage. On this hardened host, a first run may need `proxify ./dev lint` to download tool environments. Once cached, checks normally run without downloads. CI invokes `./dev lint` as well.

Important details:

- With no file arguments, the commands operate on tracked files. Pass new untracked files explicitly until they are staged; otherwise a green run can miss them. Do not stage unrelated files just to run checks.
- `format` writes changes, including Ruff's safe fixes; `lint` checks without fixing. Review the resulting diff for behavior changes. Prefer targeted formatting for a small task rather than unrelated repository-wide churn.
- Ruff handles Python, including extensionless scripts identified by their shebangs. ShellCheck covers supported shell dialects; shfmt handles shell formatting. Do not pretend ShellCheck supports Zsh: the dotfiles suite uses shfmt's Zsh parser.
- Prettier, Taplo, actionlint, EditorConfig checks, and conflict-marker checks cover additional files. The dotfiles suite also includes StyLua, XML formatting, and Hadolint. Consult the actual hook selection before claiming coverage.
- Keep local and CI versions aligned. Update the relevant pins and runtime requirements together, preserve pinned Action revisions, and verify the chosen releases. Do not substitute whatever linter version happens to be on the host.
- Do not weaken rules or exclude a failing file just to make CI green. Fix defects; use narrow, explained exceptions for intentional constructs. Preserve the bundled-theme exclusion in dotfiles and intentional control characters in system configuration.
- Lint success does not prove service behavior, firewall validity, bootability, or Python type correctness. Use focused additional validation appropriate to the change. For scripts, avoid imports/execution with top-level side effects; use syntax checks, mocks, or temporary fixtures. Do not add tests that merely repeat the implementation.

If tools are unavailable or checks are blocked, report the exact limitation and checks actually performed. Do not claim validation based solely on inspection.

## Installer ISO

The ISO workflow follows official Arch releases and embeds only `iso/start-install`. The launcher clones this repository's current default branch at installation time. Do not embed a checkout or pin the installer revision. Official ISO versions used to identify release assets are independent of this policy.

`iso/build check` queries Arch metadata and skips completed GitHub releases. Scheduled runs retry missing, draft, or incomplete releases; manual runs can force a rebuild. `iso/build build --work-dir /tmp/iso-work --output /tmp/iso-output` downloads the latest official ISO, verifies its checksum and signing fingerprint, and remasters it using `xorriso`, `mtools`, and GnuPG. Preserve the compressed live filesystem, volume UUID, BIOS boot configuration, and appended EFI partition. Fail on unsupported upstream layouts rather than publishing an unverified adaptation.

`iso/build test IMAGE` boots a diskless, offline BIOS VM; add `--firmware PATH_TO_OVMF_CODE` for UEFI, with the matching OVMF_VARS file beside it. A dedicated virtio channel makes the launcher exit before package updates, cloning, or installation. Keep this safeguard intact. Boot smoke tests validate reaching the launcher, not successful OS installation. Release publishing follows successful lint and both boot tests. Do not publish manually or push the workflow unless requested.

## Git and handoff

When asked to commit, review the final diff and create small, cohesive commits. Keep commits within their owning repository; separate package selection, behavior changes, and broad mechanical formatting when that improves reviewability. Stage explicit paths or reviewed hunks, preserving unrelated staged/unstaged work and untracked drafts. Never add generated logs, caches, credentials, or scratch files.

Do not push unless requested. Report the change's purpose, checks performed, material limitations, and commit IDs when applicable. Distinguish a repository change from a live change, and state any required reload, restart, or user action. Keep this guide accurate when changing the workflow or one of the contracts it documents.
