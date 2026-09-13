'use client';

import { useEffect, useState } from 'react';
import Link from 'next/link';
import { useRouter, usePathname } from 'next/navigation';
import { Eye, LayoutDashboard, UserCircle2, LogOut, Menu, X } from 'lucide-react';

const publicLinks = [
  { href: '/', label: 'Home' },
  { href: '/#about', label: 'About DR' },
  { href: '/#founders', label: 'Our Team' },
  { href: '/#contact', label: 'Contact' },
];

export default function Navbar() {
  const [user, setUser] = useState(null);
  const [loading, setLoading] = useState(true);
  const [menuOpen, setMenuOpen] = useState(false);
  const router = useRouter();
  const pathname = usePathname();

  useEffect(() => {
    fetch('/api/auth/me')
      .then((res) => res.json())
      .then((data) => setUser(data.user))
      .catch(() => setUser(null))
      .finally(() => setLoading(false));
  }, [pathname]);

  async function handleLogout() {
    await fetch('/api/auth/logout', { method: 'POST' });
    setUser(null);
    router.push('/');
    router.refresh();
  }

  return (
    <header className="sticky top-0 z-50 border-b border-white/5 bg-ink/70 backdrop-blur-xl">
      <div className="mx-auto flex max-w-6xl items-center justify-between px-5 py-4">
        <Link href="/" className="flex items-center gap-2 font-display text-lg font-bold tracking-tight">
          <span className="flex h-9 w-9 items-center justify-center rounded-xl bg-gradient-to-br from-fuchsia-500 to-indigo-500 shadow-[0_0_20px_rgba(168,85,247,0.5)]">
            <Eye size={18} className="text-white" />
          </span>
          <span className="gradient-text">RetinaScan</span>
        </Link>

        <nav className="hidden items-center gap-1 md:flex">
          {publicLinks.map((link) => (
            <Link
              key={link.href}
              href={link.href}
              className="rounded-full px-3.5 py-2 text-sm font-medium text-white/60 transition hover:bg-white/5 hover:text-white"
            >
              {link.label}
            </Link>
          ))}

          <div className="mx-2 h-5 w-px bg-white/10" />

          {!loading && user && (
            <>
              <NavLink href="/dashboard" icon={<LayoutDashboard size={16} />} label="Dashboard" />
              <NavLink href="/profile" icon={<UserCircle2 size={16} />} label="My Profile" />
              <button
                onClick={handleLogout}
                className="ml-1 inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm font-medium text-white/70 transition hover:bg-white/5 hover:text-white"
              >
                <LogOut size={16} /> Logout
              </button>
            </>
          )}
          {!loading && !user && (
            <>
              <Link
                href="/login"
                className="rounded-full px-4 py-2 text-sm font-medium text-white/70 transition hover:text-white"
              >
                Log in
              </Link>
              <Link href="/signup" className="btn-primary !px-5 !py-2.5 text-sm">
                Get Started
              </Link>
            </>
          )}
        </nav>

        <button
          className="md:hidden text-white/80"
          onClick={() => setMenuOpen((v) => !v)}
          aria-label="Toggle menu"
        >
          {menuOpen ? <X size={22} /> : <Menu size={22} />}
        </button>
      </div>

      {menuOpen && (
        <div className="border-t border-white/5 px-5 py-4 md:hidden">
          <div className="flex flex-col gap-3">
            {publicLinks.map((link) => (
              <Link key={link.href} href={link.href} onClick={() => setMenuOpen(false)} className="text-white/80">
                {link.label}
              </Link>
            ))}
            <div className="my-1 h-px bg-white/10" />
            {!loading && user && (
              <>
                <Link href="/dashboard" onClick={() => setMenuOpen(false)} className="text-white/80">
                  Dashboard
                </Link>
                <Link href="/profile" onClick={() => setMenuOpen(false)} className="text-white/80">
                  My Profile
                </Link>
                <button onClick={handleLogout} className="text-left text-white/80">
                  Logout
                </button>
              </>
            )}
            {!loading && !user && (
              <>
                <Link href="/login" onClick={() => setMenuOpen(false)} className="text-white/80">
                  Log in
                </Link>
                <Link href="/signup" onClick={() => setMenuOpen(false)} className="text-white/80">
                  Get Started
                </Link>
              </>
            )}
          </div>
        </div>
      )}
    </header>
  );
}

function NavLink({ href, icon, label }) {
  return (
    <Link
      href={href}
      className="inline-flex items-center gap-2 rounded-full px-4 py-2 text-sm font-medium text-white/70 transition hover:bg-white/5 hover:text-white"
    >
      {icon}
      {label}
    </Link>
  );
}
