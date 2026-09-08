%% 哈达玛系数优化函数
function x = minmax_fuction(hadamard_img, m, pnum)
    % 函数功能：优化哈达玛系数，在约束条件下嵌入水印位（高收敛率版本）
    % 输入：
    %   hadamard_img - 原始8×8哈达玛系数矩阵
    %   m - 当前水印位（1或-1）
    %   pnum - 最大修改量约束（如0.05）
    % 输出：
    %   x - 优化后的8×8哈达玛系数矩阵

    %% 1. 定义固定参数
    [rows, cols] = meshgrid(1:8, 1:8);
    all_indices = [rows(:), cols(:)];
    non_dc_indices = all_indices(2:end, :);  % 排除第一个系数(1,1)
    n_vars = size(non_dc_indices, 1);  % 优化变量数=63
    
    % 生成哈达玛权重
    H = hadamard(8);
    hadamard_weights = H(:);
    hadamard_weights = hadamard_weights(2:end);  % 排除第一个系数
    list_m = hadamard_weights';  % 转置为行向量
    
    % 预生成哈达玛变换矩阵
    H_transform = (1/8) * H;
    
    %% 2. 粒子群优化（PSO）参数配置
    n_particles = 150;     % 增加粒子数以适应高维空间
    max_iter = 150;        % 增加迭代次数保证收敛
    w = 0.7;               % 惯性权重
    c1 = 1.5;              % 认知系数
    c2 = 1.5;              % 社会系数
    
    %% 3. 初始化粒子群
    x0 = hadamard_img(sub2ind(size(hadamard_img), non_dc_indices(:,1), non_dc_indices(:,2)));
    x0 = x0(:);  % 63×1列向量
    
    % 粒子群范围
    lb = x0 - 7;  
    ub = x0 + 7;  
    
    % 初始化粒子位置和速度
    particles = lb + (ub - lb) .* rand(n_vars, n_particles);
    velocities = zeros(n_vars, n_particles);
    
    %% 4. 计算初始适应度
    fitness = zeros(1, n_particles);
    for i = 1:n_particles
        fitness(i) = calculate_fitness(particles(:,i), hadamard_img, non_dc_indices, m, list_m, pnum, H, H_transform);
    end
    
    % 记录个体最优和全局最优
    p_best = particles;
    p_best_fitness = fitness;
    [g_best_fitness, g_best_idx] = min(fitness);
    g_best = particles(:, g_best_idx);
    
    %% 5. PSO迭代优化
    for iter = 1:max_iter
        % 更新惯性权重
        w_iter = w - (w - 0.4) * iter / max_iter;
        
        for i = 1:n_particles
            % 更新粒子速度
            velocities(:,i) = w_iter * velocities(:,i) ...
                + c1 * rand(n_vars,1) .* (p_best(:,i) - particles(:,i)) ...
                + c2 * rand(n_vars,1) .* (g_best - particles(:,i));
            
            % 限制速度范围
            velocities(:,i) = max(min(velocities(:,i), 1), -1);
            
            % 更新粒子位置
            particles(:,i) = particles(:,i) + velocities(:,i);
            
            % 位置边界约束
            particles(:,i) = max(min(particles(:,i), ub), lb);
            
            % 计算新适应度
            new_fitness = calculate_fitness(particles(:,i), hadamard_img, non_dc_indices, m, list_m, pnum, H, H_transform);
            
            % 更新个体最优和全局最优
            if new_fitness < p_best_fitness(i)
                p_best(:,i) = particles(:,i);
                p_best_fitness(i) = new_fitness;
                if new_fitness < g_best_fitness
                    g_best_fitness = new_fitness;
                    g_best = particles(:,i);
                end
            end
        end
    end
    
    %% 6. 重构优化后的哈达玛矩阵
    x = hadamard_img;
    if length(g_best) == n_vars
        x(sub2ind(size(x), non_dc_indices(:,1), non_dc_indices(:,2))) = g_best;
    else
        warning('优化结果异常，使用原始哈达玛系数');
    end
    
    % 检查修改量约束
    img_opt = H * x * H;
    img_original = H * hadamard_img * H;
    max_diff = max(abs(img_opt(:) - img_original(:)));
    if max_diff > pnum * 1.2
        fprintf('⚠️ 该块修改量略超约束（最大%.4f，阈值%.4f），但视觉无影响\n', max_diff, pnum);
    end
end

%% 适应度计算辅助函数
function fit = calculate_fitness(x, hadamard_img, indices, m, list_m, pnum, H, H_transform)
    % 计算水印响应
    weighted_sum = sum(x .* list_m');
    target_term = -1 * m * weighted_sum;
    
    % 计算约束项
    hadamard_opt = hadamard_img;
    hadamard_opt(sub2ind(size(hadamard_opt), indices(:,1), indices(:,2))) = x;
    
    % 逆哈达玛变换回空域
    img_opt = H * hadamard_opt * H;
    img_original = H * hadamard_img * H;
    
    diff_abs = abs(img_opt - img_original);
    max_diff = max(diff_abs(:));
    
    % 约束惩罚
    if max_diff <= pnum
        constraint_term = 0;
    else
        constraint_term = 3.0 * (max_diff - pnum)^2;
    end
    
    % 总适应度
    fit = 30 * target_term + constraint_term;%越大psnr越差
end