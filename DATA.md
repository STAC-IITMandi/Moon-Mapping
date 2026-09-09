# Getting the data

No imagery, dataset or model weight is stored in this repository. Everything is
fetched from the archives it originally came from:

| What | Original source | Login needed |
|---|---|---|
| Chandrayaan-2 **TMC-2** (orthorectified + browse) | [ISRO PRADAN](https://pradan.issdc.gov.in/ch2/) | Yes |
| Chandrayaan-2 **OHRC** (raw + calibrated) | [ISRO PRADAN](https://pradan.issdc.gov.in/ch2/) | Yes |
| LRO **NAC** (EDR / CDR) | [LROC archive, ASU](https://pds.lroc.im-ldi.com/) | No |
| Upstream **SwinIR** pretrained weights | [JingyunLiang/SwinIR releases](https://github.com/JingyunLiang/SwinIR/releases/tag/v0.0) | No |

`scripts/download_data.sh` drives all four. It is resumable — anything already
present on disk is skipped — so an interrupted run is safe to repeat.

```bash
scripts/download_data.sh help        # commands and options
scripts/download_data.sh all         # dirs + a few NAC images + SwinIR weights
```

Data lands in `data/` by default. To put it on another disk, export
`MOON_MAPPING_DATA=/path/to/somewhere` — every command honours it.

---

## 1. The public half (no account required)

```bash
scripts/download_data.sh dirs                  # create the directory skeleton
scripts/download_data.sh nac --limit 10        # 10 NAC EDRs (~2.5 GB)
scripts/download_data.sh swinir-weights        # upstream SwinIR weights
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

## 3. What cannot be re-downloaded

Two things in the original project Google Drive have no public source:

- **The project's own trained checkpoints** — the SRGAN generator
  (`g_best.pth.tar`, `g_last.pth.tar`) and the SwinIR runs (L1, SSIM,
  perceptual-loss variants, ~150 checkpoints). `srgan_config.py` expects them at
  `pretrained_weights/generate/g_best.pth.tar`.
- **The derived training crops** — the ~39,000 96×96 / 24×24 TMC–NAC image pairs
  under `SwinIR/DataSet*`.

The crops are *reproducible*: get one TMC–NAC pair, follow the alignment steps in
[`dataset-cleaning-creation-and-analysis/README.md`](dataset-cleaning-creation-and-analysis/README.md),
then cut them up with
[`dataset-cleaning-creation-and-analysis/scripts/final_gen.py`](dataset-cleaning-creation-and-analysis/scripts/final_gen.py).
One pair yields roughly 13,000 crops.

The checkpoints are not reproducible without retraining. They remain in the
[project Drive folder](https://drive.google.com/drive/folders/19TyNbSyd7i1igZMVw4YRX5xonl55yZTb?usp=sharing).

---

## Reference documents

[`docs/`](docs/) holds the ISRO data-product user guides for
[TMC-2](docs/ch2_tmc2_data_products_user_guide.pdf) and
[OHRC](docs/ch2_ohrc_data_products_user_guide.pdf), the
[long-term-archive assembly procedure](docs/LTA_Assembly_Procedure.txt) that
describes the bundle layout, and the project's own presentations.
