#!/usr/bin/env python3

import os
import re

# 读取 watermark_results.txt 文件
with open('watermark_results.txt', 'r') as f:
    lines = f.readlines()

# 处理每一行，更新文件路径
updated_lines = []
for line in lines:
    # 使用正则表达式匹配并替换文件名
    # 匹配形如 ./imgs_new1/X.jpg 或 ./imgs_new2/X.png 的路径
    def replace_path(match):
        full_match = match.group(0)
        path_part = match.group(1)  # ./imgs_new1/ 或 ./imgs_new2/
        num_part = match.group(3)   # 数字部分
        ext_part = match.group(4)   # 扩展名部分
        
        # 将数字转换为两位格式
        new_num = f"{int(num_part):02d}"
        
        return f"{path_part}{new_num}.{ext_part}"
    
    # 正则表达式模式：匹配 ./imgs_new1/X.ext 或 ./imgs_new2/X.ext
    pattern = r'(\./imgs_new\d+/)(\D*)(\d+)(\.\w+)'
    
    # 替换路径中的单数字为双数字
    updated_line = re.sub(pattern, lambda m: m.group(1) + f"{int(m.group(3)):02d}.{m.group(4)}", line)
    
    # 同时也要处理行首的文件名（如 "1.jpg" -> "01.jpg"）
    # 匹配行首的数字和扩展名
    updated_line = re.sub(r'^(\d+)(\.\w+)', lambda m: f"{int(m.group(1)):02d}{m.group(2)}\t", updated_line)
    
    updated_lines.append(updated_line)

# 写回文件
with open('watermark_results_updated.txt', 'w') as f:
    f.writelines(updated_lines)

print("watermark_results.txt 已更新，新文件保存为 watermark_results_updated.txt")