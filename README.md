# LZDoom for for Vita

Port of the GZDoom fork LZDoom to PlayStation Vita.

Copyright (c) 1998-2021 ZDoom + GZDoom teams, and contributors
Doom Source (c) 1997 id Software, Raven Software, and contributors

### Licensed under the GPL v3

##### https://www.gnu.org/licenses/quick-guide-gplv3.en.html

## Build Instructions

Your system must be able to build a native version of LZDoom before compiling. You must also install the ZMusic library on your system. You must use VitaSDK to build this project. After installing, build the ZMusic library using vita-makepkg:

```
cd vita
cd zmusic
vita-makepkg
```

LZDoom requires a native build to be done first, and uses the result as an input file (you MUST name the build directory native_build):

```
mkdir native_build
cd native_build
cmake ..
make -j$(nproc)
```

Then finally build LZDoom for Vita:

```
mkdir vita_build
cd vita_build
cmake .. -DVITA=1
make -j$(nproc)
```