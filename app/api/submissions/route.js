import { NextResponse } from 'next/server';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';

// List all of the current user's submissions (no image payload, keeps it light)
export async function GET() {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await dbConnect();
  const submissions = await Submission.find({ userId: user.userId })
    .select('-leftEyeImage -rightEyeImage')
    .sort({ createdAt: -1 });
  return NextResponse.json({ submissions });
}

// Start a new response, or resume the existing draft if one is in progress.
export async function POST() {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await dbConnect();

  let draft = await Submission.findOne({
    userId: user.userId,
    status: 'draft',
  });

  if (!draft) {
    draft = await Submission.create({
      userId: user.userId,
      status: 'draft',
      currentStep: 1,
    });
  }

  return NextResponse.json({ submission: draft });
}
