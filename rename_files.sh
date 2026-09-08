#!/bin/bash

# 重命名 imgs_new1 文件夹中的文件
echo "重命名 imgs_new1 文件夹中的文件..."

cd imgs_new1

# 首先将所有文件重命名为临时名称，避免重名冲突
for file in *.jpg; do
    num=$(echo "$file" | sed 's/\.jpg$//' | sed 's/^0*//')  # 提取数字部分并去除前导零
    mv "$file" "temp_$num.jpg"
done

# 然后将临时文件重命名为两位数格式
for file in temp_*.jpg; do
    num=$(echo "$file" | sed 's/temp_\(.*\)\.jpg/\1/')
    new_name=$(printf "%02d.jpg" $num)
    mv "$file" "$new_name"
done

cd ..

echo "imgs_new1 文件夹重命名完成"

# 重命名 imgs_new2 文件夹中的文件
echo "重命名 imgs_new2 文件夹中的文件..."

cd imgs_new2

# 首先将所有文件重命名为临时名称，避免重名冲突
for file in *.png; do
    num=$(echo "$file" | sed 's/\.png$//' | sed 's/^0*//')  # 提取数字部分并去除前导零
    mv "$file" "temp_$num.png"
done

# 然后将临时文件重命名为两位数格式
for file in temp_*.png; do
    num=$(echo "$file" | sed 's/temp_\(.*\)\.png/\1/')
    new_name=$(printf "%02d.png" $num)
    mv "$file" "$new_name"
done

cd ..

echo "imgs_new2 文件夹重命名完成"
echo "所有文件重命名完成！"