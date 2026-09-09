# VideoSeal attack-layer reference

Upstream project: [facebookresearch/videoseal](https://github.com/facebookresearch/videoseal)

Pinned upstream commit: `870ca7fb33578b90f14c602016b6c2788096226e`

License: MIT. See `LICENSE` in this directory. The copied source files retain their upstream copyright headers.

## Included files

- `videoseal/augmentation/valuemetric.py`
  - JPEG with straight-through gradient
  - Gaussian blur
  - Median filtering with straight-through gradient
  - Brightness, contrast, saturation, and hue changes
  - Gaussian noise and grayscale conversion
- `videoseal/augmentation/geometric.py`
  - Resize and other upstream geometric operators
  - RIW print-scan work should use Resize only; Crop, CropResizePad, Perspective, Rotate, and HorizontalFlip are out of scope for the current non-cropping protocol.
- `videoseal/utils/image.py`
  - Real JPEG forward helper used by the straight-through JPEG layer
  - Median-filter helper

## Intended RIW use

The current print-scan optimization should adapt only:

1. `GaussianBlur`
2. `GaussianNoise`
3. downscale-then-upscale behavior based on `Resize`
4. `Brightness`
5. `Contrast`
6. `Saturation`
7. `Hue`
8. optional `JPEG` when scanned files are stored as JPEG
9. optional `MedianFilter(kernel_size=3)`

Do not use the upstream random single-augmentation selection behavior. RIW must explicitly evaluate clean, individual attack, and combined print-scan branches as specified in the repository-root implementation document.

This directory is an upstream snapshot, not RIW's final attack package. RIW-owned implementations should live under `riw_optimization/attacks/` and must be covered by gradient and shape tests.

The reference modules require Python packages `torch`, `torchvision`, and `Pillow`. They were syntax-checked when vendored; a runtime import test requires these dependencies to be installed in the RIW Python environment.
