#!/bin/bash
#
# MIT License
#
# Copyright (c) 2017 Christian Schnell <christian.d.schnell@gmail.com>
#
# Permission is hereby granted, free of charge, to any person obtaining a copy
# of this software and associated documentation files (the "Software"), to deal
# in the Software without restriction, including without limitation the rights
# to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
# copies of the Software, and to permit persons to whom the Software is
# furnished to do so, subject to the following conditions:
#
# The above copyright notice and this permission notice shall be included in all
# copies or substantial portions of the Software.
#
# THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
# IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
# FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
# AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
# LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
# OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
# SOFTWARE.

set -o pipefail  # pass error through pipes
set -o errtrace  # pass error through functions
set -o nounset   # exit script when using an uninitialised variable
set -o errexit   # exit script if any statement returns non-zero

# --- constants --------------------------------------------------------------

readonly APT_PKGS_RPI_DEV="zlib1g-dev libjpeg-dev libpng-dev\
 libfreetype6-dev libssl1.0-dev libicu-dev libxslt1-dev libdbus-1-dev\
 libfontconfig1-dev libcap-dev libudev-dev libpci-dev libnss3-dev\
 libasound2-dev libbz2-dev libgcrypt11-dev libdrm-dev libcups2-dev\
 libevent-dev libinput-dev libts-dev libmtdev-dev libpcre2-dev libre2-dev\
 libwebp-dev libopus-dev unixodbc-dev libsqlite0-dev libxcursor-dev\
 libxcomposite-dev libxdamage-dev libxrandr-dev libxtst-dev libxss-dev\
 libxkbcommon-dev libdouble-conversion-dev libbluetooth-dev\
 libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev"

readonly APT_PKGS_RPI_X11_DEV="libx11-xcb-dev libgbm-dev libxcb-xfixes0-dev\
 libxcb-glx0-dev libsm-dev libxkbcommon-x11-dev libgtk-3-dev libwayland-dev\
 libxcb-cursor-dev libxcb-keysyms1-dev libxcb-xinerama0-dev libxcb-sync-dev\
 libxcb-randr0-dev libxcb-icccm4-dev"

readonly APT_PKGS_RPI_TOOLS="ttf-mscorefonts-installer fontconfig upower"

readonly DEFAULT_QT_CONFIG="-release -opensource -confirm-license\
 -platform linux-g++ -device linux-rasp-pi2-g++ -device-option\
 CROSS_COMPILE=arm-linux-gnueabihf- -opengl es2 -no-gtk -nomake tests\
 -nomake examples"

readonly ATTR_RED=`tput setaf 1`
readonly ATTR_GREEN=`tput setaf 2`
readonly ATTR_RESET=`tput sgr0`

# --- functions --------------------------------------------------------------

function exit_handler() {
    if [ $COMPLETED_NORMAL = false ]; then
        echo_fail "*** Build failed"
    fi
}

function print_attr() {
    echo "${1}[build-qt5-rpi]${ATTR_RESET} $(date -d@$SECONDS -u +%H:%M:%S) ${2}"
}

function echo_msg() {
    print_attr $ATTR_GREEN "$1"
}

function echo_fail() {
    set +o xtrace
    print_attr $ATTR_RED "$1"
}

function write_config() {
    echo "CFG_RPI_LOGIN=\${CFG_RPI_LOGIN:=$CFG_RPI_LOGIN}
CFG_QT_SOURCE=\${CFG_QT_SOURCE:=$CFG_QT_SOURCE}
CFG_QT_CONFIG=\${CFG_QT_CONFIG:=$CFG_QT_CONFIG}
CFG_QT_USE_X11=\${CFG_QT_USE_X11:=$CFG_QT_USE_X11}
CFG_ROOT=\${CFG_ROOT:=$CFG_ROOT}
CFG_BUILD=\${CFG_BUILD:=$CFG_BUILD}
CFG_SYSROOT=\${CFG_SYSROOT:=$CFG_SYSROOT}
CFG_PREFIX=\${CFG_PREFIX:=$CFG_PREFIX}
CFG_EXTPREFIX=\${CFG_EXTPREFIX:=$CFG_EXTPREFIX}
CFG_HOSTPREFIX=\${CFG_HOSTPREFIX:=$CFG_HOSTPREFIX}
CFG_RELPREFIX=\${CFG_RELPREFIX:=$CFG_RELPREFIX}" > "$CFG_CONF"
}

function sync_rpi() {
    local APT_PACKAGES=$APT_PKGS_RPI_DEV
    if [ $CFG_QT_USE_X11 = true ]; then
        APT_PACKAGES+=" $APT_PKGS_RPI_X11_DEV"
    fi
    APT_PACKAGES+=" $APT_PKGS_RPI_TOOLS"
    ssh $CFG_RPI_LOGIN sudo apt-get -y install $APT_PACKAGES

    rsync -aR --del --copy-unsafe-links --exclude=/lib/systemd --exclude=/usr/lib/ssl/private $CFG_RPI_LOGIN:/lib :/usr/include :/usr/lib :/usr/share :/opt/vc "$CFG_SYSROOT"
}

function clean_host() {
    rm -rf "$CFG_BUILD"/* "$CFG_BUILD"/.[^.]* "$CFG_EXTPREFIX"/* "$CFG_HOSTPREFIX"/*
}

function configure_qt() {
    mkdir -p "$CFG_ROOT" "$CFG_BUILD"
    pushd "$CFG_BUILD"
    "$CFG_QT_SOURCE/configure" $CFG_QT_CONFIG -sysroot "$CFG_SYSROOT" -prefix "$CFG_PREFIX" -extprefix "$CFG_EXTPREFIX" -hostprefix "$CFG_HOSTPREFIX"
    popd
}

function make_qt() {
    make -C "$CFG_BUILD" -j$(nproc)
}

function file_replace_c_str() {
    local FILE=$1 OLD=$2 NEW=$3
    if [ ${#OLD} -lt ${#NEW} ]; then
        echo_fail "*** error: New string '$NEW' must not be longer than '$OLD'!"
        exit 1
    fi
    sed -e "s@${OLD}\\x00@${NEW}\\x00${OLD:${#NEW}+1}\\x00@" -i "$FILE"
}

function patch_libQt5WebEngineCore_so_5_9_3() {
    # Possible fix in Qt 5.10?
    # http://code.qt.io/cgit/qt/qtwebengine.git/commit/?id=e812237b6980584fc5939f49f6a18315cc694c3a
    local LIBFILE="$CFG_BUILD/qtwebengine/lib/libQt5WebEngineCore.so.5.9.3"
    if [ -e $LIBFILE ]; then
        file_replace_c_str "$LIBFILE" "$CFG_SYSROOT/opt/vc/lib" /opt/vc/lib
        file_replace_c_str "$LIBFILE" libEGL.so.1 libEGL.so
        file_replace_c_str "$LIBFILE" libGLESv2.so.2 libGLESv2.so
    fi
}

function install_qt_to_host() {
    mkdir -p "$CFG_EXTPREFIX" "$CFG_HOSTPREFIX"
    make -C "$CFG_BUILD" install
}

function clean_rpi() {
    ssh $CFG_RPI_LOGIN sudo rm -rf "$CFG_PREFIX" /etc/ld.so.conf.d/qt5.conf
    ssh $CFG_RPI_LOGIN sudo ldconfig
}

function install_qt_to_rpi() {
    # create installation directory on pi
    ssh $CFG_RPI_LOGIN sudo mkdir -p "$CFG_PREFIX"
    ssh $CFG_RPI_LOGIN sudo chown pi:pi "$CFG_PREFIX"
    # mirror Qt runtime to pi
    rsync -a --del "$CFG_EXTPREFIX"/ $CFG_RPI_LOGIN:"$CFG_PREFIX"
    ssh $CFG_RPI_LOGIN sudo sync
    # create ld.so.conf and run ldconfig on pi
    echo "$CFG_PREFIX/lib" | ssh $CFG_RPI_LOGIN sudo tee /etc/ld.so.conf.d/qt5.conf > /dev/null
    ssh $CFG_RPI_LOGIN sudo ldconfig
}

function pack_archives() {
    local QT_VERSION=$($CFG_BUILD/qtbase/bin/qmake -v | tail -1 | cut -d' ' -f4)
    mkdir -p "$CFG_RELPREFIX"
    tar -cjf "$CFG_RELPREFIX/qt${QT_VERSION}-sysroot-rpi.tar.bz2" -C $(dirname "$CFG_SYSROOT") $(basename "$CFG_SYSROOT")
    tar -cjf "$CFG_RELPREFIX/qt${QT_VERSION}-sdk-rpi.tar.bz2" -C $(dirname "$CFG_EXTPREFIX") $(basename "$CFG_EXTPREFIX")
    tar -cjf "$CFG_RELPREFIX/qt${QT_VERSION}-hosttools-${HOSTTYPE}.tar.bz2" -C $(dirname "$CFG_HOSTPREFIX") $(basename "$CFG_HOSTPREFIX")
}

function show_help() {
    echo "Usage:
    build-qt5-rpi.sh [OPTION | COMMAND]...

Commands:
    init
        Creates build configuration file '$CFG_CONF'
    sync
        Setup Raspberry Pi build environment
    config
        Cleanup and configure Qt build
    build
        Make Qt (parallelized over number of cores)
    install
        Install Qt runtime to host and Raspberry Pi, create archives
    all
        Same as 'config build install'
    help
        Show help

Options:
    -c FILE     Use config file FILE [$CFG_CONF]
    -s PATH     Use Qt source directory PATH [$CFG_QT_SOURCE]
    -h, --help  Show help

Configuration variables:
    CFG_RPI_LOGIN   Pi SSH login <USER>@<HOST> [$CFG_RPI_LOGIN]
    CFG_QT_SOURCE   Qt source path [$CFG_QT_SOURCE]
    CFG_QT_CONFIG   Qt configure options [$CFG_QT_CONFIG]
    CFG_QT_USE_X11  true: Enable X11 support [$CFG_QT_USE_X11]
    CFG_ROOT        Root directory [$CFG_ROOT]
    CFG_BUILD       Build directory [$CFG_BUILD]
    CFG_SYSROOT     Sysroot directory [$CFG_SYSROOT]
    CFG_PREFIX      Pi install prefix [$CFG_PREFIX]
    CFG_EXTPREFIX   Host install prefix [$CFG_EXTPREFIX]
    CFG_HOSTPREFIX  Tools install prefix [$CFG_HOSTPREFIX]
    CFG_RELPREFIX   Release install prefix [$CFG_RELPREFIX]

Examples:
    build-qt5-rpi.sh -s ../qt-everywhere-opensource-src-5.9.3 init
        Initialize build with Qt 5.9.3 sources
    build-qt5-rpi.sh all
        Configure, build and install Qt
    build-qt5-rpi.sh build
        Build Qt"
}

# --- main -------------------------------------------------------------------

DO_INIT=false
DO_SYNC=false
DO_CONFIG=false
DO_BUILD=false
DO_INSTALL=false
DO_HELP=false

while [ "$#" -gt 0 ]; do
    case "$1" in
        init)
            DO_INIT=true;;
        sync)
            DO_SYNC=true;;
        config)
            DO_CONFIG=true;;
        build)
            DO_BUILD=true;;
        install)
            DO_INSTALL=true;;
        all)
            DO_CONFIG=true; DO_BUILD=true; DO_INSTALL=true;;
        help|-h|--help)
            DO_HELP=true;;
        -s|--source)
            if [ ! -e "$2" ]; then
                echo_fail "*** error: source path '$2' not found"
                exit 1
            fi
            CFG_QT_SOURCE=$(realpath $2)
            shift;;
        -c|--conf)
            if [ ! -e "$2" ]; then
                echo_fail "*** error: file '$2' not found"
                exit 1
            fi
            CFG_CONF=$(realpath $2)
            shift;;
        *)
            echo_fail "*** error: unknown option: $1 (use the -h option for usage information)"
            exit 1;;
    esac
    shift
done

CFG_CONF=${CFG_CONF:=$PWD/build-qt5-rpi.conf}

if [ -e "$CFG_CONF" ]; then
    source "$CFG_CONF"
elif [ $DO_INIT = false ] && [ $DO_HELP = false ]; then
    echo_fail "*** error: configuration file '$CFG_CONF' not found"
    exit 1
fi

CFG_RPI_LOGIN=${CFG_RPI_LOGIN:=pi@raspberrypi}              # Raspberry pi ssh login <USER>@<HOST>
CFG_QT_SOURCE=${CFG_QT_SOURCE:=~/qt5}                       # Qt source directory
CFG_QT_CONFIG=${CFG_QT_CONFIG:=$DEFAULT_QT_CONFIG}          # Qt configure options
CFG_QT_USE_X11=${CFG_QT_USE_X11:=false}                     # true: Include support for X11
CFG_ROOT=${CFG_ROOT:=$PWD}                                  # Root directory
CFG_BUILD=${CFG_BUILD:=$CFG_ROOT/build}                     # Build directory
CFG_SYSROOT=${CFG_SYSROOT:=$CFG_ROOT/sysroot}               # Sysroot directory
CFG_PREFIX=${CFG_PREFIX:=/usr/local/qt5}                    # Raspberry Pi runtime installation directory
CFG_EXTPREFIX=${CFG_EXTPREFIX:=$CFG_ROOT/sdk}               # Host runtime installation directory
CFG_HOSTPREFIX=${CFG_HOSTPREFIX:=$CFG_ROOT/hosttools}       # Host tools installation directory
CFG_RELPREFIX=${CFG_RELPREFIX:=$CFG_ROOT/release}           # Release archives directory

export PKG_CONFIG_LIBDIR=$CFG_SYSROOT/usr/lib/pkgconfig:$CFG_SYSROOT/usr/share/pkgconfig:$CFG_SYSROOT/usr/lib/arm-linux-gnueabihf/pkgconfig:$CFG_SYSROOT/opt/vc/lib/pkgconfig
export PKG_CONFIG_SYSROOT_DIR=$CFG_SYSROOT

if [ $DO_HELP = true ]; then
    show_help
    exit 1
fi

COMPLETED_NORMAL=false

trap exit_handler EXIT
trap exit ERR

echo_msg "Qt5 cross-builder for Raspberry Pi"

if [ $DO_INIT = true ]; then
    echo_msg "Executing command: init"
    set -o xtrace
    write_config
    set +o xtrace
    echo_msg "init: ok."
fi

if [ $DO_SYNC = true ]; then
    echo_msg "Executing command: sync"
    set -o xtrace
    sync_rpi
    set +o xtrace
    echo_msg "sync: ok."
fi

if [ $DO_CONFIG = true ]; then
    echo_msg "Executing command: config"
    set -o xtrace
    if [ ! -d "$CFG_SYSROOT" ]; then
        sync_rpi
    fi
    clean_host
    configure_qt
    set +o xtrace
    echo_msg "config: ok."
fi

if [ $DO_BUILD = true ]; then
    echo_msg "Executing command: build"
    set -o xtrace
    make_qt
    patch_libQt5WebEngineCore_so_5_9_3
    set +o xtrace
    echo_msg "build: ok."
fi

if [ $DO_INSTALL = true ]; then
    echo_msg "Executing command: install"
    set -o xtrace
    install_qt_to_host
    clean_rpi
    install_qt_to_rpi
    pack_archives
    set +o xtrace
    echo_msg "install: ok."
fi

echo_msg "All done."

COMPLETED_NORMAL=true
