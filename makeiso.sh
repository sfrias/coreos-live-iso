#!/bin/sh
# Author: Naoki OKAMURA (Nyarla) <nyarla[ at ]thotep.net>
# Usage: ./makeiso.sh
# Unlicense: This script is under the public domain.
# Requires: gzip tar mkisofs syslinux curl (or axel) ssh

set -e
 
# Default configurations
SYSLINUX_VERSION=${SYSLINUX_VERSION:="6.02"}
COREOS_VERSION=${COREOS_VERSION:="dev-channel"}
BOOT_ENV=${BOOT_ENV:="bios"}
SSH_PUBKEY_PATH=${SSH_PUBKEY_PATH:=~/.ssh/id_rsa.pub}
CURL=${CURL:="curl"} 
 
# Initialze variables
SYSLINUX_BASE_URL="ftp://www.kernel.org/pub/linux/utils/boot/syslinux"
SYSLINUX_BASENAME="syslinux-$SYSLINUX_VERSION"
SYSLINUX_URL="${SYSLINUX_BASE_URL}/${SYSLINUX_BASENAME}.tar.gz"
 
COREOS_BASE_URL="http://storage.core-os.net/coreos/amd64-generic"
COREOS_KERN_BASENAME="coreos_production_pxe.vmlinuz"
COREOS_INITRD_BASENAME="coreos_production_pxe_image.cpio.gz"
COREOS_VER_URL="${COREOS_BASE_URL}/${COREOS_VERSION}/version.txt"
COREOS_KERN_URL="${COREOS_BASE_URL}/${COREOS_VERSION}/${COREOS_KERN_BASENAME}"
COREOS_INITRD_URL="${COREOS_BASE_URL}/${COREOS_VERSION}/${COREOS_INITRD_BASENAME}"

if [ ! -f "${SSH_PUBKEY_PATH}" ]; then
    echo "Missing ${SSH_PUBKEY_PATH}. Please run ssh-keygen to generate keys."
    exit
fi
SSH_PUBKEY=`cat ${SSH_PUBKEY_PATH}`
 
bindir=`cd $(dirname $0) && pwd`
workdir=$bindir/${COREOS_VERSION}
 
echo "-----> Initialize working directory"
if [ ! -d $workdir ];then
    mkdir -p $workdir
fi;
 
cd $workdir
 
mkdir -p iso/coreos
mkdir -p iso/syslinux
mkdir -p iso/isolinux

echo "-----> CoreOS version "
$CURL -o version.txt ${COREOS_VER_URL}
cat version.txt
 
echo "-----> Download CoreOS's kernel"
if [ ! -e iso/coreos/vmlinuz ]; then
  $CURL -o iso/coreos/vmlinuz $COREOS_KERN_URL
fi
 
echo "-----> Download CoreOS's initrd"
if [ ! -e iso/coreos/cpio.gz ]; then
  $CURL -o iso/coreos/cpio.gz $COREOS_INITRD_URL
fi
cd iso/coreos
mkdir -p usr/share/oem
cat<<EOF > usr/share/oem/run
#!/bin/sh
 
# Place your OEM run commands here...
 
EOF
chmod +x usr/share/oem/run
gzip -d cpio.gz
find usr | cpio -o -A -H newc -O cpio
gzip cpio
rm -rf usr/share/oem
cd $workdir
 
echo "-----> Download syslinux and copy to iso directory"
if [ ! -e ${SYSLINUX_BASENAME} ]; then
  $CURL -o ${SYSLINUX_BASENAME}.tar.gz $SYSLINUX_URL
fi
tar zxf ${SYSLINUX_BASENAME}.tar.gz
 
cp ${SYSLINUX_BASENAME}/${BOOT_ENV}/com32/chain/chain.c32 iso/syslinux/
cp ${SYSLINUX_BASENAME}/${BOOT_ENV}/com32/lib/libcom32.c32 iso/syslinux/
cp ${SYSLINUX_BASENAME}/${BOOT_ENV}/com32/libutil/libutil.c32 iso/syslinux/
cp ${SYSLINUX_BASENAME}/${BOOT_ENV}/memdisk/memdisk iso/syslinux/
 
cp ${SYSLINUX_BASENAME}/${BOOT_ENV}/core/isolinux.bin iso/isolinux/
cp ${SYSLINUX_BASENAME}/${BOOT_ENV}/com32/elflink/ldlinux/ldlinux.c32 iso/isolinux/
 
echo "-----> Make isolinux.cfg file"
cat<<EOF > iso/isolinux/isolinux.cfg
INCLUDE /syslinux/syslinux.cfg
EOF
 
echo "-----> Make syslinux.cfg file"
cat<<EOF > iso/syslinux/syslinux.cfg
default coreos
prompt 1
timeout 15
 
label coreos
  kernel /coreos/vmlinuz
  append initrd=/coreos/cpio.gz root=squashfs: state=tmpfs: sshkey="${SSH_PUBKEY}"
EOF
 
echo "-----> Make ISO file"
cd iso
mkisofs -v -l -r -J -o ${bindir}/CoreOS.${COREOS_VERSION}.iso -b isolinux/isolinux.bin -c isolinux/boot.cat -no-emul-boot -boot-load-size 4 -boot-info-table .
isohybrid ${bindir}/CoreOS.${COREOS_VERSION}.iso
echo "-----> Cleanup"
cd $bindir
rm -rf $workdir
 
echo "-----> Finished"
echo "-----> Install ${bindir}/CoreOS.${COREOS_VERSION}.iso and ssh core@<ip>"
