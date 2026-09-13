import { NextResponse } from 'next/server';
import { getCurrentUser } from '@/lib/session';
import { describeReportsConfig } from '@/lib/reportSets';

export const dynamic = 'force-dynamic';

// Diagnostics: shows which folder the app is reading reports from and which
// sets it found. Handy when a match unexpectedly fails — hit
// /api/reports/status while signed in.
export async function GET() {
  const user = await getCurrentUser();
  if (!user) {
    return NextResponse.json({ error: 'Unauthorized' }, { status: 401 });
  }
  return NextResponse.json(describeReportsConfig());
}
