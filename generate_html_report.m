function generate_html_report()
% generate_html_report - 从watermark_results.txt生成HTML报告
% 该脚本读取watermark_results.txt文件，并生成一个包含图片展示的HTML页面

% 读取结果文件
filename = 'watermark_results.txt';
if ~exist(filename, 'file')
    error('文件 %s 不存在！', filename);
end

% 读取文件内容
fid = fopen(filename, 'r');
lines = textscan(fid, '%s', 'Delimiter', '\n');
fclose(fid);
lines = lines{1};

% 创建HTML文件
html_filename = 'watermark_report.html';
fid = fopen(html_filename, 'w');

% 写入HTML头部
fprintf(fid, '<!DOCTYPE html>\n');
fprintf(fid, '<html>\n');
fprintf(fid, '<head>\n');
fprintf(fid, '    <title>水印嵌入效果报告</title>\n');
fprintf(fid, '    <style>\n');
fprintf(fid, '        body { font-family: Arial, sans-serif; margin: 20px; }\n');
fprintf(fid, '        .container { display: flex; align-items: flex-start; margin-bottom: 30px; }\n');
fprintf(fid, '        .image-container { margin-right: 30px; text-align: center; }\n');
fprintf(fid, '        .image-container img { max-width: 300px; max-height: 300px; border: 1px solid #ccc; }\n');
fprintf(fid, '        .info { min-width: 200px; }\n');
fprintf(fid, '        h3 { margin-top: 5px; margin-bottom: 5px; }\n');
fprintf(fid, '        .metrics { margin-top: 10px; }\n');
fprintf(fid, '        .metrics p { margin: 5px 0; }\n');
fprintf(fid, '        .header { background-color: #f2f2f2; padding: 10px; border-radius: 5px; margin-bottom: 20px; }\n');
fprintf(fid, '    </style>\n');
fprintf(fid, '</head>\n');
fprintf(fid, '<body>\n');
fprintf(fid, '    <div class="header">\n');
fprintf(fid, '        <h1>水印嵌入效果报告</h1>\n');
fprintf(fid, '        <p>本报告展示了原始图片与嵌入水印后图片的对比，以及相关评估指标(SSIM, PSNR, 64位提取率, 39位提取率)</p>\n');
fprintf(fid, '    </div>\n');

% 解析每一行数据并生成对应的HTML内容
for i = 1:length(lines)
    line = lines{i};
    
    % 跳过空行
    if isempty(line)
        continue;
    end
    
    % 分割行数据
    parts = strsplit(line, '\t');
    if length(parts) < 6
        fprintf('警告：第%d行数据格式不正确，跳过处理\n', i);
        continue;
    end
    
    % 提取各项数据
    img_name = parts{1};           % 图片名
    ssim = parts{2};               % SSIM值
    psnr = parts{3};               % PSNR值
    extraction_rate_64 = parts{4}; % 64位提取率
    extraction_rate_39 = parts{5}; % 39位提取率
    original_path = parts{6};      % 原始图片路径
    watermarked_path = parts{7};   % 水印图片路径
    
    % 写入图片容器
    fprintf(fid, '    <div class="container">\n');
    fprintf(fid, '        <div class="image-container">\n');
    fprintf(fid, '            <h3>原始图片</h3>\n');
    fprintf(fid, '            <img src="%s" alt="Original Image: %s">\n', original_path, img_name);
    fprintf(fid, '            <p>%s</p>\n', original_path);
    fprintf(fid, '        </div>\n');
    
    fprintf(fid, '        <div class="image-container">\n');
    fprintf(fid, '            <h3>嵌入水印后</h3>\n');
    fprintf(fid, '            <img src="%s" alt="Watermarked Image: %s">\n', watermarked_path, img_name);
    fprintf(fid, '            <p>%s</p>\n', watermarked_path);
    fprintf(fid, '        </div>\n');
    
    fprintf(fid, '        <div class="info">\n');
    fprintf(fid, '            <h3>评估指标</h3>\n');
    fprintf(fid, '            <div class="metrics">\n');
    fprintf(fid, '                <p><strong>图片名称:</strong> %s</p>\n', img_name);
    fprintf(fid, '                <p><strong>SSIM:</strong> %s</p>\n', ssim);
    fprintf(fid, '                <p><strong>PSNR:</strong> %s dB</p>\n', psnr);
    fprintf(fid, '                <p><strong>64位提取率:</strong> %s%%</p>\n', extraction_rate_64);
    fprintf(fid, '                <p><strong>39位提取率:</strong> %s%%</p>\n', extraction_rate_39);
    fprintf(fid, '            </div>\n');
    fprintf(fid, '        </div>\n');
    
    fprintf(fid, '    </div>\n');
    fprintf(fid, '    <hr>\n');
end

% 写入HTML尾部
fprintf(fid, '</body>\n');
fprintf(fid, '</html>\n');

% 关闭文件
fclose(fid);

fprintf('HTML报告已生成：%s\n', html_filename);
end