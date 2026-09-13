# RetinaScan — Diabetic Retinopathy Data Collector

A full-stack Next.js 14 app for collecting eye images + health data to train a
diabetic retinopathy detection model. Sign up, log in, fill out a multi-step
form (health info → left eye photo → right eye photo → review), and view all
your past submissions from your profile. Progress auto-saves at every step,
just like a Google Form — and you must finish your current response before
starting a new one.

## Tech stack

- **Next.js 14** (App Router) — frontend + API routes in one project (ideal for Vercel)
- **MongoDB + Mongoose** — one `User` collection, one `Submission` collection
- **JWT auth** (via `jose`) stored in an httpOnly cookie — no third-party auth service needed
- **Tailwind CSS + Framer-motion-style CSS animations + lucide-react icons** — the UI layer
- Images are resized/compressed in the browser and stored as base64 strings directly on the
  `Submission` document (kept intentionally simple/"lite" — no S3/Cloudinary needed)

## 1. Run it locally in VS Code

```bash
# 1. Unzip the project and open it in VS Code
cd dr-app
npm install

# 2. Create your local env file
cp .env.example .env.local
```

Edit `.env.local`:

```
MONGODB_URI=mongodb://127.0.0.1:27017/dr-data-collector
JWT_SECRET=some_long_random_string
REPORTS_DIR=C:\Pranav\college\sih\SIH_MathWorks_2026\reports
SETS_DIR=C:\Pranav\college\sih\SIH_MathWorks_2026\sets
```

- If you're running MongoDB locally, just make sure `mongod` is running (default port 27017) — the connection string above will work as-is.
- `REPORTS_DIR` / `SETS_DIR` are only needed for `npm run sync:reports`, which copies the MATLAB pipeline's output into this repo. The reports themselves are committed (`reports/`, `public/demo-sets/`), so the app runs without them — see §7.1 of the Developer Guide.

Upload one of the demo left/right pairs (they're in `public/demo-sets/`, or served at `/demo-sets/...`) and the app serves that set's real screening PDF and attention maps instead of the placeholder report, with the patient block rewritten from whatever you typed into the form. MATLAB is never invoked at runtime, so this works on Vercel.
- If you'd rather use MongoDB Atlas (needed for Vercel anyway, since Vercel can't reach `localhost`), grab your connection string from Atlas and paste it in instead — see step 2.

Generate a strong `JWT_SECRET` with:
```bash
openssl rand -base64 32
```

Then run:

```bash
npm run dev
```

Visit `http://localhost:3000`.

## 2. Set up MongoDB Atlas (required for Vercel deployment)

Vercel's servers can't reach a MongoDB running on your own laptop, so for production you need a
cloud MongoDB instance. The free tier of MongoDB Atlas is enough for this project:

1. Go to https://www.mongodb.com/cloud/atlas and create a free (M0) cluster.
2. Under **Database Access**, create a database user with a username/password.
3. Under **Network Access**, add `0.0.0.0/0` (allow access from anywhere) — simplest for a Vercel deployment.
4. Click **Connect → Drivers**, copy the connection string. It looks like:
   ```
   mongodb+srv://<username>:<password>@cluster0.xxxxx.mongodb.net/dr-data-collector?retryWrites=true&w=majority
   ```
5. Use that as your `MONGODB_URI` in both `.env.local` (for local testing against the cloud DB) and in Vercel's environment variables (below).

## 3. Deploy to Vercel

1. Push this project to a GitHub repo.
2. Go to https://vercel.com/new and import the repo.
3. Vercel auto-detects Next.js — no build settings need to change.
4. Before deploying, add these **Environment Variables** in the Vercel project settings:
   - `MONGODB_URI` → your Atlas connection string
   - `JWT_SECRET` → the same random string you generated earlier (or a new one for production)
   - Do **not** set `REPORTS_DIR` or `SETS_DIR` — those are Windows paths that don't exist on Vercel.
     Leave them unset and the app uses the `reports/` folder committed to the repo.
5. Click **Deploy**. That's it — the same codebase handles the frontend, the API routes, and talks
   straight to MongoDB Atlas.

### A note on the MATLAB pipeline

MATLAB can't run on Vercel, and nothing here tries to. The screening reports are generated ahead of
time on your machine and committed to the repo (`npm run sync:reports`); at runtime the app only
matches an upload to one of them, rewrites the patient block, and serves it. Re-run the pipeline →
re-run the sync → commit → redeploy.

`next.config.js` lists `reports/` under `outputFileTracingIncludes`. Next's build tracer can't see
files that are only read at runtime, so without that entry they'd be dropped from the serverless
bundle and every report would 404 in production.

## How the data flows

- `models/User.js` — `{ name, email, passwordHash }`
- `models/Submission.js` — `{ userId, status: 'draft'|'completed', currentStep, personalData: {...}, leftEyeImage, rightEyeImage, completedAt }`

Flow:
1. `POST /api/auth/signup` / `/api/auth/login` — sets an httpOnly JWT cookie.
2. Visiting `/submit` finds-or-creates a `draft` Submission for the logged-in user.
3. Each "Save & Continue" click sends a `PATCH /api/submissions/:id` with just that step's data —
   this is what makes progress persist between sessions, like a form autosave.
4. The final "Submit response" call sends `{ complete: true }`, which locks the document
   (`status: 'completed'`) so it can no longer be edited.
5. `/profile` lists every submission for the user (completed + any in-progress draft);
   `/profile/[id]` shows the full detail view including both eye images.
6. A user can only have **one active draft at a time** — the dashboard offers to resume it or
   discard it, but won't let you start a second one until the current one is completed or deleted.

## Notes on scale / "lite" by design

- Images are resized client-side (max width ~900px, JPEG quality ~0.72) before upload, which
  keeps each document small and avoids Vercel's serverless request body limits.
- If your dataset grows large and you outgrow storing images as base64 in MongoDB, the natural
  next step is swapping `leftEyeImage`/`rightEyeImage` for URLs pointing at S3/Cloudinary/Vercel
  Blob — the rest of the app doesn't need to change.
