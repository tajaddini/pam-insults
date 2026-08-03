# pam-insults

Print a random insult when authentication fails on Ubuntu 26.04 (and other Debian-family systems that use `pam-auth-update`).

This could be an equivalent of `Defaults insults` in `sudoers`. That option was dropped from `sudo-rs`, which is the default sudo provider on Ubuntu 26.04, so this method   injects the message at the PAM layer instead. As a side effect it works for *any* consumer of `common-auth` (sudo, `su`, `login`, `sshd` with keyboard-interactive), not just sudo.

## How it works

`pam_exec.so` runs a picker script at the end of the `auth` stack. The script writes one line to stdout; `pam_exec`'s `stdout` option relays that line to the user through the PAM conversation.

> The module is registered as a profile in `/usr/share/pam-configs/`, not by hand-editing `/etc/pam.d/common-auth`; as `pam-auth-update` recalculates the `success=N` jump offsets for every other module in the stack whenever the set of installed modules changes. Hand-edited jump arithmetic silently breaks the next time a PAM package is upgraded.

Profile settings:

| Field       | Value              | Reason                                                            |
| ----------- | ------------------ | ----------------------------------------------------------------- |
| `Auth-Type` | `Primary`          | It must sit inside the primary block, not after `pam_deny`.       |
| `Priority`  | `0`                | Lowest priority runs last, i.e. immediately before `pam_deny.so`. |
|  Control    | `[default=ignore]` | The module can never change the auth outcome.                     |

**Example: **  
Resulting `/etc/pam.d/common-auth` on a system with `pam_unix` + `pam_sss`:

```text
auth	[success=3 default=ignore]	pam_unix.so nullok
auth	[success=2 default=ignore]	pam_sss.so use_first_pass
auth	[default=ignore]	pam_exec.so stdout quiet /usr/local/bin/pam-insult /usr/local/share/insults
auth	requisite			pam_deny.so
auth	required			pam_permit.so
```

A successful `pam_unix` jumps 3 modules forward, landing on `pam_permit`, so the insult is skipped. A failure falls through to `pam_exec`, then `pam_deny`.

> The exact `success=N` values depend on which PAM modules are installed. Do not copy them; let `pam-auth-update` generate them.

## Installation

```bash
git clone https://github.com/tajaddini/pam-insults.git
cd pam-insults
sudo ./install.sh
```
the installation script copies the files, sets ownership/permissions, and runs `pam-auth-update --force`.

> Make both scripts executable before committing, so a fresh clone works without a `chmod`:
> ```bash
> chmod +x install.sh uninstall.sh bin/pam-insult
> git add -A && git commit -m "PAM-based random insults on auth failure"
> ```

### ⚠️ Do this before you test

Keep a root shell open in a separate terminal for the whole session:

```bash
sudo -i
```

That session survives a broken PAM stack and is your recovery path. Do not close it until verification passes.

#### Verify

From a **non-root** terminal:

```bash
# 1. Insult on failure
sudo -k && sudo true          # type a wrong password

# 2. Success path is unaffected
sudo -k && sudo true          # type the correct password

# 3. common-auth is shared, so check another consumer
su - "$USER"                  # correct password should succeed

# 4. Inspect the generated stack
cat /etc/pam.d/common-auth
```

If all four behave, close the root shell.

## Adding insults

Drop any `.txt` file into `/usr/local/share/insults/`.
One insult per line.
Blank lines and lines starting with `#` are ignored.

> The picker chooses a random file, then a random line from it — so a file with 5 lines and a file with 500 lines get equal weight. Use one file if you want uniform weighting across all lines.

### Example

```bash
sudoedit /usr/local/share/insults/mine.txt
sudo chmod 644 /usr/local/share/insults/mine.txt
```

No `pam-auth-update` run is needed; files are read at authentication time.

## Enable/disabling this

```bash
sudo pam-auth-update --disable insults
sudo pam-auth-update --enable insults
```

After editing `/usr/share/pam-configs/insults` itself, apply with:

```bash
sudo pam-auth-update --force
```

## Uninstall

```bash
sudo ./uninstall.sh
```

This disables the profile, regenerates the PAM stack, then removes the script,
the profile, and the insults directory.

## Notes and caveats

> **Post-failure delay.** `sudo-rs` sleeps briefly after a failed attempt before printing `Authentication failed`. The insult appears first, then the pause, then sudo's message. The delay is a hardcoded brute-force mitigation in `sudo-rs` and is not configurable via `sudoers`. `passwd_timeout` controls input timeout, not this. I suggest you leave it alone.

> **Graphical logins.** GDM and other greeters may render or discard PAM info messages inconsistently. Behaviour there is cosmetic and not guaranteed.

> **SSH.** The message reaches the client only for keyboard-interactive/password auth. Public-key auth never touches `common-auth`.

> **File ownership is a security boundary.** `pam_exec` runs the picker as root during authentication. 
> Keep the script and the insults directory root-owned and non-group/world-writable. 
> ***The script only prints file contents and it does not evaluate them; a writable insults file would let a local user inject arbitrary bytes, including terminal escape equences, into a root-context output stream. ***
> `install.sh` enforces `755` on directories and the script, `644` on the text files.

> **Never add `expose_authtok`** to the `pam_exec` line. That would pipe the typed password to the script's stdin.

> **Fail-open by design.** The picker exits `0` unconditionally and the control flag is `[default=ignore]`, so a missing directory, empty file, or broken script cannot lock you out.
