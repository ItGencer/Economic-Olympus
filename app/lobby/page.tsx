import { redirect } from 'next/navigation';

export default function LobbyIndexPage({
  searchParams,
}: {
  searchParams: { code?: string };
}) {
  const code = searchParams.code?.trim().toUpperCase();

  if (code) {
    redirect(`/lobby/${encodeURIComponent(code)}`);
  }

  redirect('/#start');
}
