import Link from 'next/link';
import { Eye, Mail, MapPin, Github, Twitter, Linkedin } from 'lucide-react';

export default function Footer() {
  return (
    <footer className="border-t border-white/5 bg-black/20">
      <div className="mx-auto max-w-6xl px-5 py-14">
        <div className="grid grid-cols-1 gap-10 sm:grid-cols-2 lg:grid-cols-4">
          {/* Brand */}
          <div>
            <Link href="/" className="flex items-center gap-2 font-display text-lg font-bold">
              <span className="flex h-8 w-8 items-center justify-center rounded-lg bg-gradient-to-br from-fuchsia-500 to-indigo-500">
                <Eye size={16} className="text-white" />
              </span>
              <span className="gradient-text">RetinaScan</span>
            </Link>
            <p className="mt-3 text-sm text-white/40">
              An open research initiative building a dataset to help train
              machine learning models to detect diabetic retinopathy earlier.
            </p>
          </div>

          {/* Quick links */}
          <div>
            <p className="mb-3 text-sm font-semibold text-white/80">Quick links</p>
            <ul className="space-y-2 text-sm text-white/40">
              <li><Link href="/" className="hover:text-white">Home</Link></li>
              <li><Link href="/#about" className="hover:text-white">About diabetic retinopathy</Link></li>
              <li><Link href="/#founders" className="hover:text-white">Our team</Link></li>
              <li><Link href="/signup" className="hover:text-white">Get started</Link></li>
            </ul>
          </div>

          {/* Resources (dummy) */}
          <div>
            <p className="mb-3 text-sm font-semibold text-white/80">Resources</p>
            <ul className="space-y-2 text-sm text-white/40">
              <li><a href="#" className="hover:text-white">Privacy policy</a></li>
              <li><a href="#" className="hover:text-white">Terms of use</a></li>
              <li><a href="#" className="hover:text-white">Data usage &amp; consent</a></li>
              <li><a href="#" className="hover:text-white">FAQs</a></li>
            </ul>
          </div>

          {/* Contact (dummy) */}
          <div>
            <p className="mb-3 text-sm font-semibold text-white/80">Contact us</p>
            <ul className="space-y-3 text-sm text-white/40">
              <li className="flex items-center gap-2">
                <Mail size={15} className="shrink-0 text-fuchsia-300" />
                <a href="mailto:contact.retinascan@gmail.com" className="hover:text-white">
                  contact.retinascan@gmail.com
                </a>
              </li>
              <li className="flex items-center gap-2">
                <MapPin size={15} className="shrink-0 text-fuchsia-300" />
                Hyderabad, Telangana, India
              </li>
            </ul>
            <div className="mt-4 flex gap-3">
              <a href="#" aria-label="Twitter" className="flex h-9 w-9 items-center justify-center rounded-full bg-white/5 text-white/50 hover:bg-white/10 hover:text-white">
                <Twitter size={16} />
              </a>
              <a href="#" aria-label="LinkedIn" className="flex h-9 w-9 items-center justify-center rounded-full bg-white/5 text-white/50 hover:bg-white/10 hover:text-white">
                <Linkedin size={16} />
              </a>
              <a href="#" aria-label="GitHub" className="flex h-9 w-9 items-center justify-center rounded-full bg-white/5 text-white/50 hover:bg-white/10 hover:text-white">
                <Github size={16} />
              </a>
            </div>
          </div>
        </div>

        <div className="mt-12 border-t border-white/5 pt-6 text-center text-xs text-white/30">
          © {new Date().getFullYear()} RetinaScan. Built for diabetic retinopathy research. All data used strictly for ML research purposes.
        </div>
      </div>
    </footer>
  );
}
