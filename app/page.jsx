import Link from 'next/link';
import {
  Eye,
  ScanEye,
  ShieldCheck,
  Database,
  ArrowRight,
  Sparkles,
  ClipboardList,
  UploadCloud,
  CheckCircle2,
  AlertTriangle,
  HeartPulse,
  Activity,
  Mail,
} from 'lucide-react';
import GradientBackdrop from '@/components/GradientBackdrop';

const founders = [
  {
    name: 'Rishav Sharma',
    role: 'Co-Founder & CEO',
    bio: 'Leads product and research partnerships. Passionate about applying ML to accessible healthcare in India.',
    avatarSeed: 'Rishav Sharma',
  },
  {
    name: 'Ananya Verma',
    role: 'Co-Founder & CTO',
    bio: 'Builds the ML pipeline and data infrastructure that turns raw submissions into a training-ready dataset.',
    avatarSeed: 'Ananya Verma',
  },
  {
    name: 'Dr. Karan Mehta',
    role: 'Medical Advisor',
    bio: 'Practicing ophthalmologist advising on clinical accuracy, data quality, and patient safety.',
    avatarSeed: 'Karan Mehta',
  },
];

export default function HomePage() {
  return (
    <div className="relative">
      <GradientBackdrop />

      {/* HERO */}
      <section className="mx-auto flex max-w-5xl flex-col items-center px-5 pb-20 pt-20 text-center sm:pt-28">
        <div className="mb-6 inline-flex items-center gap-2 rounded-full glass px-4 py-1.5 text-xs font-medium text-white/70 animate-fade-up">
          <Sparkles size={14} className="text-fuchsia-400" />
          Open research initiative &middot; Help train real ML models
        </div>

        <h1 className="animate-fade-up font-display text-4xl font-bold leading-[1.1] tracking-tight sm:text-6xl [animation-delay:100ms] opacity-0">
          See the future of{' '}
          <span className="gradient-text">early diabetic retinopathy</span>{' '}
          detection
        </h1>

        <p className="mt-6 max-w-2xl animate-fade-up text-balance text-lg text-white/60 [animation-delay:220ms] opacity-0">
          We're building an open dataset of retinal images and health metrics
          to train machine learning models that can catch diabetic eye
          disease earlier. Your submission — a couple of eye photos and a
          short health form — genuinely moves the research forward.
        </p>

        <div className="mt-10 flex animate-fade-up flex-col gap-4 sm:flex-row [animation-delay:340ms] opacity-0">
          <Link href="/signup" className="btn-primary text-base">
            Get Started <ArrowRight size={18} />
          </Link>
          <Link href="/login" className="btn-secondary text-base">
            I already have an account
          </Link>
        </div>
      </section>

      {/* HERO IMAGES */}
      <section className="mx-auto max-w-6xl px-5 pb-20">
        <div className="grid grid-cols-2 gap-4 sm:grid-cols-4">
          <img
            src="https://images.unsplash.com/photo-1517920366573-9d35a519b7c2?auto=format&fit=crop&w=600&q=80"
            alt="Close-up of a human eye"
            className="h-40 w-full rounded-2xl object-cover sm:h-56 transition duration-300 hover:scale-[1.03]"
          />
          <img
            src="https://images.unsplash.com/photo-1682663946978-48c2c9f8ffe9?auto=format&fit=crop&w=600&q=80"
            alt="An eye exam room with diagnostic equipment"
            className="h-40 w-full rounded-2xl object-cover sm:h-56 transition duration-300 hover:scale-[1.03]"
          />
          <img
            src="https://images.unsplash.com/photo-1539036776273-021ec1d78bec?auto=format&fit=crop&w=600&q=80"
            alt="Eye testing machine used in ophthalmology"
            className="h-40 w-full rounded-2xl object-cover sm:h-56 transition duration-300 hover:scale-[1.03]"
          />
          <img
            src="https://images.unsplash.com/photo-1576210117723-cd06449a467d?auto=format&fit=crop&w=600&q=80"
            alt="Medical eye test in progress"
            className="h-40 w-full rounded-2xl object-cover sm:h-56 transition duration-300 hover:scale-[1.03]"
          />
        </div>
      </section>

      {/* STATS / TRUST STRIP */}
      <section className="border-y border-white/5 bg-white/[0.02] py-10">
        <div className="mx-auto grid max-w-5xl grid-cols-1 gap-8 px-5 sm:grid-cols-3">
          <Stat icon={<Database size={20} />} title="Structured dataset" subtitle="Every response stored cleanly for model training" />
          <Stat icon={<ShieldCheck size={20} />} title="Your data, your account" subtitle="Only you can see the responses you submit" />
          <Stat icon={<ScanEye size={20} />} title="Two-eye capture" subtitle="Left & right eye images per response" />
        </div>
      </section>

      {/* HOW IT WORKS */}
      <section className="mx-auto max-w-5xl px-5 py-24">
        <h2 className="text-center font-display text-3xl font-bold sm:text-4xl">
          How contributing <span className="gradient-text">works</span>
        </h2>
        <p className="mx-auto mt-3 max-w-xl text-center text-white/50">
          A guided, form-style flow — just like filling out a form, except
          your progress is saved automatically at every step.
        </p>

        <div className="mt-14 grid grid-cols-1 gap-6 sm:grid-cols-3">
          <StepCard
            number="01"
            icon={<ClipboardList size={22} />}
            title="Share health details"
            desc="A short form covering age, diabetes history and a few key vitals."
          />
          <StepCard
            number="02"
            icon={<UploadCloud size={22} />}
            title="Upload eye images"
            desc="Add a photo of your left eye, then your right eye. Progress saves as you go."
          />
          <StepCard
            number="03"
            icon={<CheckCircle2 size={22} />}
            title="Review & submit"
            desc="Confirm everything looks right, submit, and it's added to your profile."
          />
        </div>
      </section>

      {/* ABOUT / DIABETIC RETINOPATHY IN INDIA */}
      <section id="about" className="border-y border-white/5 bg-white/[0.02] px-5 py-24 scroll-mt-20">
        <div className="mx-auto max-w-5xl">
          <div className="mx-auto max-w-2xl text-center">
            <h2 className="font-display text-3xl font-bold sm:text-4xl">
              Diabetic Retinopathy — <span className="gradient-text">a growing concern in India</span>
            </h2>
            <p className="mt-4 text-white/60">
              India is home to one of the largest diabetic populations in the world, and diabetic
              retinopathy (DR) — a complication that damages the blood vessels of the retina — is
              becoming one of the leading causes of preventable blindness among working-age adults
              in the country. Many cases go undiagnosed until vision loss is already significant,
              largely because early-stage DR often has no noticeable symptoms and access to
              retinal screening remains limited in rural and semi-urban areas. This is exactly the
              gap an accessible, camera-based screening model could help close — which is why
              every response you contribute here matters.
            </p>
          </div>

          <div className="mt-14 grid grid-cols-1 gap-6 md:grid-cols-2">
            <InfoCard
              icon={<AlertTriangle size={20} />}
              color="amber"
              title="Common symptoms"
              items={[
                'Blurred, patchy, or fluctuating vision',
                'Dark spots or "floaters" drifting across your sight',
                'Difficulty seeing clearly at night',
                'Colors appearing faded or washed out',
                'Sudden vision loss in advanced, untreated cases',
              ]}
            />
            <InfoCard
              icon={<HeartPulse size={20} />}
              color="emerald"
              title="Precautions & prevention"
              items={[
                'Get a dilated eye exam at least once a year if you have diabetes',
                'Keep blood sugar (HbA1c), blood pressure, and cholesterol under control',
                'Don\'t wait for symptoms — early-stage DR is often symptom-free',
                'Quit smoking, which significantly raises DR risk',
                'Report any sudden change in vision to a doctor immediately',
              ]}
            />
          </div>

          <div className="mt-6 glass-card flex items-start gap-4 p-6">
            <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-fuchsia-500/15 text-fuchsia-300">
              <Activity size={20} />
            </div>
            <p className="text-sm text-white/60">
              <span className="font-semibold text-white/80">Why this project exists: </span>
              Screening every diabetic patient manually isn't scalable given India's doctor-to-patient
              ratio in ophthalmology. A well-trained ML model, given enough diverse and accurately
              labeled retinal images, could help flag high-risk cases early and prioritize them for a
              real clinical exam — extending the reach of the few specialists we have.
            </p>
          </div>
        </div>
      </section>

      {/* FOUNDERS */}
      <section id="founders" className="mx-auto max-w-5xl px-5 py-24 scroll-mt-20">
        <h2 className="text-center font-display text-3xl font-bold sm:text-4xl">
          Meet the <span className="gradient-text">team</span>
        </h2>
        <p className="mx-auto mt-3 max-w-xl text-center text-white/50">
          A small team of builders and clinicians working on making eye screening more accessible.
        </p>

        <div className="mt-14 grid grid-cols-1 gap-6 sm:grid-cols-3">
          {founders.map((f) => (
            <div key={f.name} className="glass-card p-7 text-center transition duration-300 hover:-translate-y-1">
              <img
                src={`https://ui-avatars.com/api/?name=${encodeURIComponent(f.avatarSeed)}&background=a855f7&color=fff&size=128&bold=true`}
                alt={f.name}
                className="mx-auto h-20 w-20 rounded-full ring-2 ring-fuchsia-400/40"
              />
              <h3 className="mt-4 font-display text-lg font-semibold">{f.name}</h3>
              <p className="text-sm font-medium text-fuchsia-300">{f.role}</p>
              <p className="mt-2 text-sm text-white/50">{f.bio}</p>
            </div>
          ))}
        </div>
      </section>

      {/* CTA */}
      <section id="contact" className="mx-auto max-w-4xl px-5 pb-28 scroll-mt-20">
        <div className="glass-card relative overflow-hidden px-8 py-14 text-center">
          <div className="absolute -top-24 right-0 h-64 w-64 rounded-full bg-fuchsia-600/30 blur-[100px]" />
          <div className="absolute -bottom-24 left-0 h-64 w-64 rounded-full bg-indigo-600/30 blur-[100px]" />
          <Eye className="mx-auto mb-5 text-fuchsia-400" size={36} />
          <h3 className="font-display text-2xl font-bold sm:text-3xl">
            Ready to contribute your first response?
          </h3>
          <p className="mx-auto mt-3 max-w-md text-white/60">
            It takes about two minutes. Create a free account to begin.
          </p>
          <Link href="/signup" className="btn-primary mt-8 inline-flex text-base">
            Get Started <ArrowRight size={18} />
          </Link>
          <div className="mt-6 flex items-center justify-center gap-2 text-sm text-white/40">
            <Mail size={14} /> Questions? Reach us at{' '}
            <a href="mailto:contact.retinascan@gmail.com" className="text-fuchsia-300 hover:text-fuchsia-200">
              contact.retinascan@gmail.com
            </a>
          </div>
        </div>
      </section>
    </div>
  );
}

function Stat({ icon, title, subtitle }) {
  return (
    <div className="flex items-start gap-4">
      <div className="flex h-11 w-11 shrink-0 items-center justify-center rounded-xl bg-white/5 text-fuchsia-300">
        {icon}
      </div>
      <div>
        <p className="font-semibold text-white">{title}</p>
        <p className="text-sm text-white/40">{subtitle}</p>
      </div>
    </div>
  );
}

function StepCard({ number, icon, title, desc }) {
  return (
    <div className="glass-card group relative overflow-hidden p-7 transition duration-300 hover:-translate-y-1">
      <span className="font-display text-4xl font-bold text-white/10 transition group-hover:text-white/20">
        {number}
      </span>
      <div className="mt-3 mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl bg-gradient-to-br from-fuchsia-500/20 to-indigo-500/20 text-fuchsia-300">
        {icon}
      </div>
      <h4 className="font-display text-lg font-semibold">{title}</h4>
      <p className="mt-2 text-sm text-white/50">{desc}</p>
    </div>
  );
}

function InfoCard({ icon, color, title, items }) {
  const colorMap = {
    amber: 'bg-amber-500/15 text-amber-300',
    emerald: 'bg-emerald-500/15 text-emerald-300',
  };
  return (
    <div className="glass-card p-7">
      <div className={`mb-4 inline-flex h-11 w-11 items-center justify-center rounded-xl ${colorMap[color]}`}>
        {icon}
      </div>
      <h4 className="font-display text-lg font-semibold">{title}</h4>
      <ul className="mt-4 space-y-2.5">
        {items.map((item) => (
          <li key={item} className="flex items-start gap-2.5 text-sm text-white/60">
            <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-fuchsia-400" />
            {item}
          </li>
        ))}
      </ul>
    </div>
  );
}
