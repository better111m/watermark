[B_jnd, rgb_jnd] = jnd_python2matlab('4.png');
function [B_jnd_map, rgb_jnd_map] = jnd_python2matlab(img_path)
    %% 一、参数配置（与Python代码完全对齐）
    if nargin < 2, target_size = 1024; end
    clc = 0.3;    % 融合系数（用来平衡亮度掩蔽和对比度掩蔽的融合系数——原本亮度掩蔽和对比度掩蔽叠加后允许的修改幅度，会因为clc变大而被“抵消一部分”。 ）
    alpha = 1.0;  % 亮度掩蔽强度（越大越暗的地方改的越多）
    beta = 1.117; % 对比度掩蔽强度（越大纹理处改的越多）
    blue = true;  % B通道增强标记
    
    %% 二、图像预处理
    % 读取并调整尺寸
    img = imread(img_path);
    img = imresize(img, [target_size, target_size]);
    img = im2double(img) * 255;  % [0,255]范围
    
    % 分离RGB通道
    R = img(:,:,1); G = img(:,:,2); B = img(:,:,3);
    
    %% 三、定义卷积核（与Python完全一致）
    % Sobel X核
    kernel_x = [-1 0 1; -2 0 2; -1 0 1];
    % Sobel Y核
    kernel_y = [1 2 1; 0 0 0; -1 -2 -1];
    % 亮度均值核（5x5高斯核）
    kernel_lum = [1 1 1 1 1; 
                  1 2 2 2 1; 
                  1 2 0 2 1; 
                  1 2 2 2 1; 
                  1 1 1 1 1];
    
    %% 四、亮度掩蔽计算（jnd_la）
    % 计算局部亮度均值（卷积+归一化）
    la_R = conv2(R, kernel_lum, 'same') / 32;
    la_G = conv2(G, kernel_lum, 'same') / 32;
    la_B = conv2(B, kernel_lum, 'same') / 32;
    
    % 分段函数计算亮度掩蔽
    la_R = compute_la_mask(la_R);
    la_G = compute_la_mask(la_G);
    la_B = compute_la_mask(la_B);
    
    la_R = alpha * la_R;
    la_G = alpha * la_G;
    la_B = alpha * la_B;
    
    %% 五、对比度掩蔽计算（jnd_cm）
    % 计算梯度幅值
    cm_R = compute_cm_mask(R, kernel_x, kernel_y);
    cm_G = compute_cm_mask(G, kernel_x, kernel_y);
    cm_B = compute_cm_mask(B, kernel_x, kernel_y);
    
    cm_R = beta * cm_R;
    cm_G = beta * cm_G;
    cm_B = beta * cm_B;
    
    %% 六、JND热力图融合（与Python逻辑一致）
    % 融合亮度+对比度掩蔽
    jnd_R = max(la_R + cm_R - clc * min(la_R, cm_R), 0);
    jnd_G = max(la_G + cm_G - clc * min(la_G, cm_G), 0);
    jnd_B = max(la_B + cm_B - clc * min(la_B, cm_B), 0);
    
    % 构建RGB JND矩阵
    jnd_map = cat(3, jnd_R, jnd_G, jnd_B);
    
    % B通道增强（与Python的blue参数一致）
    if blue
        jnd_map(:,:,1) = jnd_map(:,:,1) * 0.5;  % R通道衰减
        jnd_map(:,:,2) = jnd_map(:,:,2) * 0.5;  % G通道衰减
        jnd_map(:,:,3) = jnd_map(:,:,3) * 1.0;  % B通道保持
    end
    
    % 输出B通道最大修改量矩阵（归一化到[0,1]）
%     B_jnd_map = rgb_jnd_map(:,:,3) / 255;
    B_jnd_map = jnd_map(:,:,3);
    %% 七、结果保存（可选）
    save('jnd_matlab_result.mat', 'B_jnd_map', 'jnd_map');
    imwrite(mat2gray(B_jnd_map), 'B_channel_jnd_map.png');
    
    fprintf('转换完成！\n');
    fprintf('B通道JND矩阵尺寸：%dx%d\n', size(B_jnd_map,1), size(B_jnd_map,2));
end

%% 子函数：亮度掩蔽分段计算
function la_mask = compute_la_mask(la)
    la_mask = zeros(size(la));
    mask_low = la <= 127;
    mask_high = ~mask_low;
    
    % 低亮度区域：17*(1 - sqrt(la/127 + eps))
    la_mask(mask_low) = 17 * (1 - sqrt(la(mask_low)/127 + eps));
    
    % 高亮度区域：3/128*(la-127) + 3
    la_mask(mask_high) = 3/128 * (la(mask_high) - 127) + 3;
end

%% 子函数：对比度掩蔽计算
function cm_mask = compute_cm_mask(channel, kernel_x, kernel_y)
    % 计算x/y方向梯度
    grad_x = conv2(channel, kernel_x, 'same');
    grad_y = conv2(channel, kernel_y, 'same');
    
    % 梯度幅值
    cm = sqrt(grad_x.^2 + grad_y.^2);
    
    % 对比度掩蔽公式：16*cm^2.4/(cm^2 + 26^2)
    cm_mask = 16 * (cm.^2.4) ./ (cm.^2 + 26^2);
end