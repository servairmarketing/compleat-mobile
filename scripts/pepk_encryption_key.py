#!/usr/bin/env python3
"""Normalise the Play Console encryption key pasted into the pepk-export
workflow's input box, and tell the workflow which pepk mode to use.

The Play Console's "Export and upload a key from Java keystore" page offers
**Download encryption public key** (a file `encryption_public_key.pem`) and
its sample command uses `--rsa-aes-encryption
--encryption-key-path=encryption_public_key.pem`. Older console versions
showed a 136-hex-character string for `--encryptionkey=<hex>` instead. This
script accepts either:

  * the CONTENTS of the .pem file, pasted into GitHub's single-line "Run
    workflow" box — browsers drop or replace the line breaks on that paste,
    so the text is re-wrapped here; the -----BEGIN/END----- lines are
    optional (base64 alone is accepted);
  * the 136-hex string.

It is a PUBLIC key: nothing here is secret. Output:
  * PEM mode: the re-wrapped key is written to <pem-out> (checked with
    `openssl pkey -pubin`), and $GITHUB_ENV gets PEPK_KEY_MODE=pem +
    PEPK_KEY_PEM=<pem-out>;
  * hex mode: $GITHUB_ENV gets PEPK_KEY_MODE=hex + ENCRYPTION_KEY_HEX, and
    the value is masked in the log (::add-mask::) exactly as before.
Exit 1 with a `::error::` the non-coder operator can act on otherwise.

Usage:  PEPK_PASTED_KEY="<raw input>" python3 scripts/pepk_encryption_key.py <pem-out>
"""
import base64
import os
import re
import subprocess
import sys

HELP = ("Open the file encryption_public_key.pem (from the Play Console's "
        "'Download encryption public key') in Notepad or TextEdit, "
        "Edit > Select All, Copy, and paste the whole text into the "
        "encryption_public_key box. It starts with -----BEGIN PUBLIC KEY-----.")


def fail(msg: str) -> int:
    print(f"::error::{msg} {HELP}")
    return 1


def set_env(**kv: str) -> None:
    path = os.environ.get("GITHUB_ENV")
    if not path:                       # local test run
        for k, v in kv.items():
            print(f"[env] {k}={v}")
        return
    with open(path, "a", encoding="utf-8") as fh:
        for k, v in kv.items():
            fh.write(f"{k}={v}\n")


def main() -> int:
    if len(sys.argv) != 2:
        print("usage: pepk_encryption_key.py <pem-out>", file=sys.stderr)
        return 2
    pem_out = sys.argv[1]
    raw = os.environ.get("PEPK_PASTED_KEY", "")
    compact = re.sub(r"\s+", "", raw)
    if not compact:
        return fail("The encryption_public_key box was empty.")

    # --- legacy console form: 4-byte identity + 64-byte P256 point = 136 hex
    if re.fullmatch(r"[0-9a-fA-F]{136}", compact):
        print(f"::add-mask::{compact}")
        set_env(PEPK_KEY_MODE="hex", ENCRYPTION_KEY_HEX=compact)
        print("Encryption key: 136-hex console string -> pepk --encryptionkey mode.")
        return 0

    # --- PEM form (line breaks may have been dropped or turned into spaces)
    m = re.search(r"-{3,}\s*BEGIN\s+([A-Z ]*?)\s*-{3,}(.*?)-{3,}\s*END\s+[A-Z ]*?\s*-{3,}",
                  raw, re.S)
    if m:
        label = re.sub(r"\s+", " ", m.group(1)).strip() or "PUBLIC KEY"
        body = m.group(2)
    elif "BEGIN" in raw.upper() or "END" in raw.upper():
        return fail("The pasted text has a BEGIN/END line but it is incomplete "
                    "or mangled.")
    else:
        label, body = "PUBLIC KEY", raw
    if "PRIVATE" in label.upper():
        return fail("That is a PRIVATE key — stop; never paste a private key "
                    "anywhere. The Play Console gives you a PUBLIC key file.")
    b64 = re.sub(r"\s+", "", body)
    if not re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", b64):
        return fail("The pasted text is not a .pem public key (it contains "
                    "characters that cannot be part of one).")
    try:
        der = base64.b64decode(b64, validate=True)
    except Exception:
        return fail("The pasted text is not a complete .pem public key "
                    "(base64 does not decode) — part of it may be missing.")
    if len(der) < 64:
        return fail("The pasted text is far too short to be the .pem public key.")

    lines = [b64[i:i + 64] for i in range(0, len(b64), 64)]
    pem = f"-----BEGIN {label}-----\n" + "\n".join(lines) + f"\n-----END {label}-----\n"
    fd = os.open(pem_out, os.O_WRONLY | os.O_CREAT | os.O_TRUNC, 0o600)
    with os.fdopen(fd, "w", encoding="utf-8") as fh:
        fh.write(pem)

    r = subprocess.run(["openssl", "pkey", "-pubin", "-in", pem_out, "-noout", "-text"],
                       capture_output=True, text=True)
    if r.returncode != 0:
        os.unlink(pem_out)
        return fail("openssl cannot read the pasted text as a public key "
                    f"({r.stderr.strip().splitlines()[-1] if r.stderr.strip() else 'no detail'}).")
    first = (r.stdout.strip().splitlines() or ["?"])[0].strip()
    set_env(PEPK_KEY_MODE="pem", PEPK_KEY_PEM=pem_out)
    print(f"Encryption key: PEM '{label}' ({len(der)} DER bytes; {first}) "
          f"-> pepk --rsa-aes-encryption --encryption-key-path mode; written to {pem_out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
