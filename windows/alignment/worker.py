"""Prepare and run the isolated CPU word aligner for Sekai Soundbar."""

from contextlib import redirect_stdout
from hashlib import file_digest, sha256
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tarfile
import unicodedata
from urllib.error import URLError
from urllib.request import urlopen
import wave


VERSION = 1
ROOT = Path(__file__).resolve().parent
PROTOCOL = sys.stdout
MODEL_SHA = "ed3a0b6b1c0edf879ad9b11b1af5a0e6ab5db9205f891f668f8b0e6c6326e34e"
MODEL_URL = f"https://openaipublic.azureedge.net/main/whisper/models/{MODEL_SHA}/base.pt"
SOURCES = (
    ("stable_whisper", "stable_ts-2.19.1",
     "https://files.pythonhosted.org/packages/94/d9/d326f9dbbb7da6806aa8cfc080342e5f78dc33552f4339bdc8a6251d11a3/stable_ts-2.19.1.tar.gz",
     "0ecaf1ed93e029839569618d2da9a57b883ad04db21f0680146e0650caaf4f52"),
    ("whisper", "openai_whisper-20250625",
     "https://files.pythonhosted.org/packages/35/8e/d36f8880bcf18ec026a55807d02fe4c7357da9f25aebd92f85178000c0dc/openai_whisper-20250625.tar.gz",
     "37a91a3921809d9f44748ffc73c0a55c9f366c85a3ef5c2ae0cc09540432eb96"),
)
SAMPLE_RATE = 16000


def emit(job, **event):
    print(json.dumps(dict(version=VERSION, id=job, **event), ensure_ascii=False, allow_nan=False),
          file=PROTOCOL, flush=True)


def download(url, destination, expected_hash, limit):
    digest = sha256()
    size = 0
    with urlopen(url, timeout=35) as response, destination.open("xb") as output:
        if not response.geturl().startswith("https://"):
            raise ValueError("Адрес загрузки обработчика должен использовать HTTPS.")
        while data := response.read(1024 * 1024):
            size += len(data)
            if size > limit:
                raise ValueError("Загруженный файл превышает ожидаемый размер.")
            digest.update(data)
            output.write(data)
    if digest.hexdigest() != expected_hash:
        raise ValueError("Контрольная сумма загруженного файла не совпадает.")


def prepare(runtime, work, progress):
    staged = work / "runtime"
    model = staged / "models/base.pt"
    model.parent.mkdir(parents=True)
    progress("model", .05)
    try:
        download(MODEL_URL, model, MODEL_SHA, 175 * 1024 * 1024)
    except (URLError, TimeoutError) as error:
        raise ValueError("Не удалось скачать Whisper base. Повторите подготовку при доступе к серверу OpenAI.") from error

    progress("dependencies", .36)
    packages = staged / "packages"
    try:
        subprocess.run([sys.executable, "-I", "-m", "pip", "--isolated",
                        "--disable-pip-version-check", "--no-cache-dir", "install",
                        "--no-input", "--no-index", "--no-deps", "--require-hashes",
                        "--only-binary", ":all:", "--target", str(packages),
                        "-r", str(ROOT / "cpu-windows.lock")],
                       stdin=subprocess.DEVNULL, stdout=sys.stderr, check=True, timeout=1500)
    except (subprocess.SubprocessError, OSError) as error:
        raise ValueError("Не удалось установить CPU-зависимости. Проверьте подключение и свободное место.") from error

    for module, name, url, digest in SOURCES:
        archive = work / (name + ".tar.gz")
        download(url, archive, digest, 4 * 1024 * 1024)
        extracted = work / name
        with tarfile.open(archive) as source:
            source.extractall(extracted, filter="data")
        tree = extracted / name
        shutil.copytree(tree / module, packages / module)
        for notice in tree.glob("LICENSE*"):
            shutil.copyfile(notice, packages / f"{name}-{notice.name}")

    progress("checking", .95)
    # Release imported DLLs before moving the completed runtime on Windows.
    check = ("import os, sys; dlls = os.add_dll_directory(sys.argv[1]); sys.path.insert(0, sys.argv[1]); "
             "import stable_whisper, torch; assert torch.version.cuda is None")
    try:
        subprocess.run([sys.executable, "-I", "-c", check, str(packages)], stdin=subprocess.DEVNULL,
                       stdout=sys.stderr, check=True, timeout=120)
        subprocess.run([str(ffmpeg_path(packages)), "-version"], stdin=subprocess.DEVNULL,
                       stdout=sys.stderr, check=True, timeout=15)
    except (subprocess.SubprocessError, OSError) as error:
        raise ValueError("Не удалось запустить CPU-обработчик или FFmpeg.") from error
    (staged / "ready.json").write_text(json.dumps({"version": VERSION, "model": MODEL_SHA}), encoding="utf-8")
    previous = work / "previous-runtime"
    if runtime.exists():
        runtime.rename(previous)
    try:
        staged.rename(runtime)
    except OSError:
        if previous.exists():
            previous.rename(runtime)
        raise


def ffmpeg_path(packages):
    decoder = next((packages / "imageio_ffmpeg/binaries").glob("ffmpeg-win-x86_64-*.exe"), None)
    if decoder is None:
        raise ValueError("В модуле отсутствует FFmpeg для Windows x64.")
    return decoder


def decode(audio, work, packages):
    before = audio.stat()
    wave_file = work / "decode.wav"
    try:
        subprocess.run([str(ffmpeg_path(packages)), "-nostdin", "-v", "error",
                        "-protocol_whitelist", "file,pipe", "-i", str(audio), "-t", "1801",
                        "-vn", "-ac", "1", "-ar", str(SAMPLE_RATE), "-c:a", "pcm_s16le", str(wave_file)],
                       stdin=subprocess.DEVNULL, stdout=sys.stderr, check=True, timeout=120)
    except (subprocess.SubprocessError, OSError) as error:
        raise ValueError("Не удалось прочитать аудио. Выберите обычный MP3, FLAC, WAV или M4A.") from error
    after = audio.stat()
    if (before.st_size, before.st_mtime_ns) != (after.st_size, after.st_mtime_ns):
        raise ValueError("Аудиофайл изменился во время чтения. Повторите расчёт.")
    with wave.open(str(wave_file), "rb") as stream:
        duration = stream.getnframes() / SAMPLE_RATE
        if not 0 < duration <= 1800:
            raise ValueError("Поддерживаются записи длительностью до 30 минут.")
        return stream.readframes(stream.getnframes()), duration


def lexical(text):
    return "".join(character for character in unicodedata.normalize("NFKC", text).casefold() if character.isalnum())


def timings(result, text, duration):
    words = []
    for index, segment in enumerate(result.to_dict().get("segments", []) if result else []):
        for item in segment.get("words", []):
            word = item["word"].strip()
            if not lexical(word):
                continue
            start = round(float(item["start"]), 3)
            end = round(min(float(item["end"]), duration), 3)
            if not 0 <= start < end <= duration + .001:
                raise ValueError("Часть слов не удалось привязать к аудио. Проверьте запись и текст.")
            words.append(dict(word=word, line=index, start=start, end=end,
                              status="review" if end - start < .04 or end - start > 5 else "estimated"))
    if not words or len(words) > 10000 or lexical(" ".join(item["word"] for item in words)) != lexical(text):
        raise ValueError("Не удалось выровнять весь текст. Проверьте запись и слова песни.")
    return dict(schema=1, duration=duration, words=words,
                analysis={"timings": "ready", "timelineComplete": True, "revision": "windows-cpu-v1"})


def align(request, runtime, work, progress):
    audio = Path(request["audio"]).resolve(strict=True)
    if not audio.is_file() or not 0 < audio.stat().st_size <= 2 * 1024**3:
        raise ValueError("Выберите локальный аудиофайл размером до 2 ГБ.")
    text = request["lyrics"].strip()
    if len(text.encode("utf-8")) > 128 * 1024 or not lexical(text):
        raise ValueError("Добавьте готовый текст песни размером до 128 КБ.")
    packages = runtime / "packages"
    progress("decoding", .03)
    pcm, duration = decode(audio, work, packages)
    if request["trackDuration"] > 0 and abs(duration - request["trackDuration"]) > max(2, min(5, duration * .01)):
        raise ValueError("Длительность аудиофайла не совпадает с треком в плеере.")

    progress("loading", .12)
    model_path = runtime / "models/base.pt"
    with model_path.open("rb") as checkpoint:
        if file_digest(checkpoint, "sha256").hexdigest() != MODEL_SHA:
            (runtime / "ready.json").unlink(missing_ok=True)
            raise ValueError("Файл модели повреждён. Подготовьте модуль повторно.")
    sys.path.insert(0, str(packages))
    dlls = os.add_dll_directory(str(packages))
    import numpy
    import stable_whisper
    import torch
    import whisper

    samples = numpy.frombuffer(pcm, dtype="<i2").astype(numpy.float32) / 32768.0
    torch.set_num_threads(min(4, os.cpu_count() or 1))
    with torch.inference_mode():
        model = stable_whisper.load_model(str(model_path), device="cpu")
        model.set_alignment_heads(whisper._ALIGNMENT_HEADS["base"])
        mel = whisper.log_mel_spectrogram(whisper.pad_or_trim(samples), n_mels=model.dims.n_mels)
        _, languages = model.detect_language(mel)
        progress("aligning", .2)
        result = model.align(samples, text, language=max(languages, key=languages.get),
                             original_split=True, vad=False, verbose=None, failure_threshold=.2,
                             progress_callback=lambda pos, total: progress("aligning", .2 + .75 * pos / max(1, total)))
    dlls.close()
    progress("saving", .98)
    document = json.dumps(timings(result, text, duration), ensure_ascii=False, allow_nan=False)
    (work / "result.json").write_text(document, encoding="utf-8")


def main():
    request = json.loads(sys.stdin.buffer.readline(1024 * 1024))
    job = request["id"]
    if request["version"] != VERSION or not re.fullmatch(r"[a-f0-9-]{36}", job):
        return 2
    runtime = Path(request["data"]) / "cpu-v1"
    work = Path(request["work"])
    def progress(phase, fraction):
        emit(job, type="progress", phase=phase, fraction=max(0, min(1, fraction)))

    try:
        with redirect_stdout(sys.stderr):
            if request["action"] == "prepare":
                prepare(runtime, work, progress)
            elif request["action"] == "align":
                align(request, runtime, work, progress)
            else:
                raise ValueError("Неизвестное задание обработчика.")
    except ValueError as error:
        emit(job, type="result", ok=False, message=str(error)[:400])
        return 2
    except Exception as error:
        print(repr(error), file=sys.stderr)
        emit(job, type="result", ok=False, message="Не удалось выполнить задание. Прежняя лирика сохранена.")
        return 2
    emit(job, type="result", ok=True)
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
