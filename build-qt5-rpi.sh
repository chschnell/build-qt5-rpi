#!/bin/bash
#
# MIT License
#
# Copyright (c) 2018 Christian Schnell <christian.d.schnell@gmail.com>
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

shopt -s expand_aliases

alias echo_on='{ set -o xtrace; } 2> /dev/null'
alias echo_off='{ set +o xtrace; } 2> /dev/null'

# --- constants --------------------------------------------------------------

readonly APT_PKGS_RPI_DEV="zlib1g-dev libjpeg62-turbo-dev libpng-dev\
 libfreetype6-dev libssl1.0-dev libicu-dev libxslt1-dev libdbus-1-dev\
 libfontconfig1-dev libcap-dev libudev-dev libpci-dev libnss3-dev\
 libasound2-dev libbz2-dev libgcrypt11-dev libdrm-dev libcups2-dev\
 libevent-dev libinput-dev libts-dev libmtdev-dev libpcre3-dev libre2-dev\
 libwebp-dev libopus-dev unixodbc-dev libsqlite0-dev libxcursor-dev\
 libxcomposite-dev libxdamage-dev libxrandr-dev libxtst-dev libxss-dev\
 libxkbcommon-dev libdouble-conversion-dev libbluetooth-dev\
 libgstreamer0.10-dev libgstreamer-plugins-base0.10-dev libgstreamer1.0-dev\
 libgstreamer-plugins-base1.0-dev libatspi2.0-dev"

readonly APT_PKGS_RPI_X11_DEV="libx11-xcb-dev libgbm-dev libxcb-xfixes0-dev\
 libxcb-glx0-dev libsm-dev libxkbcommon-x11-dev libgtk-3-dev libwayland-dev\
 libxcb-cursor-dev libxcb-keysyms1-dev libxcb-xinerama0-dev libxcb-sync-dev\
 libxcb-randr0-dev libxcb-icccm4-dev"

readonly APT_PKGS_RPI_TOOLS="ttf-mscorefonts-installer fontconfig upower"

readonly DEFAULT_QT_CONFIG="-release -opensource -confirm-license\
 -platform linux-g++ -device linux-rasp-pi2-g++ -device-option\
 CROSS_COMPILE=arm-linux-gnueabihf- -opengl es2 -silent -nomake tests\
 -nomake examples"

readonly ATTR_RED="$(tput bold && tput setaf 1)"
readonly ATTR_GREEN="$(tput bold && tput setaf 2)"
readonly ATTR_WHITE="$(tput bold && tput setaf 7)"
readonly ATTR_RESET="$(tput sgr0)"

# --- functions --------------------------------------------------------------

function print_attr {
    echo -e "${1}[build-qt5-rpi $(date -d@$SECONDS -u +%H:%M:%S)]${ATTR_RESET} ${2}"
}

function log_msg {
    print_attr $ATTR_GREEN "$1"
}

function log_info {
    print_attr $ATTR_WHITE "$1"
}

function log_error {
    echo_off
    print_attr $ATTR_RED "$1"
}

function error_exit {
    echo_off
    print_attr $ATTR_RED "*** error: $1"
    exit 1
}

function write_config {
    cat <<EOF > "$CFG_CONF"
#
# Raspbian image file
#
CFG_RPI_RASPBIAN_IMG="$CFG_RPI_RASPBIAN_IMG"

#
# Qt source directory
#
CFG_QT_SOURCE="$CFG_QT_SOURCE"

#
# Qt configure options
#
CFG_QT_CONFIG="$CFG_QT_CONFIG"

#
# X11 support (false|true)
#   false: Disable support for X11
#   true:  Enable support for X11
#
CFG_QT_USE_X11=$CFG_QT_USE_X11

#
# Maintainer's e-mail address in generated .deb packages, for example:
#   John Smith <john.smith@example.org>
#
CFG_DEB_MAINTAINER="$CFG_DEB_MAINTAINER"
EOF
}

MNT_SYSROOT_DEV=""
MNT_HAVE_CHROOT=false

function exit_handler {
    echo_off
    trap '' SIGINT
    unmount_all
    if [ $COMPLETED_NORMAL = false ]; then
        echo
        log_error "*** Build failed"
    fi
}

function mount_sysroot {
    if [ -d "$SYSROOT_IMG_DIR" ]; then
        error_exit "sysroot already mounted"
    fi
    local LOSETUP_OPTS="" MOUNT_OPTS=""
    if [ "$#" -ge 1 ] && [ "$1" = "-r" ]; then
        LOSETUP_OPTS="-r"
        MOUNT_OPTS="-o ro"
    fi
    mkdir "$SYSROOT_IMG_DIR"
    MNT_SYSROOT_DEV="$(sudo losetup -f)"
    { log_info "Mounting \"${SYSROOT_IMG}\" into \"$SYSROOT_IMG_DIR\" using \"${MNT_SYSROOT_DEV}\""; } 2> /dev/null
    sudo losetup ${LOSETUP_OPTS} -P "${MNT_SYSROOT_DEV}" "${SYSROOT_IMG}"
    sudo mount ${MOUNT_OPTS} "${MNT_SYSROOT_DEV}p2" "${SYSROOT_IMG_DIR}"
    sudo mount ${MOUNT_OPTS} "${MNT_SYSROOT_DEV}p1" "${SYSROOT_IMG_DIR}/boot"
}

function mount_sysroot_chroot {
    mount_sysroot
    { log_info "Installing support for chroot with qemu into \"$SYSROOT_IMG_DIR\""; } 2> /dev/null
    MNT_HAVE_CHROOT=true
    sudo mount -t proc proc "${SYSROOT_IMG_DIR}/proc"
    sudo mount -o bind /dev "${SYSROOT_IMG_DIR}/dev"
    sudo mount -t devpts devpts "${SYSROOT_IMG_DIR}/dev/pts"
    sudo cp -p /usr/bin/qemu-arm-static "${SYSROOT_IMG_DIR}/usr/bin"
}

function unmount_all {
    if [ "$MNT_HAVE_CHROOT" = true ]; then
        { log_info "Removing chroot support from \"$SYSROOT_IMG_DIR\""; } 2> /dev/null
        sudo umount "${SYSROOT_IMG_DIR}/dev/pts" "${SYSROOT_IMG_DIR}/dev" "${SYSROOT_IMG_DIR}/proc" || true
        sudo rm -f "${SYSROOT_IMG_DIR}/usr/bin/qemu-arm-static" || true
        MNT_HAVE_CHROOT=false
    fi
    if [ -d "$SYSROOT_IMG_DIR" ]; then
        { log_info "Unmounting \"${SYSROOT_IMG}\""; } 2> /dev/null
        sudo umount "${SYSROOT_IMG_DIR}/boot" "${SYSROOT_IMG_DIR}" || true
        sudo losetup -d "${MNT_SYSROOT_DEV}" || true
        rmdir "$SYSROOT_IMG_DIR"
        MNT_SYSROOT_DEV=""
    fi
}

function get_rpi_apt_dev_dependencies {
    local RESULT="$APT_PKGS_RPI_DEV"
    if [ $CFG_QT_USE_X11 = true ]; then
        RESULT+=" $APT_PKGS_RPI_X11_DEV"
    fi
    echo "$RESULT"
}

function get_rpi_apt_nondev_dependencies {
    local WORK_LIST="$(get_rpi_apt_dev_dependencies)"
    local TODO_LIST DONE_LIST RESULT_LIST PACKAGE
    while [ -n "$WORK_LIST" ]; do
        for PACKAGE in `sudo LC_ALL=C.UTF-8 LANGUAGE=C.UTF-8 LANG=C.UTF-8 chroot "$SYSROOT_IMG_DIR" \
                dpkg-query -Wf '${Depends},' $WORK_LIST | \
                sed 's/,/\n/g; s/([^)]*)//g; s/\s|[^\n]*\n/\n/g'`; do
            if echo $DONE_LIST | grep -q "\<$PACKAGE\>"; then
                continue
            elif [[ $PACKAGE =~ .*-dev$ ]]; then
                TODO_LIST+="$PACKAGE "
            else
                RESULT_LIST+="$PACKAGE"$'\n'
            fi
            DONE_LIST+=" $PACKAGE"
        done
        WORK_LIST="$TODO_LIST"
        TODO_LIST=""
    done
    echo -n "$RESULT_LIST" | sort | uniq | paste -sd " " -
}

function build_sysroot_img {
    { log_info "Creating \"${SYSROOT_IMG}\""; } 2> /dev/null
    cp "$CFG_RPI_RASPBIAN_IMG" "$SYSROOT_IMG"

    mount_sysroot_chroot

    { log_info "Updating apt repository index in \"${SYSROOT_IMG}\""; } 2> /dev/null
    sudo chroot "$SYSROOT_IMG_DIR" apt-get update -q
    { log_info "Upgrading apt packages in \"${SYSROOT_IMG}\""; } 2> /dev/null
    sudo LC_ALL=C.UTF-8 LANGUAGE=C.UTF-8 LANG=C.UTF-8 chroot "$SYSROOT_IMG_DIR" apt-get -qy upgrade
    { log_info "Running rpi-update in \"${SYSROOT_IMG}\""; } 2> /dev/null
    sudo chroot "$SYSROOT_IMG_DIR" rpi-update
    { log_info "Updating apt repository index in \"${SYSROOT_IMG}\""; } 2> /dev/null
    sudo chroot "$SYSROOT_IMG_DIR" apt-get update -q
    { log_info "Installing apt packages for Qt in \"${SYSROOT_IMG}\""; } 2> /dev/null
    sudo LC_ALL=C.UTF-8 LANGUAGE=C.UTF-8 LANG=C.UTF-8 chroot "$SYSROOT_IMG_DIR" apt-get -qy install $(get_rpi_apt_dev_dependencies)

    replace_absolute_symlinks "/lib" "/usr/include" "/usr/lib" "/usr/share" "/opt/vc"

    { log_info "Copying sysroot to \"${QT_SYSROOT_DIR}\""; } 2> /dev/null
    pushd "${SYSROOT_IMG_DIR}"
    sudo rsync -aR --del --exclude=/lib/systemd --exclude=/usr/lib/ssl/private \
        lib usr/include usr/lib usr/share opt/vc "${QT_SYSROOT_DIR}"
    popd

    unmount_all
}

function replace_absolute_symlinks {
    echo_off
    local DIRECTORY SYMLINK SYMLINK_TARGET
    for DIRECTORY in "$@"; do
        log_info "Replacing absolute with relative symlinks in \"${SYSROOT_IMG}${DIRECTORY}\""
        for SYMLINK in $(find "${SYSROOT_IMG_DIR}${DIRECTORY}" -type l); do
            SYMLINK_TARGET="$(readlink $SYMLINK)"
            if [ "${SYMLINK_TARGET:0:1}" = "/" ]; then
                log_info "replacing symlink ${SYMLINK} -> ${SYMLINK_TARGET}"
                sudo ln -sfr "${SYSROOT_IMG_DIR}${SYMLINK_TARGET}" "${SYMLINK}"
            fi
        done
    done
    echo_on
}

function clean_host {
    { log_info "Cleaning host files from previous build"; } 2> /dev/null
    sudo rm -rf "$QT_BUILD_DIR" "$RPI_SDK_DIR" "$HOST_TOOLS_DIR"
}

function configure_qt {
    { log_info "Running Qt's configure"; } 2> /dev/null
    mkdir -p "$ROOT_DIR" "$QT_BUILD_DIR"
    pushd "$QT_BUILD_DIR"
    "$CFG_QT_SOURCE/configure" $CFG_QT_CONFIG -sysroot "$QT_SYSROOT_DIR" -prefix "$RPI_SDK_DIR" -extprefix "$RPI_SDK_DIR" -hostprefix "$HOST_TOOLS_DIR"
    popd
}

function make_qt {
    { log_info "Running Qt's make"; } 2> /dev/null
    make -C "$QT_BUILD_DIR" "-j$(nproc)"
}

function file_replace_c_str {
    local FILE=$1 OLD=$2 NEW=$3
    if [ ${#OLD} -lt ${#NEW} ]; then
        error_exit "New string '$NEW' must not be longer than '$OLD'"
    fi
    sed -e "s@${OLD}\\x00@${NEW}\\x00${OLD:${#NEW}+1}\\x00@" -i "$FILE"
}

function patch_libQt5WebEngineCore_so_5_9_3 {
    if [ -e "${QT_BUILD_DIR}/qtwebengine/lib/libQt5WebEngineCore.so.5.9.3" ]; then
        local LIBFILE=$(realpath "${QT_BUILD_DIR}/qtwebengine/lib/libQt5WebEngineCore.so.5.9.3")
        { log_info "Patching broken paths in \"${LIBFILE}\""; } 2> /dev/null
        file_replace_c_str "${LIBFILE}" "${QT_SYSROOT_DIR}/opt/vc/lib" /opt/vc/lib
        file_replace_c_str "${LIBFILE}" libEGL.so.1 libEGL.so
        file_replace_c_str "${LIBFILE}" libGLESv2.so.2 libGLESv2.so
    fi
}

function install_qt_to_host {
    { log_info "Running Qt's make install"; } 2> /dev/null
    sudo mkdir -p "$RPI_SDK_DIR" "$HOST_TOOLS_DIR"
    sudo make -C "$QT_BUILD_DIR" install
}

function build_rpi_deb {
    local QT_VERSION="$1"
    local ARCH="armhf"
    local DEB_PACKAGE_NAME="qt-everywhere-opensource-rpi"
    local DEB_PACKAGE_DIR="${DEB_PACKAGE_NAME}_${QT_VERSION}_${ARCH}"

    { log_info "Building \"${DEB_PACKAGE_DIR}.deb\""; } 2> /dev/null

    sudo rm -rf "${DEB_PACKAGE_DIR}.deb" "${DEB_PACKAGE_DIR}"
    mkdir -p "${DEB_PACKAGE_DIR}/DEBIAN" "${DEB_PACKAGE_DIR}${RPI_SDK_DIR}" "${DEB_PACKAGE_DIR}/etc/ld.so.conf.d"

    { log_info "Building list of package dependencies"; } 2> /dev/null
    mount_sysroot_chroot
    echo_off
    local DEPENDENCIES="$(get_rpi_apt_nondev_dependencies)"
    echo_on
    unmount_all

    DEPENDENCIES+=" ${APT_PKGS_RPI_TOOLS}"

    { log_info "Creating \"/DEBIAN/control\""; } 2> /dev/null
    cat <<EOF > "${DEB_PACKAGE_DIR}/DEBIAN/control"
Package: ${DEB_PACKAGE_NAME}
Architecture: ${ARCH}
Maintainer: ${CFG_DEB_MAINTAINER}
Priority: optional
Version: ${QT_VERSION}
Description: Custom qt-everywhere-opensource for Raspberry Pi
Depends: $(echo "${DEPENDENCIES}" | sed "s/ /, /g")
EOF

    { log_info "Creating \"/DEBIAN/triggers\""; } 2> /dev/null
    echo "activate-noawait ldconfig" > "${DEB_PACKAGE_DIR}/DEBIAN/triggers"

    { log_info "Creating \"/etc/ld.so.conf.d/qt5.conf\""; } 2> /dev/null
    echo "$RPI_SDK_DIR/lib" > "${DEB_PACKAGE_DIR}/etc/ld.so.conf.d/qt5.conf"

    { log_info "Copying files into \"${DEB_PACKAGE_DIR}\""; } 2> /dev/null
    cp -rp "${RPI_SDK_DIR}" "${DEB_PACKAGE_DIR}/usr/local"

    { log_info "Building ${DEB_PACKAGE_DIR}"; } 2> /dev/null
    sudo chown -R root:root "${DEB_PACKAGE_DIR}"
    dpkg-deb --build "${DEB_PACKAGE_DIR}"
    sudo rm -rf "${DEB_PACKAGE_DIR}"
}

function build_host_deb {
    local QT_VERSION="$1"
    local ARCH="$(dpkg --print-architecture)"
    local DEB_PACKAGE_NAME="qt-everywhere-opensource-host"
    local DEB_PACKAGE_DIR="${DEB_PACKAGE_NAME}_${QT_VERSION}_${ARCH}"

    { log_info "Building \"${DEB_PACKAGE_DIR}.deb\""; } 2> /dev/null

    sudo rm -rf "${DEB_PACKAGE_DIR}.deb" "${DEB_PACKAGE_DIR}"
    mkdir -p "${DEB_PACKAGE_DIR}/DEBIAN" "${DEB_PACKAGE_DIR}${RPI_SDK_DIR}"

    { log_info "Creating \"${DEB_PACKAGE_DIR}/DEBIAN/control\""; } 2> /dev/null
    cat <<EOF > "${DEB_PACKAGE_DIR}/DEBIAN/control"
Package: ${DEB_PACKAGE_NAME}
Architecture: ${ARCH}
Maintainer: ${CFG_DEB_MAINTAINER}
Priority: optional
Version: ${QT_VERSION}
Description: Host cross-tools of qt-everywhere-opensource for Raspberry Pi
Depends: build-essential, crossbuild-essential-armhf
EOF

    { log_info "Copying files into \"${DEB_PACKAGE_DIR}\""; } 2> /dev/null
    cp -rp "${QT_SYSROOT_DIR}" "${RPI_SDK_DIR}" "${HOST_TOOLS_DIR}"/* "${DEB_PACKAGE_DIR}/usr/local"

    { log_info "Building ${DEB_PACKAGE_DIR}"; } 2> /dev/null
    sudo chown -R root:root "${DEB_PACKAGE_DIR}"
    dpkg-deb --build "${DEB_PACKAGE_DIR}"
    sudo rm -rf "${DEB_PACKAGE_DIR}"
}

function build_debs {
    { log_info "Querying qmake for QT_VERSION"; } 2> /dev/null
    local QT_VERSION="$($HOST_TOOLS_DIR/bin/qmake -query QT_VERSION)"

    build_rpi_deb "$QT_VERSION"
    build_host_deb "$QT_VERSION"
}

# --- main -------------------------------------------------------------------

function help_exit {
    cat <<EOF
Usage:
    $(basename $0) [OPTION | COMMAND]...

Commands:
    init -r <RASPBIAN_IMG_FILE> -s <QT_SOURCE_DIR>
        Creates build configuration file "build-qt5-rpi.conf"
    mksysroot
        Creates sysroot for Qt from a modified copy of a Raspbian image
    config
        Cleans remains from previous build and configures Qt
    build
        Makes Qt (parallelized over number of cores)
    install
        Installs Qt runtime to host and Raspberry Pi, creates .deb packages
    all
        Same as 'config build install'
    help
        Shows this help and exits

Options:
    -r FILE     Use Raspbian Image file FILE
    -s DIR      Use Qt source directory DIR
    -l FILE     Log all script output to FILE
    -c FILE     Use build configuration file FILE
    -h          Show help and exit

Examples:
    $(basename $0) init -r raspbian-stretch-lite.img -s qt-everywhere-opensource-src-5.9.4
        Initialize build with Qt 5.9.3 sources and Raspbian Stretch Lite image
    $(basename $0) config
        Configure Qt
    $(basename $0) build
        Build Qt
    $(basename $0) install
        Install Qt to local host and create .deb packages
    $(basename $0) build install
        Both build and install Qt (multiple commands are allowed)
EOF
    exit 0
}

DO_INIT=false
DO_MKSYSROOT=false
DO_CONFIG=false
DO_BUILD=false
DO_INSTALL=false
LOGFILE=""

while [ "$#" -gt 0 ]; do
    case "$1" in
        init)
            DO_INIT=true ;;
        mksysroot)
            DO_MKSYSROOT=true ;;
        config)
            DO_CONFIG=true ;;
        build)
            DO_BUILD=true ;;
        install)
            DO_INSTALL=true ;;
        all)
            DO_CONFIG=true
            DO_BUILD=true
            DO_INSTALL=true
            ;;
        -r|--raspbian-img)
            if [ ! -f "$2" ]; then
                error_exit "Raspbian image file '$2' not found"
            fi
            CFG_RPI_RASPBIAN_IMG="$(realpath $2)"
            shift
            ;;
        -s|--source)
            if [ ! -d "$2" ]; then
                error_exit "Qt source directory '$2' not found"
            fi
            CFG_QT_SOURCE="$(realpath $2)"
            shift
            ;;
        -l|--log)
            LOGFILE="$(realpath $2)"
            shift
            ;;
        -c|--conf)
            if [ ! -f "$2" ]; then
                error_exit "build configuration file '$2' not found"
            fi
            CFG_CONF="$(realpath $2)"
            shift
            ;;
        -h|--help|"help")
            help_exit
            ;;
        *)
            error_exit "unknown option: $1 (use the -h option for usage information)"
            ;;
    esac
    shift
done

CFG_CONF=${CFG_CONF:=$PWD/build-qt5-rpi.conf}

if [ -f "$CFG_CONF" ]; then
    source "$CFG_CONF"
elif [ "$DO_INIT" = false ]; then
    error_exit "configuration file '$CFG_CONF' not found"
fi

CFG_RPI_RASPBIAN_IMG=${CFG_RPI_RASPBIAN_IMG:=}
CFG_QT_SOURCE=${CFG_QT_SOURCE:=}
CFG_QT_CONFIG=${CFG_QT_CONFIG:=$DEFAULT_QT_CONFIG}
CFG_QT_USE_X11=${CFG_QT_USE_X11:=false}
CFG_DEB_MAINTAINER=${CFG_DEB_MAINTAINER:=${USER}@$(hostname -f)}

ROOT_DIR="$(dirname $CFG_CONF)"
SYSROOT_IMG="${ROOT_DIR}/sysroot.img"
SYSROOT_IMG_DIR="${ROOT_DIR}/sysroot"
QT_BUILD_DIR="${ROOT_DIR}/build"
QT_SYSROOT_DIR="/usr/local/qt5-rpi-sysroot"
RPI_SDK_DIR="/usr/local/qt5-rpi"
HOST_TOOLS_DIR="/usr/local/qt5"

if [ -z "$CFG_RPI_RASPBIAN_IMG" ]; then
    error_exit "missing Raspbian image file (required argument -r, use -h for help)"
elif [ -z "$CFG_QT_SOURCE" ]; then
    error_exit "missing Qt source directory (required argument -s, use -h for help)"
fi

if [ "$DO_CONFIG" = true ] && [ ! -f "$SYSROOT_IMG" ]; then
    DO_MKSYSROOT=true
fi

export PKG_CONFIG_SYSROOT_DIR="${QT_SYSROOT_DIR}"
export PKG_CONFIG_LIBDIR="${QT_SYSROOT_DIR}/usr/lib/pkgconfig\
:${QT_SYSROOT_DIR}/usr/share/pkgconfig\
:${QT_SYSROOT_DIR}/usr/lib/arm-linux-gnueabihf/pkgconfig\
:${QT_SYSROOT_DIR}/opt/vc/lib/pkgconfig"

PS4='[$(basename ${BASH_SOURCE[0]}):$LINENO] '

COMPLETED_NORMAL=false

trap exit_handler EXIT
trap exit ERR

if [ -n "$LOGFILE" ]; then
    exec &> >(tee -i "$LOGFILE")
fi

log_msg "Qt5 cross-builder for Raspberry Pi"

if [ $DO_INIT = true ]; then
    log_msg "init: starting"
    echo_on
    write_config
    echo_off
    log_msg "init: done"
fi

if [ $DO_MKSYSROOT = true ]; then
    log_msg "mksysroot: starting"
    echo_on
    build_sysroot_img
    echo_off
    log_msg "mksysroot: done"
fi

if [ $DO_CONFIG = true ]; then
    log_msg "config: starting"
    echo_on
    clean_host
    configure_qt
    echo_off
    log_msg "config: done"
fi

if [ $DO_BUILD = true ]; then
    log_msg "build: starting"
    echo_on
    make_qt
    patch_libQt5WebEngineCore_so_5_9_3
    echo_off
    log_msg "build: done"
fi

if [ $DO_INSTALL = true ]; then
    log_msg "install: starting"
    echo_on
    install_qt_to_host
    build_debs
    echo_off
    log_msg "install: done"
fi

COMPLETED_NORMAL=true

log_msg "All done."
