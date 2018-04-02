# build-qt5-rpi

Bash script to fully cross-compile Qt 5 using a pure Debian host targeting a Raspberry Pi 2/3 without X11.

**Table of contents**

 * [Introduction](#introduction)
 * [Host installation](#host-installation)
   * [Virtual machine setup](#virtual-machine-setup)
   * [Debian setup](#debian-setup)
   * [Downloads](#downloads)
 * [Building Qt5](#building-qt5)
   * [Build details](#build-details)
 * [Raspberry Pi installation](#raspberry-pi-installation)
   * [Pi setup](#pi-setup)
   * [Qt5 installation](#qt5-installation)
 * [Example](#example)
 * [Troubleshooting and support](#troubleshooting-and-support)

## Introduction

This build script `build-qt5-rpi` is intended to cross-build Qt everywhere-opensource 5.9.4 (and 5.9.3) targeting a Raspberry Pi 2 or 3 (min. 1G RAM). It requires a virtual or physical host machine that runs a 32- or 64-Bit Debian 9 (other distributions like Ubuntu are currently not supported).

The primary focus is on cross-building Qt applications for target devices without X11. Building for the Pi with X11 is supported but not tested very well (feedback welcome).

Note that build-qt5-rpi does not access a physical Raspberry Pi to cross-compile Qt for it, instead it mounts and operates on a modified Raspbian image to generate the sysroot for Qt's build system.

This script generates two `.deb` installers, one with the sdk and runtime for the Pi and another for build hosts of the same architecture as the one used (amd64 or i386). These two installers are fully self-contained and can easily be deployed independently from the build host.

## Host installation

You will only need to run the commands in this section once on your build host.

### Virtual machine setup

A 64-Bit virtual machine dedicated to the purpose of running this build script is recommended.

You can choose any hypervisor to host the Debian virtual machine. The script was developed using [Oracle VirtualBox](https://www.virtualbox.org/).

Create a 32- or 64-Bit virtual machine and give it at least 32GB of hard disk space. On a 64-Bit machine, assign it as many processor cores and RAM as is reasonably possible on your physical machine.

**Extra notes for 32-Bit hosts only**

 * If you plan to use only a single processor core, give your machine 4GB of RAM.
 * If you plan to use multiple cores instead and your CPU supports PAE ([Physical Addresss Extension](https://en.wikipedia.org/wiki/Physical_Address_Extension)), then:
   * assign as many cores and as much RAM (max. 4GB times the number of cores) as reasonably possible, and
   * make sure to enable PAE and IO-APIC in the virtual machine to make the extra RAM accessible to the kernel (tested with 4 cores and 8GB of RAM).
 * You can test these settings later once the host is up and running by running `uname -r` where you should read something like 4.9.0-4-686-**pae** and by running `free -h` where you can check the RAM size.

### Debian setup

Boot the host machine up and install Debian from the `.iso`. You can work with the defaults in Debian setup, for a minimal setup unselect all at `tasksel` except:

 * [X] `SSH Server`
 * [X] `standard system utilites`

Once the installation is complete log in to your host and, if you want, use `ip addr` to find your host's IP address and then use a SSH terminal (like [putty](http://www.putty.org/) on Windows) from here on to interact more comfortably with your build host.

Next it is necessary to install `sudo` on your build host, and it is recommended to give yourself full sudo rights (without any permission checks). The build script uses `sudo` to mount the sysroot image into the file system, and to set ownerships of files in generated .deb packages. If you do not give yourself full sudo rights you will be prompted for your root password when you run the build script.

Choose one of these options to install sudo (these commands ask for the root password):

 * Option 1: sudo with permission checks (build script will be interrupted with root password prompt)

   ```bash
   su -c "apt-get -y install sudo && adduser $USER sudo && service sudo restart"
   ```

 * Option 2: sudo without permission checks (build script will run without interruptions)

   ```bash
   su -c "apt-get -y install sudo && adduser $USER sudo &&\
     echo \"$USER ALL=(ALL) NOPASSWD:ALL\" > /etc/sudoers.d/$USER &&\
     service sudo restart"
   ```

Then, install the apt packages required by the host in order to build Qt5, like the armhf cross-toolchain:

```bash
sudo apt-get install build-essential crossbuild-essential-armhf\
  qemu-user-static pkg-config git perl python gperf bison ruby flex gyp\
  libnss3-dev libnspr4-dev libfreetype6-dev libpng-dev libdbus-1-dev
```

**Extra notes for 64-Bit hosts only**

* Enable 32-Bit architecture support and refresh local apt repository index:

   ```bash
   # enable 32-Bit architecture support
   sudo dpkg --add-architecture i386
   
   # refresh local apt repository index
   sudo apt-get update
   ```

* Install required 32-Bit compatibility apt packages:
   
   ```bash
   # install 32-Bit compatibility packages
   sudo apt-get install linux-libc-dev:i386 g++-6-multilib
   ```

### Downloads

Finish your host setup with a of clone this repository and two downloads:

```bash
# change to your home directory (or any directory of your choice)
cd

# clone this repository
git clone https://github.com/chschnell/build-qt5-rpi

# download and unpack Raspbian Stretch Lite 2018-03-13 image
wget https://downloads.raspberrypi.org/raspbian_lite/images/raspbian_lite-2018-03-14/2018-03-13-raspbian-stretch-lite.zip
unzip 2018-03-13-raspbian-stretch-lite.zip

# download and unpack Qt 5.9.4 sources
wget http://download.qt.io/archive/qt/5.9/5.9.4/single/qt-everywhere-opensource-src-5.9.4.tar.xz
tar -xf qt-everywhere-opensource-src-5.9.4.tar.xz
```

This completes the host installation.

## Building Qt5

Configure, build and install Qt:

```bash
# create a build directory of any name and change into it
mkdir ~/qt5.9.4
cd ~/qt5.9.4

# initialize this build and create configuration file `build-qt5-rpi.conf`
../build-qt5-rpi/build-qt5-rpi.sh init -r ../2018-03-13-raspbian-stretch-lite.img -s ../qt-everywhere-opensource-src-5.9.4

# create `sysroot.img` unless it already exists, then run Qt's configure
../build-qt5-rpi/build-qt5-rpi.sh config

# run Qt's make
../build-qt5-rpi/build-qt5-rpi.sh build

# install Qt locally and build the .deb packages
../build-qt5-rpi/build-qt5-rpi.sh install
```

If all goes well then you can now use this host to cross-build Qt applications for your Pi. Before deploying your application you need to copy `qt-everywhere-opensource-rpi_5.9.4_armhf.deb` to your Pi and install it there, see [Raspberry Pi installation](#raspberry-pi-installation).

### Build details

The script runs through several stages in fixed order, any stage or set of stages can be specified on the command line (see also `build-qt5-rpi.sh -h`). Stages in detail:

 1. **init** - This stage creates the build configuration file `build-qt5-rpi.conf` in your local directory.
    You can customize your Qt build by changing variables in this file before running any of the other stages, see the comments inside it for more information.
 2. **mksysroot** - Creates a copy of the Raspbian image specified in `build-qt5-rpi.conf`, then updates the copied image and installs apt packages needed by Qt using `chroot` and `qemu`. Finally copies relevant files from the modified image into `/usr/local/qt5-rpi-sysroot` which is later used by the Qt builder as the sysroot. You can usually ignore this stage, it will be run automatically by the next stage `config` if needed.
 3. **config** - Runs `mksysroot` when running for the first time.
    Cleans all remains from a previous build on the host, then runs Qt's `configure`.
 4. **build** - Runs Qt's `make` parallelized over your number of cores.
    Qt 5.9.3: patches broken paths in `libQt5WebEngineCore.so.5.9.3`.
 5. **install** - Installs Qt and creates the `.deb` installers. Cleans all remains from a previous build on the Pi, installs sdk locally on the host in `/usr/local/qt5-rpi` and the host-tools in `/usr/local/qt5`, then creates the `.deb` packages.

Once the build is complete you'll find these files and subdirectories in the host's build directory:

 * `./build/` - Qt's build directory. See `build/config.summary` for a summary of Qt's feature auto-detection.
 * `./build-qt5-rpi.conf` - Build configuration file, created in the `init` stage.
 * `./qt-everywhere-opensource-host_5.9.4_amd64.deb` - Contains a copy of the Raspbian sysroot `/usr/local/qt5-rpi-sysroot` (armhf), a copy of the Qt sdk and runtime `/usr/local/qt5-rpi` (armhf) and a copy of the Qt host tools `/usr/local/qt5` (amd64 or i386). The installer copies host tools (`bin/qmake` etc.) into `/usr/local` to make them directly available through the default `PATH`. Depends on: `build-essential` and `crossbuild-essential-armhf`.
 * `./qt-everywhere-opensource-rpi_5.9.4_armhf.deb` - Contains a copy of the Qt sdk and runtime `/usr/local/qt5-rpi` (armhf). The Qt shared libraries are automatically registered and unregistered with a `ldconfig` trigger. Depends on all non-dev packages that were installed in the build environment. Also depends on `ttf-mscorefonts-installer` for improved fonts and on `upower` to counter the `org.freedesktop.UPower.GetDisplayDevice` warnings from Qt.
 * `./sysroot.img` - Locally modified copy of a Raspbian image.

The script also creates these directories:

 * `/usr/local/qt5/` - Qt host tools (`qmake` and others) in host's architecture (amd64 or i386)
 * `/usr/local/qt5-rpi/` - Qt sdk and runtime (libraries, headers and examples) for Raspberry Pi (armhf)
 * `/usr/local/qt5-rpi-sysroot/` - Raspberry Pi sysroot for cross-building Qt applications (armhf)

## Raspberry Pi installation

### Pi setup

Write the Raspbian Stretch Lite image that you [downloaded](#downloads) earlier to a SD card, attach a keyboard and monitor to the Pi and boot it up. Log in and run `raspi-config`:

```bash
pi@raspberrypi:~ $ sudo raspi-config
```

You should at least modify these settings (most importantly, `SSH` and `Memory split`):

 * Localisation Options
   * `Locale`, `Timezone`, `Keyboard Layout` and `Wi-fi Country`: adjust these to your preferred settings, if applicable
 * Interfacing Options
   * `SSH`: enable server
 * Advanced Options
   * `Memory Split`: give your GPU 256M
   * `Overscan`: disable (in case you want to get rid of black borders around your screen)

Keep the Pi running. We will use SSH from here to access the Pi remotely, so you won't need the Pi's keyboard and monitor from here on.

To simplify logging in to your Pi, create a SSH key pair with empty password on your host and install the public key onto the Pi. Normally you should be able to connect to your Pi using username `pi` and hostname `raspberrypi`, otherwise replace `raspberrypi` with the IP address of your Pi in the commands below.

```bash
# create RSA key pair (replace pi@raspberrypi if necessary)
ssh-keygen -t rsa -C pi@raspberrypi -N "" -f ~/.ssh/id_rsa

# copy pulic key to your Pi (replace pi@raspberrypi if necessary)
# note: this command will ask for your Pi user password
cat ~/.ssh/id_rsa.pub | ssh -o StrictHostKeyChecking=no pi@raspberrypi "mkdir -p .ssh && chmod 700 .ssh && cat >> .ssh/authorized_keys"
```

Next you will have to update your Pi using these commands:

```bash
# log in to your Pi
ssh pi@raspberrypi

# update Raspbian
pi@raspberrypi:~ $ sudo apt-get update && sudo apt-get -y upgrade

# update kernel, fix /opt/vc/lib and refresh apt (again)
pi@raspberrypi:~ $ sudo rpi-update && sudo apt-get update

# reboot
pi@raspberrypi:~ $ sudo reboot
```

**Note:** Currently, Qt without X11 doesn't work properly on the Pi without running `rpi-update` to fix the VideoCore libraries in `/opt/vc/lib`. This will hopefully change with a future Raspbian release.

### Qt5 installation

These are the steps to install Qt on a single Pi from the host. The `.deb` package for the Pi can of course easily be copied to and installed on any number of your devices.

 * First, copy the Qt `.deb` installer from your build host to your Pi:

   ```bash
   scp qt-everywhere-opensource-rpi_5.9.4_armhf.deb pi@raspberrypi:
   ```

 * Log in to your Pi:

   ```bash
   ssh pi@raspberrypi
   ```

 * Install Qt and all its missing dependencies (note the use of `apt` instead of `apt-get`):

   ```bash
   pi@raspberrypi:~ $ sudo apt install ./qt-everywhere-opensource-rpi_5.9.4_armhf.deb
   ```

 * In case you need to, this is how you would remove your Qt package and its dependencies again from your Pi:

   ```bash
   # remove Qt runtime
   pi@raspberrypi:~ $ sudo apt remove qt-everywhere-opensource-rpi
   
   # remove dependencies
   pi@raspberrypi:~ $ sudo apt autoremove
   ```

While you're logged in to your Pi, consider these additional steps for your setup (specifically if you don't plan to use X11):

 * To counter the `Unable to query physical screen size` warnings, find your display's dimensions in millimeters and set these environment variables:
   
   ```bash
   # add to Pi's ~/.profile to make these settings permanent
   # example 1: Samsung SyncMaster P2450H with 531mm x 298mm
   export QT_QPA_EGLFS_PHYSICAL_WIDTH=531
   export QT_QPA_EGLFS_PHYSICAL_HEIGHT=298
   # example 2: Raspberry Pi 7" touchscreen: 155mm x 86mm
   #export QT_QPA_EGLFS_PHYSICAL_WIDTH=155
   #export QT_QPA_EGLFS_PHYSICAL_HEIGHT=86
   ```

 * To hide the mouse cursor in case you have a touchscreen:
   ```bash
   # add to Pi's ~/.profile to make this setting permanent
   export QT_QPA_EGLFS_HIDECURSOR=1
   ```

 * If you use a mouse or a touchscreen without X11, consider installing console mouse support:
   
   ```bash
   pi@raspberrypi:~ $ sudo apt-get install gpm
   ```
   
   This allows you to wake the console screen saver using your mouse or touchscreen.

## Example

In this example we will build Qt's `minibrowser` for the Pi and run it without X11.

On the host, add Qt's host tools (for `qmake` etc.) to your PATH:

```bash
# add to ~/.profile to make this setting permanent
export PATH=$PATH:/usr/local/qt5/bin
```

Now build and test the `minibrowser` example:

```bash
cd ~/qt5.9.4
mkdir example
cd example

# configure, make and install minibrowser example
qmake ../../qt-everywhere-opensource-src-5.9.4/qtwebview/examples/examples.pro
make
INSTALL_ROOT="$PWD" make install

# copy minibrowser to your Raspberry Pi
scp -r usr/local/qt5-rpi/examples/webview/minibrowser pi@raspberrypi:minibrowser

# log in to your Pi
ssh pi@raspberrypi

# example 1: http://html5test.com
pi@raspberrypi:~ $ minibrowser/minibrowser html5test.com

# example 2 (SSL): https://www.youtube.com
pi@raspberrypi:~ $ minibrowser/minibrowser https://www.youtube.com/tv#/watch?v=DLzxrzFCyOs
```

If you want to build all examples remove `-nomake examples` from variable `CFG_QT_CONFIG` in your build configuration file `build-qt5-rpi.conf`, then configure, build and install Qt again.

## Troubleshooting and support

**Check for conflicting libraries**

 * Check that you don't have any of the `mesa` libraries installed. Test and see that you get no output from this command:
 
   ```bash
   pi@raspberrypi:~ $ dpkg-query --list | grep mesa
   ```
   
   In case you do see package names printed by this command try to remove the listed packages with `apt-get remove`.

 * Check that you don't have any of the other `qt` libraries installed. Test and see that you get no output from this command:
 
   ```bash
   pi@raspberrypi:~ $ dpkg-query --list | grep qt | grep -v qt-everywhere-opensource-rpi
   ```
   
   In case you do see package names printed by this command try to remove the listed packages with `apt-get remove`.

**Check VideoCore libraries**

 * Check that you have the proper VideoCore libraries installed. Run this command and compare that you get the same output:

   ```bash
   pi@raspberrypi:~ $ ldconfig -p | grep -E "(libEGL|libGLESv2|libOpenVG|libWFC).so"
      libWFC.so (libc6,hard-float) => /opt/vc/lib/libWFC.so
      libOpenVG.so (libc6,hard-float) => /opt/vc/lib/libOpenVG.so
      libGLESv2.so (libc6,hard-float) => /opt/vc/lib/libGLESv2.so
      libEGL.so (libc6,hard-float) => /opt/vc/lib/libEGL.so
   ```

 * In case you receive no or some different output you may further check to see if you have the proper VideoCore libraries installed in `/opt/vc/lib` (this is what you should normally see, most likely not the case):

   ```bash
   pi@raspberrypi:~ $ ls -la /opt/vc/lib/lib{EGL,GLESv1_CM,GLESv2,OpenVG,WFC}.so
   -rw-r--r-- 1 root root 202072 Apr  1 06:09 /opt/vc/lib/libEGL.so
   lrwxrwxrwx 1 root root     12 Apr  1 06:09 /opt/vc/lib/libGLESv1_CM.so -> libGLESv2.so
   -rw-r--r-- 1 root root 105768 Apr  1 06:09 /opt/vc/lib/libGLESv2.so
   -rw-r--r-- 1 root root  99200 Apr  1 06:09 /opt/vc/lib/libOpenVG.so
   -rw-r--r-- 1 root root  78552 Apr  1 06:09 /opt/vc/lib/libWFC.so
   ```

 * Run `sudo rpi-update` to try to fix VideoCore library issues.

**Other known issues**

 * If you execute a Qt application on the Pi and get an error similar to:

   ```bash
   GL ERROR: GL_OUT_OF_MEMORY
   ```

   then try to increase the GPU memory split on your Pi (see [Pi setup](#pi-setup)).

**Submitting issues**

If you have a reproducable problem then please re-run the stage in which it occurs while passing the `-l FILE` option, for example:

```bash
# run the "build" stage and write log to "myerror.log"
build-qt5-rpi.sh build -l myerror.log
```

and then provide relevant parts of this log file with your issue report.