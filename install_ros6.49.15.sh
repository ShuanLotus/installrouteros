#!/bin/bash

# 安装必要软件
echo "Installing required packages..."
apt update -y && apt install unzip -y || { echo "Failed to install packages"; exit 1; }

# 定义变量
VERSION="6.49.15"
IMG_FILE="chr-${VERSION}.img"
ZIP_FILE="${IMG_FILE}.zip"
MOUNT_POINT="/mnt"
OFFSET=512

# 自动获取第一个活动的网络接口名称
INTERFACE=$(ip -o link show | awk -F': ' '$2 != "lo" {print $2; exit}')
echo "Detected network interface: ${INTERFACE}"

# 下载镜像文件
echo "Downloading CHR image..."
wget "https://github.com/elseif/MikroTikPatch/releases/download/${VERSION}/${ZIP_FILE}" || { echo "Failed to download image"; exit 1; }

# 解压镜像文件
echo "Unzipping ${ZIP_FILE}..."
unzip -o "${ZIP_FILE}" || { echo "Failed to unzip ${ZIP_FILE}"; exit 1; }

# 显示镜像文件信息
echo "Displaying image file information..."
fdisk -lu "${IMG_FILE}" || { echo "Failed to read partition table"; exit 1; }

# 自动获取系统主磁盘设备名称
SYSTEM_DISK=$(lsblk -p -n -l -o NAME,TYPE | grep disk | head -n1 | awk '{print $1}')
echo "Detected system disk: ${SYSTEM_DISK}"

# 挂载镜像文件
echo "Mounting image file..."
mount -o loop,offset=${OFFSET} "${IMG_FILE}" "${MOUNT_POINT}" || { echo "Failed to mount image"; exit 1; }

# 获取网卡的 IP 地址
ADDR0=$(ip addr show ${INTERFACE} | grep global | cut -d' ' -f 6 | head -n 1)
if [ -z "${ADDR0}" ]; then
    echo "Failed to get IP address for ${INTERFACE}"
    exit 1
fi

# 创建 rw 目录并写入 autorun.scr 文件
mkdir -p "${MOUNT_POINT}/rw"
echo "
/ip address add address=${ADDR0} interface=[/interface ethernet find where name=ether1]
/ip route add gateway=\$GATE0
" > /mnt/rw/autorun.scr

# 卸载镜像文件
echo "Unmounting image file..."
umount "${MOUNT_POINT}" || { echo "Failed to unmount ${MOUNT_POINT}"; exit 1; }

# 触发系统同步
echo "Syncing filesystems..."
sync
echo u > /proc/sysrq-trigger

# 写入镜像并重启
echo "Writing image to ${SYSTEM_DISK} and rebooting..."
dd if="${IMG_FILE}" bs=1024 of="${SYSTEM_DISK}" && sync && reboot

echo "Script completed successfully."