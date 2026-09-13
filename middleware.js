import { NextResponse } from 'next/server';
import { verifyToken } from './lib/auth';

const protectedPaths = ['/dashboard', '/submit', '/profile'];
const authPaths = ['/login', '/signup'];

export async function middleware(request) {
  const { pathname } = request.nextUrl;
  const token = request.cookies.get('token')?.value;
  const payload = token ? await verifyToken(token) : null;

  if (protectedPaths.some((p) => pathname.startsWith(p)) && !payload) {
    const loginUrl = new URL('/login', request.url);
    loginUrl.searchParams.set('redirect', pathname);
    return NextResponse.redirect(loginUrl);
  }

  if (authPaths.some((p) => pathname.startsWith(p)) && payload) {
    return NextResponse.redirect(new URL('/dashboard', request.url));
  }

  return NextResponse.next();
}

export const config = {
  matcher: [
    '/dashboard/:path*',
    '/submit/:path*',
    '/profile/:path*',
    '/login',
    '/signup',
  ],
};
