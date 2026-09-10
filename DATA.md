# Getting the data

No imagery, dataset or model weight is stored in this repository. Everything is
fetched from the archives it originally came from:

| What | Original source | Login needed |
|---|---|---|
| Chandrayaan-2 **TMC-2** (orthorectified + browse) | [ISRO PRADAN](https://pradan.issdc.gov.in/ch2/) | Yes |
| Chandrayaan-2 **OHRC** (raw + calibrated) | [ISRO PRADAN](https://pradan.issdc.gov.in/ch2/) | Yes |
| LRO **NAC** (EDR / CDR) | [LROC archive, ASU](https://pds.lroc.im-ldi.com/) | No |
| Upstream **SwinIR** pretrained weights | [JingyunLiang/SwinIR releases](https://github.com/JingyunLiang/SwinIR/releases/tag/v0.0) | No |
| This project's **trained SwinIR checkpoints** | [`swinir-checkpoints-v1` release](https://github.com/STAC-IITMandi/Moon-Mapping/releases/tag/swinir-checkpoints-v1) | No |

`scripts/download_data.sh` drives all five. It is resumable — anything already
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
scripts/download_data.sh swinir-weights        # upstream SwinIR weights
scripts/download_data.sh checkpoints           # this project's trained weights (777 MB)
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

## 3. Trained weights and derived data

> **The project Google Drive is not redundant — do not delete it.** Two things
> exist only there and cannot be recovered from any archive or by re-running any
> script: the **training crops** (~1.8 GB, produced by manual image alignment)
> and the **W&B / TensorBoard run logs** (~102 MB). The 131 intermediate
> checkpoints are also Drive-only, though of much lower value. Details below.

### The SwinIR checkpoints — final epochs published, full history in the Drive

The last epoch of each training run is published as release assets, so the
common case needs no Drive access:

```bash
scripts/download_data.sh checkpoints
```

That pulls five files (777 MB total) into `AI Models/SwinIR/Checkpoints/` from
[`swinir-checkpoints-v1`](https://github.com/STAC-IITMandi/Moon-Mapping/releases/tag/swinir-checkpoints-v1):

| Asset | Run | Size |
|---|---|---|
| `swinir_l1_epoch15.pt` | L1 loss, epoch 15 (last) | 157 MB |
| `swinir_ssim_epoch33.pt` | SSIM loss, epoch 33 (last) | 157 MB |
| `swinir_perceptual_epoch62.pt` | perceptual loss, epoch 62 (last) | 154 MB |
| `swinir_perceptual_lightning_epoch26.ckpt` | Lightning perceptual-loss run, epoch 26 | 155 MB |
| `swinir_run63_epoch63.pt` | unlabelled run in `Checkpoints/` root, epoch 63 | 154 MB |

Two caveats worth knowing:

- These are the **latest** epoch of each run, not the **best** by any metric.
  No evaluation log survived, so there is nothing to rank the epochs by. The
  Lightning filename quotes a *training* loss, not a validation score.
- `swinir_run63_epoch63.pt` comes from four loose checkpoints (epochs 60–63)
  sitting in the `Checkpoints/` root with no run label. It is *probably* a
  continuation of the perceptual-loss run: the epoch numbers carry on from 62,
  and it stores the same 2,051 tensors as `swinir_perceptual_epoch62.pt`,
  whereas the L1 checkpoint stores 1,120. That is strong circumstantial
  evidence, not a label — treat the run attribution as unconfirmed.

The **full epoch-by-epoch history** — 136 checkpoints, 17.6 GiB — stays in the
[project Drive](https://drive.google.com/drive/folders/19TyNbSyd7i1igZMVw4YRX5xonl55yZTb?usp=sharing)
under `Models/Moon-Mapping/AI Models/SwinIR/Checkpoints/`:
`PerceptualLoss/` 62, `SSIM Loss - Pretrained Chkpts/` 33, `prev_ckpts/` 20,
`L1_Chkpts/` 15, root 4, `model_1_pl_perceptual_loss/` 2. Copy them out by hand
if you need intermediate epochs. Nothing there is regenerable without
retraining.

Skip `prev_ckpts/`: those 20 files are 122 KB each, far too small to be SwinIR
weights, so they are not usable checkpoints.

Not to be confused with the 13 `.pth` files under
`SwinIR/experiments/pretrained_models/` and `SwinIR/model_zoo/swinir/` — those
are *upstream* SwinIR weights, and `scripts/download_data.sh swinir-weights`
fetches them from the SwinIR project's own releases.

### The SRGAN weights — they do not exist

`AI Models/Moon Mapping/srgan_config.py` reads its generator from
`pretrained_weights/generate/g_best.pth.tar` (and `g_last.pth.tar` for resuming
training), but **no such file was ever saved** — not in this repository, not in
the project Drive, which contains no `.tar` files at all.

This means the SRGAN does not run in *any* mode as configured:

- `mode = "generate"` / `"evaluate"` need a trained generator, so they cannot
  work until one exists. `cascade.py` (the ×4 → ×16 cascade) likewise has
  nothing to load.
- `mode = "train"` also fails, less obviously. `train_srgan.py` guards its
  pretrained-weight load with `if srgan_config.pretrained_g_model_weights_path:`
  — a truthiness test on the *string*, not a check that the file is there. The
  string is non-empty, so it calls `torch.load()` on the missing
  `g_last.pth.tar` and dies with `FileNotFoundError`.

To train from scratch, blank both paths in `srgan_config.py`:

```python
pretrained_d_model_weights_path = ""
pretrained_g_model_weights_path = ""
```

### The derived training crops — Drive only, and NOT reproducibly regenerable

The training crops live in the
[project Drive](https://drive.google.com/drive/folders/19TyNbSyd7i1igZMVw4YRX5xonl55yZTb?usp=sharing)
under `Models/Moon-Mapping/AI Models/SwinIR/`, in four variants totalling about
1.8 GB:

| Folder | Files |
|---|---|
| `DataSet/` | 11,000 |
| `DataSet_ Grayscale/` | 11,000 |
| `DataSet_Gray_High/` | 11,000 |
| `DataSet_Gray_8x/` | 6,108 |

**Treat these as irreplaceable.** Only the last step of the pipeline that made
them is scripted. Per
[`dataset-cleaning-creation-and-analysis/README.md`](dataset-cleaning-creation-and-analysis/README.md),
everything before it was done by hand:

- the TMC image was cropped manually in Fiji,
- brightness and contrast were matched manually in Fiji, verified with a digital
  colour meter,
- rotation was done manually in GIMP, with "slight scaling changes… also done
  manually".

[`final_gen.py`](dataset-cleaning-creation-and-analysis/scripts/final_gen.py)
only performs the final cut-up, and it reads two aligned full-size images
(`tmc.png`, `nac2.png`) that **are not in the Drive and do not survive anywhere**.

So the crops cannot be regenerated bit-for-bit. Re-running the pipeline means
redoing the manual alignment by eye and getting different pixels — which also
means the published checkpoints could not be re-evaluated against the data they
were trained on. Copy these out of the Drive before you touch it.

One further gap: there is no record of which variant trained which run. Nothing
in the code or the filenames maps `DataSet_Gray_8x` (or any other) to the L1,
SSIM or perceptual-loss checkpoints.

---

## Reference documents

[`docs/`](docs/) holds the ISRO data-product user guides for
[TMC-2](docs/ch2_tmc2_data_products_user_guide.pdf) and
[OHRC](docs/ch2_ohrc_data_products_user_guide.pdf), the
[long-term-archive assembly procedure](docs/LTA_Assembly_Procedure.txt) that
describes the bundle layout, and the project's own presentations.
