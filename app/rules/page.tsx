import type { Metadata } from 'next';
import type { ReactNode } from 'react';

import SiteHeader from '@/components/SiteHeader';

export const metadata: Metadata = {
  title: 'Правила гри',
  description:
    'Зрозумілі правила Economic Olympus: мета гри, хід, клітинки, борги, казино, ділові зустрічі та перемога.',
};

type InfoItem = {
  title: string;
  text: string;
};

const quickFacts = [
  { label: 'Гравці', value: '2-6', detail: 'партія для компанії друзів' },
  { label: 'Старт', value: '10 000 $', detail: 'початковий баланс кожного' },
  { label: 'Імідж', value: '0', detail: 'репутація росте або падає' },
  { label: 'Перемога', value: '51%', detail: 'голосів директорів' },
];

const tableOfContents = [
  { href: '#goal', label: 'Мета гри' },
  { href: '#turn', label: 'Хід гравця' },
  { href: '#rings', label: 'Кола поля' },
  { href: '#resources', label: 'Баланс та імідж' },
  { href: '#inner-cells', label: 'Внутрішнє коло' },
  { href: '#outer-cells', label: 'Зовнішнє коло' },
  { href: '#special-cards', label: 'Картки та ризики' },
  { href: '#victory', label: 'Перемога' },
];

const innerCells: InfoItem[] = [
  {
    title: 'Start',
    text: 'Початкова клітинка. Коли гравець проходить Start під час повного кола, він отримує +1000 $.',
  },
  {
    title: 'Ділова зустріч',
    text: 'Ризикована угода: можна відмовитись або кинути d20 і перевірити результат через імідж.',
  },
  {
    title: 'Казино',
    text: 'Ставка на парну або непарну суму двох кубиків. Виграш множиться на коефіцієнт x2-x10.',
  },
  {
    title: 'Random',
    text: 'Випадкова життєва подія: може принести гроші або створити додаткові витрати.',
  },
  {
    title: 'Імідж',
    text: 'Пропозиція купити репутаційне покращення. Якщо грошей не вистачає, купити не можна.',
  },
  {
    title: 'Негативна репутація',
    text: 'Кидок d6 визначає, наскільки зменшиться імідж.',
  },
  {
    title: 'Зарплата',
    text: 'Гравець кидає d20. Позитивний імідж дає премію, від’ємний імідж створює штраф.',
  },
  {
    title: 'Відпустка',
    text: 'Гравець пропускає наступний хід і повертається до гри після паузи.',
  },
];

const outerCells: InfoItem[] = [
  {
    title: 'Компанія',
    text: 'Можна купувати акції. 51% акцій дає контроль над компанією.',
  },
  {
    title: 'Тендер',
    text: 'Можна купити тендер. Якщо інший гравець потрапляє на нього, він платить власнику.',
  },
  {
    title: 'Клієнт',
    text: 'Продаж товарного запасу залежить від іміджу гравця, кидка кубика та настрою клієнта.',
  },
  {
    title: 'Директор',
    text: 'Якщо гравець контролює компанію, він може стати її директором.',
  },
  {
    title: 'Реклама',
    text: 'Платна можливість підняти імідж. Ціна від 100 $ до 1000 $, приріст іміджу від 1 до 10.',
  },
  {
    title: 'Податкова',
    text: 'Знімає 20% від поточного позитивного балансу. Якщо баланс нижче нуля, податок не нараховується.',
  },
  {
    title: 'Позитивна репутація',
    text: 'Додає 1 пункт іміджу без оплати.',
  },
  {
    title: 'Казино, Random, Імідж, Зарплата, Відпустка',
    text: 'Ці клітинки працюють за тими самими правилами, що й на внутрішньому колі.',
  },
];

const casinoSteps = [
  'Гравець може відмовитись від казино, тоді баланс не змінюється.',
  'Ставка не має верхнього ліміту.',
  'Гравець може ставити навіть із боргом; програш збільшує борг.',
  'Після ставки гравець обирає парне або непарне число.',
  'Кидаються два шестигранні кубики, а їхня сума визначає результат.',
  'Якщо прогноз правильний, запускається коефіцієнт x2-x10, і виграш дорівнює ставці, помноженій на цей коефіцієнт.',
  'Якщо прогноз неправильний, ставка віднімається з балансу. Якщо баланс був від’ємний, борг збільшується.',
];

const dealSteps = [
  'На картці з’являється коефіцієнт зустрічі від 5 до 50.',
  'Гравець обирає “Згода” або “Відмова”. Після вибору рішення змінити не можна.',
  'Якщо гравець відмовився, картка закривається, баланс не змінюється.',
  'Якщо гравець погодився, кидається d20, тобто число від 1 до 20.',
  'Підсумок зустрічі: коефіцієнт зустрічі + d20.',
  'Якщо підсумок не більший за імідж гравця, зустріч успішна. Якщо більший, зустріч провалена.',
  'Сума результату: імідж гравця мінус підсумок зустрічі, помножити на 1000 $. Позитивна сума додається, негативна віднімається.',
];

const randomRules = [
  'Картка Random показує випадкову подію з життя бізнесу.',
  'Позитивна подія додає від 100 $ до 2000 $. Сума завжди кратна 100.',
  'Негативна подія віднімає від 1000 $ до 5000 $. Сума завжди кратна 100.',
  'Якщо борг гравця більший за 10 000 $, на клітинці Random випадає тільки позитивна подія.',
  'Якщо після негативної події баланс стає нижче нуля, у гравця з’являється або збільшується борг.',
];

const salarySteps = [
  'На клітинці “Зарплата” відкривається картка з поточним іміджем гравця.',
  'Гравець кидає d20, тобто отримує число від 1 до 20.',
  'Якщо імідж більший за 0, гравець отримує премію: результат d20 помножити на 1000 $.',
  'Якщо імідж менший за 0, гравець отримує штраф: результат d20 помножити на 100 $, і ця сума віднімається з балансу.',
  'Якщо імідж дорівнює 0, баланс не змінюється.',
];

function Section({
  id,
  eyebrow,
  title,
  children,
}: {
  id: string;
  eyebrow?: string;
  title: string;
  children: ReactNode;
}) {
  return (
    <section className="scroll-mt-24 border-b border-slate-200 py-10" id={id}>
      {eyebrow ? (
        <p className="text-sm font-semibold uppercase tracking-normal text-emerald-700">
          {eyebrow}
        </p>
      ) : null}
      <h2 className="mt-2 text-2xl font-bold tracking-normal text-slate-950 sm:text-3xl">
        {title}
      </h2>
      <div className="mt-5 space-y-5 text-base leading-7 text-slate-700">
        {children}
      </div>
    </section>
  );
}

function RuleGrid({ items }: { items: InfoItem[] }) {
  return (
    <div className="grid gap-3 sm:grid-cols-2">
      {items.map((item) => (
        <article
          className="rounded-md border border-slate-200 bg-white p-4 shadow-sm"
          key={item.title}
        >
          <h3 className="text-base font-bold tracking-normal text-slate-950">
            {item.title}
          </h3>
          <p className="mt-2 text-sm leading-6 text-slate-600">{item.text}</p>
        </article>
      ))}
    </div>
  );
}

function StepList({ items }: { items: string[] }) {
  return (
    <ol className="space-y-3">
      {items.map((item, index) => (
        <li className="flex gap-3" key={item}>
          <span className="mt-0.5 flex h-7 w-7 shrink-0 items-center justify-center rounded-md bg-emerald-100 text-sm font-bold text-emerald-800">
            {index + 1}
          </span>
          <span>{item}</span>
        </li>
      ))}
    </ol>
  );
}

export default function RulesPage() {
  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <SiteHeader />

      <main>
        <section className="border-b border-slate-200 bg-white">
          <div className="mx-auto w-full max-w-7xl px-4 py-10 sm:px-6 lg:py-14">
            <p className="text-sm font-semibold uppercase tracking-normal text-emerald-700">
              Правила гри
            </p>
            <div className="mt-4 grid gap-8 lg:grid-cols-[1fr_420px] lg:items-end">
              <div>
                <h1 className="max-w-3xl text-4xl font-bold tracking-normal text-slate-950 sm:text-5xl">
                  Як грати в Economic Olympus
                </h1>
                <p className="mt-5 max-w-3xl text-lg leading-8 text-slate-700">
                  Це економічна настільна гра про репутацію, ризик, активи та
                  шлях до великого бізнесу. Гравці ходять по черзі, приймають
                  рішення на клітинках, заробляють або втрачають гроші,
                  нарощують імідж і борються за контроль над компаніями.
                </p>
              </div>

              <div className="grid grid-cols-2 gap-3">
                {quickFacts.map((fact) => (
                  <div
                    className="rounded-md border border-slate-200 bg-slate-50 p-4"
                    key={fact.label}
                  >
                    <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                      {fact.label}
                    </p>
                    <p className="mt-2 text-2xl font-bold text-slate-950">
                      {fact.value}
                    </p>
                    <p className="mt-1 text-sm leading-5 text-slate-600">
                      {fact.detail}
                    </p>
                  </div>
                ))}
              </div>
            </div>
          </div>
        </section>

        <div className="mx-auto grid w-full max-w-7xl gap-8 px-4 py-8 sm:px-6 lg:grid-cols-[240px_1fr] lg:py-10">
          <aside className="hidden lg:block">
            <nav className="sticky top-24 rounded-md border border-slate-200 bg-white p-4 shadow-sm">
              <p className="text-xs font-semibold uppercase tracking-normal text-slate-500">
                Зміст
              </p>
              <div className="mt-3 space-y-1">
                {tableOfContents.map((item) => (
                  <a
                    className="block rounded-md px-3 py-2 text-sm font-semibold text-slate-600 transition hover:bg-emerald-50 hover:text-emerald-800"
                    href={item.href}
                    key={item.href}
                  >
                    {item.label}
                  </a>
                ))}
              </div>
            </nav>
          </aside>

          <div className="min-w-0">
            <Section id="goal" title="Мета гри" eyebrow="Фінальна ціль">
              <p>
                Перемагає гравець, який стає Генеральним директором. Для цього
                потрібно отримати щонайменше 51% голосів активних директорів.
              </p>
              <p>
                Також партія завершується автоматично, якщо через вибування
                гравців у грі лишився тільки один активний учасник. У такому
                випадку саме він стає переможцем.
              </p>
              <p>
                До перемоги веде ланцюжок рішень: покращувати імідж, заробляти
                гроші, переходити на зовнішнє коло, купувати акції, отримувати
                контроль над компаніями та ставати директором.
              </p>
            </Section>

            <Section id="turn" title="Як проходить хід" eyebrow="Базовий ритм">
              <StepList
                items={[
                  'Гравці ходять по черзі.',
                  'У свій хід гравець кидає кубик d6 і рухається вперед на кількість клітинок, що випала.',
                  'Якщо під час руху гравець проходить Start на внутрішньому колі, він отримує +1000 $.',
                  'Клітинка, на яку потрапив гравець, відкриває дію: картку, оплату, покупку, ризик або бонус.',
                  'Якщо гравець потрапив на “Відпустку”, він пропускає свій наступний хід, а інші гравці ходять далі.',
                  'Якщо дія потребує рішення, гравець обирає один із варіантів на картці.',
                  'Коли дія завершена, черга переходить до наступного гравця.',
                ]}
              />
            </Section>

            <Section id="rings" title="Два кола поля" eyebrow="Шлях розвитку">
              <div className="grid gap-4 md:grid-cols-2">
                <article className="rounded-md border border-slate-200 bg-white p-5 shadow-sm">
                  <h3 className="text-lg font-bold text-slate-950">
                    Внутрішнє коло
                  </h3>
                  <p className="mt-2">
                    Стартовий етап гри. Тут гравець набирає імідж, проходить
                    ділові зустрічі, ризикує в казино, отримує зарплату та
                    стикається з випадковими подіями.
                  </p>
                </article>
                <article className="rounded-md border border-slate-200 bg-white p-5 shadow-sm">
                  <h3 className="text-lg font-bold text-slate-950">
                    Зовнішнє коло
                  </h3>
                  <p className="mt-2">
                    Бізнес-етап гри. Тут з’являються компанії, акції, тендери,
                    клієнти та директори. Саме на цьому колі гравець готується
                    до перемоги.
                  </p>
                </article>
              </div>
              <p>
                Перехід на зовнішнє коло стає доступним, коли у гравця
                позитивний баланс, немає боргового блокування та є щонайменше 7
                успішних ділових зустрічей. Після 10 успішних зустрічей гра
                обов’язково запропонує вибір: перейти на зовнішнє коло або ще
                залишитись всередині.
              </p>
            </Section>

            <Section
              id="resources"
              title="Баланс, імідж і борги"
              eyebrow="Ресурси гравця"
            >
              <div className="grid gap-3 md:grid-cols-3">
                <article className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
                  <h3 className="font-bold text-slate-950">Баланс</h3>
                  <p className="mt-2 text-sm leading-6">
                    Гроші потрібні для ставок, покупок, реклами, іміджу,
                    тендерів і акцій. Баланс може стати від’ємним.
                  </p>
                </article>
                <article className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
                  <h3 className="font-bold text-slate-950">Імідж</h3>
                  <p className="mt-2 text-sm leading-6">
                    Репутація впливає на ділові зустрічі, клієнтів і вибори.
                    Від’ємний імідж погіршує результати так само, як позитивний
                    допомагає.
                  </p>
                </article>
                <article className="rounded-md border border-slate-200 bg-white p-4 shadow-sm">
                  <h3 className="font-bold text-slate-950">Борг</h3>
                  <p className="mt-2 text-sm leading-6">
                    Борг виникає, коли баланс нижче нуля. Якщо це сталося на
                    зовнішньому колі, гравець повертається на Start
                    внутрішнього кола. Борг понад 50 000 $ вмикає попередження.
                    Борг 100 000 $ або більше вибиває гравця з гри, а його
                    акції повертаються в банк.
                  </p>
                </article>
              </div>
              <p>
                Поки борг не погашено і баланс не повернувся до нуля або вище,
                гравець не може перейти на зовнішнє коло.
              </p>
              <p>
                Якщо гравець вибув через борг 100 000 $ або більше, його фішка
                більше не бере участі в ходах. Акції, які він купив, знову
                стають доступними для інших гравців.
              </p>
              <p>
                Якщо після вибування активних гравців ще більше одного, партія
                продовжується. Коли активних гравців лишається двоє, наступне
                вибування одного з них одразу приносить перемогу іншому.
              </p>
            </Section>

            <Section
              id="inner-cells"
              title="Клітинки внутрішнього кола"
              eyebrow="Перший етап"
            >
              <RuleGrid items={innerCells} />
            </Section>

            <Section
              id="outer-cells"
              title="Клітинки зовнішнього кола"
              eyebrow="Великий бізнес"
            >
              <RuleGrid items={outerCells} />
            </Section>

            <Section
              id="special-cards"
              title="Картки та ризикові дії"
              eyebrow="Що важливо пам’ятати"
            >
              <div className="space-y-8">
                <article>
                  <h3 className="text-xl font-bold text-slate-950">
                    Ділова зустріч
                  </h3>
                  <div className="mt-4">
                    <StepList items={dealSteps} />
                  </div>
                </article>

                <article>
                  <h3 className="text-xl font-bold text-slate-950">Казино</h3>
                  <p className="mt-3">
                    Казино можна прийняти навіть із боргом. Ставка безлімітна:
                    гравець сам обирає суму, а програш може збільшити борг.
                  </p>
                  <div className="mt-4">
                    <StepList items={casinoSteps} />
                  </div>
                </article>

                <article>
                  <h3 className="text-xl font-bold text-slate-950">Random</h3>
                  <div className="mt-4">
                    <StepList items={randomRules} />
                  </div>
                </article>

                <article>
                  <h3 className="text-xl font-bold text-slate-950">
                    Зарплата
                  </h3>
                  <div className="mt-4">
                    <StepList items={salarySteps} />
                  </div>
                </article>

                <article>
                  <h3 className="text-xl font-bold text-slate-950">
                    Негативна репутація
                  </h3>
                  <p className="mt-3">
                    Гравець запускає картку та кидає d6. Втрата іміджу дорівнює
                    результату кубика. Після кнопки “Далі” ця кількість
                    віднімається від іміджу.
                  </p>
                </article>
              </div>
            </Section>

            <Section id="victory" title="Компанії, директори та перемога">
              <div className="grid gap-4 md:grid-cols-2">
                <article className="rounded-md border border-slate-200 bg-white p-5 shadow-sm">
                  <h3 className="text-lg font-bold text-slate-950">
                    Акції та контроль
                  </h3>
                  <p className="mt-2">
                    У кожної компанії 2000 акцій. Якщо гравець має 51% або
                    більше, він контролює компанію і може претендувати на
                    директорський статус.
                  </p>
                </article>
                <article className="rounded-md border border-slate-200 bg-white p-5 shadow-sm">
                  <h3 className="text-lg font-bold text-slate-950">
                    Вибори Генерального директора
                  </h3>
                  <p className="mt-2">
                    Кандидат перемагає, якщо набирає щонайменше 51% голосів
                    активних директорів. Після цього партія завершується.
                  </p>
                </article>
              </div>
              <p>
                Імідж допомагає проходити перевірки, але сам по собі не
                гарантує перемогу. Головне — перетворити репутацію та гроші на
                контроль над активами.
              </p>
              <p>
                Якщо в партії було більше двох гравців, вибування просто
                зменшує кількість активних учасників, доки їх не стане двоє.
                Якщо після будь-якого вибування лишається один активний гравець,
                він перемагає автоматично. Якщо активних гравців двоє або
                більше, гра триває до перемоги через директорський статус і
                контроль 51%.
              </p>
            </Section>
          </div>
        </div>
      </main>
    </div>
  );
}
