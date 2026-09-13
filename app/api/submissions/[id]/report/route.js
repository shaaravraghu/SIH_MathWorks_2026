import fs from 'fs';
import { NextResponse } from 'next/server';
import dbConnect from '@/lib/mongodb';
import Submission from '@/models/Submission';
import { getCurrentUser } from '@/lib/session';
import { resolveReportFile } from '@/lib/reportSets';
import { personalizeReportPdf } from '@/lib/personalizeReport';

export const dynamic = 'force-dynamic';

// Serves this submission's screening report: the PDF the MATLAB pipeline
// generated for the matched image set, with the patient block rewritten from
// the submitted form data. Findings and images are left exactly as generated.
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

  const reportPdf = submission.analysis?.reportPdf;
  if (!reportPdf) {
    return NextResponse.json(
      { error: 'No screening report is available for this submission.' },
      { status: 404 }
    );
  }

  const filePath = resolveReportFile(reportPdf.split('/'));
  if (!filePath) {
    return NextResponse.json({ error: 'Bad report path' }, { status: 400 });
  }

  let original;
  try {
    original = await fs.promises.readFile(filePath);
  } catch {
    return NextResponse.json({ error: 'Report file not found' }, { status: 404 });
  }

  let bytes;
  try {
    ({ bytes } = await personalizeReportPdf(original, submission));
  } catch (err) {
    // A patching failure shouldn't cost the user their report — fall back to
    // the pipeline's original, which is correct apart from the patient block.
    console.error('Could not personalize report PDF:', err);
    bytes = original;
  }

  const asDownload = request.nextUrl.searchParams.get('download') === '1';

  return new NextResponse(Buffer.from(bytes), {
    headers: {
      'Content-Type': 'application/pdf',
      'Content-Length': String(bytes.length),
      'Content-Disposition': `${asDownload ? 'attachment' : 'inline'}; filename="screening-report-${params.id}.pdf"`,
      'Cache-Control': 'private, no-store',
    },
  });
}
