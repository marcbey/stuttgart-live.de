#!/usr/bin/env python3
"""Collect GitHub-hosted screenshots from issue or comment text for Codex."""

from __future__ import annotations

import argparse
import json
import mimetypes
import re
import sys
from pathlib import Path
from typing import Iterable
from urllib.parse import urlparse
from urllib.request import Request, urlopen


ALLOWED_HOSTS = {
    "github.com",
    "raw.githubusercontent.com",
    "user-images.githubusercontent.com",
    "private-user-images.githubusercontent.com",
    "media.githubusercontent.com",
    "avatars.githubusercontent.com",
}

IMAGE_MARKDOWN_RE = re.compile(r"!\[[^\]]*]\(([^)\s]+)(?:\s+\"[^\"]*\")?\)")
IMAGE_HTML_RE = re.compile(r"<img[^>]+src=[\"']([^\"']+)[\"']", re.IGNORECASE)
URL_RE = re.compile(r"https?://[^\s<>()]+")

MAX_IMAGES = 4
MAX_BYTES = 15 * 1024 * 1024


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser(
        description="Download GitHub-hosted screenshots referenced in text files."
    )
    parser.add_argument(
        "--source-file",
        dest="source_files",
        action="append",
        required=True,
        help="Text file to scan for image URLs. May be provided multiple times.",
    )
    parser.add_argument(
        "--output-dir",
        required=True,
        help="Directory where downloaded images should be written.",
    )
    parser.add_argument(
        "--metadata-file",
        required=True,
        help="Path for a JSON metadata file describing downloaded images.",
    )
    return parser.parse_args()


def extract_urls(text: str) -> list[str]:
    matches: list[str] = []
    matches.extend(IMAGE_MARKDOWN_RE.findall(text))
    matches.extend(IMAGE_HTML_RE.findall(text))
    matches.extend(URL_RE.findall(text))

    urls: list[str] = []
    seen: set[str] = set()

    for raw_url in matches:
      url = raw_url.strip().strip(".,);]")
      if url.startswith("<") and url.endswith(">"):
          url = url[1:-1]
      if url in seen:
          continue
      seen.add(url)
      urls.append(url)

    return urls


def allowed_image_url(url: str) -> bool:
    parsed = urlparse(url)
    return parsed.scheme == "https" and parsed.netloc in ALLOWED_HOSTS


def iter_candidate_urls(source_files: Iterable[Path]) -> list[str]:
    urls: list[str] = []
    seen: set[str] = set()

    for path in source_files:
        text = path.read_text(encoding="utf-8")
        for url in extract_urls(text):
            if not allowed_image_url(url) or url in seen:
                continue
            seen.add(url)
            urls.append(url)

    return urls[:MAX_IMAGES]


def extension_for(content_type: str, url: str) -> str:
    guessed = mimetypes.guess_extension(content_type.split(";", 1)[0].strip())
    if guessed:
        return guessed

    suffix = Path(urlparse(url).path).suffix
    if suffix:
        return suffix

    return ".img"


def download_image(url: str, destination: Path) -> tuple[bool, str]:
    request = Request(url, headers={"User-Agent": "stuttgart-live-codex-workflow/1.0"})

    try:
        with urlopen(request, timeout=20) as response:
            content_type = response.headers.get("Content-Type", "")
            if not content_type.startswith("image/"):
                return False, f"Skipped non-image URL: {url}"

            content_length = response.headers.get("Content-Length")
            if content_length and int(content_length) > MAX_BYTES:
                return False, f"Skipped oversized image (>15 MB): {url}"

            payload = response.read(MAX_BYTES + 1)
            if len(payload) > MAX_BYTES:
                return False, f"Skipped oversized image (>15 MB): {url}"

            destination.write_bytes(payload)
            return True, content_type
    except Exception as error:  # pragma: no cover - defensive workflow utility
        return False, f"Failed to download {url}: {error}"


def main() -> int:
    args = parse_args()
    source_files = [Path(path) for path in args.source_files]
    output_dir = Path(args.output_dir)
    metadata_file = Path(args.metadata_file)
    output_dir.mkdir(parents=True, exist_ok=True)

    image_paths: list[str] = []
    notes: list[str] = []

    for index, url in enumerate(iter_candidate_urls(source_files), start=1):
        ok, detail = download_image(url, output_dir / f"image-{index}")
        if not ok:
            notes.append(f"- {detail}")
            continue

        content_type = detail
        downloaded = output_dir / f"image-{index}"
        final_path = downloaded.with_suffix(extension_for(content_type, url))
        downloaded.rename(final_path)

        rel_path = final_path.as_posix()
        image_paths.append(rel_path)
        notes.append(f"- {rel_path} (downloaded from {url})")

    if not notes:
        notes.append("- No GitHub-hosted screenshots were detected in the provided text.")

    metadata_file.parent.mkdir(parents=True, exist_ok=True)
    metadata_file.write_text(
        json.dumps({"image_paths": image_paths, "notes": "\n".join(notes)}, ensure_ascii=False, indent=2),
        encoding="utf-8",
    )

    return 0


if __name__ == "__main__":
    sys.exit(main())
