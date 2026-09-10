# Getting the data

No imagery, dataset or model weight is stored in this repository. Everything is
fetched from the archives it originally came from:

| What | Original source | Login needed |
|---|---|---|
| Chandrayaan-2 **TMC-2** (orthorectified + browse) | [ISRO PRADAN](https://pradan.issdc.gov.in/ch2/) | Yes |
| Chandrayaan-2 **OHRC** (raw + calibrated) | [ISRO PRADAN](https://pradan.issdc.gov.in/ch2/) | Yes |
| LRO **NAC** (EDR / CDR) | [LROC archive, ASU](https://pds.lroc.im-ldi.com/) | No |
| Original **SwinIR** pretrained weights | [JingyunLiang/SwinIR releases](https://github.com/JingyunLiang/SwinIR/releases/tag/v0.0) | No |
| This project's **trained SwinIR checkpoints** | [`swinir-checkpoints-v1` release](https://github.com/STAC-IITMandi/Moon-Mapping/releases/tag/swinir-checkpoints-v1) | No |
| This project's **SwinIR training data** | [`training-data-v1` release](https://github.com/STAC-IITMandi/Moon-Mapping/releases/tag/training-data-v1) | No |

`scripts/download_data.sh` drives all six. It is resumable — anything already
present on disk is skipped — so an interrupted run is safe to repeat.

```bash
scripts/download_data.sh help        # commands and options
scripts/download_data.sh all         # dirs + a few NAC images + all public weights
```

Data lands in `data/` by default. To put it on another disk, export
`MOON_MAPPING_DATA=/path/to/somewhere` — every command honours it.

---

## 1. The public half (no account required)

```bash
scripts/download_data.sh dirs                  # create the directory skeleton
scripts/download_data.sh nac --limit 10        # 10 NAC EDRs (~2.5 GB)
scripts/download_data.sh swinir-weights        # original SwinIR weights
scripts/download_data.sh checkpoints           # this project's trained weights (777 MB)
scripts/download_data.sh training-data         # the SwinIR training crops (1.7 GB)
```

NAC product ids are read from
`dataset-cleaning-creation-and-analysis/dataset-preparation/csv_files/nac_names.csv`
(14,026 of them). **Be deliberate with `--all`:** each NAC image is about 250 MB,
so the full list is several petabytes. The project only ever used a couple of
NAC strips for training, so `--limit` is the normal path.

The CSVs list *CDR* ids (`…LC` / `…RC`). The script maps each to its *EDR*
counterpart (`…LE` / `…RE`), because the ISIS calibration pipeline in
`dataset-cleaning-creation-and-analysis/scripts/nac2png.sh` starts from EDRs.
Pass `--cdr` if you want the already-calibrated products instead.

Because the LROC archive is not laid out predictably from a product id alone,
the script resolves each id to its volume path through the archive's own
product-lookup page before downloading.

### Calibrating NAC EDRs

EDRs are raw. Turning one into a PNG needs [USGS ISIS](https://github.com/DOI-USGS/ISIS3):

```bash
cd data/NAC/EDR
bash ../../../dataset-cleaning-creation-and-analysis/scripts/nac2png.sh
```

That runs `lronac2isis` → `spiceinit` → `lronaccal` → `lronacecho` → `isis2std`,
which is the sequence the LROC team recommends.

---

## 2. The Chandrayaan-2 half (PRADAN account required)

PRADAN has no public API and no anonymous download. Access is a browser session,
so the script needs the session cookie from a browser where you are logged in.

### Getting a session cookie

1. Register at <https://pradan.issdc.gov.in/ch2/> and sign in.
2. Open your browser's developer tools → **Application** (Chrome) or
   **Storage** (Firefox) → **Cookies** → `pradan.issdc.gov.in`.
3. Copy the value of **`JSESSIONID`**.
4. Export it:

```bash
export PRADAN_JSESSIONID=<the value you copied>
```

The session is short-lived and rate-limited. When it expires mid-run the script
stops with a clear message; log in again, re-export, and re-run to resume.

> PRADAN enforces per-session download caps, request-rate limits and timeouts,
> and its own documentation warns that violations may lead to blocking. The
> script sleeps between requests (`SLEEP_BETWEEN`, default 5s) and sends the
> same 10-minute keep-alive that PRADAN's generated scripts use. Please leave
> those in place.

### Downloading

```bash
scripts/download_data.sh ohrc --limit 5              # OHRC products
scripts/download_data.sh tmc  --ortho --limit 5      # orthorectified TMC products
scripts/download_data.sh tmc  --limit 5              # TMC from the scraped catalogue
```

Product names come from the catalogues committed in this repo:

- `DataSet/TMC/coordinates.csv` — 3,246 TMC products with corner coordinates,
  scraped from PRADAN with Selenium
  (`dataset-cleaning-creation-and-analysis/dataset-preparation/scraping.ipynb`)
- `.../csv_files/tmc_oth.csv` — 855 orthorectified TMC products (`--ortho`)
- `DataSet/OHRC_ShapeFiles/` — the ISRO-supplied OHRC footprint shapefiles

Downloads are unzipped into the PDS4 bundle layout that `DataSet/Generator.py`
and `DataSet/Gen2.py` expect — they walk `data/<level>/<date>/` and derive the
matching `browse/<level>/<date>/` path from it:

```
data/
├── OHRC/files/{data,browse,geometry,miscellaneous}/{raw,calibrated}/<YYYYMMDD>/
├── TMC/browse_calibrated_<year>/dir_<year>/<YYYYMMDD>/
└── NAC/{EDR,CDR}/
```

### The reliable fallback: replay a PRADAN cart

The OHRC archive paths are documented by the real PRADAN-generated scripts kept
in [`docs/pradan-session-script-examples/`](docs/pradan-session-script-examples/).
**The TMC path is inferred by analogy with them and has not been verified against
a live session.** If `tmc` returns 404s, don't fight it — let PRADAN generate the
paths itself:

1. Log in, search for your products, add them to the cart.
2. Download the session script the portal offers.
3. Replay it:

```bash
scripts/download_data.sh pradan-script ~/Downloads/tmc_2026Jan01T000000000.sh
```

This reads the product paths straight out of that file, so the URLs are exactly
the ones PRADAN itself would have used. It works for any instrument.

---

## 3. Model weights and training data

### Trained SwinIR checkpoints

```bash
scripts/download_data.sh checkpoints
```

Pulls five checkpoints (777 MB) into `AI Models/SwinIR/Checkpoints/` from the
[`swinir-checkpoints-v1`](https://github.com/STAC-IITMandi/Moon-Mapping/releases/tag/swinir-checkpoints-v1)
release — the final epoch of each training run:

| File | Trained with | Size |
|---|---|---|
| `swinir_l1_epoch15.pt` | L1 loss | 157 MB |
| `swinir_ssim_epoch33.pt` | SSIM loss | 157 MB |
| `swinir_perceptual_epoch62.pt` | perceptual loss | 154 MB |
| `swinir_perceptual_lightning_epoch26.ckpt` | perceptual loss (Lightning) | 155 MB |
| `swinir_run63_epoch63.pt` | unlabelled | 154 MB |

Load one with `torch.load()`; the `.ckpt` is a PyTorch Lightning checkpoint and
keeps its weights under the `state_dict` key.

These are each run's last epoch rather than a best-scoring one, so if you care
which performs better, evaluate them against your own held-out data. Earlier
epochs are not published; ask the maintainers if you need them.

### Original SwinIR weights

```bash
scripts/download_data.sh swinir-weights
```

Fetches the 13 pretrained models released by the SwinIR authors into
`AI Models/SwinIR/experiments/pretrained_models/` and
`AI Models/SwinIR/model_zoo/swinir/`. `main_test_swinir.py` and `predict.py`
expect them there.

### SRGAN weights

There are none. `AI Models/Moon Mapping/srgan_config.py` points at
`pretrained_weights/generate/g_best.pth.tar`, but no trained SRGAN generator
was ever published, so `mode = "generate"` and `mode = "evaluate"` — and
`cascade.py`, which drives the ×4 → ×16 cascade — have nothing to load.

To train one yourself, blank these two settings first, or `train_srgan.py` will
try to load the missing file and stop with `FileNotFoundError`:

```python
pretrained_d_model_weights_path = ""
pretrained_g_model_weights_path = ""
```

Then set `mode = "train"` and point `train_gt_images_dir` / `train_lr_images_dir`
at your image pairs.

### Training data

```bash
scripts/download_data.sh training-data
```

Downloads and unpacks the crops the SwinIR models were trained on into
`data/training/`, from the
[`training-data-v1`](https://github.com/STAC-IITMandi/Moon-Mapping/releases/tag/training-data-v1)
release:

| Set | Pairs | Input | Target | Colour |
|---|---|---|---|---|
| `DataSet/` | 5,500 | 64×64 | 256×256 | RGB |
| `DataSet_ Grayscale/` | 5,500 | 64×64 | 256×256 | grayscale |
| `DataSet_Gray_High/` | 5,500 | 64×64 | 256×256 | grayscale |
| `DataSet_Gray_8x/` | 3,054 | 64×64 | 512×512 | grayscale |

Each set holds `Train/` (inputs) and `GT/` (targets), paired by filename:
`Train/1234.png` matches `GT/1234.png`. The first three are ×4; the last is ×8.
`DataSet_ Grayscale` and `DataSet_Gray_High` share the same `GT/` images and
differ only in their `Train/` inputs.

`--only <name>` fetches one set instead of all five, and the run logs come down
as `training_logs.tar.gz`:

```bash
scripts/download_data.sh training-data --only dataset_gray_8x
```

Point the SwinIR notebooks (`AI Models/SwinIR/train.ipynb`) at the extracted
directory.

#### Building your own set

The SRGAN expects 96×96 targets against 24×24 inputs, which is a different
layout to the sets above. To generate pairs at any size from source imagery:

1. Pick an orthorectified TMC image and an LRO NAC image that falls inside it —
   `.../csv_files/tmc_nac_contains.csv` lists 11,940 such pairings — and
   download both (see sections 1 and 2).
2. Align them following
   [`dataset-cleaning-creation-and-analysis/README.md`](dataset-cleaning-creation-and-analysis/README.md):
   crop the TMC image to the NAC extent, match brightness and contrast, and
   rotate so features coincide. These steps are manual, done in Fiji and GIMP.
3. Save the aligned pair as `tmc.png` and `nac2.png`, then cut them up:

   ```bash
   python dataset-cleaning-creation-and-analysis/scripts/final_gen.py
   ```

   One pair yields roughly 13,000 crops in `images/<name>/{high,low}/`. Edit the
   `ns` variable in that script to change the target crop size.

Point `srgan_config.py` at the result.

---

## Reference documents

[`docs/`](docs/) holds the ISRO data-product user guides for
[TMC-2](docs/ch2_tmc2_data_products_user_guide.pdf) and
[OHRC](docs/ch2_ohrc_data_products_user_guide.pdf), the
[long-term-archive assembly procedure](docs/LTA_Assembly_Procedure.txt) that
describes the bundle layout, and the project's own presentations.
