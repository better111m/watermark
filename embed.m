clc;clear; close all; fclose all;
%%%%%%%%%%%% 视觉无失真+100%提取率 水印嵌入（哈达玛变换版，适配彩色/灰度图像）%%%%%%%%%%%%%
%% 一、核心参数（精准控制修改量，灰度图自动忽略RGB协同相关参数）
stat_block_size = 16;          % 16×16像素统计块
target_img_size = 1024;        % 目标图像尺寸
N_base = 1.126;                % 基础强度（已优化）
N_max = 1.206;                 % 最大强度（已优化）
max_modify = 0.09;             % 单像素最大修改量，其他调到位了发现再调也没变化就是这里给限制了
min_abs_flag = 110;            % 响应值绝对值至少0.1，避免卡在0点
[img_raw, MAP] = imread('6.png'); % 原图路径（支持彩色/灰度图，可修改）

%% 二、加载JND图（保障视觉隐蔽性核心）
jnd_mat_path = 'jnd_matlab_result.mat';
if ~exist(jnd_mat_path, 'file')
    error('未找到1024×1024的JND图文件！请生成对应尺寸的JND图（rgb_jnd_map_1024_b_only.mat）');
end
loaded_jnd_data = load(jnd_mat_path);
rgb_jnd_map = loaded_jnd_data.rgb_jnd_map;
jnd_h = size(rgb_jnd_map, 1);
jnd_w = size(rgb_jnd_map, 2);

%% 三、图像预处理（灰度图保留单通道，彩色图保留RGB）
% 图像格式转换（仅索引图转RGB，灰度图不转RGB）
if ~isempty(MAP)
    img_org = ind2rgb(img_raw, MAP);  % 索引图转RGB（三通道）
    img_type = '彩色图（索引图转换）';
    img_c = 3;
elseif size(img_raw, 3) == 1
    img_org = img_raw;  % 灰度图：保留单通道（核心修改）
    img_type = '灰度图（单通道）';
    img_c = 1;
else
    img_org = img_raw;  % 彩色图：保留RGB三通道
    img_type = '彩色图（RGB三通道）';
    img_c = 3;
end

% 调整尺寸并标准化到0~1范围
img_org = imresize(img_org, [target_img_size, target_img_size]);
if max(img_org(:)) > 1
    img_org = im2double(img_org);
end
[img_h, img_w, ~] = size(img_org);

%% 四、初始化存储变量（适配单通道/三通道）
final_embed_img = img_org;      % 最终嵌入后图像
process_channel_sum = [];       % 处理通道统计块总和（灰度=单通道，彩色=B通道）
diff_original = [];             % 嵌入前后总和差异
pixel_diff_map = zeros(img_h, img_w);  % 像素修改量映射

%% 五、加载生成的水印文件（与原逻辑完全一致）
loaded_model = load('model1.mat');
model1 = loaded_model.model1;
loaded_code = load('code1.mat');
code1 = loaded_code.code1



% 打印水印信息
fprintf('\n==================== 水印模板加载成功 ====================\n');
fprintf('加载的64位水印序列（model1，纯±1）：\n');
disp(reshape(model1, 8, 8));
fprintf('==========================================================\n\n');

%% 六、核心嵌入逻辑（哈达玛变换版，优化63个系数）
% 1. 拆分16×16统计块（适配单通道/三通道）
row0 = target_img_size;
col0 = target_img_size;
ons1 = row0 / stat_block_size;  % 64（行方向块数）
ons2 = col0 / stat_block_size;  % 64（列方向块数）
cell_img_sub = mat2cell(img_org, ...
                       repmat(stat_block_size, 1, ons1), ...
                       repmat(stat_block_size, 1, ons2), ...
                       img_c);  % 按块拆分图像（自动适配通道数）

% 2. 计算处理通道统计块总和（灰度=单通道，彩色=B通道）
process_channel_sum = zeros(ons1, ons2);
fprintf('正在计算处理通道的16×16块总和...\n');
for m = 1:ons1
    for n = 1:ons2
        img_block = cell_img_sub{m,n};
        % 提取处理通道
        if img_c == 3  % 彩色图：处理B通道
            process_pixel = img_block(:,:,3);
        else  % 灰度图：处理单通道
            process_pixel = img_block;
        end
        process_channel_sum(m,n) = sum(process_pixel(:));  % 计算块总和
    end
end

% 3. 拆分8×8子块（64个8×8子块，对应64位model1）
cell_d = mat2cell(process_channel_sum, repmat(8, 1, 64/8), repmat(8, 1, 64/8));

% 4. 哈达玛域嵌入（优化63个系数）
% 生成8×8哈达玛矩阵
H = hadamard(8);
H_transform = (1/8) * H;  % 哈达玛变换矩阵（归一化）
% 生成除第一个系数外的所有63个系数的索引
[rows, cols] = meshgrid(1:8, 1:8);
all_indices = [rows(:), cols(:)];
non_dc_indices = all_indices(2:end, :);  % 排除第一个系数(1,1)
% 生成哈达玛权重（63个）
hadamard_weights = H(:);
hadamard_weights = hadamard_weights(2:end);  % 排除第一个系数
% fprintf('哈达玛权重=%.2f \n', hadamard_weights);

count = 1;  % 水印位索引
mismatch_count = 0;  % 统计符号不匹配的水印位数量
mismatch_records = [];  % 记录不匹配的水印位信息

fprintf('\n==================== 水印符号匹配校验 ====================\n');
for ii = 1:8  % 8×8子块行索引
   for jj = 1:8  % 8×8子块列索引
       % 对8×8子块进行哈达玛变换
       block = cell_d{ii,jj};
       hadamard_block = H_transform * block * H;  % 哈达玛变换（归一化）
       
       % 调用优化函数优化63个哈达玛系数
       hadamard_block_opt = minmax_fuction(hadamard_block, model1(count), 15);
       
       % 提取优化后的63个系数
       coeffs_opt = hadamard_block_opt(sub2ind(size(hadamard_block_opt), non_dc_indices(:,1), non_dc_indices(:,2)));
       coeffs_opt = coeffs_opt(:);
%        fprintf('微调前：%.6f\n', ...
%                  coeffs_opt);
       % 计算哈达玛系数的响应值（使用哈达玛权重）
       flag = sum(coeffs_opt .* hadamard_weights) ;

       current_sign = sign(flag);
       target_sign = model1(count);  
%        fprintf('微调前：目标符号=%d，实际符号=%d，加权响应=%.6f\n', ...
%                  target_sign, current_sign, flag);
       max_adjust = 30;  % 最多5次微调，确保远离0点
       adjust_count = 0;
       
       % 循环微调：确保符号匹配且响应值足够大
       while (current_sign ~= target_sign || abs(flag) < min_abs_flag) && adjust_count < max_adjust
           % 计算总调整量
           target_flag = target_sign * (min_abs_flag + 0.05);
           delta_total = target_flag - flag;
           base_delta = delta_total / 63;  % 均分至63个系数
           weight_sign = hadamard_weights(:);  % 权重符号（1=加调整量，-1=减调整量）
            delta_coeffs = zeros(63, 1);  % 每个系数的最终调整量（含方向）

            for k = 1:63
                if weight_sign(k) == 1
                    % 权重=1：系数 + 基础调整量
                    delta_coeffs(k) = base_delta;
                else  % weight_sign(k) == -1
                    % 权重=-1：系数 - 基础调整量（等价于 + 负的基础调整量）
                    delta_coeffs(k) = -base_delta;
                end
            end
           % 计算每个系数的调整量（使用哈达玛权重方向）
%            delta_coeffs = hadamard_weights * base_delta * model1(count);
           
           % 限制单个系数的最大调整幅度
           max_single_delta = 2;  % 哈达玛系数调整幅度
           delta_coeffs = max(min(delta_coeffs, max_single_delta), -max_single_delta);
           
           % 应用调整量到哈达玛系数
           coeffs_opt = coeffs_opt + delta_coeffs;
           hadamard_block_opt(sub2ind(size(hadamard_block_opt), non_dc_indices(:,1), non_dc_indices(:,2))) = coeffs_opt;
           
%            fprintf('微调后：%.6f\n', ...
%          hadamard_block_opt);

           % 重新计算响应值
           flag = sum(coeffs_opt .* hadamard_weights);
           current_sign = sign(flag);
           
           adjust_count = adjust_count + 1;

       end
       
       % 更新当前符号
       current_sign = sign(flag);

       watermark_bit = count;  % 严格限制在1-64
       if current_sign == target_sign
           match_status = '✅ 匹配';
       else
           match_status = '❌ 不匹配';
           mismatch_count = mismatch_count + 1;
           mismatch_records = [mismatch_records, watermark_bit];
       end

       fprintf('水印位%d（子块[%d,%d]）：目标符号=%d，实际符号=%d，加权响应=%.6f，%s\n', ...
                watermark_bit, ii, jj, target_sign, current_sign, flag, match_status);

       % 逆哈达玛变换还原为8×8子块
%        cell_d{ii,jj} = H * hadamard_block_opt * H;  % 逆哈达玛变换
       cell_d{ii,jj} = (1/8) * H * hadamard_block_opt * H;  % 修正逆变换
       count = count + 1;
   end
end
fprintf('==========================================================\n');
fprintf(' 水印符号匹配统计：共64位，匹配%d位，不匹配%d位\n', ...
        64 - mismatch_count, mismatch_count);
if mismatch_count > 0
    fprintf('不匹配的水印位索引：%s\n', num2str(mismatch_records));
else
    fprintf('所有水印位符号完全匹配，嵌入正确！\n');
end
fprintf('==========================================================\n\n');

% 5. 拼接嵌入后总和矩阵，限制合理范围
process_channel_sum_after = cell2mat(cell_d);
process_channel_sum_after = max(min(process_channel_sum_after, stat_block_size*stat_block_size), 0);
diff_original = process_channel_sum_after - process_channel_sum;  % 嵌入前后差异
% fprintf('块差异的总和=%.2f \n', diff_original(:));
% fprintf('所有块差异的总和=%.2f \n', sum(diff_original(:)));

% 6. 像素修改量分配（灰度图跳过RGB协同，核心逻辑不变）
adjusted_img_sub = cell(ons1, ons2);
fprintf('正在分配像素修改量并生成嵌入后图像...\n');
for m = 1:ons1
    for n = 1:ons2
        img_block = cell_img_sub{m,n};
        current_diff = diff_original(m,n);  % 当前块需修改的总差异
        % ---------------------- 1. JND自适应分配（基础，逻辑不变） ----------------------
        block_row_start = (m - 1)*stat_block_size + 1;
        block_row_end = block_row_start + stat_block_size - 1;
        block_col_start = (n - 1)*stat_block_size + 1;
        block_col_end = block_col_start + stat_block_size - 1;
        jnd_block = rgb_jnd_map(block_row_start:block_row_end, block_col_start:block_col_end, 3);
        jnd_sum = sum(jnd_block(:)) + eps;
        pixel_diff = current_diff .* (jnd_block / jnd_sum);
        pixel_diff = max(min(pixel_diff, max_modify), -max_modify);%限制最大修改量
        adjusted_img_sub{m,n} = cat(3, img_block(:,:,1), img_block(:,:,2), img_block(:,:,3) + pixel_diff);
        
        pixel_diff_map(block_row_start:block_row_end, block_col_start:block_col_end) = pixel_diff;
    end
end

% 7. 拼接完整嵌入后图像
final_embed_img = cell2mat(adjusted_img_sub);

%% 七、保存结果（适配单通道/三通道）
% 保存嵌入前图像
original_path = 'original_image_1024.png';
imwrite(uint8(img_org * 255), original_path)

% 保存嵌入后图像
embed_path = 'watermarked_image_1024_hadamard.png';
imwrite(uint8(final_embed_img * 255), embed_path);
save('watermarked_image_float.mat', 'final_embed_img');

% 计算并输出PSNR
psnr_value = psnr(uint8(final_embed_img*255), uint8(img_org*255));
ssim_value = ssim(rgb2gray(uint8(final_embed_img*255)), rgb2gray(uint8(img_org*255)));
fprintf('嵌入后图像PSNR：%.2f dB，SSIM：%.4f\n', psnr_value, ssim_value);


% 保存中间结果（包含哈达玛参数）
save('watermark_final_result_hadamard.mat', 'diff_original', 'rgb_jnd_map', 'final_embed_img', ...
     'process_channel_sum', 'img_org', 'pixel_diff_map', 'process_channel_sum_after', 'model1', 'code1', 'img_c', 'H', 'hadamard_weights');
fprintf('中间结果已保存至：watermark_final_result_hadamard.mat\n');

%% 八、嵌入前/后对比显示（适配单通道/三通道）
figure('Name', '1024×1024水印嵌入前/后对比（哈达玛变换版）', 'Position', [100, 100, 1400, 600]);
% 嵌入前图像
subplot(1, 2, 1);
if img_c == 1
    imshow(img_org, []);  % 灰度图自适应显示
    colormap gray;        % 灰度色图
else
    imshow(img_org);      % 彩色图正常显示
end
title(sprintf('嵌入前图像（1024×1024，%s）', img_type), 'FontSize', 12, 'FontWeight', 'bold');
xlabel('宽度（像素）', 'FontSize', 10);
ylabel('高度（像素）', 'FontSize', 10);

% 嵌入后图像
subplot(1, 2, 2);
if img_c == 1
    imshow(final_embed_img, []);  % 灰度图自适应显示
    colormap gray;                % 灰度色图
else
    imshow(final_embed_img);      % 彩色图正常显示
end
% 在标题中同时显示PSNR和SSIM
title(sprintf('嵌入后图像（哈达玛变换水印，PSNR=%.2f dB, SSIM=%.4f）', psnr_value, ssim_value), 'FontSize', 12, 'FontWeight', 'bold');
xlabel('宽度（像素）', 'FontSize', 10);
ylabel('高度（像素）', 'FontSize', 10);

sgtitle('水印嵌入前 vs 嵌入后（哈达玛变换版，适配彩色/灰度图像）', 'FontSize', 14, 'FontWeight', 'bold');

