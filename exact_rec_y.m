clc;clear; close all; fclose all;
%%%%%%%%%%%% 优化版水印提取（哈达玛变换版，适配彩色/灰度图像） %%%%%%%%%%%%%%
%% 一、关键参数（必须与嵌入代码完全一致，无修改）
blocksize = 16;         % 16×16统计块（与嵌入一致）
target_img_size = 1024; % 1024×1024尺寸
watermark_len_embed = 64;% 64位水印
bch_t = 5;              % BCH纠错能力
bch_n = 63;             % BCH(63,39,5)
bch_k = 39;             % 原始信息位

% 路径配置
% optimized_img_path = 'watermarked_image_1024_hadamard.png';  % 哈达玛预处理后的图像
optimized_img_path = './imgs/4_5.tif';  % 哈达玛预处理后的图像
% optimized_img_path = 'watermarked_image_1024_hadamard_original_optimized.png';  % 哈达玛预处理后的图像

original_watermark_path = 'original_watermark.mat';
bch_param_path = 'code1.mat';
model1_path = 'model1.mat';

%% 二、图像预处理（适配彩色/灰度，核心修改）
fprintf('==================== 加载并预处理图像 ====================\n');
[scanned_img_raw, MAP] = imread(optimized_img_path);

% 图像格式适配：保留原始通道类型（灰度单通道/彩色RGB）
if ~isempty(MAP)
    scanned_img = ind2rgb(scanned_img_raw, MAP);  % 索引图转RGB（三通道）
    img_type = '彩色图（索引图转换）';
    img_c = 3;
elseif size(scanned_img_raw, 3) == 1
    scanned_img = scanned_img_raw;  % 灰度图：保留单通道（核心适配）
    img_type = '灰度图（单通道）';
    img_c = 1;
else
    scanned_img = scanned_img_raw;  % 彩色图：保留RGB三通道
    img_type = '彩色图（RGB三通道）';
    img_c = 3;
end

% 尺寸+归一化（强制1024×1024）
scanned_img = imresize(scanned_img, [target_img_size, target_img_size]);
if max(scanned_img(:)) > 1
    scanned_img = im2double(scanned_img);
end

% 输出图像基本信息
[img_h, img_w, ~] = size(scanned_img);
fprintf('图像信息：%s，尺寸：%d×%d，通道数：%d\n', img_type, img_h, img_w, img_c);

%% 新增：提前加载model1（关键修复！确保提取时能使用target_sign）
if ~exist(model1_path, 'file')
    error('未找到model1.mat！请确保嵌入代码已生成该文件');
end
load(model1_path, 'model1');
if length(model1) ~= 64 || ~all(ismember(model1, [-1, 1]))
    error('model1格式错误！需64位±1序列');
end
fprintf('✅ 成功加载model1（64位±1水印序列）\n');

%% 三、核心提取逻辑（哈达玛变换版）
% 1. 拆分16×16统计块（适配单通道/三通道）
row0 = target_img_size;
col0 = target_img_size;
ons1 = row0 / blocksize;  % 64
ons2 = col0 / blocksize;  % 64
cell_img_scanned = mat2cell(scanned_img, ...
                           repmat(blocksize, 1, ons1), ...
                           repmat(blocksize, 1, ons2), ...
                           img_c);  % 最后一维适配通道数

% 2. 计算处理通道统计块总和（彩色=B通道，灰度=单通道，高斯加权求和逻辑不变）
process_channel_sum_scanned = zeros(ons1, ons2);


for m = 1:ons1
    for n = 1:ons2
        img_block = cell_img_scanned{m, n};
        % 提取处理通道（彩色=B通道，灰度=单通道）
        if img_c == 3
            process_pixel = img_block(:,:,3);  % 彩色图：处理B通道
        else
            process_pixel = img_block;  % 灰度图：处理单通道
        end
        % 加权求和（核心逻辑不变）
        process_channel_sum_scanned(m,n) = sum(process_pixel(:));  % 计算块总和

    end
end

% 3. 拆分为8×8哈达玛子块（替换DCT）
cell_d_scanned = mat2cell(process_channel_sum_scanned, ...
                         repmat(8, 1, watermark_len_embed/8), ...
                         repmat(8, 1, watermark_len_embed/8));

% 4. 哈达玛域加权响应提取（替换DCT）
% 生成8×8哈达玛矩阵（与嵌入一致）
H = hadamard(8);
H_transform = (1/8) * H;  % 归一化哈达玛变换矩阵
% 生成除DC系数外的63个系数索引和权重（与嵌入一致）
[rows, cols] = meshgrid(1:8, 1:8);
all_indices = [rows(:), cols(:)];
non_dc_indices = all_indices(2:end, :);  % 排除第一个系数(1,1)
hadamard_weights = H(:);
hadamard_weights = hadamard_weights(2:end);  % 排除DC系数

extracted_seq_01 = zeros(1, watermark_len_embed);
bit_idx = 1;
watermark_responses = zeros(1, watermark_len_embed);  % 保存每个水印位的加权响应值
fprintf('\n==================== 提取64位水印序列（哈达玛系数加权） ====================\n');
for ii = 1:8
    for jj = 1:8
        % 哈达玛变换（替换DCT）
        hadamard_scanned = H_transform * cell_d_scanned{ii, jj} * H;
        
        % 提取63个非DC系数（与嵌入一致）
        coeffs_scanned = hadamard_scanned(sub2ind(size(hadamard_scanned), non_dc_indices(:,1), non_dc_indices(:,2)));
        coeffs_scanned = coeffs_scanned(:);
        
        % 计算哈达玛加权响应（与嵌入时的flag计算逻辑一致）
        watermark_response = sum(coeffs_scanned .* hadamard_weights);
        watermark_responses(bit_idx) = watermark_response;
        
        target_sign = model1(bit_idx);
        response_abs = abs(watermark_response);
        
        % 响应值判断逻辑（完全不变）
        if watermark_response > 0
            extracted_seq_01(bit_idx) = 1;
        else
            extracted_seq_01(bit_idx) = 0;
        end
        
        fprintf('8×8块(%d,%d) | 哈达玛加权响应=%.6f | 提取位=%d\n', ...
                ii, jj, watermark_response, extracted_seq_01(bit_idx));
        bit_idx = bit_idx + 1;
    end
end

% 5. 转换为±1序列（逻辑完全不变）
extracted_model1 = extracted_seq_01 * 2 - 1;
fprintf('\n提取的64位±1序列：\n');
disp(reshape(extracted_model1, 8, 8));

%% 四、BCH解码（保持原逻辑，无修改）
final_watermark = [];
error_bits = 0;
fprintf('\n==================== BCH解码（还原39位原始水印） ====================\n');
if exist(bch_param_path, 'file')
    load(bch_param_path);
    if exist('code1', 'var') && all(ismember(code1, [0, 1]))
        gen_poly = code1;
        fprintf('✅ 加载BCH生成多项式\n');
    else
        error('code1.mat格式错误！');
    end
else
    error('未找到code1.mat！');
end

% 截取前63位解码
coded_seq_for_decode = extracted_seq_01(1:bch_n);
[final_watermark, error_bits] = bch_decode(coded_seq_for_decode, bch_t, gen_poly, bch_n, bch_k);

%% 五、正确率计算（保持原逻辑，无修改）
% 1. 64位±1序列对比
model1_accuracy = NaN;
match_bits_model1 = sum(model1 == extracted_model1);
model1_accuracy = (match_bits_model1 / 64) * 100;
fprintf('\n【正确率1：64位±1序列对比】\n');
fprintf('生成的model1：\n');
disp(reshape(model1, 8, 8));
fprintf('提取的model1：\n');
disp(reshape(extracted_model1, 8, 8));
fprintf('匹配位数：%d/64 | 正确率：%.2f%%\n', match_bits_model1, model1_accuracy);

% 输出错误水印位详情
fprintf('\n==================== 错误水印位详情（如有） ====================\n');
error_bit_indices = find(model1 ~= extracted_model1);
if ~isempty(error_bit_indices)
    fprintf('⚠️ 共检测到%d个错误水印位，详情如下：\n', length(error_bit_indices));
    for err_idx = 1:length(error_bit_indices)
        bit_num = error_bit_indices(err_idx);
        ii_err = ceil(bit_num / 8);
        jj_err = mod(bit_num - 1, 8) + 1;
        target_sign = model1(bit_num);
        extracted_sign = extracted_model1(bit_num);
        err_response = watermark_responses(bit_num);
        fprintf('  水印位%d（子块[%d,%d]）：目标符号=%d | 提取符号=%d | 哈达玛响应=%.6f\n', ...
                bit_num, ii_err, jj_err, target_sign, extracted_sign, err_response);
    end
else
    fprintf('✅ 无错误水印位，64位序列完全匹配！\n');
end

% 2. 39位原始水印对比
orig_wm_accuracy = NaN;
if exist(original_watermark_path, 'file') && ~isempty(final_watermark)
    load(original_watermark_path, 'original_watermark');
    if length(original_watermark) == bch_k && all(ismember(original_watermark, [0, 1]))
        match_bits_orig = sum(original_watermark == final_watermark);
        orig_wm_accuracy = (match_bits_orig / bch_k) * 100;
        fprintf('\n【正确率2：39位原始水印对比】\n');
        fprintf('生成的原始水印（3行13列）：\n');
        disp(reshape(original_watermark, 3, 13));
        fprintf('解码后水印（3行13列）：\n');
        disp(reshape(final_watermark, 3, 13));
        fprintf('匹配位数：%d/39 | 正确率：%.2f%%\n', match_bits_orig, orig_wm_accuracy);
    end
end

%% 六、结果保存与输出（保持原逻辑，无修改）
fprintf('\n==================== 最终提取结果 ====================\n');
fprintf('1. 64：错误位数=%d , 39：错误位数=%d位\n', 64-match_bits_model1, 39-match_bits_orig);
fprintf('2. 64位±1序列正确率：%.2f%%\n', model1_accuracy);
fprintf('3. 39位原始水印正确率：%.2f%%\n', orig_wm_accuracy);
fprintf('==========================================================\n');

save('watermark_extraction_hadamard_result.mat', ...
     'extracted_seq_01', 'extracted_model1', 'final_watermark', 'error_bits', ...
     'model1_accuracy', 'orig_wm_accuracy', 'img_type', 'img_c');
fprintf('哈达玛变换版提取结果已保存至：watermark_extraction_hadamard_result.mat\n');

%% =========================================================================
% BCH解码函数（保持原代码完全不变）
% =========================================================================
function [decoded_watermark, err_count] = bch_decode(voted_seq, t, gen_poly, n, k)
    err_count = 0;
    decoded_watermark = zeros(1, k);
    
    % 有通信工具箱
    if exist('bchdec', 'file') && exist('gf', 'file')
        try
            coded_seq_gf = gf(voted_seq, 1);
            [decoded_gf, err_count] = bchdec(coded_seq_gf, n, k);
            gf_zero = gf(0, 1);
            is_zero_logic = (decoded_gf == gf_zero);
            decoded_num = double(~is_zero_logic);
            decoded_watermark = squeeze(decoded_num);
        catch
            decoded_watermark = voted_seq(1:k);
            parity_len = n - k;
            decoded_with_parity = [decoded_watermark, zeros(1, parity_len)];
            err_count = sum(xor(voted_seq, decoded_with_parity));
            warning('通信工具箱解码失败，使用简化解码');
        end
    % 无通信工具箱
    else
        warning('未检测到通信工具箱，使用简化解码逻辑');
        decoded_watermark = voted_seq(1:k);
        parity_len = n - k;
        if parity_len > 0
            decoded_with_parity = [decoded_watermark, zeros(1, parity_len)];
            err_count = sum(xor(voted_seq, decoded_with_parity));
        end
    end
    
    % 确保输出为1维行向量
    decoded_watermark = squeeze(decoded_watermark);
    if size(decoded_watermark, 2) ~= k
        decoded_watermark = decoded_watermark';
    end
end