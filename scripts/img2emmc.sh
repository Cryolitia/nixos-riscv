#!/usr/bin/env bash
set -e

# --- 1. 路径定位与输出准备 ---
# 如果提供了参数则使用参数，否则使用 result/sd-image 下唯一的 zst
if [ -n "$1" ]; then
    INPUT_ZST="$1"
else
    INPUT_ZST=$(ls result/sd-image/*.img.zst)
fi

echo "使用镜像: ${INPUT_ZST}"

# 脚本依赖路径
PARTITION_XML="scripts/partition_emmc.xml"
CONVERT_SCRIPT="scripts/raw2cimage.py"
OUT_DIR="output"

# 自动创建输出目录
if [ ! -d "$OUT_DIR" ]; then
    echo "创建输出目录: $OUT_DIR"
    mkdir -p "$OUT_DIR"
fi

rm "$OUT_DIR"/*.emmc

# --- 2. 准备临时工作环境 ---
WORK_DIR=$(mktemp -d)
echo "创建临时目录: ${WORK_DIR}"

cleanup() {
    echo "释放资源并清理临时文件..."
    [ -d "${WORK_DIR}/mnt" ] && sudo umount "${WORK_DIR}/mnt" 2>/dev/null || true
    sudo losetup -D 2>/dev/null || true
    rm -rf "${WORK_DIR}"
}
trap cleanup EXIT

# --- 3. 解压与提取 ---
cp "${INPUT_ZST}" "${WORK_DIR}/image.img.zst"

pushd "${WORK_DIR}" > /dev/null
echo "正在解压镜像..."
zstd -d image.img.zst

echo "挂载 Loop 设备并提取分区..."
LOOP_DEV=$(sudo losetup -fP --show image.img)

# 提取 Boot 分区内容 (p1)
mkdir -p mnt
sudo mount "${LOOP_DEV}p1" mnt
cp mnt/boot.sd ./boot.emmc
sudo umount mnt

# 提取 Rootfs 分区内容 (p2)
sudo dd if="${LOOP_DEV}p2" of=rootfs_ext4.emmc status=progress bs=4M
popd > /dev/null

# --- 4. 运行 Sophgo 转换工具并存入 output ---
echo "开始转换并保存至 ${OUT_DIR}..."

# 处理 boot
nix run nixpkgs#python3 -- "${CONVERT_SCRIPT}" "${WORK_DIR}/boot.emmc" "${OUT_DIR}" "${PARTITION_XML}"

# 处理 rootfs
nix run nixpkgs#python3 -- "${CONVERT_SCRIPT}" "${WORK_DIR}/rootfs_ext4.emmc" "${OUT_DIR}" "${PARTITION_XML}"

echo "--------------------------------------"
echo "成功！处理后的文件位于: ${OUT_DIR}/"
ls -lh "${OUT_DIR}"
