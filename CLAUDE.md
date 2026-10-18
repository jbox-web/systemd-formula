# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

This is one of the 32 forks under `salt-formulas/`; the parent `../CLAUDE.md`
covers what they share (toolchain, `bin/kitchen` usage, pre-commit, CI, the
`template-formula` layout, line length and modelines). This file only records
where `systemd-formula` departs from that baseline.

## Commands

One Kitchen suite, `default`, on the three fleet platforms:

```bash
bin/kitchen list                                  # default-debian-13-3008-2, default-debian-13-3006-27, default-debian-11-3006-27
bin/kitchen test default-debian-13-3008-2         # converge + InSpec, then destroy
pre-commit run --all-files                        # same lint as the CI job
```

The containers run systemd as PID 1 (`privileged: true`, `run_command:
/lib/systemd/systemd`), which is what lets the controls assert on enabled and
running units.

## How this formula differs from the template

- **No `package/` / `config/` / `service/` split.** The tree is cut by systemd
  component instead: `journald/`, `networkd/`, `resolved/`, `timesyncd/`,
  `units/`, each an independent entry point. The root `systemd/init.sls` only
  installs packages (`pkg`, `pkgs_libs`, `pkgs_extra`) and includes none of the
  components; each must be targeted by name.
- **`map.jinja` predates `tplroot`.** Paths are the literal `systemd/…`, there
  is no `osarchmap.yaml`, and `defaults.yaml` nests everything under a
  top-level `systemd:` key read with `default='systemd'`. The chain is
  defaults ← `osfamilymap` ← `osmap` ← `osfingermap` ← `systemd:lookup`, then
  `pillar.get('systemd', default=…, merge=True)`. Only `_mapdata/init.sls`
  derives `tplroot`.
- **`systemd.units` bypasses `map.jinja`.** It iterates the raw
  `pillar['systemd']` and treats every key listed in `units/unittypes.yaml`
  (`service`, `timer`, `path`, …) as a unit type, so unit definitions sit
  beside `resolved`, `networkd`, etc. under the same `systemd:` pillar.
  `enabled`, `status` and `dropin` are control keys stripped by
  `units/unit.jinja`; every other key becomes an INI section. `dropin: true`
  writes `/etc/systemd/system/<unit>.<type>.d/salt-override.conf` instead of
  the unit file. Enable/disable and start/stop are declarative `service.*`
  states (only `service` and `path` units get a running/dead state; default is
  enabled + stopped).
- **Two configuration modes per daemon.** `journald`, `resolved` and
  `timesyncd` read `config_source`: `file` renders the TOFS template from
  `<component>/files/default/` through `files_switch(…, lookup=<component>,
  use_subpath=True)`; `pillar` writes keys with `ini.options_present` (strict).
  In pillar mode resolved and timesyncd write a **fixed key list** spelled out
  in their `config.sls` (journald filters against an allow-list), so a new
  option needs a code change, not just a pillar key.
- **networkd has two unrelated states.**
  - `systemd.networkd` installs the package, runs the service and, when no
    `profiles` are set, `file.recurse`s `files/default/network/` onto
    `/etc/systemd/network` with `clean: True` — it wipes any file it does not
    ship.
  - `systemd.networkd.profiles` renders each
    `networkd:profiles:<type>:<name>` pillar entry (a list of single-key
    section dicts) to `/etc/systemd/network/<name>.<type>` through
    `templates/profile.jinja`, with per-file owner/mode from
    `networkd:fileattr`. Only when `networkctl_reload` is true (set by
    `osmap.yaml` for Fedora alone) does it include `systemd.networkd.reload`,
    which pulls in `systemd.networkd` and runs `networkctl reload` on change.
    Otherwise nothing reloads or restarts networkd — a profile change applies
    at the next reboot — and the directory is managed without `clean`, so a
    profile removed from pillar stays on disk.
- **`systemd.reload`** (`systemctl daemon-reload` as a `cmd.wait`) is pulled in
  by `timesyncd` and `units`; states that change unit files `watch_in` it.
- `timesyncd` drops an `allowvirtual.conf` override clearing
  `ConditionVirtualization` on virtual machines and Docker, and removes it on
  physical hosts. The `timezone` pillar key is no longer applied here; the
  timezone belongs to `timezone-formula`.

## Tests

- The `default` suite applies `systemd._mapdata`, `systemd`,
  `systemd.networkd`, `systemd.networkd.profiles`, `systemd.journald`, the
  helper `rsync_test_package` (`test/salt/states/`, provides the binary and
  config the `rsync` unit needs) and `systemd.units`, fed with `pillar.example`
  as the `systemd` pillar. Editing `pillar.example` therefore changes the test
  input, and the InSpec controls assert on its literal values.
- `systemd.resolved` and `systemd.timesyncd` are **not converged by any suite**.
- There are no `_mapdata` reference dumps (`test/integration/default/files/`
  does not exist), so a map default change is not caught by a comparison.
