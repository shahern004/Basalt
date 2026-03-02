#!/usr/bin/env python3

"""
Download and extract https://linuxrepo.rootforest.com/L3H/certs/l3harris_latest.tar.gz
exactly like:
    curl -L -o- <url> | tar -xvz

Requirements
------------
* Python 3.6+
* requests  (install with: pip install requests)

The script streams the download directly into the tarfile module,
so it works even for large archives without using large amounts of RAM.

# TODO remove once we re-build container with lhx certs
"""

import sys
import argparse
import requests
import tarfile
import pathlib
from urllib.parse import urlparse

# ----------------------------------------------------------------------
def download_and_extract(url: str, destination: pathlib.Path) -> None:
    """
    Stream‑download a gzip‑compressed tar archive from *url* and extract it
    into *destination* while printing the names of the extracted members.

    Parameters
    ----------
    url: str
        The HTTP(S) URL of the tar.gz file.
    destination: pathlib.Path
        Directory where the archive will be unpacked.
    """
    # Make sure the destination exists
    destination.mkdir(parents=True, exist_ok=True)

    # ``allow_redirects=True`` mirrors curl's ``-L`` behaviour.
    with requests.get(url, stream=True, allow_redirects=True) as resp:
        resp.raise_for_status()               # abort on HTTP errors
        # ``resp.raw`` is a file‑like object that yields the streamed bytes.
        # Using mode "r|gz" lets tarfile read the gzip stream incrementally.
        with tarfile.open(fileobj=resp.raw, mode="r|gz") as tar:
            for member in tar:
                # Print the member name – this is the “verbose” part.
                print(member.name)
                # Extract the member safely (prevents path traversal attacks).
                safe_extract(tar, member, path=destination)

# ----------------------------------------------------------------------
def safe_extract(tar: tarfile.TarFile, member: tarfile.TarInfo,
                 *, path: pathlib.Path) -> None:
    """
    Extract a *member* from *tar* into *path* while protecting against
    absolute paths or ``..`` components that could escape the target directory.
    """
    # Resolve the final path of the member
    member_path = path / member.name
    # Ensure the resolved path stays within the destination folder
    if not pathlib.Path(member_path).resolve().is_relative_to(path.resolve()):
        raise Exception(f"Attempted Path Traversal in Tar File: {member.name}")

    # Perform the actual extraction
    tar.extract(member, path=path)

# ----------------------------------------------------------------------
def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download a tar.gz file and extract it (Python equivalent of "
                    "`curl -L -o- <url> | tar -xvz`)."
    )
    parser.add_argument(
        "url",
        help="URL of the tar.gz archive to download."
    )
    parser.add_argument(
        "-d", "--dest",
        type=pathlib.Path,
        default=pathlib.Path("."),
        help="Directory where files will be extracted (default: current directory)."
    )
    return parser.parse_args()

# ----------------------------------------------------------------------
def main() -> int:
    args = parse_args()
    try:
        download_and_extract(args.url, args.dest)
        return 0
    except Exception as exc:          # pragma: no cover – user‑visible error handling
        print(f"Error: {exc}", file=sys.stderr)
        return 1

# ----------------------------------------------------------------------
if __name__ == "__main__":
    sys.exit(main())
