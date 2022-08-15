#ставим пакеты, чтобы dracut не ругался на их отсутствие
yum install -y xfsdump epel-release wget device-mapper-multipath cryptsetup dmraid && yum install -y ntfs-3g
wget --no-check-certificate -O /sbin/busybox https://busybox.net/downloads/binaries/1.28.1-defconfig-multiarch/busybox-x86_64 && chmod +x /sbin/busybox
script
#Подготовим временный том для / раздела
pvcreate /dev/sdb && vgcreate vg_root /dev/sdb && lvcreate -n lv_root -l +100%FREE /dev/vg_root
#Создадим на нем файловую систему и смонтируем его, чтобы перенести туда данные
mkfs.xfs /dev/vg_root/lv_root && mount /dev/vg_root/lv_root /mnt
#Этой командой скопируем все данные с / раздела в /mnt, в итоге вы должны увидеть SUCCESS
xfsdump -J - /dev/VolGroup00/LogVol00 | xfsrestore -J - /mnt
#переконфигурируем grub для того, чтобы при старте перейти в новый /
for i in /proc/ /sys/ /dev/ /run/ /boot/; do mount --bind $i /mnt/$i; done
chroot /mnt/
grub2-mkconfig -o /boot/grub2/grub.cfg
#Обновим образ initrd.
cd /boot ; for i in `ls initramfs-*img`; do dracut -v $i `echo $i|sed "s/initramfs-//g; s/.img//g"` --force; done
sed -i 's:rd.lvm.lv=VolGroup00/LogVol00:rd.lvm.lv=vg_root/lv_root:' /boot/grub2/grub.cfg
#Перезагружаемся успешно с новым рут томом. Убедиться в этом можно посмотрев вывод lsblk



Ctrl+D
reboot
vagrant ssh
sudo -i
lsblk
#Теперь нам нужно изменить размер старой VG и вернуть на него рут. Для этого удаляем старый LV размеров в 40G и создаем новый на 8G
lvremove -y /dev/VolGroup00/LogVol00 && lvcreate -y -n VolGroup00/LogVol00 -L 8G /dev/VolGroup00
#Проделываем на нем те же операции, что и в первый раз:
mkfs.xfs /dev/VolGroup00/LogVol00 && mount /dev/VolGroup00/LogVol00 /mnt
xfsdump -J - /dev/vg_root/lv_root | xfsrestore -J - /mnt
#Так же как в первый раз переконфигурируем grub, за исключением правки /etc/grub2/grub.cfg
for i in /proc/ /sys/ /dev/ /run/ /boot/; do mount --bind $i /mnt/$i; done
chroot /mnt/
grub2-mkconfig -o /boot/grub2/grub.cfg
cd /boot ; for i in `ls initramfs-*img`; do dracut -v $i `echo $i|sed "s/initramfs-//g; s/.img//g"` --force; done

#Пока не перезагружаемся и не выходим из под chroot - мы можем заодно перенести /var
#На свободных дисках создаем зеркало
pvcreate /dev/sd{c,d} && vgcreate vg_var /dev/sd{c,d} && lvcreate -L 950M -m1 -n lv_var vg_var
#Создаем на нем ФС и перемещаем туда /var
mkfs.ext4 /dev/vg_var/lv_var && mount /dev/vg_var/lv_var /mnt && cp -aR /var/* /mnt/
#На всякий случай сохраняем содержимое старого var (или же можно его просто удалить):
mkdir /tmp/oldvar && mv /var/* /tmp/oldvar && umount /mnt && mount /dev/vg_var/lv_var /var
echo "`blkid | grep var: | awk '{print $2}'` /var ext4 defaults 0 0" >> /etc/fstab
#После чего можно успешно перезагружаться в новый (уменьшенный root) и удалять временную Volume Group
Ctrl+D
reboot
lvremove -y /dev/vg_root/lv_root && vgremove /dev/vg_root && pvremove /dev/sdb
#Выделяем том под /home по тому же принципу что делали для /var
lvcreate -n LogVol_Home -L 2G /dev/VolGroup00 && mkfs.xfs /dev/VolGroup00/LogVol_Home && mount /dev/VolGroup00/LogVol_Home /mnt/
cp -aR /home/* /mnt/ && rm -rf /home/* && umount /mnt && mount /dev/VolGroup00/LogVol_Home /home/
#Правим fstab для автоматического монтирования /home
echo "`blkid | grep Home | awk '{print $2}'` /home xfs defaults 0 0" >> /etc/fstab

#/home - сделать том для снапшотов
#Сгенерируем файлы в /home/
touch /home/file{1..20}
#Снять снапшот
lvcreate -L 100MB -s -n home_snap /dev/VolGroup00/LogVol_Home
#Удалить часть файлов:
rm -f /home/file{11..20}
#Процесс восстановления со снапшота
umount /home
lvconvert --merge /dev/VolGroup00/home_snap
mount /home

#пробую на sdb+sde поставить btrfs с кешем, снапшотами и разметить там каталог /opt


pvcreate /dev/sd{b,e} && vgcreate vg_opt /dev/sd{b,e}
lvcreate -l 100%FREE -n lv_opt vg_opt /dev/sdb -y
lvcreate -L 1M -n lv_opt vg_opt








