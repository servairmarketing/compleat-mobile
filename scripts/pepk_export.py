#!/usr/bin/env python3
"""Run Google's pepk.jar non-interactively WITHOUT putting passwords on a
command line.

pepk (Play Encrypt Private Key) asks for the keystore password and, when it
needs one, the key password through java.io.Console — which is null on a CI
runner (no TTY), so a plain pipe into stdin crashes with a
NullPointerException. Its only other option is `--keystore-pass` /
`--key-pass` flags, which would expose the secrets to every process on the
runner through the argument list. This helper does neither: it runs pepk
inside a pseudo-terminal, waits for each password prompt, answers it from an
ENVIRONMENT VARIABLE, and prints pepk's output with the secret values
redacted. Console.readPassword turns echo off before reading, so the
passwords are never written back to the terminal either.

Usage (all pepk flags except the password ones are passed through):
    PEPK_STORE_PASSWORD=... PEPK_KEY_PASSWORD=... \
      python3 scripts/pepk_export.py --jar pepk.jar -- \
        --keystore=release.jks --alias=... --output=out.zip \
        --encryptionkey=<hex> --include-cert

Exit code = pepk's exit code (1 on a bad password / alias / key, 0 on
success). Proven 2026-10-01 in Cloud Shell against throwaway PKCS12 and JKS
keystores (docs/PLAY_INTERNAL_DISTRIBUTION_PLAN_2026-09-28.md §7.5).
"""
import argparse
import os
import pty
import select
import sys


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--jar", required=True, help="path to pepk.jar")
    ap.add_argument("--timeout", type=float, default=300.0,
                    help="seconds of total silence before giving up")
    ap.add_argument("pepk_args", nargs=argparse.REMAINDER,
                    help="pepk flags (after --); must NOT include password flags")
    a = ap.parse_args()
    pepk_args = [x for x in a.pepk_args if x != "--"]
    for x in pepk_args:
        if x.startswith(("--keystore-pass", "--key-pass")):
            print("pepk_export: refusing password flags on the command line; "
                  "use PEPK_STORE_PASSWORD / PEPK_KEY_PASSWORD", file=sys.stderr)
            return 2

    store_pw = os.environ.get("PEPK_STORE_PASSWORD", "")
    key_pw = os.environ.get("PEPK_KEY_PASSWORD", "") or store_pw
    if not store_pw:
        print("pepk_export: PEPK_STORE_PASSWORD is not set", file=sys.stderr)
        return 2
    answers = [store_pw, key_pw]          # prompt order: keystore, then key
    secrets = {s for s in (store_pw, key_pw) if s}

    cmd = ["java", "-jar", a.jar] + pepk_args
    pid, fd = pty.fork()
    if pid == 0:                           # child: becomes pepk on the pty
        os.execvp(cmd[0], cmd)

    buf = b""
    transcript = b""
    sent = 0
    pending = b""                          # text since the last answer
    try:
        while True:
            r, _, _ = select.select([fd], [], [], a.timeout)
            if not r:
                print("pepk_export: no output from pepk for "
                      f"{a.timeout:.0f}s — giving up", file=sys.stderr)
                os.kill(pid, 9)
                break
            try:
                chunk = os.read(fd, 4096)
            except OSError:                # EIO = child closed the pty
                break
            if not chunk:
                break
            transcript += chunk
            pending += chunk
            # A prompt is a line that mentions "password" and has not been
            # terminated by a newline (Console.readPassword blocks there).
            tail = pending.split(b"\n")[-1]
            if sent < len(answers) and b"password" in tail.lower():
                os.write(fd, answers[sent].encode() + b"\n")
                sent += 1
                pending = b""
    finally:
        _, status = os.waitpid(pid, 0)
        os.close(fd)

    out = transcript.decode("utf-8", "replace")
    for s in secrets:                      # belt-and-braces redaction
        out = out.replace(s, "<redacted>")
    sys.stdout.write(out if out.endswith("\n") else out + "\n")
    sys.stdout.flush()
    rc = os.waitstatus_to_exitcode(status)
    print(f"pepk_export: answered {sent} password prompt(s); pepk exit {rc}")
    return rc


if __name__ == "__main__":
    sys.exit(main())
