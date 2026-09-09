# References

The project Google Drive keeps PDF copies of the papers below. They are not
committed here — these are published works, so they are linked at source instead.

## Super-resolution

- **SwinIR: Image Restoration Using Swin Transformer** — Liang et al., ICCVW 2021.
  [arXiv:2108.10257](https://arxiv.org/abs/2108.10257) ·
  [code](https://github.com/JingyunLiang/SwinIR)
  The basis for [`SwinIR/`](SwinIR/) and [`Transformer_Model-main/`](Transformer_Model-main/).
- **Swin Transformer: Hierarchical Vision Transformer using Shifted Windows** —
  Liu et al., ICCV 2021. [arXiv:2103.14030](https://arxiv.org/abs/2103.14030) ·
  [code](https://github.com/microsoft/Swin-Transformer)
  The backbone; vendored in [`Swin-Transformer/`](Swin-Transformer/).
- **Photo-Realistic Single Image Super-Resolution Using a Generative Adversarial
  Network (SRGAN)** — Ledig et al., CVPR 2017.
  [arXiv:1609.04802](https://arxiv.org/abs/1609.04802)
  The basis for [`Moon Mapping/`](Moon%20Mapping/).
- **Image Super-Resolution Using Deep Convolutional Networks (SRCNN)** —
  Dong et al., TPAMI 2016. [arXiv:1501.00092](https://arxiv.org/abs/1501.00092)
  (the Drive copy is filed as *SR for Conv Nets.pdf*)
- **Real-Time Single Image and Video Super-Resolution Using an Efficient
  Sub-Pixel Convolutional Neural Network (ESPCN)** — Shi et al., CVPR 2016.
  [arXiv:1609.05158](https://arxiv.org/abs/1609.05158)

## Mission and instrument documentation

- Chandrayaan-2 TMC-2 and OHRC data-product user guides — see [`../docs/`](../docs/)
- [PRADAN, ISSDC Chandrayaan-2 data archive](https://pradan.issdc.gov.in/ch2/)
- [LROC archive (ASU)](https://pds.lroc.im-ldi.com/) ·
  [LROC NAC instrument overview](https://lroc.im-ldi.com/)

## Model code provenance

| Directory | Upstream | Notes |
|---|---|---|
| [`Moon Mapping/`](Moon%20Mapping/) | SRGAN (PyTorch reimplementation) | Adapted for 24→96 px TMC→NAC pairs |
| [`SwinIR/`](SwinIR/) | [JingyunLiang/SwinIR](https://github.com/JingyunLiang/SwinIR) | Project's working copy: adds `train.ipynb`, `train2.ipynb`, lunar training config |
| [`SwinIR-0.0/`](SwinIR-0.0/) | [SwinIR v0.0](https://github.com/JingyunLiang/SwinIR/releases/tag/v0.0) | Earlier snapshot kept for comparison |
| [`Swin-Transformer/`](Swin-Transformer/) | [microsoft/Swin-Transformer](https://github.com/microsoft/Swin-Transformer) | Vendored upstream; project work is in `SR Moon Images/train.ipynb` |
| [`Transformer_Model-main/`](Transformer_Model-main/) | — | Project's own from-scratch SwinIR layer implementation |
