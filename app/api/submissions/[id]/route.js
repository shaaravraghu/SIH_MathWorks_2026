import { NextResponse } from 'next/server';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';
import { matchReportSet, refreshStaleAnalysis } from '@/lib/reportSets';

// Keeps only the two fields we use, so a client can't stash arbitrary data
// on the submission.
function sanitizeMeta(meta) {
  if (!meta || typeof meta !== 'object') return undefined;
  return {
    fileName: typeof meta.fileName === 'string' ? meta.fileName.slice(0, 260) : undefined,
    sha256: /^[0-9a-f]{64}$/i.test(meta.sha256 || '') ? meta.sha256.toLowerCase() : undefined,
  };
}

function toPlainMeta(meta) {
  if (!meta) return null;
  return typeof meta.toObject === 'function' ? meta.toObject() : meta;
}

export async function GET(request, { params }) {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await dbConnect();
  const submission = await Submission.findOne({
    _id: params.id,
    userId: user.userId,
  });
  if (!submission) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }
  await refreshStaleAnalysis(submission);
  return NextResponse.json({ submission });
}

export async function PATCH(request, { params }) {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await dbConnect();

  const submission = await Submission.findOne({
    _id: params.id,
    userId: user.userId,
  });
  if (!submission) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }
  if (submission.status === 'completed') {
    return NextResponse.json(
      { error: 'This response has already been submitted and is locked.' },
      { status: 400 }
    );
  }

  const body = await request.json();
  const {
    personalData,
    leftEyeImage,
    rightEyeImage,
    leftEyeMeta,
    rightEyeMeta,
    currentStep,
    complete,
  } = body;

  if (personalData) {
    submission.personalData = {
      ...(submission.personalData ? submission.personalData.toObject() : {}),
      ...personalData,
    };
  }
  if (leftEyeImage !== undefined) submission.leftEyeImage = leftEyeImage;
  if (rightEyeImage !== undefined) submission.rightEyeImage = rightEyeImage;
  if (leftEyeMeta !== undefined) submission.leftEyeMeta = sanitizeMeta(leftEyeMeta);
  if (rightEyeMeta !== undefined) submission.rightEyeMeta = sanitizeMeta(rightEyeMeta);
  if (currentStep !== undefined) submission.currentStep = currentStep;

  if (complete) {
    if (
      !submission.personalData ||
      !submission.leftEyeImage ||
      !submission.rightEyeImage
    ) {
      return NextResponse.json(
        { error: 'Please complete every step before submitting.' },
        { status: 400 }
      );
    }
    // Pull the pre-generated report for this eye pair, if we recognise it.
    submission.analysis =
      matchReportSet(
        toPlainMeta(submission.leftEyeMeta),
        toPlainMeta(submission.rightEyeMeta)
      ) || null;
    submission.markModified('analysis');

    submission.status = 'completed';
    submission.completedAt = new Date();
  }

  await submission.save();
  return NextResponse.json({ submission });
}

export async function DELETE(request, { params }) {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  await dbConnect();
  const submission = await Submission.findOne({
    _id: params.id,
    userId: user.userId,
  });
  if (!submission) {
    return NextResponse.json({ error: 'Not found' }, { status: 404 });
  }
  if (submission.status === 'completed') {
    return NextResponse.json(
      { error: 'Cannot delete a completed response.' },
      { status: 400 }
    );
  }
  await submission.deleteOne();
  return NextResponse.json({ success: true });
}
