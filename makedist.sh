#!/bin/sh

MAJOR=14
MINOR=2
MEDIA="../FreeBSD-${MAJOR}.${MINOR}-RELEASE-amd64-dvd1.iso"

dist=''
# set type of install
case "$1" in 
    'base')
        dist=base
        LABEL="${MAJOR}_${MINOR}_BASE"
        ;;
    'guac')
        dist=guac
        LABEL="${MAJOR}_${MINOR}_GUAC"
        ;;
    'unifi')
        dist=unifi
        LABEL="${MAJOR}_${MINOR}_UNIFI"
        ;;
    'wiki')
        dist=wiki
        LABEL="${MAJOR}_${MINOR}_WIKI"
        ;;
    *)
        echo "Usage: $0 [base|guac|unifi|wiki]"
        exit 1
        ;;
esac

BITSDIR=release-media

# the only sanity check here
if [[ ! -f $MEDIA ]]; then
    echo "No FreeBSD install DVD found, quitting."
    exit 1
fi

# Untar to create dirtree
echo "-------CREATE $BITSDIR && UNPACK MEDIA"
mkdir $BITSDIR
bsdtar -C "$BITSDIR" -xf "$MEDIA"

# to create dist: 
#   make file structure, e.g. mkdir -p usr/local/etc/
#   put files in there, usr/local/etc/{myscript,otherscript}.sh
#   zip it and xz it, put in BSDINSTALL_DISTDIR of install media
# this will zip it up and copy to BSDINSTALL_DISTDIR (usr/freebsd-dist)
echo "-------CREATE/COPY DIST AND SELECT ITS INSTALL"
tar -cvJf dist.txz usr
cp dist.txz "${BITSDIR}/usr/freebsd-dist"
cp installerconfig.base "${BITSDIR}/etc/installerconfig"
sed -i "s/SELECTEDDIST/$dist/" "${BITSDIR}/etc/installerconfig"

# Change some files
echo "-------MODIFY FILES FOR ROOT MOUNT AND FAST BOOT (TERM)"
echo "/dev/iso9660/$LABEL / cd9660 ro 0 0" > "${BITSDIR}/etc/fstab"
echo 'autoboot_delay="0"' >> "${BITSDIR}/boot/loader.conf"
# quick and dirty; if console, don't wait for user input, set TERM to xterm
sed -i 's/read TERM//' "${BITSDIR}/usr/libexec/bsdinstall/startbsdinstall"
sed -i 's/TERM=${TERM:-vt100}/TERM=xterm/' "${BITSDIR}/usr/libexec/bsdinstall/startbsdinstall"

# create DOS image with EFI filesystem and copy over EFI boot file
echo "-------CREATE EFI IMG"
TMPDIR=$(mktemp -d /tmp/efiboot.XXXXXXX)
BOOTIMG="${TMPDIR}/efiboot"
mkfs.vfat \
    -F 12 \
    -s 1 \
    -n EFISYS \
    -C \
    "$BOOTIMG" \
    2048

mkdir -p "${TMPDIR}/efi"
sudo mount -o loop "$BOOTIMG" "${TMPDIR}/efi"
sudo mkdir -p "${TMPDIR}/efi/EFI/BOOT"
sudo cp "${BITSDIR}/boot/loader.efi" "${TMPDIR}/efi/EFI/BOOT/bootx64.efi"
sudo umount "${TMPDIR}/efi"
mv "$BOOTIMG" "${BITSDIR}/boot/efiboot"
rm -rf "$TMPDIR"

# create ISO
echo "-------CREATE ISO IMG"
IMAGE="FreeBSD-${MAJOR}.${MINOR}-${dist}.iso"

# UEFI ONLY. BIOS booting of FreeBSD media is broken on SeaBIOS anyway.
xorriso -as mkisofs \
    -sysid "FreeBSD" -V "$LABEL" \
    -r -J -l \
    -eltorito-alt-boot \
    -e boot/efiboot \
      -no-emul-boot \
    -o "$IMAGE" \
    "$BITSDIR"

# Clean up
echo "-------REMOVE WORKING DIR AND DIST FILE"
rm -rf "$BITSDIR"
rm dist.txz

cat << EOF


###############################################################################

              All done. Your file is: $IMAGE

###############################################################################


EOF
