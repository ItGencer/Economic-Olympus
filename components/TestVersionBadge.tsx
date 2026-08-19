'use client';

type TestVersionBadgeProps = {
  className?: string;
};

export function TestVersionBadge({ className = '' }: TestVersionBadgeProps) {
  return (
    <span
      className={`inline-flex items-center justify-center rounded-full border border-amber-300/45 bg-amber-300/12 px-3 py-1 text-xs font-black uppercase tracking-normal text-amber-100 shadow-[0_0_18px_rgba(251,191,36,0.18)] ${className}`}
    >
      Тестова версія гри
    </span>
  );
}

export default TestVersionBadge;
