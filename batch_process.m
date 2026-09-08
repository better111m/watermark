% 主处理脚本：批量处理图片并进行水印嵌入和提取
% 该脚本循环处理imgs_new1目录中的图片，依次进行水印嵌入和提取操作
% 并将结果保存到指定文档中

clear; clc; close all;

% 定义目录路径
input_dir = './imgs_new1';  % 输入图片目录
output_dir = './imgs_new2'; % 输出图片目录
results_file = 'watermark_results.txt'; % 结果保存文件

% 检查输入目录是否存在
if ~exist(input_dir, 'dir')
    error('输入目录 %s 不存在！', input_dir);
end

% 检查输出目录是否存在，如果不存在则创建
if ~exist(output_dir, 'dir')
    mkdir(output_dir);
end

% 获取输入目录中的所有图片文件
img_extensions = {'*.jpg', '*.jpeg', '*.png', '*.bmp', '*.tif', '*.tiff'};
image_files = [];
for i = 1:length(img_extensions)
    img_list = dir(fullfile(input_dir, img_extensions{i}));
    if ~isempty(img_list)
        image_files = [image_files; img_list];
    end
end

% 如果没有找到图片文件，则报错
if isempty(image_files)
    error('在目录 %s 中未找到任何图片文件！', input_dir);
end

% 清空结果文件
fid = fopen(results_file, 'w');
fclose(fid);

% 循环处理每张图片
for i = 1:length(image_files)
    fprintf('正在处理第 %d 张图片: %s\n', i, image_files(i).name);
    
    % 构造输入图片路径
    input_img_path = fullfile(input_dir, image_files(i).name);
    
    % 获取文件名（不含扩展名）用于后续处理
    [img_path, img_name, img_ext] = fileparts(image_files(i).name);
    fprintf('  调试信息: 原始文件名="%s", img_path="%s", img_name="%s", img_ext="%s"\n', image_files(i).name, img_path, img_name, img_ext);
    
    % 确保获取到了文件名
    if isempty(img_name)
        img_name = image_files(i).name;
        fprintf('  警告：无法分离文件扩展名，使用完整文件名: %s\n', img_name);
    end
    
    % 确保img_name不是空的
    if isempty(img_name)
        img_name = sprintf('image_%d', i);
        fprintf('  使用默认名称: %s\n', img_name);
    end
    
    % 等待嵌入函数完成并生成文件后再进行提取
    pause(2); % 增加延迟确保文件写入完成
    
    % 1. 进行水印嵌入
    fprintf('  开始水印嵌入...\n');
    [psnr_val, ssim_val] = embed_rec_y_func(input_img_path, output_dir);
    
    % 构造嵌入水印后的图片路径 - 与embed_rec_y_func中的一致（使用.png扩展名）
    watermarked_img_path = fullfile(output_dir, [img_name '.png']);
    
    % 检查文件是否存在
    if ~exist(watermarked_img_path, 'file')
        fprintf('  错误：水印图片不存在: %s\n', watermarked_img_path);
        continue; % 跳过此图片
    end
    
    % 2. 进行水印提取
    fprintf('  开始水印提取...\n');
    [extraction_rate_64, extraction_rate_39] = extract_rec_y_func(watermarked_img_path, 'model1.mat');

    % 3. 将结果写入文档
    fid = fopen(results_file, 'a');
    fprintf(fid, '%s\t%.4f\t%.4f\t%.2f\t%.2f\t%s\t%s\n', [img_name img_ext], ssim_val, psnr_val, extraction_rate_64, extraction_rate_39, input_img_path, watermarked_img_path);
    fclose(fid);

    fprintf('  处理完成 - SSIM: %.4f, PSNR: %.4f, 64位提取率: %.2f%%, 39位提取率: %.2f%%\n', ssim_val, psnr_val, extraction_rate_64, extraction_rate_39);
    fprintf('  结果已保存到 %s\n', results_file);
    fprintf('\n');
end

fprintf('所有图片处理完成！结果已保存到 %s\n', results_file);