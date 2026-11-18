# Установка 3.0.0-rc.4

[Статус и инструкция native API](NATIVE-INTEGRATION.md).

Предварительная версия требует SekaiPOP с API расширений. Скопируйте содержимое папки из архива в `~/.config/sekaipop/plugins/dock-equalizer/` так, чтобы в ней находился `plugin.json`, и перезапустите оболочку. [Архив и патч оболочки](https://github.com/Aferon-08/sekaipop-dock-equalizer/releases/tag/v3.0.0-rc.4)

Для стабильной версии с адаптерами используйте [инструкцию ветки v2](https://github.com/Aferon-08/sekaipop-dock-equalizer/blob/main/docs/INSTALL.md). Обновление кода v3 не сбрасывает пользовательские записи, разметки или seed. Для удаления кода применяется штатный менеджер (для репозиториев, установленных им); данные сохраняются по выбранной пользователем политике менеджера.

Для визуализации нужны Quickshell, Python 3, CAVA с поддержкой FIFO, setpriv/nice и PipeWire-Pulse или PulseAudio с библиотекой libpulse. Необязательные обработчики setup-wordtime.py, setup-multivoice.py и setup-cuda.py подготавливают окружения в каталоге данных.

PyGObject (`python-gobject` в Arch) даёт прямой доступ к позициям и перемоткам MPRIS. При его отсутствии общие часы используют позицию из Quickshell.
