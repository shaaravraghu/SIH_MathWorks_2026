'use client';

import { useEffect, useRef } from 'react';

export default function GradientBackdrop() {
  const ref = useRef(null);

  useEffect(() => {
    function handleMove(e) {
      const x = (e.clientX / window.innerWidth) * 100;
      const y = (e.clientY / window.innerHeight) * 100;
      if (ref.current) {
        ref.current.style.setProperty('--mx', `${x}%`);
        ref.current.style.setProperty('--my', `${y}%`);
      }
    }
    window.addEventListener('mousemove', handleMove);
    return () => window.removeEventListener('mousemove', handleMove);
  }, []);

  return (
    <div
      ref={ref}
      className="pointer-events-none fixed inset-0 -z-10 overflow-hidden transition-colors duration-700"
      style={{
        background:
          'radial-gradient(600px circle at var(--mx, 50%) var(--my, 15%), rgba(168,85,247,0.16), transparent 55%), #050510',
      }}
    >
      <div className="absolute inset-0 bg-grid-white [mask-image:radial-gradient(ellipse_60%_50%_at_50%_0%,black,transparent)]" />
      <div className="absolute -top-40 left-1/4 h-[32rem] w-[32rem] animate-blob rounded-full bg-fuchsia-600/30 blur-[110px]" />
      <div className="absolute top-1/3 -right-20 h-[28rem] w-[28rem] animate-blob rounded-full bg-indigo-600/30 blur-[110px] [animation-delay:4s]" />
      <div className="absolute bottom-0 left-1/3 h-[26rem] w-[26rem] animate-blob rounded-full bg-cyan-500/20 blur-[110px] [animation-delay:8s]" />
    </div>
  );
}
