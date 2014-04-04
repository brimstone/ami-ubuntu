# http://www.technology-mania.com/2011/05/create-ubuntu-ami-from-scratch-on-local.html
# https://wiki.debian.org/Cloud/CreateEC2Image

BASE=precise
ADDPACKAGES=ssh linux-virtual isc-dhcp-client
SSHKEY=/home/brimstone/.ssh/id_rsa.pub
MIRROR=http://localhost:3142/ubuntu
EC2_HOME := ${PWD}/ec2
JAVA_HOME := /usr

# Ubuntu specific
debootstrap:
	sudo debootstrap --variant=minbase --include="${ADDPACKAGES}" precise "${BASE}" ${MIRROR}

clean-base: debootstrap
	sudo chroot "${BASE}" apt-get clean
	du -hs "${BASE}"

fix-fstab: debootstrap
	printf 'LABEL=cloudimg-rootfs	/	ext3	defaults	0	1\n' > "${BASE}/etc/fstab"

fix-swap: debootstrap
	printf '/dev/xvda2	swap	swap	defaults	0	0\n' > "${BASE}/etc/fstab"

fix-interfaces: debootstrap
	printf 'auto eth0\niface eth0 inet dhcp\n' >> "${BASE}/etc/network/interfaces"

fix-grub: debootstrap
	mkdir "${BASE}/boot/grub"
	echo 'default 0' > "${BASE}/boot/grub/menu.lst"
	echo 'fallback 1' >> "${BASE}/boot/grub/menu.lst"
	echo 'timeout 1' >> "${BASE}/boot/grub/menu.lst"
	echo 'title precise' >> "${BASE}/boot/grub/menu.lst"
	echo '     root (hd0)' >> "${BASE}/boot/grub/menu.lst"
	echo '     kernel /boot/vmlinuz-3.2.0-23-virtual root=LABEL=cloudimg-rootfs console=hvc0' >> "${BASE}/boot/grub/menu.lst"
	echo '     initrd /boot/initrd.img-3.2.0-23-virtual' >> "${BASE}/boot/grub/menu.lst"
	echo '' >> "${BASE}/boot/grub/menu.lst"
	echo 'title precise' >> "${BASE}/boot/grub/menu.lst"
	echo '     root (hd0,0)' >> "${BASE}/boot/grub/menu.lst"
	echo '     kernel /boot/vmlinuz-3.2.0-23-virtual root=LABEL=cloudimg-rootfs console=hvc0' >> "${BASE}/boot/grub/menu.lst"
	echo '     initrd /boot/initrd.img-3.2.0-23-virtual' >> "${BASE}/boot/grub/menu.lst"

rm-hwclock: debootstrap
	sudo chroot "${BASE}" update-rc.d -f hwclock remove
	sudo chroot "${BASE}" update-rc.d -f hwclock-save remove

# I wonder if some of this should happen with chef instead
ssh-key: debootstrap
	sed -i 's/#PasswordAuthentication yes/PasswordAuthentication no/' "${BASE}/etc/ssh/sshd_config"
	mkdir "${BASE}/root/.ssh" || true
	cat ${SSHKEY} > "${BASE}/root/.ssh/authorized_keys"
	chmod 700 "${BASE}/root/.ssh"
	chmod 600 "${BASE}/root/.ssh/authorized_keys"

locale-gen: debootstrap
	sudo chroot "${BASE}" locale-gen en_US.UTF-8

#mkimg: base
#	dd if=/dev/zero of="${BASE}.img" bs=10M count=100
#	printf "0,750,L\n,,S,\n;\n" | sfdisk -u M "${BASE}.img"
#	kpartx -a "${BASE}.img"
#	mkfs.ext3 /dev/mapper/loop0p1
#	mkswap /dev/mapper/loop0p2
#	mkdir mnt
#	mount /dev/mapper/loop0p1 mnt
#	rsync -a "${BASE}/" mnt/
#	umount mnt
#	rmdir mnt
#	kpartx -d "${BASE}.img"

mkflatimg: base
	dd if=/dev/zero of="${BASE}.img" bs=10M count=100
	mkfs.ext3 -F -L cloudimg-rootfs "${BASE}.img"
	mkdir mnt
	mount -o loop "${BASE}.img" mnt
	rsync -a "${BASE}/" mnt/
	umount mnt
	rmdir mnt

# meta
base: debootstrap clean-base fix-fstab fix-interfaces rm-hwclock ssh-key fix-grub

# EC2 stuff
ec2-api-tools.zip:
	wget http://s3.amazonaws.com/ec2-downloads/ec2-api-tools.zip

ec2-ami-tools.zip:
	wget http://s3.amazonaws.com/ec2-downloads/ec2-ami-tools.zip

ec2: ec2-api-tools.zip ec2-ami-tools.zip
	unzip ec2-api-tools.zip
	unzip ec2-ami-tools.zip
	mkdir ec2
	rsync -ar ec2-api-tools-*/* ec2
	rsync -ar ec2-ami-tools-*/* ec2
	rm -rf ec2-api-tools*
	rm -rf ec2-ami-tools*

bundle-image: ec2
	# ec2/bin/ec2-bundle-image -i precise.img --cert ~/.aws/cert-2XWJ6NYUFQS3GXV23GBETYWRK6RN2P63.pem -k ~/.aws/pk-2XWJ6NYUFQS3GXV23GBETYWRK6RN2P63.pem -u 2526-6169-6508 -r x86_64

upload-bundle: ec2
	# ec2/bin/ec2-upload-bundle -b brimstone-amis -m /tmp/precise.img.manifest.xml -a AKIAJQKRKC6ML7VU3YFA -s 5cHNLW20DHP2qw7xKAXKWtsUz+u3xUaWQdehj/Dv

register-bundle: ec2
	# ec2/bin/ec2-register brimstone-amis/precise.img.manifest.xml -n brimstone-amis/precise  -K ~/.aws/pk-2XWJ6NYUFQS3GXV23GBETYWRK6RN2P63.pem -C ~/.aws/cert-2XWJ6NYUFQS3GXV23GBETYWRK6RN2P63.pem

import-volume: ec2
	@ec2/bin/ec2-import-volume precise.img -o "$(AWS_ACCESS_KEY)" -w "$(AWS_SECRET_KEY)" -f raw -b brimstone-amis -z us-east-1a

	# ec2/bin/ec2-describe-images -o amazon --region us-east-1 | grep -i grub | grep x86_64 | column -t

	# while [ "$astatus" != "completed" ]; do astatus=$(ec2/bin/ec2-describe-conversion-tasks| awk '/import-vol-fh67x6ta/ {print $NF}'); echo $astatus; sleep 30; done; notify-send "done"

# special
.PHONY: all
all: bundle-image upload-bundle register-bundle

clean:
	rm -rf "${BASE}"
