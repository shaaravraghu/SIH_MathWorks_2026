/** @type {import('next').NextConfig} */
const nextConfig = {
  reactStrictMode: true,
  experimental: {
    serverActions: {
      bodySizeLimit: '8mb',
    },
    // reports/ and the font are read from disk at runtime, so Next's build
    // tracer can't see them. Without this they're left out of the serverless
    // bundle on Vercel and every report 404s in production.
    outputFileTracingIncludes: {
      '/api/reports/**': ['./reports/**/*', './lib/sourceImages.json'],
      '/api/submissions/**': [
        './reports/**/*',
        './lib/sourceImages.json',
        './assets/fonts/*',
      ],
      '/profile/**': ['./reports/**/*', './lib/sourceImages.json'],
    },
  },
};

module.exports = nextConfig;
