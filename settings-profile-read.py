#!/usr/bin/env python3
"""Read a bounded local profile selected in the settings panel."""

import json
from pathlib import Path
import sys
from urllib.parse import unquote, urlsplit


LIMIT = 64 * 1024


def reject_constant(_value):
    raise ValueError("Invalid JSON number")


def read_profile(url):
    parsed = urlsplit(url)
    if parsed.scheme != "file" or parsed.netloc not in ("", "localhost"):
        raise ValueError("Выберите локальный JSON-файл.")
    path = Path(unquote(parsed.path))
    if not path.is_absolute() or not path.is_file():
        raise ValueError("Файл профиля недоступен.")
    with path.open("rb") as stream:
        data = stream.read(LIMIT + 1)
    if len(data) > LIMIT:
        raise ValueError("Файл профиля больше 64 КБ.")
    try:
        return json.loads(data.decode("utf-8-sig"), parse_constant=reject_constant)
    except (ValueError, RecursionError):
        raise ValueError("Не удалось прочитать JSON профиля.") from None


if __name__ == "__main__":
    try:
        document = read_profile(sys.argv[1])
        print(json.dumps({"document": document}, ensure_ascii=False, allow_nan=False))
    except (OSError, ValueError) as error:
        print(json.dumps({"error": str(error)}, ensure_ascii=False))
