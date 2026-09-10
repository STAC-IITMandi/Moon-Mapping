# Moon-Mapping

A project by the [STAC](https://github.com/STAC-IITMandi) core team at IIT Mandi:
train super-resolution models to upscale Chandrayaan-2 **TMC-2** imagery
(~5 m/px) towards **30 cm/px**, using LRO **NAC** and Chandrayaan-2 **OHRC**
imagery as high-resolution ground truth — and from that build a high-resolution
lunar atlas.

The approach is to learn the TMC→NAC mapping on aligned image pairs: TMC crops
resized to 24×24 px as input, the matching NAC crops at 96×96 px as target.
Two model families were tried, an SRGAN and a SwinIR transformer.

> **Data is not in this repository.** Every image, dataset and checkpoint is
> fetched from its original archive by [`scripts/download_data.sh`](scripts/download_data.sh).
> Start with **[DATA.md](DATA.md)**.

## Quick start

```bash
git clone https://github.com/Sukhvansh2004/Moon-Mapping.git
cd Moon-Mapping
pip install -r requirements.txt

scripts/download_data.sh help     # what's available
scripts/download_data.sh all      # dirs + sample NAC images + SwinIR weights
```

The Chandrayaan-2 half needs a free PRADAN account — see [DATA.md](DATA.md).

## Repository layout

```
AI Models/                  the super-resolution models
├── Moon Mapping/             SRGAN: train, generate, cascade to 16x, evaluate
├── Transformer_Model-main/   SwinIR layers written from scratch (RSTB, STL, attention)
├── SwinIR/                   the project's working SwinIR copy + training notebooks
├── SwinIR-0.0/               earlier SwinIR snapshot, kept for comparison
├── Swin-Transformer/         vendored upstream backbone
└── REFERENCES.md             papers and code provenance

DataSet/                    footprint geometry and dataset generation
├── Generator.py, Gen2.py     TMC↔OHRC footprint intersection from PDS4 labels
├── tmc_break.py              lunar-ellipsoid lat/lon → pixel mapping
├── crop.py, readOHRC.py      cropping; reading PDS4 OHRC products
├── dataset_prep*.ipynb       dataset assembly notebooks
├── TMC/coordinates.csv       3,246 TMC products, scraped with corner coordinates
└── OHRC_ShapeFiles/          ISRO-supplied OHRC footprint shapefiles

dataset-cleaning-creation-and-analysis/
├── README.md                 how the training pairs were built — read this first
├── scripts/                  NAC calibration (ISIS), coordinate maths, crop generation
└── dataset-preparation/      scraping and intersection notebooks + CSV catalogues

docs/                       ISRO data-product user guides, LTA procedure, presentations
scripts/download_data.sh    fetches all data from PRADAN / LROC
DATA.md                     data setup guide
Mid_ISRO.pdf                mid-project report
```

## How the training data was built

The full account is in
[`dataset-cleaning-creation-and-analysis/README.md`](dataset-cleaning-creation-and-analysis/README.md).
In short:

1. Find NAC images fully contained within an orthorectified TMC image
   (855 TMC footprints × 14,026 NAC footprints, intersected in the notebooks).
2. Calibrate the NAC EDR with the LROC-recommended ISIS pipeline
   ([`nac2png.sh`](dataset-cleaning-creation-and-analysis/scripts/nac2png.sh)).
3. Crop the TMC image to the NAC extent
   ([`NACTMC_coords.py`](dataset-cleaning-creation-and-analysis/scripts/NACTMC_coords.py)),
   then match brightness/contrast and rotate so features line up.
4. Cut both into 96×96 px (NAC) and 24×24 px (TMC) pairs, discarding tiles that
   are mostly no-data
   ([`final_gen.py`](dataset-cleaning-creation-and-analysis/scripts/final_gen.py)).

One TMC–NAC pair yields roughly 13,000 crops; two pairs were used for training.

OHRC was investigated as ground truth but largely abandoned: of ~90 OHRC images,
only ~10 overlapped any TMC image.

## Models

**SRGAN** — [`AI Models/Moon Mapping/`](AI%20Models/Moon%20Mapping/). A 16-block
SRResNet generator at ×4, cascaded twice for ×16
([`cascade.py`](AI%20Models/Moon%20Mapping/cascade.py)). `srgan_config.py` has a
single `mode` switch (`train` / `generate` / `evaluate`) that selects the paths
and hyperparameters for each stage.

**SwinIR** — [`AI Models/SwinIR/`](AI%20Models/SwinIR/) and
[`AI Models/Transformer_Model-main/`](AI%20Models/Transformer_Model-main/). A
shifted-window transformer, trained with L1, SSIM and perceptual losses in
separate runs.

**On trained weights.** The 136 SwinIR checkpoints were never published to a
public mirror and remain in the
[project Drive](https://drive.google.com/drive/folders/19TyNbSyd7i1igZMVw4YRX5xonl55yZTb?usp=sharing).
The SRGAN weights are a different matter: `srgan_config.py` points at
`g_best.pth.tar` / `g_last.pth.tar`, and neither file exists anywhere. As
shipped it therefore runs in no mode at all — to train from scratch you must
first blank the two `pretrained_*_model_weights_path` settings. See
[DATA.md § What cannot be re-downloaded](DATA.md#3-what-cannot-be-re-downloaded).

## Data sources

- **Chandrayaan-2 TMC-2 and OHRC** — ISRO/ISSDC [PRADAN](https://pradan.issdc.gov.in/ch2/)
- **LRO NAC** — [LROC archive, Arizona State University](https://pds.lroc.im-ldi.com/)

Please observe each archive's access terms and citation requirements. PRADAN in
particular enforces session and rate limits.
