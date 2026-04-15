import Link from 'next/link'
import { House, Search, AudioLines } from 'lucide-react'

export function Sidebar() {
  return (
    <aside
      className="fixed left-0 top-0 h-screen w-[240px] bg-[var(--background-card)] text-[var(--foreground)] border-r border-white/10"
    >
      <div className="flex h-full flex-col px-6 py-5">
        {/* Logo / Titel */}
        <div className="mb-10 flex items-center gap-3">
          <AudioLines size={40} color="var(--accent)" aria-hidden="true" />
          <h3 className="text-xl font-semibold text-[var(--accent)]">
            Media Lens
          </h3>
        </div>

        {/* Navigation */}
        <nav className="flex flex-col gap-2">
          <Link
            href="/"
            className="flex items-center gap-3 rounded-xl px-3 py-2 text-lg transition hover:bg-white/5 hover:text-[var(--accent)]"
          >
            <House size={24} aria-hidden="true" />
            <span>Home</span>
          </Link>

          <Link
            href="/search"
            className="flex items-center gap-3 rounded-xl px-3 py-2 text-lg transition hover:bg-white/5 hover:text-[var(--accent)]"
          >
            <Search size={24} aria-hidden="true" />
            <span>Suche</span>
          </Link>
        </nav>

        {/* Optional: unten Profil o.ä. */}
        <div className="mt-auto text-xs text-white/40">
          © {new Date().getFullYear()} Media Lens
        </div>
      </div>
    </aside>
  )
}