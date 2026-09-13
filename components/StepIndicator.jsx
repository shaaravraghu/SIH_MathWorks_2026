'use client';

import { Check, ClipboardList, Eye, ScanEye, CheckCheck } from 'lucide-react';

const steps = [
  { id: 1, label: 'Health info', icon: ClipboardList },
  { id: 2, label: 'Left eye', icon: Eye },
  { id: 3, label: 'Right eye', icon: ScanEye },
  { id: 4, label: 'Review', icon: CheckCheck },
];

export default function StepIndicator({ current }) {
  return (
    <div className="mb-10 flex items-center justify-between">
      {steps.map((step, idx) => {
        const isDone = current > step.id;
        const isActive = current === step.id;
        const Icon = step.icon;
        return (
          <div key={step.id} className="flex flex-1 items-center">
            <div className="flex flex-col items-center gap-2">
              <div
                className={`flex h-10 w-10 items-center justify-center rounded-full border-2 transition-all duration-300 sm:h-11 sm:w-11
                ${
                  isDone
                    ? 'border-fuchsia-400 bg-fuchsia-500/20 text-fuchsia-300'
                    : isActive
                    ? 'border-fuchsia-400 bg-gradient-to-br from-fuchsia-500 to-indigo-500 text-white shadow-[0_0_20px_rgba(168,85,247,0.5)]'
                    : 'border-white/15 bg-white/5 text-white/30'
                }`}
              >
                {isDone ? <Check size={18} /> : <Icon size={18} />}
              </div>
              <span
                className={`hidden text-xs font-medium sm:block ${
                  isActive || isDone ? 'text-white/80' : 'text-white/30'
                }`}
              >
                {step.label}
              </span>
            </div>
            {idx < steps.length - 1 && (
              <div
                className={`mx-2 h-0.5 flex-1 rounded transition-all duration-300 ${
                  current > step.id ? 'bg-fuchsia-400' : 'bg-white/10'
                }`}
              />
            )}
          </div>
        );
      })}
    </div>
  );
}
