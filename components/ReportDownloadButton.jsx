'use client';

import { useState } from 'react';
import { FileDown, Loader2, CheckCircle2 } from 'lucide-react';
import { downloadReportPdf } from '@/lib/generateReport';

// Simulated "analysing" delay before the download starts, so the demo reads
// like the model is running. Set to 0 to make the download instant.
const REPORT_GENERATION_DELAY_MS = 10000;

export default function ReportDownloadButton({ submission }) {
  const [status, setStatus] = useState('idle'); // 'idle' | 'generating' | 'done'
  const [error, setError] = useState('');

  // When the uploaded pair matched one of the pre-generated sets, serve the
  // pipeline's real PDF with this submission's details written into its
  // patient block. Otherwise fall back to the placeholder built in-browser.
  const reportUrl = submission?.analysis
    ? `/api/submissions/${submission._id}/report`
    : null;

  async function handleDownload() {
    setError('');
    setStatus('generating');
    try {
      const [res] = await Promise.all([
        reportUrl ? fetch(`${reportUrl}?download=1`) : Promise.resolve(null),
        new Promise((resolve) => setTimeout(resolve, REPORT_GENERATION_DELAY_MS)),
      ]);

      if (res) {
        if (!res.ok) throw new Error('Could not fetch the screening report.');
        const blob = await res.blob();
        const href = URL.createObjectURL(blob);
        const link = document.createElement('a');
        link.href = href;
        link.download = `screening-report-${submission._id}.pdf`;
        document.body.appendChild(link);
        link.click();
        link.remove();
        URL.revokeObjectURL(href);
      } else {
        downloadReportPdf(submission);
      }

      setStatus('done');
      setTimeout(() => setStatus('idle'), 2500);
    } catch (err) {
      setError(err.message || 'Download failed.');
      setStatus('idle');
    }
  }

  return (
    <div className="flex flex-col items-center gap-1.5">
      <button
        onClick={handleDownload}
        disabled={status === 'generating'}
        className="btn-primary disabled:cursor-not-allowed disabled:opacity-70"
      >
        {status === 'generating' && (
          <>
            <Loader2 size={16} className="animate-spin" />
            {reportUrl ? 'Analysing images...' : 'Generating report...'}
          </>
        )}
        {status === 'done' && (
          <>
            <CheckCircle2 size={16} /> Downloaded!
          </>
        )}
        {status === 'idle' && (
          <>
            <FileDown size={16} /> Download report
          </>
        )}
      </button>
      {error && <p className="text-xs text-red-300">{error}</p>}
    </div>
  );
}
