import Link from 'next/link';
import { redirect } from 'next/navigation';
import { PlusCircle, PlayCircle, UserCircle2, CheckCircle2, Clock } from 'lucide-react';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';
import GradientBackdrop from '@/components/GradientBackdrop';
import DiscardDraftButton from '@/components/DiscardDraftButton';

export const dynamic = 'force-dynamic';

export default async function DashboardPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');

  await dbConnect();
  const [draft, completedCount] = await Promise.all([
    Submission.findOne({ userId: user.userId, status: 'draft' }).select(
      '-leftEyeImage -rightEyeImage'
    ),
    Submission.countDocuments({ userId: user.userId, status: 'completed' }),
  ]);

  return (
    <div className="relative min-h-[calc(100vh-73px)] px-5 py-16">
      <GradientBackdrop />
      <div className="mx-auto max-w-4xl">
        <h1 className="font-display text-3xl font-bold sm:text-4xl">
          Welcome, <span className="gradient-text">{user.name}</span>
        </h1>
        <p className="mt-2 text-white/50">
          Here's an overview of your contributions so far.
        </p>

        <div className="mt-10 grid grid-cols-1 gap-6 sm:grid-cols-2">
          <div className="glass-card flex items-center gap-4 p-6">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-emerald-500/15 text-emerald-300">
              <CheckCircle2 size={22} />
            </div>
            <div>
              <p className="text-2xl font-bold">{completedCount}</p>
              <p className="text-sm text-white/50">Completed responses</p>
            </div>
          </div>
          <div className="glass-card flex items-center gap-4 p-6">
            <div className="flex h-12 w-12 items-center justify-center rounded-xl bg-amber-500/15 text-amber-300">
              <Clock size={22} />
            </div>
            <div>
              <p className="text-2xl font-bold">{draft ? 1 : 0}</p>
              <p className="text-sm text-white/50">In-progress draft</p>
            </div>
          </div>
        </div>

        <div className="glass-card mt-8 p-8 text-center">
          {draft ? (
            <>
              <h2 className="font-display text-xl font-semibold">
                You have a response in progress
              </h2>
              <p className="mt-2 text-sm text-white/50">
                Pick up right where you left off — step {draft.currentStep} of 4.
              </p>
              <div className="mt-6 flex flex-col items-center justify-center gap-3 sm:flex-row">
                <Link href="/submit" className="btn-primary">
                  <PlayCircle size={18} /> Resume response
                </Link>
                <DiscardDraftButton draftId={draft._id.toString()} />
              </div>
            </>
          ) : (
            <>
              <h2 className="font-display text-xl font-semibold">
                Ready for a new response?
              </h2>
              <p className="mt-2 text-sm text-white/50">
                Each response includes a short health form plus your left and
                right eye images.
              </p>
              <Link href="/submit" className="btn-primary mt-6 inline-flex">
                <PlusCircle size={18} /> Start new response
              </Link>
            </>
          )}
        </div>

        <div className="mt-6 text-center">
          <Link
            href="/profile"
            className="inline-flex items-center gap-2 text-sm font-medium text-white/60 hover:text-white"
          >
            <UserCircle2 size={16} /> View all my submitted data
          </Link>
        </div>
      </div>
    </div>
  );
}
