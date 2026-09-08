% 清理现有提取结果文件到新文件夹
% 该脚本将当前目录下的 *_extraction_result.mat 文件移动到 extraction_results 文件夹

% 创建提取结果文件夹
extraction_results_dir = './extraction_results';
if ~exist(extraction_results_dir, 'dir')
    mkdir(extraction_results_dir);
end

% 查找当前目录下所有的 *_extraction_result.mat 文件
current_dir = pwd;
mat_files = dir(fullfile(current_dir, '*_extraction_result.mat'));

% 移动文件到新文件夹
for i = 1:length(mat_files)
    old_path = fullfile(current_dir, mat_files(i).name);
    new_path = fullfile(extraction_results_dir, mat_files(i).name);
    
    % 移动文件
    movefile(old_path, new_path);
    fprintf('已移动文件: %s -> %s\n', mat_files(i).name, new_path);
end

fprintf('文件整理完成！共移动 %d 个文件到 %s 文件夹。\n', length(mat_files), extraction_results_dir);