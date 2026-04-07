% StudyData template — initialize with initStudyData()
% Fields are populated progressively as the pipeline runs

function S = initStudyData()

% vertebral landmarks block
S.landmarks.L1L2.defined          = false;
S.landmarks.L1L2.method           = '';      % 'auto' | 'manual' | 'semi-auto'
S.landmarks.L1L2.L1_sup_z_mm      = NaN;    % physical z, LPS, sup. L1 endplate
S.landmarks.L1L2.L2_inf_z_mm      = NaN;    % physical z, LPS, inf. L2 endplate
S.landmarks.L1L2.slab_thickness_mm = NaN;
S.landmarks.L1L2.scoutPixelRow_L1  = NaN;   % row index on sagittal scout (for overlay)
S.landmarks.L1L2.scoutPixelRow_L2  = NaN;
S.landmarks.L1L2.dixonSlices       = [];    % 1-based indices into Dixon volume
S.landmarks.L1L2.mreSlices         = [];    % 1-based indices into MRE volume
S.landmarks.L1L2.mreCoverage       = NaN;   % fraction of slab covered by MRE FOV

% L1-L2 body composition features
S.features.l1l2.muscleArea_cm2     = NaN;
S.features.l1l2.satArea_cm2        = NaN;
S.features.l1l2.muscleSATratio     = NaN;
S.features.l1l2.musclePDFF_pct     = NaN;
S.features.l1l2.muscleStiffness_kPa = NaN;  % NaN if MRE doesn't cover L1-L2
S.features.l1l2.SMI                = NaN;   % skeletal muscle index (cm2/m2), if height known
S.features.l1l2.nDixonSlicesUsed   = 0;
S.features.l1l2.nMREslicesUsed     = 0;

S.patientID       = '';
S.studyDate       = '';
S.studyUID        = '';
S.site            = '';          % 'Mayo' | 'UCSD'
S.importTimestamp = '';

% --- Series (populated by importDICOM) ---
S.scout   = emptySeriesStruct();   % 3-plane localizer
S.dixon   = emptyDixonStruct();    % 4-channel Dixon
S.mre     = emptyMREStruct();      % magnitude + stiffness map
S.pdff    = emptySeriesStruct();   % PDFF map (Dixon-derived)

% --- Segmentation masks (populated by segmentation module) ---
S.seg.liver   = [];
S.seg.spleen  = [];
S.seg.muscle  = [];
S.seg.sat     = [];
S.seg.conf    = struct();          % per-organ confidence scores

% --- Extracted features (populated by feature extraction module) ---
S.features = struct();

% --- QC (populated by QC module) ---
S.qc.flags        = {};
S.qc.status       = 'pending';    % 'passed' | 'flagged' | 'failed'
S.qc.reviewNeeded = false;
S.qc.notes        = '';
end