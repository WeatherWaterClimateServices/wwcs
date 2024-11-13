Flashgordon is a Python tool to configure and flash the mainboards of the WWCS stations.

# Install

In Windows in order to run the application you need to:

- Install the Flashgordon application with the `flashgordon_installer.exe`
  executable.

# Development environment

In order to set up a development environment for Flashgordon first you need to
install:

- Python 3 (in Windows use Python 3.7 because PySide6 only provides Windows
  wheels for Python 3.7)
- The Qt libraries, since the GUI is built with Qt

Thne create a virtual environment and install the requirements.

    python3 -m venv venv
    source venv/bin/activate
    pip install -U pip
    pip install -r requirements.txt

In Windows to activate the virtual environment:

    # In cmd.exe
    venv\Scripts\activate.bat

    # In PowerShell
    venv\Scripts\Activate.ps1

Now you can run the program:

    python flashgordon.py

## Troubleshooting

If the program fails to run it may be because a library is missing.
For example if it fails fail with an error like:

```
$ python flashgordon.py
qt.qpa.plugin: Could not load the Qt platform plugin "xcb" in "" even though it was found.
```

Try running with `QT_DEBUG_PLUGINS=1` for extra information, for example:

```
$ QT_DEBUG_PLUGINS=1 python flashgordon.py
[...]
Cannot load library [...] (libxcb-cursor.so.0: cannot open shared object file: [...])
[...]
```

Then install the missing library.

# Windows installer

Building a installer is a 2 step process:

- Use pyinstaller to bundle the program with its requirements (this step works
  as well for Linux and macOS)

- Use InstallForge to create the Windows installer program

This tutorial explains the process in detail:

- https://www.pythonguis.com/tutorials/packaging-pyside6-applications-windows-pyinstaller-installforge/

## pyinstaller

First install Python 3.7 and the requirements:

    pip install -r requirements.txt

Now to bundle the application type:

    pyinstaller flashgordon.py --add-binary="arduino-cli.exe;." --add-data="src;src" -i src/flashgordon.ico -w

To run this command for Linux or macOS just replace `src;src` by `src:src`.

Explanation of the options:

    --add-binary="arduino-cli.exe;."    Adds the arduino-cli.exe binary
    --add-data="src;src"                Adds the src folder to the distribution
    -i src/flashgordon.ico              Sets the icon for the application
    -w                                  Avoids opening a console window

Once pyinstaller is exectued it will generate the following:

    flashgordon.spec
        This file contains the build configuration and instructions.

    build/
        Intermediary build files, can be ignored.

    dist/flashgordon/
        Inside this directory you will find the flashgordon executable and the
        libraries it needs.

Try running the program `dist/flashgordon/flashgordon.exe`.
If it works then go to the next and final step to create the Windows installer.

## InstallForge

First install InstallForge, download from https://installforge.net/download/

Then run InstallForge. These are the options that have been used to create the
installer.

In the *General / General* page:

- Product name: FlashGordon
- Product version: 1.0
- Company name: Caritas Switzerland
- Supported Operating Systems: Windows 8, Windows 10, Windows 11

In the *Setup / Files* page:

- Add all the files and folders within the `dist/flashgordon` directory (but
  not the directory itself)
- Check *Allow user to change installation path*

In the *Setup / Uninstall* page:

- Check *Include Uninstaller*

In the *Dialogs / Finish* page:

- Run Application: `<InstallPath>\flashgordon.exe`

In the *System / Shortcuts* page:

- Check *Create desktop shortcuts for all users*
- Add 2 shortcuts, one for *Startmenu* and the other for *Desktop*:
  in *Target file* type `<InstallPath>\flashgordon.exe`,
  in *Shortcut Name* type `Flashgordon`

In the `Build / Build` page:

- In *Setup file* type `flashgordon_installer.exe`, in the directory you wish
  to create the installer.

Then click the big button *Build* in the top bar.

You may as well wish to save the configuration to later replay it, this will
generate a `flashgordon.ifp`; however sharing this file may not be obvious
as the paths to the dist folder will likely be different from one user to
another.
