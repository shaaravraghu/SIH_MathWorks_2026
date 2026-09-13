import { redirect } from 'next/navigation';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';
import SubmissionWizard from '@/components/SubmissionWizard';
import GradientBackdrop from '@/components/GradientBackdrop';

export const dynamic = 'force-dynamic';

export default async function SubmitPage() {
  const user = await getCurrentUser();
  if (!user) redirect('/login');

  await dbConnect();
  let draft = await Submission.findOne({ userId: user.userId, status: 'draft' });
  if (!draft) {
    draft = await Submission.create({ userId: user.userId, status: 'draft', currentStep: 1 });
  }

  const initialData = JSON.parse(JSON.stringify(draft));

  return (
    <div className="relative min-h-[calc(100vh-73px)] px-5 py-16">
      <GradientBackdrop />
      <div className="mx-auto max-w-2xl">
        <SubmissionWizard initialData={initialData} />
      </div>
    </div>
  );
}
