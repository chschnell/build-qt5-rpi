# build-qt5-rpi

Builder script to fully cross-compile Qt 5 using a pure Debian host targeting a Raspberry Pi 2/3 without X11.

**Table of contents**

* [Setup](#setup)
  * [Raspberry Pi Setup](#raspberry-pi-setup)
  * [Host Virtual Machine Setup](#host-virtual-machine-setup)
  * [Host Debian Setup](#host-debian-setup)
* [Build Qt5](#build-qt5)
* [Build Example](#build-example)
  * [Raspberry Pi Runtime Setup](#raspberry-pi-runtime-setup)
  * [Build and install example](#build-and-install-example)
  * [Run example](#run-example)

## Setup

To run this script you need:

 * Raspberry Pi 2 or 3 (tested on a Pi 3)
 * Raspberry Pi OS: Raspbian Stretch Lite ([2017-11-29-raspbian-stretch-lite.img](https://www.raspberrypi.org/downloads/raspbian/))
 * Host: Anything capable of running a 32-Bit Debian 9 (i.e. [Oracle VirtualBox](https://www.virtualbox.org/) or a PC)
 * Host OS: Debian 9 Stretch 32-Bit netinst ([debian-9.3.0-i386-netinst.iso](https://www.debian.org/CD/netinst/index.html))

The reason for 32-Bit Debian 9 is that we can use its built-in armhf cross-compiler for Qt without relying on any 3rd party tools.

It seems currently not possible to set up a 64-Bit Debian host using its built-in i386, amd64 and armhf toolchains in the same installation (Qt builds some host tools for 32-Bit target, regardless of the host's architecture).

A [32-Bit Ubuntu](https://www.ubuntu.com/download/alternative-downloads) >= 16.04 should also work for the host (not tested).

### Raspberry Pi Setup

Write the Raspbian Lite image to a SD card, attach a keyboard and monitor to the Pi and boot it up. Log in and run these basic commands:

```bash
# change locale, timezone and keyboard (if neccessary)
# enable SSH server
# set GPU memory split to 256MB
sudo raspi-config

# update Raspbian distribution
sudo apt-get update
sudo apt-get -y upgrade

# update Raspbian Kernel and fix /opt/vc/lib
sudo rpi-update
sudo reboot
```

Note:

 * Currently, Qt cannot be build without running `rpi-update` to fix the VideoCore libraries in `/opt/vc/lib`. This will hopefully change with a future Raspbian release.
 * You don't need to install any other APT packages on the Pi as it is part of the build script. In case you do install other packages, take caution to not pull in any of the `mesa` or `qt5` packages as they might break the build. You can check if any of these packages are installed by running `dpkg-query --list | grep -E "(mesa|qt)"`, this command lists all of these installed packages (which should be empty).

Keep the Pi running. You won't need the keyboard and monitor from here on.

### Host Virtual Machine Setup

If you use VirtualBox, create a 32-Bit Debian virtual machine and give it at least 16GB of hard disk space.

If you plan to use only a single processor core, give your machine 4GB of RAM. If you plan to use multiple cores instead and your CPU supports PAE ([Physical Addresss Extension](https://en.wikipedia.org/wiki/Physical_Address_Extension)):

 * assign as many cores and as much RAM (max. 4GB times the number of cores) as reasonably possible, and
 * make sure to enable PAE and IO-APIC in the virtual machine to make the extra RAM accessible to the kernel (tested with 4 cores and 8GB of RAM).

Boot the machine, install Debian from `debian-9.3.0-i386-netinst.iso` and log in.

### Host Debian Setup

If you use VirtualBox, use `ip addr` to find your host's IP address and then use a SSH terminal (like [putty](http://www.putty.org/) on Windows) from here on to interact with the host machine.

In case you did enable PAE in the virtual machine earlier, you can test it by running `uname -r` where you should read something like 4.9.0-4-686-**pae** and by running `free -h` where you can compare the RAM size.

Completely optional (the bash script does not need root permissions, only a few steps in this section) but useful, install `sudo`:

```bash
# become root
su

# download and install sudo
apt-get install sudo

# add your user account to the sudo group (replace USER_NAME with your user name)
adduser USER_NAME sudo

# optional: disable password authentification for your account (replace USER_NAME with your user name)
echo "USER_NAME ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/USER_NAME

# reload sudo
service sudo restart

# logout root
exit
```

Next, create a SSH key pair with empty password and install the public key on the Pi. Normally you should be able to connect to your Pi using username `pi` and hostname `raspberrypi`, otherwise replace `raspberrypi` with the IP address of your Pi in the commands below.

```bash
# create RSA key pair (replace pi@raspberrypi if necessary)
ssh-keygen -t rsa -C pi@raspberrypi -N "" -f ~/.ssh/id_rsa

# copy the pulic key to your Pi (replace pi@raspberrypi if necessary)
cat ~/.ssh/id_rsa.pub | ssh -o StrictHostKeyChecking=no pi@raspberrypi "mkdir -p .ssh && chmod 700 .ssh && cat >> .ssh/authorized_keys"
```

Finally, as root, install the apt packages required for building Qt5:

```bash
# install toolchain and cross-toolchain as well as several build tools
sudo apt-get install build-essential crossbuild-essential-armhf pkg-config git perl python gperf bison ruby flex gyp libnss3-dev libnspr4-dev
```

## Build Qt5

Install this repository and the Qt sources:

```bash
# change to your home directory (or any direcotry of your choice)
cd

# clone this repository
git clone https://github.com/chschnell/build-qt5-rpi

# download Qt 5.9.3 sources
wget http://download.qt.io/official_releases/qt/5.9/5.9.3/single/qt-everywhere-opensource-src-5.9.3.tar.xz

# unpack
tar -xf qt-everywhere-opensource-src-5.9.3.tar.xz
```

For the impatient, this will fully build and install Qt from sources in `../qt-everywhere-opensource-src-5.9.3` in a single run:

```bash
# create a build directory of any name and change into it:
mkdir qt5.9.3
cd qt5.9.3

../build-qt5-rpi/build-qt5-rpi.sh -s ../qt-everywhere-opensource-src-5.9.3 init config build install
```

Once the build is complete you'll find these subdirectories in your build directory (assuming default path settings):

 * `sysroot` - Mirror of Pi's armhf files in `/lib`, `/usr/include`, `/usr/lib`, `/usr/share` and `/opt/vc`
 * `build` - Qt's build directory
 * `sdk` - Qt SDK (libraries, headers and examples) for armhf architecture
 * `hosttools` - Qt host tools (`qmake` and others) for host's architecture
 * `release` - Tar archives of `sysroot`, `sdk` and `hosttools`

The script runs through several stages in fixed order, any stage or set of stages can be specified on the command line (see also `build-qt5-rpi.sh -h`). Stages in detail:

 1. **init**

    This stage creates the build configuration file `build-qt5-rpi.conf` in the local directory. You can customize the build by changing variables in this file before running any of the other stages, see `build-qt5-rpi.sh -h` for more information.

 2. **sync**

    Install APT development packages on the Pi and mirror local sysroot from the Pi. You only need to run this stage after manually installing APT packages on the Pi, else you can igonore it (it will be run automatically in the next stage `config`).

 3. **config**

    Run `sync` when running for the first time. Clean all remains from a previous build on the host, then run Qt's `configure`.

 4. **build**

    Run Qt's `make` parallelized over number of cores. Patch broken paths in `libQt5WebEngineCore.so.5` if its realpath exists.

 5. **install**

    Install Qt locally. Clean all remains from a previous build on the Pi, then install SDK on the Pi and setup and run `ldconfig`. Build tar archives.

## Build Example

This demonstrates how to build and run a single example from the Qt sources. In order to build all examples remove `-nomake examples` from variable `DEFAULT_QT_CONFIG` in your `build-qt5-rpi.conf` configuration file, then configure and build Qt.

### Raspberry Pi Runtime Setup

These final touches are recommended, though not strictly required, to improve running Qt applications without X11 on the Pi.

 * To counter the `Unable to query physical screen size` warnings, find your display's dimensions in millimeters and set these environment variables:
   
   ```bash
   # add to Pi's ~./profile (example Samsung SyncMaster P2450H with 531x298 mm):
   export QT_QPA_EGLFS_PHYSICAL_WIDTH=531
   export QT_QPA_EGLFS_PHYSICAL_HEIGHT=298
   ```

 * To hide the mouse cursor:
   ```bash
   # add to Pi's ~./profile:
   export QT_QPA_EGLFS_HIDECURSOR=1
   ```

 * To get rid of black borders around your screen, disable `overscan` on the Pi:
   
   ```bash
   ssh pi@raspberrypi sudo raspi-config
   ```

The builder script already installs these additional packages on the Pi (you need to install them when deploying to a different Pi):

 * To counter the `org.freedesktop.UPower.GetDisplayDevice` warnings, install APT package `upower` on the Pi:
   
   ```bash
   ssh pi@raspberrypi sudo apt-get install upower
   ```

 * For better fonts, install MS Fonts on Pi:
   
    ```bash
    ssh pi@raspberrypi sudo apt-get install fontconfig ttf-mscorefonts-installer
    ```

### Build and install example

On the host, add Qt's hosttools to your PATH (assuming path settings from above):

```bash
# add to ~./profile
export PATH=$PATH:$HOME/qt5.9.3/hosttools/bin
```

Then, cross-build Qt's `qtwebview` example:

```bash
mkdir -p ~/qt5.9.3/examples
pushd ~/qt5.9.3/examples
qmake ~/qt-everywhere-opensource-src-5.9.3/qtwebview/examples/examples.pro
make -j$(nproc)
make install
popd
```

Copy local `~/qt5.9.3/sdk/examples` to Pi's `~/examples`:

```bash
rsync -a ~/qt5.9.3/sdk/examples pi@raspberrypi:
```

### Run example

Run `qtwebview` on the Pi without X11:

```bash
# log in to Pi
ssh pi@raspberrypi

# example 1: http://html5test.com
examples/webview/minibrowser/minibrowser html5test.com

# example 2 (SSL): https://www.youtube.com
examples/webview/minibrowser/minibrowser https://www.youtube.com/tv#/watch?v=DLzxrzFCyOs
```
