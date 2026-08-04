import Image from 'next/image';

export function SiteFooter() {
  return (
    <footer className="border-t border-violet-300/20 px-4 py-6 sm:px-6">
      <div className="neo-panel mx-auto flex w-full max-w-7xl flex-col gap-4 rounded-[20px] border border-violet-300/25 px-5 py-5 sm:flex-row sm:items-center sm:justify-between">
        <div className="flex min-w-0 items-center gap-3">
          <span className="grid h-12 w-12 shrink-0 place-items-center overflow-hidden rounded-full border border-amber-300/55 bg-white shadow-[0_0_22px_rgba(192,132,252,0.35)]">
            <Image
              alt=""
              className="h-full w-full object-cover"
              height={48}
              src="/economic_olympus_logo.png"
              width={48}
            />
          </span>
          <div className="min-w-0">
            <p className="neo-heading truncate text-base font-bold tracking-normal text-violet-50">
              Economic Olympus
            </p>
            <p className="mt-1 text-sm font-semibold text-slate-400">
              Онлайн-гра про репутацію, ризик і контроль активів.
            </p>
          </div>
        </div>

        <div className="flex flex-col gap-1 text-sm font-semibold text-slate-300 sm:items-end">
          <p>
            Гра <span className="text-fuchsia-200">Economic Olympus</span>
          </p>
          <p>
            Розробник сайту{' '}
            <span className="text-fuchsia-200">Gencer IT</span>
          </p>
        </div>
      </div>
    </footer>
  );
}

export default SiteFooter;
