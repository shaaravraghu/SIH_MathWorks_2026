import fs from 'fs';
import path from 'path';
import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { resolveReportFile } from '@/lib/reportSets';

export const dynamic = 'force-dynamic';

const CONTENT_TYPES = {
  '.pdf': 'application/pdf',
  '.png': 'image/png',
  '.jpg': 'image/jpeg',
  '.jpeg': 'image/jpeg',
};

// Streams a file out of REPORTS_DIR (which lives outside the app, so Next
// can't serve it statically). Signed-in users only, and the path is clamped
// to REPORTS_DIR so `..` segments can't walk out of it.
export async function GET(request, { params }) {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }

  const segments = (params.path || []).map((s) => decodeURIComponent(s));
  if (segments.some((s) => !s || s === '.' || s === '..' || s.includes('\0'))) {
    return NextResponse.json({ error: 'Bad request' }, { status: 400 });
  }

  const filePath = resolveReportFile(segments);
  if (!filePath) {
    return NextResponse.json({ error: 'Bad request' }, { status: 400 });
  }

  const ext = path.extname(filePath).toLowerCase();
  const contentType = CONTENT_TYPES[ext];
  if (!contentType) {
    return NextResponse.json({ error: 'Unsupported file type' }, { status: 400 });
  }

  let file;
  try {
    file = await fs.promises.readFile(filePath);
  } catch {
    return NextResponse.json({ error: 'Report file not found' }, { status: 404 });
  }

  const asDownload = request.nextUrl.searchParams.get('download') === '1';
  const fileName = path.basename(filePath);

  return new NextResponse(file, {
    headers: {
      'Content-Type': contentType,
      'Content-Length': String(file.length),
      'Content-Disposition': `${asDownload ? 'attachment' : 'inline'}; filename="${fileName}"`,
      'Cache-Control': 'private, max-age=300',
    },
  });
}
