# Windows runtime components

Sekai Soundbar is distributed under GPL-3.0. The application license is in
`LICENSE`. The source tree for the packaged build accompanies the download.

The Windows build dynamically links Qt libraries under LGPL-3.0. Qt license
texts and third-party notices are in `licenses/Qt`. Source archives for the
Qt runtime are available at [Qt 6.8.2](https://download.qt.io/archive/qt/6.8/6.8.2/submodules/).
The relevant modules are Qt Base, Qt Declarative and Qt SVG. Qt Shader Tools
compiles the shaders at build time. The Qt DLLs can be replaced with compatible
builds.

Visual Studio builds also include the app-local Microsoft Visual C++ runtime.
MinGW builds include the GCC runtime and MinGW-w64 notices in `licenses/MinGW`.
See [GCC](https://gcc.gnu.org/releases.html) and [MinGW-w64](https://www.mingw-w64.org/downloads/).

When the optional alignment launcher is included, its CPython 3.12.10 x64
runtime is the [Python NuGet distribution](https://www.nuget.org/packages/python/3.12.10).
The Python license is in `alignment/python/LICENSE.txt`. The launcher downloads
its processing tools and model separately if enabled in the app.

The optional installer is built with [NSIS](https://nsis.sourceforge.io/License).
