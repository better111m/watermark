% 计算图像的空域 JND 阈值图（适配彩色/灰度图像，仅输出B通道对应有效JND值）
function [jnd_map, b_channel_dct_blocks] = compute_color_jnd_1024_rec_y(image_path)

    % --------------------------强制调整图像为1024×1024--------------------------
    target_size = 1024;  % 固定目标尺寸：1024×1024
    % 1. 读取图像（自动兼容彩色/灰度）
    img = imread(image_path);
    if isempty(img)
        error('无法读取图像，请检查路径是否正确');
    end
    [h_ori, w_ori, c] = size(img);
    
    % 2. 校验图像通道数（仅支持单通道灰度/三通道彩色）
    if ~ismember(c, [1, 3])
        error('输入图像必须为灰度图像（单通道）或彩色图像（RGB三通道），当前通道数：%d', c);
    end
    
    % 3. 强制调整为1024×1024（灰度图调整后仍为单通道，彩色图保持三通道）
    img_resized = imresize(img, [target_size, target_size]);
    [h, w, c_resized] = size(img_resized);
    fprintf('图像已调整为1024×1024尺寸（原始尺寸：%d×%d，原始通道数：%d）\n', h_ori, w_ori, c);
    if h ~= target_size || w ~= target_size
        error('图像调整失败！目标尺寸1024×1024，当前尺寸：%d×%d', h, w);
    end
    % -----------------------------------------------------------------------------
    
    % 归一化到0-1范围（便于DCT计算）
    img_norm = double(img_resized) / 255.0;
    
    % 初始化输出变量（1024×1024×3，仅第3通道有效，R/G通道设为0）
    rgb_jnd_map = zeros(h, w, 3);  % R/G=0，第3通道存储JND值
    b_channel_dct_blocks = cell(1);  % 存储处理通道的DCT块（彩色=B通道，灰度=单通道）
    
    % 定义频域视觉权重矩阵（Watson模型简化版，8×8，与原逻辑一致）
    visual_weight = [
        1.0, 1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.3;
        1.4, 2.0, 2.8, 4.0, 5.6, 8.0, 11.3, 16.0;
        2.0, 2.8, 4.0, 5.6, 8.0, 11.3, 16.0, 22.6;
        2.8, 4.0, 5.6, 8.0, 11.3, 16.0, 22.6, 32.0;
        4.0, 5.6, 8.0, 11.3, 16.0, 22.6, 32.0, 45.3;
        5.6, 8.0, 11.3, 16.0, 22.6, 32.0, 45.3, 64.0;
        8.0, 11.3, 16.0, 22.6, 32.0, 45.3, 64.0, 90.5;
        11.3, 16.0, 22.6, 32.0, 45.3, 64.0, 90.5, 128.0
    ];
    cross_mask_weight = 0.2;  % 通道间交叉掩蔽权重（仅彩色图R/G对B有效）
    
    % --------------------------通道选择（兼容彩色/灰度）--------------------------
    if c_resized == 3  % 彩色图：处理B通道（Matlab索引3）
        process_ch = 3;
        channel_img = img_norm(:, :, process_ch);  % 提取B通道
        fprintf('检测到彩色图像，处理B通道（索引3）...\n');
    else  % 灰度图：单通道直接作为处理通道（等价于原逻辑的B通道）
        process_ch = 1;
        channel_img = img_norm(:, :, process_ch);  % 提取单通道
        fprintf('检测到灰度图像，处理单通道（等价于原逻辑B通道）...\n');
    end
    channel_jnd = zeros(h, w);  % 处理通道的空域JND图
    % -----------------------------------------------------------------------------
    
    % 遍历所有8×8块（步长8，1024是8的倍数，无需补0，效率更高）
    block_idx = 1;  % 块索引
    fprintf('正在计算1024×1024图像的JND图...\n');
    for i = 1:8:h
        for j = 1:8:w
            % 提取8×8块（1024是8的倍数，块尺寸刚好8×8，无需补0）
            block = channel_img(i:i+7, j:j+7);
            
            % 对处理通道块进行DCT变换（减去均值以消除直流偏移，与原逻辑一致）
            block_dct = dct2(block - 0.5);
            b_channel_dct_blocks{block_idx} = block_dct;  % 保存处理通道的DCT块
            block_idx = block_idx + 1;
            
            % 计算亮度掩蔽因子（L）：基于处理通道DC系数（与原逻辑完全一致）
            dc = abs(block_dct(1, 1));
            if dc < 0.2
                L = 0.5;  % 暗区：人眼敏感度高，L更小（修改量更小）
            elseif dc <= 0.8
                L = 1.0;  % 中间亮度区：敏感度适中
            else
                L = 1.5;  % 亮区：敏感度低，L更大
            end
            
            % 计算纹理掩蔽因子（T）：含自身AC能量+交叉通道AC能量（仅彩色图有效）
            % 1. 处理通道自身AC能量（排除DC系数，与原逻辑一致）
            self_ac_energy = sum(sum(block_dct(2:end, 2:end).^2));
            
            % 2. 交叉通道（R/G）AC能量（仅彩色图有效，灰度图无交叉通道）
            cross_ac_energy = 0;
            if c_resized == 3  % 仅彩色图计算R/G对B的交叉掩蔽
                for other_ch = 1:2  % 遍历R（1）、G（2）通道
                    other_block = img_norm(i:i+7, j:j+7, other_ch);  % 同位置R/G块
                    other_block_dct = dct2(other_block - 0.5);  % R/G块DCT变换
                    cross_ac_energy = cross_ac_energy + sum(sum(other_block_dct(2:end, 2:end).^2));
                end
            end
            
            % 3. 总纹理能量（处理通道自身+交叉掩蔽，灰度图仅含自身）
            total_ac_energy = self_ac_energy + cross_mask_weight * cross_ac_energy;
            % 计算纹理掩蔽因子T（与原逻辑完全一致）
            if total_ac_energy < 0.12
                T = 0.55;  % 低纹理（纯色块）：敏感度高，T小
            elseif total_ac_energy <= 1.2
                T = 0.55 + 0.4 * (total_ac_energy - 0.12);  % 中等纹理：T线性增长
            else
                T = 0.95;  % 高纹理：敏感度低，T大
            end
            
            % 计算频域JND块（与原逻辑一致）
            freq_jnd_block = visual_weight .* L .* T;
            
            % 频域JND→空域JND（IDCT逆变换，与原逻辑一致）
            spatial_jnd_block = idct2(freq_jnd_block) + 0.5;  % 加回之前减去的均值
            % 裁剪异常值（确保JND在合理范围：0.001-0.1，与原逻辑一致）
            spatial_jnd_block = max(min(spatial_jnd_block, 0.1), 0.001);
            
            % 将空域JND块写入处理通道的JND图
            channel_jnd(i:i+7, j:j+7) = spatial_jnd_block;
        end
    end
    
    % 归一化JND值（缩放至0-0.1，与原逻辑一致）
    channel_jnd = channel_jnd / max(channel_jnd(:)) * 0.1;
    jnd_map(:, :, 3) = channel_jnd;  % 仅第3通道存储有效JND值，R/G通道保持0
    
    % --------------------------保存1024×1024 JND图到本地--------------------------
    jnd_save_path = 'jnd_matlab_result.mat';
    save(jnd_save_path, 'jnd_map');
    fprintf('1024×1024 JND图已保存至：%s\n', jnd_save_path);
    fprintf('JND图规格：%d×%d×3，仅第3通道为有效JND值（0-0.1），R/G通道为0\n', ...
            size(jnd_map,1), size(jnd_map,2));

end