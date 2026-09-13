'use client';

import { useState } from 'react';
import { Activity, ExternalLink, ImageOff, Layers, ScanEye } from 'lucide-react';

// Colour per ICDR grade, mildest to most severe.
const GRADE_STYLES = {
  0: 'bg-emerald-500/15 text-emerald-300 border-emerald-400/30',
  1: 'bg-lime-500/15 text-lime-300 border-lime-400/30',
  2: 'bg-amber-500/15 text-amber-300 border-amber-400/30',
  3: 'bg-orange-500/15 text-orange-300 border-orange-400/30',
  4: 'bg-red-500/15 text-red-300 border-red-400/30',
};

const VIEWS = [
  { key: 'attentionUrl', label: 'Attention map', icon: ScanEye },
  { key: 'panelsUrl', label: 'Analysis panels', icon: Layers },
];

export default function AnalysisPanel({ analysis, submissionId }) {
  const [view, setView] = useState('attentionUrl');

  if (!analysis) return null;

  // The report is served per-submission so the patient block carries this
  // person's details rather than the pipeline's placeholder ones.
  const reportUrl = submissionId ? `/api/submissions/${submissionId}/report` : null;

  const gradeStyle =
    GRADE_STYLES[analysis.grade] ?? 'bg-white/10 text-white/70 border-white/20';

  return (
    <div className="mt-6 rounded-2xl border border-white/10 bg-white/[0.03] p-5">
      <div className="flex flex-wrap items-center justify-between gap-3">
        <div className="flex items-center gap-3">
          <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-fuchsia-500/15 text-fuchsia-300">
            <Activity size={20} />
          </span>
          <div>
            <p className="font-semibold">Screening analysis</p>
            <p className="text-xs text-white/40">
              Matched to {analysis.setLabel || analysis.setId}
              {analysis.matchedBy === 'content'
                ? ' by image content'
                : ' by file name'}
            </p>
          </div>
        </div>

        {analysis.grade !== null && analysis.grade !== undefined && (
          <span
            className={`rounded-full border px-3 py-1 text-xs font-semibold ${gradeStyle}`}
          >
            Grade {analysis.grade}
            {analysis.gradeLabel ? ` · ${analysis.gradeLabel}` : ''}
          </span>
        )}
      </div>

      {/* The report's own one-line verdict, worded as the PDF words it. */}
      {analysis.verdict && (
        <p
          className={`mt-4 rounded-xl border px-4 py-2.5 text-sm font-medium ${
            analysis.verdict.flagged
              ? 'border-red-400/25 bg-red-500/10 text-red-200'
              : 'border-emerald-400/25 bg-emerald-500/10 text-emerald-200'
          }`}
        >
          {analysis.verdict.flagged ? 'Flagged for review' : 'Not flagged'} — worst eye{' '}
          {analysis.verdict.worstEye?.toUpperCase()}: {analysis.verdict.gradeLabel} (level{' '}
          {analysis.verdict.grade})
          {typeof analysis.verdict.referableProbability === 'number' &&
            `, referable probability ${Math.round(analysis.verdict.referableProbability * 100)}%`}
        </p>
      )}

      <div className="mt-5 flex gap-2">
        {VIEWS.map(({ key, label, icon: Icon }) => (
          <button
            key={key}
            type="button"
            onClick={() => setView(key)}
            className={`inline-flex items-center gap-1.5 rounded-full px-3 py-1.5 text-xs font-medium transition ${
              view === key
                ? 'bg-white/15 text-white'
                : 'bg-white/[0.04] text-white/50 hover:bg-white/10 hover:text-white/80'
            }`}
          >
            <Icon size={14} /> {label}
          </button>
        ))}
      </div>

      <div className="mt-4 grid grid-cols-1 gap-4 sm:grid-cols-2">
        <EyeView title="Left eye" eye={analysis.left} view={view} />
        <EyeView title="Right eye" eye={analysis.right} view={view} />
      </div>

      {reportUrl && (
        <a
          href={reportUrl}
          target="_blank"
          rel="noreferrer"
          className="mt-5 inline-flex items-center gap-2 text-sm text-fuchsia-300 hover:text-fuchsia-200"
        >
          <ExternalLink size={15} /> Open the full screening report
        </a>
      )}
    </div>
  );
}

function EyeView({ title, eye, view }) {
  const src = eye?.[view];
  const hasGrade = eye?.grade !== null && eye?.grade !== undefined;
  const gradeStyle =
    GRADE_STYLES[eye?.grade] ?? 'bg-white/10 text-white/70 border-white/20';

  return (
    <div>
      <div className="mb-2 flex items-center justify-between gap-2">
        <span className="text-xs text-white/40">{title}</span>
        {hasGrade ? (
          <span
            className={`rounded-full border px-2 py-0.5 text-[11px] font-semibold ${gradeStyle}`}
          >
            Level {eye.grade} · {eye.gradeLabel}
            {typeof eye.probability === 'number' &&
              ` · ${Math.round(eye.probability * 100)}%`}
          </span>
        ) : (
          eye?.matched === false && <span className="text-xs text-white/25">not matched</span>
        )}
      </div>
      {src ? (
        <a href={src} target="_blank" rel="noreferrer">
          {/* eslint-disable-next-line @next/next/no-img-element */}
          <img
            src={src}
            alt={`${title} ${view === 'attentionUrl' ? 'attention map' : 'analysis panels'}`}
            className="w-full rounded-xl border border-white/10 bg-black/30 object-contain transition hover:border-white/25"
          />
        </a>
      ) : (
        <div className="flex h-40 items-center justify-center gap-2 rounded-xl border border-dashed border-white/10 text-xs text-white/30">
          <ImageOff size={14} /> No image for this view
        </div>
      )}
    </div>
  );
}
