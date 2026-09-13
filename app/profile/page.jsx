import Link from 'next/link';
import { redirect } from 'next/navigation';
import { CheckCircle2, Clock, ChevronRight, PlusCircle, UserCircle2 } from 'lucide-react';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';
import GradientBackdrop from '@/components/GradientBackdrop';

export const dynamic = 'force-dynamic';

export default async function ProfilePage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');

  await dbConnect();
  const submissions = await Submission.find({ userId: user.userId })
    .select('-leftEyeImage -rightEyeImage')
    .sort({ createdAt: -1 });

  return (
    <div className="relative min-h-[calc(100vh-73px)] px-5 py-16">
      <GradientBackdrop />
      <div className="mx-auto max-w-3xl">
        <div className="mb-8 flex items-center gap-4">
          <span className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-fuchsia-500 to-indigo-500 text-2xl font-bold shadow-[0_0_25px_rgba(168,85,247,0.4)]">
            {user.name?.[0]?.toUpperCase() || <UserCircle2 />}
          </span>
          <div>
            <h1 className="font-display text-2xl font-bold sm:text-3xl">{user.name}</h1>
            <p className="text-sm text-white/50">{user.email}</p>
          </div>
        </div>

        <div className="mb-6 flex items-center justify-between">
          <h2 className="font-display text-lg font-semibold text-white/80">
            My submitted responses ({submissions.length})
          </h2>
          <Link href="/dashboard" className="btn-secondary !px-4 !py-2 text-sm">
            <PlusCircle size={16} /> New / resume
          </Link>
        </div>

        {submissions.length === 0 ? (
          <div className="glass-card p-10 text-center text-white/50">
            You haven't submitted any responses yet.
          </div>
        ) : (
          <div className="space-y-3">
            {submissions.map((s) => (
              <SubmissionRow key={s._id.toString()} submission={s} />
            ))}
          </div>
        )}
      </div>
    </div>
  );
}

function SubmissionRow({ submission }) {
  const isCompleted = submission.status === 'completed';
  const date = new Date(submission.completedAt || submission.updatedAt).toLocaleDateString(
    undefined,
    { year: 'numeric', month: 'short', day: 'numeric' }
  );

  const inner = (
    <div className="glass-card flex items-center justify-between gap-4 p-5 transition hover:bg-white/[0.06]">
      <div className="flex items-center gap-4">
        <div
          className={`flex h-11 w-11 items-center justify-center rounded-xl ${
            isCompleted ? 'bg-emerald-500/15 text-emerald-300' : 'bg-amber-500/15 text-amber-300'
          }`}
        >
          {isCompleted ? <CheckCircle2 size={20} /> : <Clock size={20} />}
        </div>
        <div>
          <p className="font-medium">
            {isCompleted ? 'Completed response' : `Draft — step ${submission.currentStep} of 4`}
          </p>
          <p className="text-sm text-white/40">{date}</p>
        </div>
      </div>
      {isCompleted ? (
        <div className="flex items-center gap-3">
          {submission.analysis?.gradeLabel && (
            <span className="rounded-full border border-white/15 bg-white/[0.06] px-3 py-1 text-xs font-medium text-white/70">
              Grade {submission.analysis.grade} · {submission.analysis.gradeLabel}
            </span>
          )}
          <ChevronRight size={18} className="text-white/30" />
        </div>
      ) : (
        <span className="rounded-full bg-amber-500/10 px-3 py-1 text-xs font-medium text-amber-300">
          In progress
        </span>
      )}
    </div>
  );

  return isCompleted ? (
    <Link href={`/profile/${submission._id.toString()}`}>{inner}</Link>
  ) : (
    <Link href="/submit">{inner}</Link>
  );
}
