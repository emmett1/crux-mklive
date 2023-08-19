#!/bin/sh -e

addmodules() {
	kmodpath=$(chroot $ROOTFS modinfo -k $KERNEL_VER -F filename $1)
	kmoddeps=$(chroot $ROOTFS modinfo -k $KERNEL_VER -F depends $1)
	#kmodfirmware=$(chroot $ROOTFS modinfo -k $KERNEL_VER -F firmware $1)
	[ "$kmodpath" ] || return 0
	kmodpathshort=${kmodpath##*/kernel/}
	[ -f $INITRDDIR/lib/modules/$KERNEL_VER/kernel/${kmodpathshort%.zst}* ] && return 0
	mkdir -p $INITRDDIR/lib/modules/$KERNEL_VER/kernel/${kmodpathshort%/*}
	case $kmodpath in
		*.zst) unzstd $ROOTFS/$kmodpath -o $INITRDDIR/lib/modules/$KERNEL_VER/kernel/${kmodpathshort%.zst} >/dev/null 2>&1;;
		*)     cp $ROOTFS/$kmodpath $INITRDDIR/lib/modules/$KERNEL_VER/kernel/${kmodpathshort%/*};;
	esac
	[ "$kmoddeps" ] || return 0
	for i in $(echo $kmoddeps | tr ',' ' '); do
		addmodules $i
	done
}

required_kmods="crypto \
	fs lib \
	drivers/block \
	drivers/md \
	drivers/ata \
	drivers/firewire \
	drivers/input \
	drivers/scsi \
	drivers/message \
	drivers/pcmcia \
	drivers/virtio \
	drivers/usb/host \
	drivers/usb/storage \
	drivers/hid \
	drivers/cdrom"

ROOTFS=$PWD/rootfs
LIVEDIR=$PWD/live-tree
INITRDDIR=$PWD/initrd-tree
INITRAMFS=$PWD/initrd.img
LIVEISO=$PWD/CRUX-LIVE-$(date +%Y%m%d).iso

DISTRONAME=CRUX
DISTROLABEL=LIVE

BUSYBOX_VERSION=1.35.0
SQUASHFS_EXCLUDE="usr/ports"

for i in $ROOTFS/boot/*; do
	case $(file $i) in
		*bzImage*) KERNEL_IMG=$i
				   KERNEL_VER=$(file $i | awk '{print $9}');;
	esac
done

if [ ! "$KERNEL_IMG" ]; then
	echo "no kernel found, aborted"
	exit 1
fi

KERNEL_MODULES_DIR=lib/modules/$KERNEL_VER

if [ ! -d "$ROOTFS/$KERNEL_MODULES_DIR" ]; then
	echo "kernel modules directory '$ROOTFS/$KERNEL_MODULES_DIR' not found, aborted"
	exit 1
fi

if [ ! -f $INITRAMFS ]; then	
	if [ ! -f $PWD/busybox ]; then
		echo "Downloading static busybox..."
		curl -O https://www.busybox.net/downloads/binaries/$BUSYBOX_VERSION-x86_64-linux-musl/busybox
	fi
	
	echo "Generating live initramfs..."
	rm -rf $INITRDDIR
	mkdir -p $INITRDDIR

	# busybox & init
	mkdir -p $INITRDDIR/bin
	install -m0755 $PWD/init $INITRDDIR/init
	install -m0755 $PWD/busybox $INITRDDIR/bin/busybox

	# add kernel modules
	for i in $required_kmods; do
		[ -d $ROOTFS/$KERNEL_MODULES_DIR/kernel/$i ] || continue
		find $ROOTFS/$KERNEL_MODULES_DIR/kernel/$i -type f | while read -r line; do
			line=${line##*/}
			line=${line%.ko*}
			addmodules $line
		done
	done
	for i in order builtin builtin.modinfo; do
		cp $ROOTFS/$KERNEL_MODULES_DIR/modules.$i $INITRDDIR/lib/modules/$KERNEL_VER/
	done
	depmod -b $INITRDDIR $KERNEL_VER

	( cd $INITRDDIR ; find . | cpio -o -H newc --quiet | gzip -9 ) > $INITRAMFS
	echo "-> $INITRAMFS $(du -h $INITRAMFS | awk '{print $1}')"
fi

if [ ! -f $PWD/rootfs.sfs ]; then
	if [ "$SQUASHFS_EXCLUDE" ]; then
		for i in $SQUASHFS_EXCLUDE; do
			sqfs_exclude="$sqfs_exclude -e $ROOTFS/$i"
		done
	fi
	echo "Squashing rootfs..."
	mksquashfs $ROOTFS $PWD/rootfs.sfs \
		-b 1048576 \
		-comp xz \
		-e $ROOTFS/root/* \
		-e $ROOTFS/home/* \
		-e $ROOTFS/tmp/* \
		-e $ROOTFS/dev/* \
		-e $ROOTFS/proc/* \
		-e $ROOTFS/sys/* \
		-e $ROOTFS/run/* \
		$sqfs_exclude 2>/dev/null
	echo "-> $PWD/rootfs.sfs $(du -h $PWD/rootfs.sfs | awk '{print $1}')"
fi

# live directories
rm -fr $LIVEDIR
mkdir -p $LIVEDIR/boot
mkdir -p $LIVEDIR/isolinux
mkdir -p $LIVEDIR/rootfs

# livemedia marker
touch $LIVEDIR/livemedia

# syslinux stuffs
cp syslinux/* $LIVEDIR/isolinux

# squashed rootfs
cp $PWD/rootfs.sfs $LIVEDIR/boot/rootfs.sfs

# bootsplash image for syslinux and grub
cp files/splash.png $LIVEDIR/isolinux

# live script
mkdir -p $LIVEDIR/rootfs/root
cp files/live_script.sh $LIVEDIR/rootfs/root

# kernel and initrd
cp $KERNEL_IMG $LIVEDIR/boot/vmlinuz
cp $INITRAMFS $LIVEDIR/boot/initrd

# customization on live environments
cp -ra liverootfs/* $LIVEDIR/rootfs

# grub stuffs
mkdir -p $LIVEDIR/boot/grub/x86_64-efi $LIVEDIR/boot/grub/fonts
echo "set prefix=/boot/grub" > $LIVEDIR/boot/grub-early.cfg
cp -a $ROOTFS/usr/lib/grub/x86_64-efi/*.mod $LIVEDIR/boot/grub/x86_64-efi
cp -a $ROOTFS/usr/lib/grub/x86_64-efi/*.lst $LIVEDIR/boot/grub/x86_64-efi
cp files/unicode.pf2 $LIVEDIR/boot/grub/fonts/

# EFI stuffs
rm -f $LIVEDIR/boot/efiboot.img
mkdir -p $LIVEDIR/efi/boot
grub-mkimage -c $LIVEDIR/boot/grub-early.cfg -o $LIVEDIR/efi/boot/bootx64.efi -O x86_64-efi -p "" iso9660 normal search search_fs_file
modprobe loop
dd if=/dev/zero of=$LIVEDIR/boot/efiboot.img count=4096
mkdosfs -n $DISTROLABEL-UEFI $LIVEDIR/boot/efiboot.img
mkdir -p $LIVEDIR/boot/efiboot
mount -o loop $LIVEDIR/boot/efiboot.img $LIVEDIR/boot/efiboot
mkdir -p $LIVEDIR/boot/efiboot/EFI/boot
cp $LIVEDIR/efi/boot/bootx64.efi $LIVEDIR/boot/efiboot/EFI/boot
umount $LIVEDIR/boot/efiboot
rm -fr $LIVEDIR/boot/efiboot

sed "s/@DISTRONAME@/$DISTRONAME/g" files/isolinux.cfg > $LIVEDIR/isolinux/isolinux.cfg
sed "s/@DISTRONAME@/$DISTRONAME/g" files/grub.cfg > $LIVEDIR/boot/grub/grub.cfg

rm -f $LIVEISO

genisoimage -R -l -J -V "$DISTROLABEL" \
	-A $DISTROLABEL \
	-b isolinux/isolinux.bin \
	-c isolinux/isolinux.boot \
	-no-emul-boot \
	-boot-load-size 4 \
	-boot-info-table \
	-eltorito-alt-boot \
	-e boot/efiboot.img \
	-no-emul-boot \
	-input-charset utf-8 \
	-o $LIVEISO $LIVEDIR
isohybrid -u $LIVEISO
echo "-> $LIVEISO $(du -h $LIVEISO | awk '{print $1}')"
