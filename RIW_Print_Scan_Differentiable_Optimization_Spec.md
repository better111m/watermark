# RIW 面向打印—扫描的可微提取裕量优化：设计与实现规格

> 本文档是一份可直接交给 Codex 执行的工程规格。实现时必须以本文档为准，先完成最小可验证版本（MVP），再进行扩展。不要擅自引入裁剪定位、屏幕拍摄、视频水印、扩散模型或额外神经网络。

## 1. 项目背景

现有 RIW 是一个基于 MATLAB 的传统鲁棒图像水印方法，代码仓库：

- RIW：https://github.com/better111m/watermark
- 可参考的攻击实现：https://github.com/facebookresearch/videoseal

RIW 当前核心结构如下：

1. 输入图像统一处理为 `1024 × 1024`；
2. 彩色图主要在 B 通道嵌入，灰度图在单通道嵌入；
3. 将图像划分为 `16 × 16` 像素统计块，得到 `64 × 64` 的块和矩阵；
4. 将块和矩阵划分成 `8 × 8` 个区域，每个区域含 `8 × 8` 个块和，对应一个水印位，共 64 位；
5. 对每个区域执行 `8 × 8` 哈达玛变换；
6. 使用 63 个非 DC 哈达玛系数的加权响应判断水印位；
7. 使用 JND 图将块和修改量分配到像素；
8. 使用 BCH(63,39,5) 将 39 位有效信息编码为 63 位，另保留 1 位形成 64 位序列。

当前不足：

- 嵌入强度主要依靠经验参数和干净图像响应确定；
- 现有 PSO 主要优化未失真图像上的响应，没有显式优化打印—扫描退化后的提取可靠性；
- 提取率和视觉质量仍有优化空间；
- 本阶段主要研究打印—扫描，不研究屏幕拍摄；
- 打印—扫描实验不裁剪，因此不加入 Crop、Cropout 或定位网络。

## 2. 本工作的核心目标

建立以下可微链路：

```text
每位嵌入强度 α
    ↓
RIW 哈达玛域嵌入 + JND 像素分配
    ↓
水印图像 Xw(α)
    ↓
多个可微打印—扫描失真版本 Tk(Xw)
    ↓
RIW 哈达玛响应 rik
    ↓
有符号提取裕量 mik = bi · rik
    ↓
鲁棒损失 + JND视觉损失
    ↓
反向传播更新 α
```

最终目标：在给定视觉质量约束下，提高各种模拟打印—扫描失真后的水印提取率和最坏位提取裕量。

本阶段的创新定位为：

> 针对 RIW 依赖经验嵌入强度、干净图像响应不能准确反映打印—扫描后可靠性的问题，建立嵌入强度、打印—扫描模拟失真与哈达玛提取响应之间的可微映射；提出多失真条件下的有符号提取裕量，在 JND 感知约束下联合优化 64 个水印区域的嵌入强度，从而改善视觉质量与打印—扫描后提取准确率之间的平衡。

## 3. 必须保持的研究边界

### 3.1 本阶段必须实现

- PyTorch 版本的 RIW 核心嵌入与响应提取；
- 每个水印位一个可优化嵌入强度，共 64 个；
- 打印—扫描相关的可微攻击池；
- 干净版本、单项攻击版本和复合攻击版本；
- 平均提取裕量损失和最坏情况损失；
- JND 加权视觉损失；
- 可重复实验、日志、结果表和曲线；
- 与原始 RIW 固定强度/原始 PSO 方案比较。

### 3.2 本阶段明确不实现

- Crop、Cropout、随机局部擦除；
- Localization Network；
- Sync Pattern、Patch 定位和几何同步；
- 大角度旋转、透视校正和屏幕拍摄；
- 屏幕摩尔纹、护眼模式；
- H.264/H.265 等视频压缩；
- VINE 的生成式编辑；
- Gaussian Shading 扩散生成水印；
- 新的端到端水印编码器/解码器；
- 未完成 MVP 前训练嵌入强度预测网络。

如果真实扫描图像在进入提取器前需要对齐，应视为数据预处理；本阶段所有优化和评测输入均保持 `1024 × 1024`，不模拟裁剪和空间位置丢失。

## 4. RIW 数学定义

### 4.1 块和矩阵

对处理通道图像 `X ∈ [0,1]^(1024×1024)`，按 `16 × 16` 分块求和：

\[
S_{m,n}=\sum_{(u,v)\in B_{m,n}}X(u,v),
\qquad S\in\mathbb R^{64\times64}.
\]

将 `S` 划分为 64 个 `8 × 8` 区域：

\[
G_i\in\mathbb R^{8\times8},\qquad i=1,\ldots,64.
\]

每个 `G_i` 对应一个水印位 `b_i ∈ {-1,+1}`。

### 4.2 哈达玛响应

令 `H` 为 `8 × 8` 哈达玛矩阵，保持与 MATLAB 代码相同的归一化方式：

\[
C_i=\frac{1}{8}HG_iH.
\]

取 63 个非 DC 系数形成向量 `c_i`，取 MATLAB 中相同的非 DC 哈达玛权重向量 `w`，提取响应为：

\[
r_i=\mathbf w^\top\mathbf c_i.
\]

硬判决仅用于评测：

\[
\hat b_i=\operatorname{sign}(r_i).
\]

定义有符号提取裕量：

\[
m_i=b_ir_i.
\]

- `m_i > 0` 表示该位判决正确；
- `m_i < 0` 表示错误；
- `m_i` 越大，距离判决边界越远。

训练/优化过程中禁止直接使用不可微的 `sign` 和 0/1 Bit Accuracy 作为损失。

## 5. 可微嵌入参数化

### 5.1 MVP 参数化：每位一个强度

第一版只优化 64 个标量，不直接优化全部 4032 个非 DC 系数：

\[
\boldsymbol\alpha=(\alpha_1,\ldots,\alpha_{64}).
\]

对第 `i` 位，在固定 RIW 哈达玛嵌入方向上调整非 DC 系数：

\[
\mathbf c'_i
=
\mathbf c_i+\alpha_i b_i\mathbf w.
\]

DC 系数不修改。随后恢复 `C'_i`，执行逆哈达玛变换得到目标块和矩阵：

\[
G'_i=\frac{1}{8}HC'_iH.
\]

拼接全部 `G'_i` 得到 `S'`，块和差异为：

\[
\Delta S=S'-S.
\]

注意：必须通过最终生成的水印图像重新计算响应，不允许假设理论系数调整后一定能无损落实到像素，因为 JND 分配、平滑和像素截断会改变实际响应。

### 5.2 强度边界

使用无约束参数 `z_i` 和 Sigmoid 参数化：

\[
\alpha_i
=
\alpha_{\min}
+(\alpha_{\max}-\alpha_{\min})\sigma(z_i).
\]

不要在每一步对 `alpha` 做破坏梯度的原地硬截断。`alpha_min`、`alpha_max` 写入配置文件，不硬编码。

### 5.3 JND 像素分配

对每个 `16 × 16` 像素块，将目标块和差异按 JND 权重分配：

\[
\Delta X_p
=
\Delta S_{m,n}
\frac{J_p+\epsilon}
{\sum_{q\in B_{m,n}}(J_q+\epsilon)}.
\]

必须保留：

- 灰度图单通道处理；
- 彩色图 B 通道主嵌入；
- 如果复现现有 RIW 的 RGB 协同修改，必须写成纯 Tensor 运算；
- 像素范围保持 `[0,1]`；
- 如需平滑，使用可微卷积，不使用 NumPy、PIL 或 OpenCV 路径。

MVP 先实现最小、清晰、可微的 JND 分配。现有 MATLAB 的邻块平滑和色彩校准可在基线一致性验证后逐项加入，并分别做消融。

## 6. 打印—扫描攻击池

优先复用或改写 VideoSeal 中以下文件的实现：

- `videoseal/augmentation/valuemetric.py`
- `videoseal/augmentation/geometric.py`

如复制代码，必须保留原项目版权和许可证头，并在本项目文档中注明来源。不要复制 VideoSeal 的整个模型。

### 6.1 必须实现的攻击

| 名称 | 来源/实现 | MVP 参数范围 | 说明 |
|---|---|---:|---|
| Identity | 自己实现 | 无 | 保留干净分支 |
| GaussianBlur | VideoSeal | kernel ∈ {3,5,7} | 模拟墨点扩散与扫描光学模糊 |
| GaussianNoise | VideoSeal | std ∈ [0.002,0.02] | 图像范围为 `[0,1]` |
| DownUpResize | 基于 `F.interpolate` 自己封装 | scale ∈ [0.6,1.0] | 先缩小再恢复到 1024，不改变输出尺寸 |
| Brightness | VideoSeal | factor ∈ [0.85,1.15] | 模拟纸张与扫描曝光 |
| Contrast | VideoSeal | factor ∈ [0.8,1.2] | 模拟打印/扫描响应差异 |
| Saturation | VideoSeal | factor ∈ [0.8,1.2] | 模拟 RGB—CMYK—RGB 色域变化 |
| Hue | VideoSeal | factor ∈ [-0.03,0.03] | 模拟轻微色相漂移 |
| JPEG-STE | VideoSeal | quality ∈ [70,95] | 仅扫描结果可能保存为 JPEG 时启用 |

可选攻击：

- `MedianFilter(kernel=3)`：模拟扫描软件平滑，使用直通梯度；
- `Grayscale`：仅灰度打印/扫描实验启用；
- 轻微运动/线性模糊：后续可参考 VINE 的随机模糊核，不属于 MVP。

### 6.2 明确禁止加入的攻击

- Crop；
- Cropout；
- Perspective；
- 大角度 Rotate；
- 屏幕摩尔纹；
- 屏摄光照模型；
- 局部擦除；
- 视频编解码；
- 生成式编辑。

### 6.3 单项攻击分支

对同一水印图像显式生成以下版本：

```python
attacked = {
    "clean": x_w,
    "blur": blur(x_w),
    "noise": gaussian_noise(x_w),
    "resize": down_up_resize(x_w),
    "color": color_attack(x_w),
    "jpeg": jpeg_ste(x_w),       # 配置允许时
    "combined": print_scan_composite(x_w),
}
```

不要直接使用 VideoSeal 默认的 `Augmenter` 随机单选逻辑。我们的优化必须能够同时看到多个失真版本并计算平均与最坏情况。

### 6.4 颜色攻击

颜色攻击定义为：

\[
T_{color}
=T_{hue}\circ T_{saturation}\circ
T_{contrast}\circ T_{brightness}.
\]

每次迭代从配置范围随机采样参数。采样参数本身不需要可微，但输出必须保持对输入图像可微。

### 6.5 复合打印—扫描攻击

定义：

\[
T_{PS}
=T_{JPEG}\circ T_{noise}\circ T_{resize}
\circ T_{blur}\circ T_{color}.
\]

若实验数据统一保存为 PNG/TIFF，则配置中关闭复合分支末尾的 JPEG。

MVP 的每个优化步骤固定计算全部分支：`clean`、`blur`、`noise`、`resize`、`color`、可选的 `jpeg` 和 `combined`。每个分支内部的攻击参数从配置范围重新采样。不要在 MVP 中按概率只选择某一种攻击；如果后续因速度问题增加抽样模式，必须保留“全分支模式”用于正式评测和消融。

为便于复现实验，攻击参数、随机种子和实际采样值必须写入日志。

## 7. 可微损失函数

### 7.1 多攻击提取裕量

对攻击 `T_k` 下第 `i` 位定义：

\[
r_{ik}(\boldsymbol\alpha)
=E_i(T_k(X_w(\boldsymbol\alpha))),
\]

\[
m_{ik}=b_ir_{ik}.
\]

其中 `E_i` 是 PyTorch 版本的 RIW 响应提取器。

### 7.2 平均鲁棒损失

使用 Softplus 间隔损失：

\[
\mathcal L_{rob}
=\frac{1}{64K}
\sum_{i=1}^{64}\sum_{k=1}^{K}
\operatorname{softplus}(\tau-m_{ik}).
\]

`tau` 是目标安全裕量，写入配置文件。不要使用硬 `sign` 作为训练损失。

### 7.3 最坏情况损失

使用 LogSumExp 平滑逼近最坏攻击/最弱位：

\[
\mathcal L_{worst}
=\frac{1}{\beta}
\log\sum_{i,k}
\exp\left(\beta(\tau-m_{ik})\right).
\]

`beta` 控制其接近最大值的程度。

### 7.4 JND 视觉质量损失

\[
\mathcal L_{JND}
=\frac{1}{N}\sum_p
\left(
\frac{X_w(p)-X(p)}{J(p)+\epsilon}
\right)^2.
\]

可增加最大修改软约束：

\[
\mathcal L_{bound}
=\frac{1}{N}\sum_p
\operatorname{softplus}
\left(
|X_w(p)-X(p)|-\eta J(p)
\right).
\]

### 7.5 强度正则项

\[
\mathcal L_{alpha}
=\frac{1}{64}\sum_i\alpha_i^2.
\]

### 7.6 总目标

\[
\boxed{
\mathcal L
=
\lambda_{rob}\mathcal L_{rob}
+\lambda_{worst}\mathcal L_{worst}
+\lambda_{JND}\mathcal L_{JND}
+\lambda_{bound}\mathcal L_{bound}
+\lambda_{alpha}\mathcal L_{alpha}
}
\]

所有权重必须进入 YAML 配置，不得散落在代码中。

## 8. BCH 的处理

MVP 中：

- 优化 64 位哈达玛响应；
- 使用 64 位 Bit Accuracy 和 63 位 BCH 解码成功率进行评测；
- BCH 硬解码不进入反向传播。

MVP 完成后可以增加 ECC 感知代理损失：

\[
p_i^{err}=\sigma(-\gamma b_ir_i),
\qquad
\sum_{i=1}^{63}p_i^{err}\le 5.
\]

该扩展必须作为独立消融项，不能与基础方法同时加入后不做分析。

## 9. 建议代码结构

不得覆盖或大规模改写原 MATLAB 基线。新增 Python/PyTorch 子项目：

```text
watermark/
├── 原有 MATLAB 文件（保持不变）
├── riw_optimization/
│   ├── __init__.py
│   ├── config.py
│   ├── hadamard.py
│   ├── response.py
│   ├── embedder.py
│   ├── jnd.py
│   ├── losses.py
│   ├── optimize.py
│   ├── evaluate.py
│   ├── attacks/
│   │   ├── __init__.py
│   │   ├── base.py
│   │   ├── blur.py
│   │   ├── noise.py
│   │   ├── resize.py
│   │   ├── color.py
│   │   ├── jpeg_ste.py
│   │   └── print_scan.py
│   ├── metrics/
│   │   ├── image_quality.py
│   │   ├── bit_metrics.py
│   │   └── bch_metrics.py
│   └── utils/
│       ├── seed.py
│       ├── logging.py
│       └── image_io.py
├── configs/
│   ├── print_scan_mvp.yaml
│   └── print_scan_eval.yaml
├── scripts/
│   ├── verify_matlab_parity.py
│   ├── optimize_single_image.py
│   ├── optimize_dataset.py
│   ├── evaluate_attacks.py
│   └── plot_strength_margin_curves.py
├── tests/
│   ├── test_hadamard.py
│   ├── test_response.py
│   ├── test_embedder.py
│   ├── test_attack_gradients.py
│   ├── test_losses.py
│   └── test_reproducibility.py
└── docs/
    ├── implementation_notes.md
    └── experiment_protocol.md
```

如果仓库已有类似目录，优先复用，避免重复建立平行实现。

## 10. 配置文件最低要求

`configs/print_scan_mvp.yaml` 至少包含：

```yaml
seed: 2026
device: cuda

image:
  size: 1024
  range: [0.0, 1.0]
  block_size: 16
  color_channel: B

watermark:
  num_bits: 64
  bch_n: 63
  bch_k: 39
  bch_t: 5

strength:
  alpha_min: 0.0
  alpha_max: 7.0        # 初始上界来自原PSO对单个非DC系数的±7搜索范围
  init_mode: clean_margin_to_tau

attacks:
  keep_clean: true
  gaussian_blur:
    enabled: true
    kernels: [3, 5, 7]
  gaussian_noise:
    enabled: true
    std_min: 0.002
    std_max: 0.02
  down_up_resize:
    enabled: true
    scale_min: 0.6
    scale_max: 1.0
    mode: bilinear
  color:
    enabled: true
    brightness: [0.85, 1.15]
    contrast: [0.8, 1.2]
    saturation: [0.8, 1.2]
    hue: [-0.03, 0.03]
  jpeg:
    enabled: true
    quality: [70, 95]
    straight_through: true
  combined:
    enabled: true
    jpeg_enabled: true

loss:
  margin_tau: 100.0     # 与原RIW的min_abs_flag=100保持一致，后续通过扫描校准
  worst_beta: 10.0
  lambda_rob: 1.0
  lambda_worst: 0.1
  lambda_jnd: 1.0
  lambda_bound: 0.1
  lambda_alpha: 0.001
  jnd_eps: 1.0e-6
  jnd_eta: 1.0

optimizer:
  name: adam
  learning_rate: 0.01
  steps: 300
  grad_clip_norm: 5.0

logging:
  log_every: 10
  save_images: true
  save_margins: true
  save_attack_params: true
```

`alpha_max=7` 和 `margin_tau=100` 是为了与现有 RIW 的 PSO 搜索范围及 `min_abs_flag` 保持一致的可运行初值，不代表最终最优参数。由于 `w` 的63个元素均为 `±1`，在忽略像素分配损失时，沿 `b_i w` 方向增加强度 `alpha_i`，理论响应增量约为 `63 alpha_i`。因此每位初始强度按干净图像响应自适应计算：

\[
\alpha_i^{(0)}
=
\operatorname{clip}
\left(
\frac{\tau-b_ir_i^{clean}}{63},
0,7
\right).
\]

实现完成后必须通过第12节扫描实验重新评估 `alpha_max` 和 `margin_tau`，并在正式实验中报告其选择依据。

## 11. 命令行接口

至少提供：

```bash
python scripts/verify_matlab_parity.py \
  --image path/to/image.png \
  --model1 model1.mat \
  --jnd jnd_matlab_result.mat

python scripts/plot_strength_margin_curves.py \
  --config configs/print_scan_mvp.yaml \
  --image path/to/image.png \
  --output outputs/strength_scan

python scripts/optimize_single_image.py \
  --config configs/print_scan_mvp.yaml \
  --image path/to/image.png \
  --output outputs/single

python scripts/optimize_dataset.py \
  --config configs/print_scan_mvp.yaml \
  --input-dir imgs_new1 \
  --output-dir outputs/dataset

python scripts/evaluate_attacks.py \
  --config configs/print_scan_eval.yaml \
  --input-dir outputs/dataset \
  --output outputs/evaluation.csv
```

路径不得硬编码。所有脚本必须支持 CPU；有 CUDA 时自动或按配置使用 CUDA。

## 12. 实施顺序

### 阶段 A：代码体检与基线冻结

1. 阅读原 RIW 的 `embed_rec_y_func.m`、`extract_rec_y_func.m`、`minmax_fuction.m`、JND 相关文件；
2. 记录真实矩阵归一化、索引顺序、通道顺序和数值范围；
3. 不修改原 MATLAB 基线；
4. 用一张固定图像导出 MATLAB 中间量：`S`、每位 `C_i`、63维系数、`r_i`、最终水印图像；
5. 形成机器可读 parity fixture。

完成标准：Python 与 MATLAB 在相同输入下的干净提取响应一致，数值误差应解释并记录。目标绝对/相对误差不高于 `1e-4`；若因图像库插值不同无法达到，必须提供误差来源和调整后的合理阈值。

### 阶段 B：PyTorch RIW 响应提取器

1. 实现分块求和；
2. 实现区域切分；
3. 实现哈达玛变换；
4. 实现63个非DC系数索引；
5. 实现加权响应；
6. 实现硬判决，仅用于评测；
7. 编写单元测试。

完成标准：64位响应维度、bit索引和 MATLAB 完全对应。

### 阶段 C：可微嵌入和 JND 分配

1. 实现每位 `alpha_i` 参数化；
2. 实现固定哈达玛嵌入方向；
3. 逆变换到目标块和差异；
4. 用纯 Tensor 实现 JND 像素分配；
5. 从最终水印图像重新提取响应；
6. 检查 `alpha.grad` 非空且有限。

完成标准：增大单个位的 `alpha_i` 时，该位正确方向裕量总体单调增加；若不单调，要记录 JND、平滑或截断造成的原因。

### 阶段 D：攻击梯度检查

逐项加入：

1. Identity；
2. GaussianBlur；
3. GaussianNoise；
4. DownUpResize；
5. Brightness/Contrast/Saturation/Hue；
6. JPEG-STE；
7. PrintScanComposite。

每个攻击都必须执行：

- 前向尺寸检查；
- 输出范围检查；
- `loss.backward()`；
- 梯度是否存在；
- 梯度是否为有限数；
- 有限差分方向检查（JPEG-STE只检查代理梯度，不要求匹配真实有限差分）。

### 阶段 E：强度—裕量扫描

在正式优化前，对多张代表性图像扫描统一强度。MVP 使用以下初始网格：

\[
\alpha\in\{0,0.5,1.0,1.5873,2.0,3.0,5.0,7.0\}.
\]

其中 `1.5873 ≈ 100/63`，对应在理想线性条件下将响应沿正确方向增加约100。若最优点落在网格边界，必须扩展网格后重新扫描。

记录：

- 每个攻击下的平均有符号裕量；
- 最小裕量；
- 64位 Bit Accuracy；
- BCH解码结果；
- PSNR、SSIM，条件允许时增加LPIPS；
- 每幅图耗时。

输出曲线：

1. `alpha — mean margin`；
2. `alpha — worst margin`；
3. `alpha — Bit Accuracy`；
4. `alpha — PSNR/SSIM`。

根据曲线确定 `alpha_init`、`alpha_max` 和 `margin_tau`。

### 阶段 F：单图优化 MVP

使用 Adam 只优化64个强度参数：

1. 生成水印图像；
2. 生成多个攻击版本；
3. 计算全部响应和裕量；
4. 计算总损失；
5. 反向传播；
6. 保存每轮损失、强度、平均裕量、最坏裕量、PSNR、SSIM；
7. 保存初始与优化后图像和差分热图。

必须保证优化过程不更新任何无关模型参数。

### 阶段 G：数据集实验和消融

至少比较：

1. 原始 RIW/PSO；
2. 固定统一强度；
3. 只优化干净图像裕量；
4. 多单项攻击平均裕量优化；
5. 平均 + 最坏情况联合优化；
6. 是否加入复合打印—扫描攻击；
7. 是否加入 JND 损失；
8. 是否加入 JPEG（按实际扫描格式决定）。

不要只报告一个随机种子的最好结果。

## 13. 评测协议

### 13.1 数字模拟评测

对每个攻击使用训练范围内和训练范围外两组强度。至少报告：

- 64位 Bit Accuracy；
- 39位有效信息恢复率；
- BCH成功率；
- 平均有符号裕量；
- 最小或低分位裕量（例如5%分位）；
- PSNR；
- SSIM；
- LPIPS（条件允许）；
- 单图优化时间和提取时间。

### 13.2 公平比较原则

优先做两种公平比较：

1. 相同 PSNR/SSIM 下比较打印—扫描后的提取率；
2. 相同提取率下比较 PSNR/SSIM。

不能只证明优化方法比低强度基线提取率高，因为它可能只是使用了更强水印。

### 13.3 真实打印—扫描评测

模拟攻击优化完成后，用真实打印机和扫描仪验证。建议记录：

- 打印机型号；
- 扫描仪型号；
- 打印 DPI；
- 扫描 DPI；
- 彩色/灰度；
- 纸张类型；
- 扫描保存格式和JPEG质量；
- 是否进行了尺寸和位置对齐；
- 每张图的真实攻击后指标。

模拟攻击只能作为可微代理，最终结论必须由真实打印—扫描实验支持。

## 14. 当前模型尚未覆盖的打印—扫描退化

MVP 暂不实现但必须在文档中标注：

- 半色调网点；
- 墨水扩散/网点增大（dot gain）；
- RGB—CMYK—RGB 非线性色彩映射；
- 纸张纹理；
- 扫描条纹；
- 特定打印机—扫描仪设备响应。

后续应通过真实原图/扫描图配对分析残差和频谱，再决定是否增加专门打印—扫描层。不要未经数据验证就一次性加入所有物理模型。

## 15. 测试与验收条件

必须全部满足：

### 15.1 正确性

- PyTorch提取响应与MATLAB基线对齐；
- 64位索引、区域位置、哈达玛权重一致；
- 输入输出固定为 `1024 × 1024`；
- 不执行裁剪；
- BCH评测链路可运行。

### 15.2 可微性

- `alpha.grad` 非空；
- Identity、Blur、Noise、Resize、Color、JPEG-STE、Composite各自反向传播不报错；
- 梯度不存在 NaN/Inf；
- 优化若干轮后总损失总体下降；
- 至少部分攻击下的最坏裕量得到提升。

### 15.3 复现性

- 固定随机种子后结果可复现；
- 配置、命令、依赖完整；
- 所有输出包含运行配置副本；
- 不依赖硬编码的本机绝对路径。

### 15.4 研究有效性

至少证明下面之一：

1. 相同视觉质量下，优化方法的模拟/真实打印扫描提取率更高；
2. 相同提取率下，优化方法的PSNR、SSIM或感知质量更好；
3. 最坏攻击或最弱水印位的裕量显著改善；
4. 多设备真实打印扫描的平均与最坏性能改善。

如果只能通过整体放大水印强度取得提升，则本方案尚未成功。

## 16. 实现过程中的强制要求

1. 先阅读并理解原RIW，不得凭本文档猜测矩阵归一化和索引；
2. 先建立MATLAB/PyTorch parity fixture，再实现优化；
3. 所有攻击必须保持对输入图像的梯度，评测专用攻击另行标注；
4. 不把PIL/NumPy/OpenCV图像操作放进训练计算图；
5. JPEG真实前向可采用STE，但必须同时提供无STE的真实评测模式；
6. 不使用VideoSeal默认随机单攻击逻辑；
7. 攻击参数不得硬编码；
8. 不修改原始RIW输出结果来迎合新方法；
9. 每完成一个阶段先运行测试，再进入下一阶段；
10. 发现原RIW代码错误时，先记录和复现，再以兼容修复形式处理；
11. 保留所有第三方代码的版权、许可证和引用信息；
12. 不提交模型权重、大型中间文件和敏感信息到Git。

## 17. Codex 执行指令

将本文件交给 Codex 后，可附上下面这段指令：

```text
请完整阅读 RIW_Print_Scan_Differentiable_Optimization_Spec.md，并严格按阶段 A→G 实现。

先检查当前仓库、Git状态、原RIW代码和可用运行环境。不要覆盖原MATLAB基线，不要加入文档明确排除的攻击或网络。第一轮只做到：
1. MATLAB/PyTorch响应一致性验证；
2. PyTorch RIW响应提取器；
3. 64个可微嵌入强度与JND分配；
4. 单元测试和梯度检查。

完成第一轮后，运行测试并汇报：修改文件、数学实现对应关系、响应误差、梯度检查结果、尚未解决的问题。确认基础正确后再继续攻击池、损失函数和优化实验。不要跳过parity验证直接训练。
```

## 18. 预期论文表述

可暂定方法名称：

> 基于多失真可微提取裕量优化的打印—扫描鲁棒图像水印方法

工作总结：

> 针对RIW在打印—扫描过程中受模糊、重采样、噪声和颜色响应变化影响，且传统经验嵌入强度难以兼顾视觉质量与提取可靠性的问题，本文建立嵌入强度、打印—扫描代理失真与哈达玛提取响应之间的可微关系，提出多攻击有符号提取裕量及最坏情况优化目标，并在JND感知约束下自适应优化各水印区域的嵌入强度。该方法在保留RIW传统变换域结构和可解释性的同时，使嵌入过程能够提前考虑打印—扫描后的提取可靠性。

---

本规格的首要原则是：先证明“嵌入强度—攻击后裕量—真实误码率”的稳定关系，再扩大模型复杂度。任何后续模块都必须通过独立消融证明必要性。
