import Link from 'next/link';
import { redirect, notFound } from 'next/navigation';
import { ArrowLeft, CheckCircle2 } from 'lucide-react';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';
import GradientBackdrop from '@/components/GradientBackdrop';
import AnalysisPanel from '@/components/AnalysisPanel';
import ReportDownloadButton from '@/components/ReportDownloadButton';
import { refreshStaleAnalysis } from '@/lib/reportSets';

export const dynamic = 'force-dynamic';

export default async function SubmissionDetailPage({ params }) {
  const user = await getCurrentUser();
  if (!user) redirect('/login');

  await dbConnect();
  const submission = await Submission.findOne({
    _id: params.id,
    userId: user.userId,
  });

  if (!submission) notFound();

  // Submissions completed before the grade source changed still carry the old
  // findings — re-match them so the page agrees with the PDF.
  await refreshStaleAnalysis(submission);

  const p = submission.personalData || {};
  const fields = [
    ['Age', p.age],
    ['Gender', p.gender],
    ['Diabetes type', p.diabetesType],
    ['Years since diagnosis', p.diabetesDurationYears],
    ['Fasting blood sugar', p.bloodSugarLevel && `${p.bloodSugarLevel} mg/dL`],
    ['HbA1c', p.hba1c && `${p.hba1c}%`],
    ['Blood pressure', p.bloodPressure],
    ['Smoker', p.smoker],
  ];

  const date = new Date(submission.completedAt || submission.createdAt).toLocaleString();

  // Plain objects only — this is handed to a client component.
  const reportData = {
    _id: submission._id.toString(),
    personalData: submission.personalData ? submission.personalData.toObject() : {},
    leftEyeImage: submission.leftEyeImage,
    rightEyeImage: submission.rightEyeImage,
    createdAt: submission.createdAt?.toISOString?.() || null,
    completedAt: submission.completedAt?.toISOString?.() || null,
    analysis: submission.analysis ? JSON.parse(JSON.stringify(submission.analysis)) : null,
  };

  return (
    <div className="relative min-h-[calc(100vh-73px)] px-5 py-16">
      <GradientBackdrop />
      <div className="mx-auto max-w-3xl">
        <Link href="/profile" className="mb-6 inline-flex items-center gap-2 text-sm text-white/50 hover:text-white">
          <ArrowLeft size={16} /> Back to profile
        </Link>

        <div className="glass-card p-8">
          <div className="mb-6 flex items-center justify-between">
            <div className="flex items-center gap-3">
              <span className="flex h-10 w-10 items-center justify-center rounded-xl bg-emerald-500/15 text-emerald-300">
                <CheckCircle2 size={20} />
              </span>
              <div>
                <p className="font-semibold">Completed response</p>
                <p className="text-xs text-white/40">Submitted {date}</p>
              </div>
            </div>
            <ReportDownloadButton submission={reportData} />
          </div>

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

          {p.additionalNotes && (
            <div className="mt-4 rounded-xl bg-white/[0.04] p-3">
              <p className="text-xs text-white/40">Notes</p>
              <p className="mt-0.5 text-sm">{p.additionalNotes}</p>
            </div>
          )}

          <div className="mt-6 grid grid-cols-1 gap-4 sm:grid-cols-2">
            <div>
              <p className="mb-2 text-xs text-white/40">Left eye</p>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={submission.leftEyeImage}
                alt="Left eye"
                className="h-56 w-full rounded-xl object-cover"
              />
            </div>
            <div>
              <p className="mb-2 text-xs text-white/40">Right eye</p>
              {/* eslint-disable-next-line @next/next/no-img-element */}
              <img
                src={submission.rightEyeImage}
                alt="Right eye"
                className="h-56 w-full rounded-xl object-cover"
              />
            </div>
          </div>

          <AnalysisPanel analysis={reportData.analysis} submissionId={reportData._id} />
        </div>
      </div>
    </div>
  );
}
