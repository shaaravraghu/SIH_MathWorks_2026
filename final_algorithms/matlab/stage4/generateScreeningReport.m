function outPath = generateScreeningReport(eyes, outPath, patient)
%GENERATESCREENINGREPORT Stage 4: the two-eye annotated PDF an ophthalmologist
%   signs off, built with MATLAB Report Generator.
%
%   Laid out for the 30-second human-in-the-loop target: the one-line verdict
%   first, then per-eye evidence in the same panel positions every time, then
%   the audit trail. Everything below the verdict exists so the reader can
%   check it, not so they have to assemble it.
%
%   eyes:    1x2 struct array from gradeOneEye (left first, then right)
%   patient: struct with optional fields name, id, age, sex, diabetes_type,
%            years_since_diagnosis, hba1c, bp, smoker
%
%   NOTE: the prototype disclaimer and audit-trail section were removed at the
%   project owner's request. The underlying numbers are unchanged and unvalidated
%   -- the grader scores QWK 0.26 within resolution strata and 44.7% specificity
%   at 90% sensitivity -- so the document no longer carries that context itself.

arguments
    eyes struct
    outPath (1,1) string
    patient struct = struct()
end

import mlreportgen.dom.*

GRADE_NAMES = ["No DR", "Mild NPDR", "Moderate NPDR", "Severe NPDR", "Proliferative DR"];

doc = Document(char(erase(outPath, ".pdf")), 'pdf');
open(doc);

% --- header ----------------------------------------------------------------
h = Heading1('Retinal Screening Report');
h.Style = {Color('#4b2e83'), FontSize('18pt')};
append(doc, h);

% --- the one line that gets read first --------------------------------------
[worstIdx] = max([eyes.grade]);
worst = eyes([eyes.grade] == worstIdx);
worst = worst(1);
referableAny = any([eyes.referable]);
% The grade and the referral flag are two separate decisions and can disagree:
% the grade comes from the cutpoints, the flag from an operating point tuned to
% 90% sensitivity, which at 44.7% specificity also flags many level 0-1 eyes.
% Saying "REFERABLE DR ... level 1" as one sentence reads as a contradiction,
% so both are stated, with the reason the flag fired.
if referableAny
    verdict = sprintf('FLAGGED FOR REVIEW — worst eye %s: %s (level %d), referable probability %.0f%%', ...
        upper(string(worst.side)), GRADE_NAMES(worst.grade + 1), worst.grade, 100 * worst.referable_probability);
    verdictColour = '#aa1111';   % DOM Color needs full 6-digit hex, not #a11
else
    verdict = sprintf('NOT FLAGGED — worst eye %s: %s (level %d), referable probability %.0f%%', ...
        upper(string(worst.side)), GRADE_NAMES(worst.grade + 1), worst.grade, 100 * worst.referable_probability);
    verdictColour = '#116611';
end
v = Paragraph(verdict);
v.Style = {Color(verdictColour), FontSize('14pt'), Bold(true)};
append(doc, v);

% --- patient block ----------------------------------------------------------
append(doc, Heading2('Patient'));
append(doc, keyValueTable({ ...
    'Patient ID',  getOr(patient, 'id', '—'); ...
    'Age',         getOr(patient, 'age', '—'); ...
    'Sex',         getOr(patient, 'sex', '—'); ...
    'Diabetes',    getOr(patient, 'diabetes_type', '—'); ...
    'Years since diagnosis', getOr(patient, 'years_since_diagnosis', '—'); ...
    'HbA1c',       getOr(patient, 'hba1c', '—'); ...
    'Blood pressure', getOr(patient, 'bp', '—')}));

% --- per-eye sections -------------------------------------------------------
for k = 1:numel(eyes)
    eye = eyes(k);
    append(doc, Heading2(sprintf('%s eye — %s (level %d)', ...
        upperFirst(eye.side), GRADE_NAMES(eye.grade + 1), eye.grade)));

    f = eye.features;
    append(doc, keyValueTable({ ...
        'Image', char(eye.id); ...
        'Referable (level 2+)', ternary(eye.referable, 'YES', 'no'); ...
        'Calibrated probability', sprintf('%.2f', eye.referable_probability); ...
        'Grade score', sprintf('%.3f', eye.grade_score); ...
        'Image quality (Stage 1)', char(string(eye.stage1.stage1_verdict)); ...
        'Microaneurysms', sprintf('%d', f.ma_count); ...
        'Haemorrhages', sprintf('%d  (per quadrant %d/%d/%d/%d)', ...
            f.haem_count, f.haem_q1, f.haem_q2, f.haem_q3, f.haem_q4); ...
        'Hard exudates', sprintf('%d', f.hard_exudate_count); ...
        'Cotton-wool spots', sprintf('%d', f.cws_count); ...
        'Neovascularisation score', sprintf('%.2f', f.nv_score); ...
        'DME flag (exudate near fovea)', ternary(f.dme_flag > 0, 'YES', 'no'); ...
        'Criterion', criterionLine(f)}));

    if isfield(eye, 'panel_file') && isfile(eye.panel_file)
        appendImage(doc, eye.panel_file, '6.8in');
    end
    if isfield(eye, 'attention_file') && isfile(eye.attention_file)
        appendImage(doc, eye.attention_file, '3.6in');
    end
end

close(doc);
outPath = string(doc.OutputPath);
end


function appendImage(doc, file, width)
import mlreportgen.dom.*
img = Image(char(file));
img.Width = width;
img.Height = [];
append(doc, Paragraph(img));
end


function t = keyValueTable(rows)
import mlreportgen.dom.*
t = Table(rows);
t.Border = 'none';
t.ColSep = 'none';
t.RowSep = 'none';
t.TableEntriesStyle = {FontSize('10pt')};
try
    % Widen the label column where the DOM version supports entry addressing;
    % the table is readable without it, so never fail a report over styling.
    t.entry(1, 1).Style = {Width('2.4in')};
catch
end
end


function s = criterionLine(f)
% The ICDR criterion the evidence supports, stated so a reviewer can check it
% against the counts above rather than re-deriving it.
if f.rule421_haem > 0
    s = '4-2-1: haemorrhages in all four quadrants';
elseif f.nv_score > 3.0
    s = 'Neovascularisation signal elevated';
elseif f.haem_count > 0 || f.ma_count > 0
    s = 'Microaneurysms / haemorrhages present';
else
    s = 'No lesion criterion met; grade from vessel and NV features';
end
end


function out = getOr(s, field, default)
if isfield(s, field) && ~isempty(s.(field))
    out = char(string(s.(field)));
else
    out = default;
end
end


function out = ternary(condition, a, b)
if condition, out = a; else, out = b; end
end


function s = upperFirst(s)
s = char(string(s));
if isempty(s), s = '?'; return; end
s(1) = upper(s(1));
end
