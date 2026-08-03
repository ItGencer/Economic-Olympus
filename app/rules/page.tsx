import { readFile } from 'node:fs/promises';
import path from 'node:path';

import type { Metadata } from 'next';

import SiteHeader from '@/components/SiteHeader';

export const metadata: Metadata = {
  title: 'Правила гри | Economic Olympus',
  description: 'Структуровані правила Economic Olympus з GAME_SPEC.md.',
};

type MarkdownBlock =
  | { type: 'heading'; level: 1 | 2 | 3; text: string }
  | { type: 'paragraph'; text: string }
  | { type: 'unordered-list'; items: string[] }
  | { type: 'ordered-list'; items: string[] }
  | { type: 'table'; rows: string[][] };

function stripMarkdownText(value: string) {
  return value
    .replace(/^#+\s+/, '')
    .replace(/^\d+\.\s+/, '')
    .replace(/^-\s+/, '')
    .replace(/\*\*/g, '')
    .trim();
}

function splitTableRow(row: string) {
  return row
    .trim()
    .replace(/^\|/, '')
    .replace(/\|$/, '')
    .split('|')
    .map((cell) => cell.trim());
}

function isDividerRow(row: string[]) {
  return row.every((cell) => /^:?-+:?$/.test(cell));
}

function parseMarkdown(markdown: string): MarkdownBlock[] {
  const lines = markdown.replace(/\r\n/g, '\n').split('\n');
  const blocks: MarkdownBlock[] = [];
  let index = 0;

  while (index < lines.length) {
    const line = lines[index];
    const trimmed = line.trim();

    if (!trimmed) {
      index += 1;
      continue;
    }

    if (trimmed.startsWith('|')) {
      const rows: string[][] = [];

      while (index < lines.length && lines[index].trim().startsWith('|')) {
        const row = splitTableRow(lines[index]);

        if (!isDividerRow(row)) {
          rows.push(row);
        }

        index += 1;
      }

      if (rows.length > 0) {
        blocks.push({ type: 'table', rows });
      }

      continue;
    }

    if (trimmed.startsWith('### ')) {
      blocks.push({
        type: 'heading',
        level: 3,
        text: stripMarkdownText(trimmed),
      });
      index += 1;
      continue;
    }

    if (trimmed.startsWith('## ')) {
      blocks.push({
        type: 'heading',
        level: 2,
        text: stripMarkdownText(trimmed),
      });
      index += 1;
      continue;
    }

    if (trimmed.startsWith('# ')) {
      blocks.push({
        type: 'heading',
        level: 1,
        text: stripMarkdownText(trimmed),
      });
      index += 1;
      continue;
    }

    if (/^-\s+/.test(trimmed)) {
      const items: string[] = [];

      while (index < lines.length && /^-\s+/.test(lines[index].trim())) {
        items.push(stripMarkdownText(lines[index].trim()));
        index += 1;
      }

      blocks.push({ type: 'unordered-list', items });
      continue;
    }

    if (/^\d+\.\s+/.test(trimmed)) {
      const items: string[] = [];

      while (index < lines.length && /^\d+\.\s+/.test(lines[index].trim())) {
        items.push(stripMarkdownText(lines[index].trim()));
        index += 1;
      }

      blocks.push({ type: 'ordered-list', items });
      continue;
    }

    const paragraphLines: string[] = [];

    while (index < lines.length) {
      const paragraphLine = lines[index].trim();

      if (
        !paragraphLine ||
        paragraphLine.startsWith('#') ||
        paragraphLine.startsWith('|') ||
        /^-\s+/.test(paragraphLine) ||
        /^\d+\.\s+/.test(paragraphLine)
      ) {
        break;
      }

      paragraphLines.push(paragraphLine);
      index += 1;
    }

    blocks.push({
      type: 'paragraph',
      text: paragraphLines.join(' '),
    });
  }

  return blocks;
}

function InlineText({ text }: { text: string }) {
  const parts = text.split(/(`[^`]+`)/g);

  return (
    <>
      {parts.map((part, index) => {
        if (part.startsWith('`') && part.endsWith('`')) {
          return (
            <code
              className="rounded bg-slate-100 px-1.5 py-0.5 text-[0.9em] font-semibold text-slate-900"
              key={`${part}-${index}`}
            >
              {part.slice(1, -1)}
            </code>
          );
        }

        return <span key={`${part}-${index}`}>{part}</span>;
      })}
    </>
  );
}

function MarkdownRenderer({ blocks }: { blocks: MarkdownBlock[] }) {
  return (
    <div className="space-y-6">
      {blocks.map((block, index) => {
        if (block.type === 'heading' && block.level === 1) {
          return (
            <h1
              className="text-4xl font-bold tracking-normal text-slate-950"
              key={`${block.text}-${index}`}
            >
              {block.text}
            </h1>
          );
        }

        if (block.type === 'heading' && block.level === 2) {
          return (
            <h2
              className="border-t border-slate-200 pt-8 text-2xl font-bold tracking-normal text-slate-950"
              key={`${block.text}-${index}`}
            >
              {block.text}
            </h2>
          );
        }

        if (block.type === 'heading' && block.level === 3) {
          return (
            <h3
              className="text-xl font-bold tracking-normal text-slate-900"
              key={`${block.text}-${index}`}
            >
              <InlineText text={block.text} />
            </h3>
          );
        }

        if (block.type === 'paragraph') {
          return (
            <p
              className="max-w-4xl text-base leading-7 text-slate-700"
              key={`${block.text}-${index}`}
            >
              <InlineText text={block.text} />
            </p>
          );
        }

        if (block.type === 'unordered-list') {
          return (
            <ul
              className="max-w-4xl list-disc space-y-2 pl-6 text-base leading-7 text-slate-700"
              key={`ul-${index}`}
            >
              {block.items.map((item, itemIndex) => (
                <li key={`${item}-${itemIndex}`}>
                  <InlineText text={item} />
                </li>
              ))}
            </ul>
          );
        }

        if (block.type === 'ordered-list') {
          return (
            <ol
              className="max-w-4xl list-decimal space-y-2 pl-6 text-base leading-7 text-slate-700"
              key={`ol-${index}`}
            >
              {block.items.map((item, itemIndex) => (
                <li key={`${item}-${itemIndex}`}>
                  <InlineText text={item} />
                </li>
              ))}
            </ol>
          );
        }

        if (block.type === 'table') {
          const [header = [], ...rows] = block.rows;

          return (
            <div
              className="max-w-4xl overflow-x-auto rounded-md border border-slate-200 bg-white"
              key={`table-${index}`}
            >
              <table className="w-full min-w-[560px] border-collapse text-left text-sm">
                <thead className="bg-slate-100 text-slate-900">
                  <tr>
                    {header.map((cell, cellIndex) => (
                      <th
                        className="border-b border-slate-200 px-4 py-3 font-bold"
                        key={`${cell}-${cellIndex}`}
                      >
                        <InlineText text={cell} />
                      </th>
                    ))}
                  </tr>
                </thead>
                <tbody>
                  {rows.map((row, rowIndex) => (
                    <tr className="border-b border-slate-100" key={rowIndex}>
                      {row.map((cell, cellIndex) => (
                        <td
                          className="px-4 py-3 align-top text-slate-700"
                          key={`${cell}-${cellIndex}`}
                        >
                          <InlineText text={cell} />
                        </td>
                      ))}
                    </tr>
                  ))}
                </tbody>
              </table>
            </div>
          );
        }

        return null;
      })}
    </div>
  );
}

export default async function RulesPage() {
  const gameSpecPath = path.join(process.cwd(), 'GAME_SPEC.md');
  const markdown = await readFile(gameSpecPath, 'utf8');
  const blocks = parseMarkdown(markdown);

  return (
    <div className="min-h-screen bg-slate-50 text-slate-950">
      <SiteHeader />

      <main className="mx-auto w-full max-w-7xl px-6 py-10">
        <section className="mb-10 border-b border-slate-200 pb-8">
          <p className="text-sm font-semibold uppercase tracking-normal text-emerald-700">
            GAME_SPEC.md
          </p>
          <h1 className="mt-3 text-4xl font-bold tracking-normal text-slate-950">
            Правила гри
          </h1>
          <p className="mt-4 max-w-3xl text-base leading-7 text-slate-700">
            Офіційна специфікація правил, клітинок, переходів, боргів і умов
            перемоги. Вміст цієї сторінки читається напряму з файлу
            <code className="ml-1 rounded bg-slate-100 px-1.5 py-0.5 text-[0.9em] font-semibold text-slate-900">
              GAME_SPEC.md
            </code>
            .
          </p>
        </section>

        <MarkdownRenderer blocks={blocks} />
      </main>
    </div>
  );
}
