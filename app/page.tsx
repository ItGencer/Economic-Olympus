const facts = [
  { label: 'Гравці', value: '2-6' },
  { label: 'Старт', value: '10 000 $' },
  { label: 'Стан', value: 'Supabase' },
  { label: 'Логіка', value: 'Сервер' },
];

const pillars = [
  {
    title: 'Заробляй репутацію',
    text: 'Імідж посилює сделки, відкриває вигідніші рішення та прямо впливає на премії.',
  },
  {
    title: 'Переходь у великий бізнес',
    text: 'Після 7-10 успішних сделок гравець може вийти із внутрішнього кола на зовнішнє.',
  },
  {
    title: 'Контролюй активи',
    text: 'Тендери, компанії, акції та директорські статуси формують шлях до фінальної перемоги.',
  },
];

export default function HomePage() {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <header className="border-b border-slate-200 bg-white shadow-sm">
        <div className="mx-auto flex w-full max-w-7xl items-center justify-between px-6 py-4">
          <a href="/" className="text-lg font-semibold tracking-normal">
            Економічна Монополія
          </a>

          <nav className="hidden items-center gap-6 text-sm font-medium text-slate-600 md:flex">
            <a href="/" className="text-slate-950">
              Головна
            </a>
            <a href="/rules" className="transition hover:text-slate-950">
              Правила гри
            </a>
            <a href="#start" className="transition hover:text-slate-950">
              Почати гру
            </a>
          </nav>

          <a
            href="#start"
            className="inline-flex h-10 items-center justify-center rounded-md border border-slate-300 px-4 text-sm font-semibold text-slate-700 transition hover:border-slate-400 hover:bg-slate-100"
          >
            Увійти
          </a>
        </div>
      </header>

      <main>
        <section className="border-b border-slate-200 bg-white">
          <div className="mx-auto grid min-h-[calc(100vh-73px)] w-full max-w-7xl gap-10 px-6 py-12 lg:grid-cols-[minmax(0,1fr)_420px] lg:items-center lg:py-16">
            <div className="max-w-3xl">
              <p className="mb-4 text-sm font-semibold uppercase tracking-normal text-emerald-700">
                Онлайн з першого ходу
              </p>
              <h1 className="text-4xl font-bold tracking-normal text-slate-950 sm:text-5xl lg:text-6xl">
                Економічна Монополія
              </h1>
              <p className="mt-6 max-w-2xl text-lg leading-8 text-slate-700">
                Браузерна економічна настільна гра, де гравці проходять шлях
                від перших сделок до контролю компаній, тендерів і виборів
                Генерального директора.
              </p>

              <div className="mt-8 grid gap-3 sm:grid-cols-2">
                <a
                  href="/lobby/new"
                  className="inline-flex h-12 items-center justify-center rounded-md bg-emerald-600 px-6 text-sm font-semibold text-white shadow-sm transition hover:bg-emerald-700"
                >
                  Створити гру
                </a>
                <a
                  href="#join"
                  className="inline-flex h-12 items-center justify-center rounded-md border border-slate-300 bg-white px-6 text-sm font-semibold text-slate-800 transition hover:border-slate-400 hover:bg-slate-100"
                >
                  Приєднатися
                </a>
              </div>

              <dl className="mt-10 grid grid-cols-2 gap-3 sm:grid-cols-4">
                {facts.map((fact) => (
                  <div
                    key={fact.label}
                    className="rounded-md border border-slate-200 bg-slate-50 p-4"
                  >
                    <dt className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                      {fact.label}
                    </dt>
                    <dd className="mt-1 text-xl font-bold text-slate-950">
                      {fact.value}
                    </dd>
                  </div>
                ))}
              </dl>
            </div>

            <aside className="rounded-md border border-slate-200 bg-slate-50 p-5">
              <div className="grid aspect-square grid-cols-7 grid-rows-7 gap-2">
                {Array.from({ length: 49 }).map((_, index) => {
                  const row = Math.floor(index / 7);
                  const col = index % 7;
                  const outer = row === 0 || row === 6 || col === 0 || col === 6;
                  const inner =
                    row >= 2 &&
                    row <= 4 &&
                    col >= 2 &&
                    col <= 4 &&
                    (row === 2 || row === 4 || col === 2 || col === 4);

                  if (!outer && !inner) {
                    return <div key={index} />;
                  }

                  return (
                    <div
                      key={index}
                      className={
                        outer
                          ? 'rounded border border-slate-300 bg-white'
                          : 'rounded border border-emerald-300 bg-emerald-50'
                      }
                    />
                  );
                })}
              </div>
              <div className="mt-5 grid grid-cols-3 gap-3 border-t border-slate-200 pt-4 text-center">
                <div>
                  <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                    Баланс
                  </p>
                  <p className="mt-1 font-bold text-slate-950">10 000 $</p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                    Імідж
                  </p>
                  <p className="mt-1 font-bold text-emerald-700">0</p>
                </div>
                <div>
                  <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                    Сделки
                  </p>
                  <p className="mt-1 font-bold text-amber-700">7-10</p>
                </div>
              </div>
            </aside>
          </div>
        </section>

        <section className="bg-slate-50" id="start">
          <div className="mx-auto grid w-full max-w-7xl gap-8 px-6 py-12 lg:grid-cols-[1fr_360px]">
            <div>
              <h2 className="text-2xl font-bold tracking-normal text-slate-950">
                Як виграти
              </h2>
              <p className="mt-4 max-w-3xl text-base leading-7 text-slate-700">
                Перемога настає після успішних виборів Генерального директора:
                кандидат має зібрати щонайменше 51% голосів активних
                директорів, а всі кидки та підрахунки виконує сервер.
              </p>

              <div className="mt-8 grid gap-4 md:grid-cols-3">
                {pillars.map((pillar) => (
                  <article
                    key={pillar.title}
                    className="rounded-md border border-slate-200 bg-white p-5"
                  >
                    <h3 className="text-base font-bold text-slate-950">
                      {pillar.title}
                    </h3>
                    <p className="mt-3 text-sm leading-6 text-slate-600">
                      {pillar.text}
                    </p>
                  </article>
                ))}
              </div>
            </div>

            <form
              action="/lobby"
              className="rounded-md border border-slate-200 bg-white p-5"
              id="join"
            >
              <label
                htmlFor="join-code"
                className="text-sm font-semibold text-slate-700"
              >
                Код гри
              </label>
              <input
                className="mt-2 h-12 w-full rounded-md border border-slate-300 px-4 text-base font-semibold uppercase outline-none transition placeholder:font-normal placeholder:normal-case focus:border-emerald-600 focus:ring-4 focus:ring-emerald-100"
                id="join-code"
                name="code"
                placeholder="ABCD12"
                type="text"
              />
              <button
                className="mt-4 inline-flex h-12 w-full items-center justify-center rounded-md bg-slate-950 px-6 text-sm font-semibold text-white transition hover:bg-slate-800"
                type="submit"
              >
                Приєднатися
              </button>
            </form>
          </div>
        </section>
      </main>
    </div>
  );
}
