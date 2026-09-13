'use client';

import { useRef, useState } from 'react';
import { UploadCloud, RefreshCcw, ImageOff } from 'lucide-react';
import { resizeImage } from '@/lib/resizeImage';

// Fingerprints the file exactly as it sits on disk — before resizeImage()
// re-encodes it — so the server can match it to a pre-generated report even
// if the file has been renamed. Returns '' where SubtleCrypto isn't available
// (non-HTTPS origins other than localhost); the file name is then the only
// signal, which is fine.
async function sha256OfFile(file) {
  try {
    const subtle = globalThis.crypto?.subtle;
    if (!subtle) return '';
    const digest = await subtle.digest('SHA-256', await file.arrayBuffer());
    return Array.from(new Uint8Array(digest))
      .map((b) => b.toString(16).padStart(2, '0'))
      .join('');
  } catch {
    return '';
  }
}

export default function ImageDropzone({ label, value, onChange }) {
  const inputRef = useRef(null);
  const [dragActive, setDragActive] = useState(false);
  const [processing, setProcessing] = useState(false);
  const [error, setError] = useState('');

  async function processFile(file) {
    if (!file) return;
    if (!file.type.startsWith('image/')) {
      setError('Please upload an image file.');
      return;
    }
    setError('');
    setProcessing(true);
    try {
      const [dataUrl, sha256] = await Promise.all([
        resizeImage(file),
        sha256OfFile(file),
      ]);
      onChange(dataUrl, { fileName: file.name, sha256 });
    } catch (err) {
      setError('Could not process that image. Try another file.');
    } finally {
      setProcessing(false);
    }
  }

  return (
    <div>
      <div
        onDragOver={(e) => {
          e.preventDefault();
          setDragActive(true);
        }}
        onDragLeave={() => setDragActive(false)}
        onDrop={(e) => {
          e.preventDefault();
          setDragActive(false);
          processFile(e.dataTransfer.files?.[0]);
        }}
        onClick={() => inputRef.current?.click()}
        className={`relative flex min-h-[260px] cursor-pointer flex-col items-center justify-center overflow-hidden rounded-2xl border-2 border-dashed transition-all duration-200
        ${
          dragActive
            ? 'border-fuchsia-400 bg-fuchsia-500/10'
            : 'border-white/15 bg-white/[0.03] hover:border-white/30 hover:bg-white/[0.05]'
        }`}
      >
        <input
          ref={inputRef}
          type="file"
          accept="image/*"
          className="hidden"
          onChange={(e) => processFile(e.target.files?.[0])}
        />

        {value ? (
          <>
            {/* eslint-disable-next-line @next/next/no-img-element */}
            <img src={value} alt={label} className="h-full w-full object-cover" />
            <div className="absolute inset-0 flex items-center justify-center bg-black/50 opacity-0 transition-opacity hover:opacity-100">
              <span className="inline-flex items-center gap-2 rounded-full bg-white/10 px-4 py-2 text-sm font-medium backdrop-blur">
                <RefreshCcw size={16} /> Replace image
              </span>
            </div>
          </>
        ) : processing ? (
          <p className="text-sm text-white/50">Processing image...</p>
        ) : (
          <div className="flex flex-col items-center gap-3 px-6 text-center">
            <div className="flex h-14 w-14 items-center justify-center rounded-2xl bg-gradient-to-br from-fuchsia-500/20 to-indigo-500/20 text-fuchsia-300">
              <UploadCloud size={26} />
            </div>
            <p className="font-medium text-white/80">{label}</p>
            <p className="text-xs text-white/40">
              Click to browse or drag & drop &middot; JPG / PNG
            </p>
          </div>
        )}
      </div>
      {error && (
        <p className="mt-2 flex items-center gap-1.5 text-sm text-red-300">
          <ImageOff size={14} /> {error}
        </p>
      )}
    </div>
  );
}
