'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { ArrowLeft, ArrowRight, AlertCircle, CheckCircle2, Loader2 } from 'lucide-react';
import StepIndicator from './StepIndicator';
import ImageDropzone from './ImageDropzone';
import ReportDownloadButton from './ReportDownloadButton';
import AnalysisPanel from './AnalysisPanel';

const emptyPersonal = {
  age: '',
  gender: '',
  diabetesType: '',
  diabetesDurationYears: '',
  bloodSugarLevel: '',
  hba1c: '',
  bloodPressure: '',
  smoker: '',
  additionalNotes: '',
};

export default function SubmissionWizard({ initialData }) {
  const router = useRouter();
  const submissionId = initialData._id;

  const [step, setStep] = useState(initialData.currentStep || 1);
  const [personalData, setPersonalData] = useState({
    ...emptyPersonal,
    ...(initialData.personalData || {}),
  });
  const [leftEyeImage, setLeftEyeImage] = useState(initialData.leftEyeImage || '');
  const [rightEyeImage, setRightEyeImage] = useState(initialData.rightEyeImage || '');
  // File name + sha256 of each upload, used server-side to pull the matching
  // pre-generated screening report.
  const [leftEyeMeta, setLeftEyeMeta] = useState(initialData.leftEyeMeta || null);
  const [rightEyeMeta, setRightEyeMeta] = useState(initialData.rightEyeMeta || null);

  const [saving, setSaving] = useState(false);
  const [error, setError] = useState('');
  const [done, setDone] = useState(false);
  const [completed, setCompleted] = useState(null);

  async function patchSubmission(body) {
    const res = await fetch(`/api/submissions/${submissionId}`, {
      method: 'PATCH',
      headers: { 'Content-Type': 'application/json' },
      body: JSON.stringify(body),
    });
    const data = await res.json();
    if (!res.ok) throw new Error(data.error || 'Something went wrong.');
    return data.submission;
  }

  function validateStep1() {
    if (!personalData.age || !personalData.gender || !personalData.diabetesType) {
      return 'Please fill in age, gender, and diabetes type at minimum.';
    }
    return '';
  }

  async function handleNext() {
    setError('');

    if (step === 1) {
      const validationError = validateStep1();
      if (validationError) return setError(validationError);
    }
    if (step === 2 && !leftEyeImage) {
      return setError('Please upload your left eye image before continuing.');
    }
    if (step === 3 && !rightEyeImage) {
      return setError('Please upload your right eye image before continuing.');
    }

    setSaving(true);
    try {
      const nextStep = Math.min(step + 1, 4);
      const body = { currentStep: nextStep };
      if (step === 1) body.personalData = personalData;
      if (step === 2) {
        body.leftEyeImage = leftEyeImage;
        body.leftEyeMeta = leftEyeMeta;
      }
      if (step === 3) {
        body.rightEyeImage = rightEyeImage;
        body.rightEyeMeta = rightEyeMeta;
      }

      await patchSubmission(body);
      setStep(nextStep);
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  }

  function handleBack() {
    setError('');
    setStep((s) => Math.max(1, s - 1));
  }

  async function handleFinalSubmit() {
    setError('');
    setSaving(true);
    try {
      const saved = await patchSubmission({
        personalData,
        leftEyeImage,
        rightEyeImage,
        leftEyeMeta,
        rightEyeMeta,
        complete: true,
      });
      setCompleted(saved);
      setDone(true);
    } catch (err) {
      setError(err.message);
    } finally {
      setSaving(false);
    }
  }

  if (done) {
    const submittedData = {
      _id: submissionId,
      personalData,
      leftEyeImage,
      rightEyeImage,
      createdAt: initialData.createdAt,
      completedAt: new Date().toISOString(),
      // The server does the report matching, so take its answer.
      analysis: completed?.analysis || null,
    };
    return (
      <div className="glass-card p-10 sm:p-14">
        <div className="flex flex-col items-center gap-4 text-center">
          <CheckCircle2 size={48} className="text-emerald-400" />
          <h2 className="font-display text-2xl font-bold">Response submitted!</h2>
          <p className="text-white/50">
            Thank you for contributing. You can download a copy of your report below, or view it
            anytime from your profile.
          </p>
          <div className="mt-4 flex flex-col items-center gap-3 sm:flex-row">
            <ReportDownloadButton submission={submittedData} />
            <button type="button" onClick={() => router.push('/profile')} className="btn-secondary">
              Go to my profile
            </button>
          </div>
        </div>

        <AnalysisPanel analysis={submittedData.analysis} submissionId={submissionId} />
      </div>
    );
  }

  return (
    <div className="glass-card p-6 sm:p-10">
      <StepIndicator current={step} />

      {error && (
        <div className="mb-6 flex items-center gap-2 rounded-xl border border-red-500/30 bg-red-500/10 px-4 py-3 text-sm text-red-300">
          <AlertCircle size={16} /> {error}
        </div>
      )}

      {step === 1 && (
        <PersonalDataForm data={personalData} onChange={setPersonalData} />
      )}

      {step === 2 && (
        <div>
          <h2 className="font-display text-xl font-semibold">Left eye image</h2>
          <p className="mb-5 mt-1 text-sm text-white/50">
            Upload a clear, well-lit photo of your left eye.
          </p>
          <ImageDropzone
            label="Upload left eye photo"
            value={leftEyeImage}
            onChange={(dataUrl, meta) => {
              setLeftEyeImage(dataUrl);
              setLeftEyeMeta(meta || null);
            }}
          />
        </div>
      )}

      {step === 3 && (
        <div>
          <h2 className="font-display text-xl font-semibold">Right eye image</h2>
          <p className="mb-5 mt-1 text-sm text-white/50">
            Upload a clear, well-lit photo of your right eye.
          </p>
          <ImageDropzone
            label="Upload right eye photo"
            value={rightEyeImage}
            onChange={(dataUrl, meta) => {
              setRightEyeImage(dataUrl);
              setRightEyeMeta(meta || null);
            }}
          />
        </div>
      )}

      {step === 4 && (
        <ReviewStep personalData={personalData} leftEyeImage={leftEyeImage} rightEyeImage={rightEyeImage} />
      )}

      <div className="mt-9 flex items-center justify-between">
        <button
          type="button"
          onClick={handleBack}
          disabled={step === 1 || saving}
          className="btn-secondary disabled:cursor-not-allowed disabled:opacity-40"
        >
          <ArrowLeft size={16} /> Back
        </button>

        {step < 4 ? (
          <button type="button" onClick={handleNext} disabled={saving} className="btn-primary disabled:opacity-60">
            {saving ? <Loader2 size={16} className="animate-spin" /> : null}
            {saving ? 'Saving...' : 'Save & Continue'}
            {!saving && <ArrowRight size={16} />}
          </button>
        ) : (
          <button type="button" onClick={handleFinalSubmit} disabled={saving} className="btn-primary disabled:opacity-60">
            {saving ? <Loader2 size={16} className="animate-spin" /> : <CheckCircle2 size={16} />}
            {saving ? 'Submitting...' : 'Submit response'}
          </button>
        )}
      </div>
    </div>
  );
}

function PersonalDataForm({ data, onChange }) {
  function set(field, value) {
    onChange({ ...data, [field]: value });
  }

  return (
    <div>
      <h2 className="font-display text-xl font-semibold">Health information</h2>
      <p className="mb-6 mt-1 text-sm text-white/50">
        This helps researchers correlate the eye images with health context.
      </p>

      <div className="grid grid-cols-1 gap-5 sm:grid-cols-2">
        <div>
          <label className="label-text">Age *</label>
          <input
            type="number"
            min="1"
            max="120"
            className="input-field"
            value={data.age}
            onChange={(e) => set('age', e.target.value)}
          />
        </div>
        <div>
          <label className="label-text">Gender *</label>
          <select className="input-field" value={data.gender} onChange={(e) => set('gender', e.target.value)}>
            <option value="">Select...</option>
            <option value="Male">Male</option>
            <option value="Female">Female</option>
            <option value="Other">Other</option>
            <option value="Prefer not to say">Prefer not to say</option>
          </select>
        </div>
        <div>
          <label className="label-text">Diabetes type *</label>
          <select
            className="input-field"
            value={data.diabetesType}
            onChange={(e) => set('diabetesType', e.target.value)}
          >
            <option value="">Select...</option>
            <option value="Type 1">Type 1</option>
            <option value="Type 2">Type 2</option>
            <option value="Prediabetic">Prediabetic</option>
            <option value="Gestational">Gestational</option>
            <option value="None">None</option>
          </select>
        </div>
        <div>
          <label className="label-text">Years since diagnosis</label>
          <input
            type="number"
            min="0"
            max="80"
            className="input-field"
            value={data.diabetesDurationYears}
            onChange={(e) => set('diabetesDurationYears', e.target.value)}
          />
        </div>
        <div>
          <label className="label-text">Fasting blood sugar (mg/dL)</label>
          <input
            type="number"
            className="input-field"
            value={data.bloodSugarLevel}
            onChange={(e) => set('bloodSugarLevel', e.target.value)}
          />
        </div>
        <div>
          <label className="label-text">HbA1c (%)</label>
          <input
            type="number"
            step="0.1"
            className="input-field"
            value={data.hba1c}
            onChange={(e) => set('hba1c', e.target.value)}
          />
        </div>
        <div>
          <label className="label-text">Blood pressure (e.g. 120/80)</label>
          <input
            type="text"
            className="input-field"
            value={data.bloodPressure}
            onChange={(e) => set('bloodPressure', e.target.value)}
          />
        </div>
        <div>
          <label className="label-text">Smoker?</label>
          <select className="input-field" value={data.smoker} onChange={(e) => set('smoker', e.target.value)}>
            <option value="">Select...</option>
            <option value="Yes">Yes</option>
            <option value="No">No</option>
            <option value="Former smoker">Former smoker</option>
          </select>
        </div>
      </div>

      <div className="mt-5">
        <label className="label-text">Additional notes</label>
        <textarea
          rows={3}
          className="input-field resize-none"
          placeholder="Anything else worth mentioning..."
          value={data.additionalNotes}
          onChange={(e) => set('additionalNotes', e.target.value)}
        />
      </div>
    </div>
  );
}

function ReviewStep({ personalData, leftEyeImage, rightEyeImage }) {
  const fields = [
    ['Age', personalData.age],
    ['Gender', personalData.gender],
    ['Diabetes type', personalData.diabetesType],
    ['Years since diagnosis', personalData.diabetesDurationYears],
    ['Fasting blood sugar', personalData.bloodSugarLevel && `${personalData.bloodSugarLevel} mg/dL`],
    ['HbA1c', personalData.hba1c && `${personalData.hba1c}%`],
    ['Blood pressure', personalData.bloodPressure],
    ['Smoker', personalData.smoker],
  ];

  return (
    <div>
      <h2 className="font-display text-xl font-semibold">Review your response</h2>
      <p className="mb-6 mt-1 text-sm text-white/50">
        Double-check everything before submitting — completed responses can't be edited.
      </p>

      <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
        {fields.map(
          ([label, value]) =>
            value && (
              <div key={label} className="rounded-xl bg-white/[0.04] p-3">
                <p className="text-xs text-white/40">{label}</p>
                <p className="mt-0.5 truncate text-sm font-medium">{value}</p>
              </div>
            )
        )}
      </div>

      {personalData.additionalNotes && (
        <div className="mt-4 rounded-xl bg-white/[0.04] p-3">
          <p className="text-xs text-white/40">Notes</p>
          <p className="mt-0.5 text-sm">{personalData.additionalNotes}</p>
        </div>
      )}

      <div className="mt-6 grid grid-cols-2 gap-4">
        <div>
          <p className="mb-2 text-xs text-white/40">Left eye</p>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={leftEyeImage} alt="Left eye" className="h-40 w-full rounded-xl object-cover" />
        </div>
        <div>
          <p className="mb-2 text-xs text-white/40">Right eye</p>
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img src={rightEyeImage} alt="Right eye" className="h-40 w-full rounded-xl object-cover" />
        </div>
      </div>
    </div>
  );
}
