# HepatosplenicMRE Analysis Platform

**Mayo Clinic R01 — AI-Assisted Hepatosplenic MRE Image Analysis**  
Principal Investigator: Meng Yin, PhD  
Collaborating Site: UCSD

---

## Overview

A portable, standardized MATLAB platform for converting abbreviated abdominal
MRE examinations into scalable multi-organ phenotypes for prognostic modeling
of portal hypertension, hepatic reserve, and body-composition vulnerability.

**Sequences processed:** 3-plane Scout · Dixon MRI (Water/Fat/FF/IP/OP) · 2D MRE

**Features extracted:** Liver/spleen volume · PDFF · Stiffness maps · Cross-organ
ratios · Abdominal muscle area · SAT area · Muscle:fat ratio · L1–L2 measures ·
Spatial heterogeneity descriptors

---

## Requirements

| Item | Version |
|------|---------|
| MATLAB | R2019b or later (R2025b recommended) |
| Image Processing Toolbox | Required (all phases) |
| Deep Learning Toolbox | Required (Phase 4 — segmentation) |
| Statistics & Machine Learning Toolbox | Recommended (Phase 6 — QC stats) |

---

## Installation

### 1. Clone the repository

```bash
git clone https://github.com/MengYinMayo/HepatosplenicMRE.git
cd HepatosplenicMRE
```

### 2. Add to MATLAB path

Run once in MATLAB:

```matlab
addpath(genpath('F:\OneDrive - Mayo Clinic\Documents\MATLAB\YinM_R01_2026_Decomp'));
savepath;
```

Or use the provided setup script:

```matlab
run('setup_platform.m');
```

### 3. Launch the GUI

```matlab
app = HepatosplenicMRE_App;
```

---

## Project Structure

```
HepatosplenicMRE/
├── HepatosplenicMRE_App.m          Phase 1 — App Designer GUI skeleton
├── setup_platform.m                Path setup and dependency check
├── functions/
│   ├── io/
│   │   ├── io_loadDICOMStudy.m     Phase 2 — Top-level DICOM loader
│   │   ├── io_recognizeSequences.m Phase 2 — Series classifier
│   │   ├── io_readDICOMSeries.m    Phase 2 — Volume reader
│   │   ├── io_extractSpatialInfo.m Phase 2 — Spatial metadata / affine
│   │   └── app_integratePhase2.m   Phase 2 — App callback implementations
│   ├── harmonization/
│   │   ├── harm_harmonizeStudy.m   Phase 2 — Full harmonization pipeline
│   │   └── harm_resampleVolume.m   Phase 2 — Affine resampling (trilinear)
│   ├── registration/               Phase 3 — L1-L2 localization + coregistration
│   ├── segmentation/               Phase 4 — Organ segmentation
│   ├── features/                   Phase 5 — Feature extraction
│   ├── qc/                         Phase 6 — Quality control engine
│   └── export/                     Phase 7 — CSV / PDF / NIfTI export
├── config/
│   └── platform_config.json        Harmonized feature definitions
└── docs/
```

---

## Development Phases

| Phase | Status | Description |
|-------|--------|-------------|
| 1 | ✅ Done | App Designer GUI skeleton |
| 2 | ✅ Done | DICOM I/O, series recognition, matrix harmonization |
| 3 | 🔄 Next | L1–L2 vertebral localization + Scout→Dixon→MRE propagation |
| 4 | ⏳ | AI organ segmentation (liver, spleen, muscle, SAT) |
| 5 | ⏳ | Automated feature extraction |
| 6 | ⏳ | Technical QC engine |
| 7 | ⏳ | Export (CSV, PDF report, NIfTI masks) |

---

## Quick Start (Command Line — no GUI)

```matlab
% Load a study
study = io_loadDICOMStudy('D:\data\Patient001\Session1');

% Harmonize all volumes to common grid
study = harm_harmonizeStudy(study);

% Inspect
disp(study.QCFlags)
disp(study.Harmonized.SpatialInfo)
size(study.Harmonized.DixonWater)
size(study.Harmonized.MREStiffness)
```

---

## Deployment

The platform is designed for **identical deployment** at:
- **Mayo Clinic** — model development
- **UCSD** — external validation

Both sites use `platform_config.json` to ensure harmonized feature definitions
and identical feature-generation rules, so external validation tests model
transportability rather than processing differences.

---

## License

Mayo Clinic Internal Research Use. Not for clinical deployment without
institutional review.
