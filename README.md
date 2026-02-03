# disk-cache

```
sudo initramfs/install.sh
sudo update-initramfs -u
sudo vi /etc/default/grub.d/40-force-partuuid.cfg
# comment out GRUB_FORCE_PARTUUID
sudo update-grub
```
