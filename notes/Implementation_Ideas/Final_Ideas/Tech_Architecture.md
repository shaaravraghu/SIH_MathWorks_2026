# Tech Architecture

How the Stage 1-4 MATLAB pipeline sits behind a web application: the stack,
the request flow, the data model, and how MATLAB is invoked.

---

## 1. Stack

| Layer | Choice | Role |
|---|---|---|
| Frontend | Vite + React | Upload a fundus image (or a patient's left/right pair), display grade, confidence, quadrant table, and the two attention overlays; confirm/override UI for the ophthalmologist |
| Backend | Node.js | HTTP API; orchestrates a MATLAB run per request/job; owns the confirm/override audit log |
| Database | MongoDB | Patients, screening runs, per-eye results, confirm/override events |
| Model / pipeline | MATLAB | Stage 1 (quality gate) -> Stage 2 (segmentation/lesions) -> Stage 3 (tabular grading MLP) -> Stage 4 (CNN + Grad-CAM, report) |

MATLAB is the only place model logic lives, and it is integrated directly
into the Node backend (§5). Node does not reimplement any grading logic — it
calls into MATLAB, then stores and serves the result.

---

## 2. Request flow

```
React (Vite)
   |  POST /api/screenings  (multipart: left image, right image, patient meta)
   v
Node.js API
   |  writes job row to MongoDB (status: queued)
   |  invokes MATLAB: runStage4(leftImage, rightImage, OutDir=..., Patient=...)
   v
MATLAB (Stage 1-4, see §3)
   |  returns: per-eye grade, referable probability, panel PNG, two
   |  attention PNGs (lesion-evidence + Grad-CAM), screening_report.pdf
   v
Node.js API
   |  stores result doc(s) in MongoDB, saves generated files (disk or GridFS)
   |  updates job row (status: done)
   v
React (Vite)
   |  GET /api/screenings/:id  -> renders grade, confidence, overlays, PDF link
   |  ophthalmologist clicks confirm / override
   v
Node.js API  -> writes override event to MongoDB (§4)
```

A screening is not interactive/real-time — Stage 4 runs ~30 s/eye (per
`runStage4.m`), so a two-eye submission is a minute of work. The API treats a
submission as an async job: return a job id immediately, poll or
websocket-push status, rather than holding the HTTP request open.

---

## 3. The MATLAB pipeline (`final_algorithms/matlab/`)

Two grading branches run **in parallel**, then are shown together — the
"hybrid CNN + explicit clinical feature branch" design from
`DR_Pipeline_Techniques_and_Datasets.md`. This is what makes Stage 2 and the
CNN/Grad-CAM branch a parallel pair rather than a sequential dependency:

```
                    +-------------------------------------------+
Stage 1             |  quality gate + enhancement (21 features)  |
(quality)           +-------------------------------------------+
                                    |
                    image passes / borderline-corrected
                                    |
              +---------------------+---------------------+
              |                                             |
   Stage 2 -> Stage 3                              Stage 4 CNN branch
   (branch b: tabular)                              (branch a: image CNN)
   segmentation, lesion                              trainDrCnn.m, 224x224
   candidates, 5-step                                 input, last conv layer
   classifier pipeline,                               named "features"
   MLP grading over ~33-38
   features (Module3_Plan.md)                              |
              |                                             |
   grade, referable_probability                    Grad-CAM heatmap over
   quadrant counts, lesion                          the SAME predicted class
   evidence map                                      (§3.1)
              |                                             |
              +---------------------+---------------------+
                                    |
                          Stage 4 report (branch c: fusion)
                    stage4Panels.m (labelled segmentation)
                    attentionOverlay.m (lesion-evidence heatmap)
                    gradCamOverlay.m  (Grad-CAM heatmap)
                    generateScreeningReport.m -> screening_report.pdf
```

Why parallel, not sequential: Stage 2's lesion evidence is causally
grounded — it names real detected structures (MAs, haemorrhages, vessels).
Grad-CAM is a gradient-attribution heatmap off the CNN, and is too coarse to
point at anything as small as a microaneurysm (the last-conv resolution
problem documented in `DR_Pipeline_Techniques_and_Datasets.md` Module 4).
Neither replaces the other. The report shows both side by side, so
disagreement between them is a visible signal — Grad-CAM lighting up where
Stage 2 found nothing, or vice versa — rather than something silently
discarded.

### 3.1 Grad-CAM in the CNN branch

`trainDrCnn.m` trains the CNN from scratch and names its last convolution
`"features"`, keeping a 14x14 final feature map at a 224 input — that
resolution is what makes the resulting attribution readable, and that layer
is what Grad-CAM attributes onto. The network, class names, input size and
feature-layer name are saved to `data/module3_cnn.mat`.

`gradCamOverlay.m` (in `final_algorithms/matlab/stage4/`) consumes that
bundle:

1. Load `module3_cnn.mat` (net + `feature_layer = "features"`).
2. `gradCAM(net, eye.image_work, predictedClass, 'FeatureLayer', "features")`
   — attribution for the **predicted class specifically**, so the heatmap
   answers "why this grade", not "what looks unusual".
3. Overlay using the same alpha and colormap convention as
   `attentionOverlay.m`, so the two panels read consistently side by side.

`gradeOneEye.m` / `runStage4.m` produce both overlays per eye and pass both
into `generateScreeningReport.m`. The report layout follows the Module 4
spec: original, annotated overlay, Grad-CAM overlay, quadrant-wise lesion
count table, ICDR grade with the triggering criterion on one line, and the
calibrated confidence.

The Grad-CAM panel carries its caveat in the caption: it is a coarse
secondary sanity check on where the CNN looked. The primary evidence is
Stage 2's lesion map, which is the half an ophthalmologist can verify
directly against the counts.

---

## 4. MongoDB schema

```
patients          { _id, name/identifier, created_at }
screenings         { _id, patient_id, status(queued/running/done/error),
                     created_at, left_image_ref, right_image_ref }
eye_results        { _id, screening_id, side(left/right), stage1_verdict,
                     grade, grade_score, referable, referable_probability,
                     quadrant_counts, lesion_counts, evidence_map_ref,
                     gradcam_map_ref, panel_image_ref, model_version }
overrides          { _id, eye_result_id, original_grade, corrected_grade,
                     reason_code, reviewer, created_at }
reports            { _id, screening_id, pdf_ref, generated_at }
```

`overrides` matters beyond the audit trail: per the explainability spec,
every override is future retraining and QA data — log the original
prediction, the corrected grade, and a reason code every time, not just the
confirmation.

Generated images and PDFs are written to `reports/` by MATLAB and served by
Node; the `*_ref` fields hold those paths. GridFS or object storage is the
swap-in if the report volume outgrows local disk.

---

## 5. MATLAB inside Node

MATLAB is integrated into the Node backend rather than run as a separate
service. Node holds a persistent MATLAB engine session and calls
`runStage4` / `gradeOneEye` on it directly, so a screening job is a function
call from the API layer — no process spawn per job, no per-call interpreter
startup, no network hop between Node and the model.

What this settles:

| Concern | Consequence of in-process MATLAB |
|---|---|
| Latency | Only pipeline time counts (~30 s/eye). No ~10-20 s interpreter startup per job. |
| Model loading | `module3_model.mat` and `module3_cnn.mat` load once into the live session and stay resident across jobs, instead of being re-read per image. |
| Concurrency | The engine session is the unit of parallelism. Run a small pool of sessions and let the job queue hand one screening to one session at a time; MATLAB state is not shared between concurrent jobs. |
| Failure isolation | A MATLAB-side error surfaces as a caught exception in Node and marks the job `error` with the message, rather than a non-zero exit code to parse. A session that dies is replaced by the pool. |
| File exchange | MATLAB still writes panels, overlays and the PDF to `reports/`; Node reads those paths back off the returned struct and records them as the `*_ref` fields (§4). |

The async job queue (§2) stays regardless — it exists because the pipeline
takes ~30 s/eye of real work, not because of how MATLAB is invoked.
