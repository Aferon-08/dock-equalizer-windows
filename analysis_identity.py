"""Version and provenance for a locally generated analysis, without storing paths."""
import hashlib
import json

REVISION = 4


def digest(value):
    return hashlib.sha256(json.dumps(value, sort_keys=True, ensure_ascii=False,
        separators=(",", ":"), allow_nan=False).encode()).hexdigest()


def file_stamp(path):
    try:
        stat = path.stat()
        return [stat.st_size, stat.st_mtime_ns, stat.st_ctime_ns]
    except FileNotFoundError:
        return None


def file_hash(path):
    with path.open("rb") as handle:
        return hashlib.file_digest(handle, "sha256").hexdigest()


def model_snapshot(files):
    return digest({name: file_stamp(path) for name, path in files.items()})


def fingerprint(audio, lyrics, reference, models, settings):
    model_key = model_snapshot(models)
    inputs = {
        "audio": file_hash(audio), "audioStamp": file_stamp(audio),
        "text": digest(lyrics.strip().replace("\r", "")),
        "reference": digest(reference) if reference else None,
        "modelSnapshot": model_key,
        "models": {name: file_hash(path) if path.is_file() else None for name, path in models.items()},
        "settings": settings,
    }
    if model_snapshot(models) != model_key:
        raise ValueError("Модели изменились во время подготовки анализа. Повторите расчёт.")
    key = digest({name: value for name, value in inputs.items() if name not in ("audioStamp", "modelSnapshot")})
    return {**inputs, "key": key}


def state(document, evidence, multivoice):
    if multivoice and evidence.get("status") == "failed":
        return "failed"
    if document.get("fallbackLines") or (multivoice and (
            evidence.get("status") == "unavailable" or evidence.get("budgetLimited") is True
            or evidence.get("fullScan") is not True)):
        return "partial"
    if any(word.get("status") == "review" or word.get("voiceReviewRequired") is True
            for word in document.get("words", [])) or (multivoice and evidence.get("status") == "uncertain"):
        return "review"
    return "complete"
