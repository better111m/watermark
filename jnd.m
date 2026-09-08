% 运行生成JND
jnd_color_B_channel_save_1024();
function jnd_color_B_channel_save_1024()
    %% 一、核心参数（与嵌入代码完全对齐）
    img = imread('1.png');  
    target_size = 1024;        % 强制匹配嵌入代码的目标尺寸
    jnd_mat_path = 'JND_B_matrix.mat'; % 保存路径与嵌入代码加载路径一致
    
    %% 二、读取图像并预处理（强制.png');    % 与嵌入代码用同一张原图（避免尺寸/内容差异）
    if ~exist('img', 'var') || isempty(img)
        error('请确认图像路径正确，或替换为嵌入代码的原图（如22.png）！');
    end
    
    % 1. 强制调整图像为1024×1024（关键：与嵌入代码尺寸一致）
    img = imresize(img, [target_size, target_size]);
    if size(img, 3) ~= 3
        img = cat(3, img, img, img); % 灰度图转三通道（兼容彩色逻辑）
    end
    
    % 2. 提取B通道并归一化
    B_channel = img(:,:,3);
    B_channel_double = im2double(B_channel);
    
    %% 三、计算JND（保持原算法，生成B通道JND）
    % 亮度掩蔽
    k1 = 1.0;    
    beta = 0.117;   
    L_mask = k1 * (B_channel_double.^beta + (1 - B_channel_double).^beta);
    
    % 对比度掩蔽
    [Gmag, ~] = imgradient(B_channel_double, 'sobel');
    k2 = 0.1;     
    C_mask = k2 * (1 + Gmag);
    
    % 合成B通道JND（1024×1024单通道）
    JND_B = L_mask + C_mask;
    
    %% 四、创建嵌入代码需要的rgb_jnd_map变量（关键修复）
    % 嵌入代码中调用rgb_jnd_map(:,:,3)，因此将JND_B扩展为三通道矩阵
    rgb_jnd_map = zeros(target_size, target_size, 3);
    rgb_jnd_map(:,:,1) = JND_B;  % R通道（冗余，不影响）
    rgb_jnd_map(:,:,2) = JND_B;  % G通道（冗余，不影响）
    rgb_jnd_map(:,:,3) = JND_B;  % B通道（实际使用的JND）
    
    %% 五、保存JND数据（包含嵌入代码需要的rgb_jnd_map）
    save(jnd_mat_path, 'rgb_jnd_map', 'JND_B', 'target_size');
    
    % 保存可视化结果（可选）
    JND_B_vis = mat2gray(JND_B);
    imwrite(im2uint8(JND_B_vis), 'JND_B_gray_1024.png');
    
    %% 六、验证信息输出
    fprintf('JND生成完成！\n');
    fprintf('保存文件：%s\n', jnd_mat_path);
    fprintf('rgb_jnd_map尺寸：%d×%d×%d\n', size(rgb_jnd_map,1), size(rgb_jnd_map,2), size(rgb_jnd_map,3));
    fprintf('JND_B尺寸：%d×%d\n', size(JND_B,1), size(JND_B,2));
end
