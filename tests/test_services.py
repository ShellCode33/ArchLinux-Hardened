"""Check installer enablement and exercise sync's read-only service audit."""

import configparser
import os
import pwd
import runpy
import subprocess
import tempfile
import unittest
from collections.abc import Callable
from pathlib import Path
from unittest.mock import patch

REPO = Path(__file__).resolve().parents[1]
SYNC = runpy.run_path(str(REPO / "sync"))
NORMALIZE: Callable[[str], str] = SYNC["unit_name"]
type UnitKey = tuple[str, str]

# Backup destinations, credentials and encryption need manual configuration.
OPTIONAL: dict[UnitKey, str] = {
    (
        "user",
        "backup-to-cloud.timer",
    ): "Opt-in archive backups; see README's manual configuration requirement",
    (
        "user",
        "restic-unattended.timer",
    ): "Opt-in Restic backups; require a configured remote and password file",
}
EXTERNALLY_ACTIVATED: dict[UnitKey, str] = {
    ("system", "usb-auto-mount@.service"): "Started by the USB udev rules, not at boot",
    (
        "system",
        "dirmngr@etc-pacman.d-gnupg.service",
    ): "Socket-activated GnuPG helper supplied by the package",
}


def installer_units(repo: Path) -> set[UnitKey]:
    return {(unit.scope, unit.name) for unit in SYNC["installer_units"](repo)}


def configured_units(paths: list[Path]) -> dict[UnitKey, list[Path]]:
    units: dict[UnitKey, list[Path]] = {}
    for path in paths:
        parts = path.parts
        if parts[:3] != ("rootfs", "etc", "systemd") or len(parts) < 5:
            continue
        scope, name = parts[3:5]
        if scope not in {"system", "user"}:
            continue
        if len(parts) == 6 and name.endswith(".d") and path.suffix == ".conf":
            name = name.removesuffix(".d")
        elif len(parts) != 5:
            continue
        if NORMALIZE(name) == name:
            units.setdefault((scope, name), []).append(path)
    return units


def reachable_units(
    repo: Path, configured: dict[UnitKey, list[Path]], roots: set[UnitKey]
) -> set[UnitKey]:
    reached: set[UnitKey] = set()
    pending = list(roots)
    while pending:
        key = pending.pop()
        if key in reached:
            continue
        reached.add(key)
        scope, name = key
        files = list(configured.get(key, []))
        stem, suffix = name.rsplit(".", 1)
        prefix, separator, instance = stem.partition("@")
        if separator and instance:
            template = (scope, f"{prefix}@.{suffix}")
            reached.add(template)
            files = configured.get(template, []) + files
        # This Also= belongs to Arch's packaged networkd unit, not the overlay.
        if key == ("system", "systemd-networkd.service"):
            pending.append((scope, "systemd-networkd-wait-online.service"))
        settings = configparser.ConfigParser(interpolation=None, strict=False)
        settings.read([repo / path for path in files])
        dependencies: list[str] = []
        for section, option in (
            ("Unit", "Wants"),
            ("Unit", "Requires"),
            ("Unit", "BindsTo"),
            ("Unit", "Upholds"),
            ("Install", "Also"),
        ):
            dependencies.extend(settings.get(section, option, fallback="").split())
        for suffix, section, option in (
            (".timer", "Timer", "Unit"),
            (".path", "Path", "Unit"),
            (".socket", "Socket", "Service"),
        ):
            if name.endswith(suffix):
                default = name.removesuffix(suffix) + ".service"
                dependencies.append(settings.get(section, option, fallback=default))
        pending.extend((scope, NORMALIZE(name)) for name in dependencies)
    return reached


class ServiceTests(unittest.TestCase):
    def test_rootfs_units_are_enabled_or_activated(self) -> None:
        paths = [
            path
            for path in SYNC["git_paths"](REPO, "ls-files", "-z")
            if (REPO / path).exists()
        ]
        configured = configured_units(paths)
        enabled = installer_units(REPO)
        exceptions = OPTIONAL | EXTERNALLY_ACTIVATED
        self.assertFalse(
            exceptions.keys() - configured.keys(), "Remove stale service exceptions"
        )
        reached = reachable_units(REPO, configured, enabled | exceptions.keys())
        missing = sorted(configured.keys() - reached)
        self.assertFalse(
            missing,
            "Rootfs units have no installer enablement or activation: "
            + ", ".join(f"{scope}: {name}" for scope, name in missing),
        )
        rules = (REPO / "rootfs/etc/udev/rules.d/99-usb-auto-mount.rules").read_text()
        self.assertIn("usb-auto-mount@%k.service", rules)

    def test_installer_parser_handles_scopes_instances_and_continuations(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "install").write_text(
                "# arch-chroot /mnt systemctl enable ignored\n"
                "arch-chroot /mnt systemctl enable one two.timer getty@tty1\n"
                "arch-chroot /mnt systemctl --global enable \\\n"
                "    three.service four.socket # comment\n"
                "arch-chroot /mnt systemctl enable --global --now five\n"
                "arch-chroot /mnt systemctl start ignored\n"
            )
            self.assertEqual(
                installer_units(repo),
                {
                    ("system", "one.service"),
                    ("system", "two.timer"),
                    ("system", "getty@tty1.service"),
                    ("user", "three.service"),
                    ("user", "four.socket"),
                    ("user", "five.service"),
                },
            )

    def test_installer_parser_rejects_dynamic_or_unknown_enablement(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            for command in (
                'enable "$unit"',
                "enable --runtime one",
                "--global --system enable one",
                "enable",
            ):
                with self.subTest(command=command):
                    (repo / "install").write_text(
                        f"arch-chroot /mnt systemctl {command}\n"
                    )
                    with self.assertRaises(ValueError):
                        installer_units(repo)

    def test_coverage_detects_omissions_and_timer_activation(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            units = repo / "rootfs/etc/systemd/system"
            units.mkdir(parents=True)
            (units / "job.service").write_text("[Service]\nExecStart=/usr/bin/true\n")
            (units / "job.timer").write_text(
                "[Timer]\nOnBootSec=1min\n[Install]\nWantedBy=timers.target\n"
            )
            paths = [path.relative_to(repo) for path in units.iterdir()]
            configured = configured_units(paths)
            self.assertEqual(
                set(configured), {("system", "job.service"), ("system", "job.timer")}
            )
            self.assertEqual(reachable_units(repo, configured, set()), set())
            reached = reachable_units(repo, configured, {("system", "job.timer")})
            self.assertFalse(configured.keys() - reached)
            wrong_scope = reachable_units(repo, configured, {("user", "job.timer")})
            self.assertEqual(configured.keys() - wrong_scope, configured.keys())

    def test_audit_reports_enablement_without_mutations(self) -> None:
        states = {
            "one.service": (0, "enabled"),
            "two.timer": (1, "disabled"),
            "getty@tty1.service": (0, "enabled"),
            "three.service": (1, "masked"),
            "four.socket": (4, ""),
            "five.service": (0, "enabled-runtime"),
        }
        commands: list[list[str]] = []

        def query(
            command: list[str], **kwargs: object
        ) -> subprocess.CompletedProcess[str]:
            commands.append(command)
            code, state = states[command[-1]]
            return subprocess.CompletedProcess(
                command, code, stdout=state + "\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "install").write_text(
                "arch-chroot /mnt systemctl enable one two.timer getty@tty1\n"
                "arch-chroot /mnt systemctl --global enable three four.socket five\n"
            )
            with (
                patch.object(subprocess, "run", query),
                self.assertLogs("sync", level="INFO") as captured,
            ):
                SYNC["audit_services"](repo, None)
            output = "\n".join(captured.output)
            for anomaly in (
                "two.timer (disabled)",
                "three.service (masked)",
                "four.socket (not-found)",
                "five.service (enabled-runtime)",
            ):
                self.assertIn(anomaly, output)
            self.assertNotIn("one.service (", output)
            self.assertIn("6 units checked, 4 anomalies", output)
            self.assertIn("global user units", output)
            self.assertEqual(len(commands), 6)
            for command in commands:
                self.assertEqual(command[0:2], ["/usr/bin/systemctl", "--root=/"])
                self.assertEqual(command[-2], "is-enabled")
                self.assertEqual(
                    command[2],
                    "--global"
                    if command[-1] in {"three.service", "four.socket", "five.service"}
                    else "--system",
                )

    def test_user_enablement_for_selected_account_suppresses_global_warning(
        self,
    ) -> None:
        calls: list[list[str]] = []

        def query(
            command: list[str], **kwargs: object
        ) -> subprocess.CompletedProcess[str]:
            calls.append(command)
            state = "disabled" if "--global" in command else "enabled"
            return subprocess.CompletedProcess(
                command, 0 if state == "enabled" else 1, stdout=state + "\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "install").write_text(
                "arch-chroot /mnt systemctl --global enable one two\n"
            )
            with (
                patch.object(subprocess, "run", query),
                self.assertLogs("sync", level="INFO") as captured,
            ):
                SYNC["audit_services"](repo, pwd.getpwuid(os.geteuid()).pw_name)
            output = "\n".join(captured.output)
            self.assertNotIn("one.service (", output)
            self.assertNotIn("two.service (", output)
            self.assertIn("2 units checked, 0 anomalies", output)
            self.assertEqual(len(calls), 2)
            self.assertTrue(
                all("--user" in command and "--root=/" in command for command in calls)
            )

    def test_user_query_failure_reports_unchecked(self) -> None:
        def query(
            command: list[str], **kwargs: object
        ) -> subprocess.CompletedProcess[str]:
            if "--user" in command:
                return subprocess.CompletedProcess(
                    command, 1, stdout="", stderr="permission denied"
                )
            return subprocess.CompletedProcess(
                command, 1, stdout="disabled\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "install").write_text(
                "arch-chroot /mnt systemctl --global enable one\n"
            )
            with (
                patch.object(subprocess, "run", query),
                self.assertLogs("sync", level="INFO") as captured,
            ):
                SYNC["audit_services"](repo, pwd.getpwuid(os.geteuid()).pw_name)
            output = "\n".join(captured.output)
            self.assertIn("Cannot check user unit one.service", output)
            self.assertIn("0 units checked, 0 anomalies, 1 unchecked", output)

    def test_enabled_instance_covers_its_template_and_drop_in(self) -> None:
        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            base = repo / "rootfs/etc/systemd/system"
            drop_in = base / "worker@demo.service.d/override.conf"
            drop_in.parent.mkdir(parents=True)
            drop_in.write_text("[Service]\nRestart=on-failure\n")
            template = base / "worker@.service"
            template.write_text("[Service]\nExecStart=/usr/bin/true\n")
            configured = configured_units(
                [template.relative_to(repo), drop_in.relative_to(repo)]
            )
            reached = reachable_units(
                repo, configured, {("system", "worker@demo.service")}
            )
            self.assertFalse(configured.keys() - reached)

    def test_query_failure_does_not_hide_other_unit_anomalies(self) -> None:
        def query(
            command: list[str], **kwargs: object
        ) -> subprocess.CompletedProcess[str]:
            if command[-1] == "one.service":
                raise subprocess.TimeoutExpired(command, 10)
            return subprocess.CompletedProcess(
                command, 1, stdout="disabled\n", stderr=""
            )

        with tempfile.TemporaryDirectory() as directory:
            repo = Path(directory)
            (repo / "install").write_text("arch-chroot /mnt systemctl enable one two\n")
            with (
                patch.object(subprocess, "run", query),
                self.assertLogs("sync", level="INFO") as captured,
            ):
                SYNC["audit_services"](repo, None)
            output = "\n".join(captured.output)
            self.assertIn("Cannot check system unit one.service", output)
            self.assertIn("two.service (disabled)", output)
            self.assertIn("1 units checked, 1 anomalies, 1 unchecked", output)


if __name__ == "__main__":
    unittest.main()
