% 创建一些示例图片用于测试
% 生成几张不同类型的测试图片

% 创建一张简单的彩色测试图片
test_img1 = uint8(rand(1024, 1024, 3) * 255);
imwrite(test_img1, './imgs_new1/test1.png');

% 创建一张渐变测试图片
[x, y] = meshgrid(1:1024, 1:1024);
test_img2 = uint8(mod(x + y, 256));
test_img2 = repmat(test_img2, [1, 1, 3]); % 扩展为RGB
imwrite(test_img2, './imgs_new1/test2.png');

% 创建一张带图案的测试图片
test_img3 = zeros(1024, 1024, 3);
for i = 1:128:1024
    for j = 1:128:1024
        test_img3(i:min(i+63, 1024), j:min(j+63, 1024), :) = rand(1, 1, 3) * 255;
    end
end
imwrite(uint8(test_img3), './imgs_new1/test3.png');

fprintf('已创建3张测试图片在imgs_new1目录中\n');