'use client';

import { useState } from 'react';
import { useRouter } from 'next/navigation';
import { Trash2 } from 'lucide-react';

export default function DiscardDraftButton({ draftId }) {
  const router = useRouter();
  const [loading, setLoading] = useState(false);

  async function handleDiscard() {
    if (!confirm('Discard this in-progress response? This cannot be undone.')) {
      return;
    }
    setLoading(true);
    await fetch(`/api/submissions/${draftId}`, { method: 'DELETE' });
    router.refresh();
  }

  return (
    <button
      onClick={handleDiscard}
      disabled={loading}
      className="btn-secondary !text-red-300 disabled:opacity-60"
    >
      <Trash2 size={16} /> {loading ? 'Discarding...' : 'Discard draft'}
    </button>
  );
}
