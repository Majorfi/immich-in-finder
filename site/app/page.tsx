import FinderWindow from "@/components/FinderWindow";

const GITHUB = "https://github.com/Majorfi/immich-in-finder";

const VIEWS = [
  {
    name: "Albums",
    description:
      "Every album is a folder. Drop a file in to upload it, rename the folder to rename the album.",
  },
  {
    name: "Timeline",
    description:
      "Your whole library by capture date — Timeline/2024/03 — straight from Immich's metadata search.",
  },
  {
    name: "People",
    description:
      "Each named person from facial recognition becomes a folder of everything they appear in.",
  },
  {
    name: "Places",
    description:
      "Geocoded shots arranged as Country → City, derived from the EXIF your camera already wrote.",
  },
  {
    name: "Tags",
    description: "Your Immich tags, one folder each. 345 tags? 345 folders.",
  },
  {
    name: "Favorites",
    description: "The photos you starred, in one flat folder. No digging.",
  },
];

const WRITES = [
  {
    title: "Drop to upload",
    description:
      "Drag a photo into an album folder and it streams to your server — never buffered in memory, so multi-gigabyte videos are fine. Duplicates are detected by checksum and linked instead of re-uploaded.",
  },
  {
    title: "Delete means trash",
    description:
      "Deleting a photo moves it to the Immich trash, recoverable for 30 days. Nothing in the Finder can permanently destroy an asset.",
  },
  {
    title: "Rename & move",
    description:
      "Rename an album folder to rename the album. Drag a photo between album folders to re-link it server-side. Open windows refresh on their own.",
  },
];

const STEPS = [
  {
    step: "1",
    title: "Point it at your server",
    description: (
      <>
        Paste your server URL and an API key from{" "}
        <span className="kbd">Account Settings → API Keys</span>. The key lives
        in your macOS Keychain.
      </>
    ),
  },
  {
    step: "2",
    title: "Enable in Finder",
    description: (
      <>
        One click registers the File Provider domain. <em>Findich</em> appears
        in the sidebar under Locations — pick which folders show up.
      </>
    ),
  },
  {
    step: "3",
    title: "Browse like it's local",
    description: (
      <>
        Files appear instantly as placeholders with thumbnails. Open one and
        the original downloads; evict it to give the space back.
      </>
    ),
  },
];

const FAQ = [
  {
    q: "Does it copy my library to the Mac?",
    a: "No. It's a window, not a sync. Browsing shows lightweight placeholders; an original is only downloaded when you open it, and you can evict it afterwards. Your photos stay on your server.",
  },
  {
    q: "Can it destroy my photos?",
    a: "Deleting in the Finder maps to the Immich trash — recoverable for 30 days from the web UI. The extension has no code path that permanently deletes an asset.",
  },
  {
    q: "What do I need?",
    a: "macOS 13 or later, a running Immich server, and an API key. To build it yourself: Xcode, XcodeGen and an Apple Developer team (File Provider extensions require real code signing).",
  },
  {
    q: "Is this an official Immich app?",
    a: "No — it's an independent open-source companion that talks to Immich's public REST API. Immich is a trademark of its respective owners.",
  },
];

function GitHubIcon({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" fill="currentColor" className={className} aria-hidden>
      <path d="M8 0C3.58 0 0 3.58 0 8c0 3.54 2.29 6.53 5.47 7.59.4.07.55-.17.55-.38 0-.19-.01-.82-.01-1.49-2.01.37-2.53-.49-2.69-.94-.09-.23-.48-.94-.82-1.13-.28-.15-.68-.52-.01-.53.63-.01 1.08.58 1.23.82.72 1.21 1.87.87 2.33.66.07-.52.28-.87.51-1.07-1.78-.2-3.64-.89-3.64-3.95 0-.87.31-1.59.82-2.15-.08-.2-.36-1.02.08-2.12 0 0 .67-.21 2.2.82.64-.18 1.32-.27 2-.27s1.36.09 2 .27c1.53-1.04 2.2-.82 2.2-.82.44 1.1.16 1.92.08 2.12.51.56.82 1.27.82 2.15 0 3.07-1.87 3.75-3.65 3.95.29.25.54.73.54 1.48 0 1.07-.01 1.93-.01 2.2 0 .21.15.46.55.38A8.01 8.01 0 0 0 16 8c0-4.42-3.58-8-8-8z" />
    </svg>
  );
}

function FolderGlyph({ className }: { className?: string }) {
  return (
    <svg viewBox="0 0 16 16" className={className} fill="currentColor" aria-hidden>
      <path d="M1 4c0-.6.4-1 1-1h4l1.2 1.5H14c.6 0 1 .4 1 1V12c0 .6-.4 1-1 1H2c-.6 0-1-.4-1-1V4z" />
    </svg>
  );
}

export default function Home() {
  return (
    <main>
      {/* Nav */}
      <nav className="mx-auto flex max-w-5xl items-center justify-between px-6 py-5">
        <p className="flex items-center gap-2 text-[15px] font-semibold">
          <FolderGlyph className="h-4 w-4 text-[#1E8EFF]" />
          Findich
        </p>
        <a
          href={GITHUB}
          className="btn-ghost flex items-center gap-2 rounded-full px-4 py-1.5 text-[13px] font-medium"
        >
          <GitHubIcon className="h-4 w-4" />
          GitHub
        </a>
      </nav>

      {/* Hero */}
      <header className="glow px-6 pt-14 pb-10 text-center sm:pt-20">
        <p className="mx-auto mb-5 w-fit rounded-full border border-[--color-line-2] px-3.5 py-1 text-[12px] font-medium text-[--color-fog]">
          Free &amp; open source · macOS 13+
        </p>
        <h1 className="mx-auto max-w-3xl text-balance text-4xl font-bold tracking-tight sm:text-6xl">
          Your photo library has a place in the Finder.
        </h1>
        <p className="mx-auto mt-5 max-w-xl text-pretty text-[17px] leading-relaxed text-[--color-fog]">
          Findich mounts your self-hosted{" "}
          <a href="https://immich.app" className="font-medium text-[--color-accent] underline decoration-[--color-accent]/30 underline-offset-4 hover:decoration-[--color-accent]">
            Immich
          </a>{" "}
          library as a native location — like iCloud Drive, but it&apos;s your
          server, your photos, your rules.
        </p>
        <div className="mt-8 flex items-center justify-center gap-3">
          <a
            href={GITHUB}
            className="btn-primary flex items-center gap-2 rounded-full px-5 py-2.5 text-[14px] font-semibold"
          >
            <GitHubIcon className="h-4 w-4" />
            View on GitHub
          </a>
          <a href="#how" className="btn-ghost rounded-full px-5 py-2.5 text-[14px] font-medium">
            How it works
          </a>
        </div>

        <div className="mx-auto mt-14 max-w-3xl">
          <FinderWindow />
        </div>

        <p className="mt-8 text-[12px] font-medium tracking-wide text-[--color-fog-2]">
          FILE PROVIDER NATIVE · NO SYNC COPY · SWIFT 6 STRICT CONCURRENCY · 96 AUTOMATED TESTS
        </p>
      </header>

      {/* Views */}
      <section className="mx-auto max-w-5xl px-6 py-20">
        <h2 className="text-center text-3xl font-bold tracking-tight sm:text-4xl">
          Six doors into one library
        </h2>
        <p className="mx-auto mt-3 max-w-xl text-center text-[15px] text-[--color-fog]">
          Immich organizes photos by meaning, not by folders. This bridges the
          gap: every way Immich slices your library becomes a folder tree —
          and you choose which ones appear.
        </p>
        <div className="mt-10 grid gap-4 sm:grid-cols-2 lg:grid-cols-3">
          {VIEWS.map((view) => (
            <article key={view.name} className="card p-5">
              <h3 className="flex items-center gap-2 text-[15px] font-semibold">
                <FolderGlyph className="h-4 w-4 text-[#1E8EFF]" />
                {view.name}
              </h3>
              <p className="mt-2 text-[13.5px] leading-relaxed text-[--color-fog]">
                {view.description}
              </p>
            </article>
          ))}
        </div>
      </section>

      {/* On demand */}
      <section className="border-y border-[--color-line] bg-[--color-paper-2]">
        <div className="mx-auto grid max-w-5xl items-center gap-10 px-6 py-20 lg:grid-cols-2">
          <div>
            <h2 className="text-3xl font-bold tracking-tight sm:text-4xl">
              A window, not a copy.
            </h2>
            <p className="mt-4 text-[15px] leading-relaxed text-[--color-fog]">
              Browsing 8,836 photos doesn&apos;t mean storing 8,836 photos.
              Items appear as placeholders with real thumbnails and file sizes;
              the original travels only when you open it, and you can evict it
              the moment you&apos;re done.
            </p>
            <ul className="mt-6 space-y-3 text-[14px] text-[--color-fog]">
              {[
                "Thumbnails and metadata stream from your server, paginated — a 4,000-asset album opens fine",
                "Originals download on open, then behave like any local file",
                "Your library never leaves the server you run",
              ].map((line) => (
                <li key={line} className="flex gap-3">
                  <span className="mt-1.5 h-1.5 w-1.5 shrink-0 rounded-full bg-[--color-accent]" />
                  {line}
                </li>
              ))}
            </ul>
          </div>
          <div className="card p-6">
            <p className="font-mono text-[12.5px] leading-7 text-[--color-fog]">
              <span className="text-[--color-fog-2]"># what the Finder sees</span>
              <br />
              Findich/
              <br />
              ├── Albums/ <span className="text-[--color-fog-2]">drag in to upload</span>
              <br />
              ├── Timeline/2024/03/
              <br />
              ├── People/Alice/
              <br />
              ├── Places/France/Paris/
              <br />
              ├── Tags/roadtrip/
              <br />
              └── Favorites/
              <br />
              <br />
              <span className="text-[--color-fog-2]"># what your Mac stores</span>
              <br />
              <span className="font-medium text-[#1a8f3c]">placeholders — until you open one</span>
            </p>
          </div>
        </div>
      </section>

      {/* Writes */}
      <section className="mx-auto max-w-5xl px-6 py-20">
        <h2 className="text-center text-3xl font-bold tracking-tight sm:text-4xl">
          Writes go back home
        </h2>
        <p className="mx-auto mt-3 max-w-xl text-center text-[15px] text-[--color-fog]">
          It&apos;s not read-only. The gestures you already know map onto your
          server — carefully.
        </p>
        <div className="mt-10 grid gap-4 lg:grid-cols-3">
          {WRITES.map((write) => (
            <article key={write.title} className="card p-6">
              <h3 className="text-[15px] font-semibold">{write.title}</h3>
              <p className="mt-2 text-[13.5px] leading-relaxed text-[--color-fog]">
                {write.description}
              </p>
            </article>
          ))}
        </div>
      </section>

      {/* How it works */}
      <section id="how" className="border-y border-[--color-line] bg-[--color-paper-2]">
        <div className="mx-auto max-w-5xl px-6 py-20">
          <h2 className="text-center text-3xl font-bold tracking-tight sm:text-4xl">
            Running in three steps
          </h2>
          <div className="mt-10 grid gap-4 lg:grid-cols-3">
            {STEPS.map((item) => (
              <article key={item.step} className="card p-6">
                <p className="grid h-8 w-8 place-items-center rounded-full bg-[--color-accent-soft] text-[14px] font-bold text-[--color-accent]">
                  {item.step}
                </p>
                <h3 className="mt-4 text-[15px] font-semibold">{item.title}</h3>
                <p className="mt-2 text-[13.5px] leading-relaxed text-[--color-fog]">
                  {item.description}
                </p>
              </article>
            ))}
          </div>
          <p className="mt-8 text-center text-[13px] text-[--color-fog-2]">
            Built from source today — packaged releases are on the roadmap.
          </p>
        </div>
      </section>

      {/* FAQ */}
      <section className="mx-auto max-w-3xl px-6 py-20">
        <h2 className="text-center text-3xl font-bold tracking-tight sm:text-4xl">
          Fair questions
        </h2>
        <div className="mt-10 space-y-4">
          {FAQ.map((item) => (
            <details key={item.q} className="card group p-5 open:border-[--color-line-2]">
              <summary className="cursor-pointer list-none text-[15px] font-semibold marker:hidden">
                <span className="flex items-center justify-between gap-4">
                  {item.q}
                  <svg
                    viewBox="0 0 16 16"
                    className="h-4 w-4 shrink-0 text-black/35 transition-transform group-open:rotate-45"
                    fill="none"
                    stroke="currentColor"
                    strokeWidth="1.5"
                    aria-hidden
                  >
                    <path d="M8 3v10M3 8h10" strokeLinecap="round" />
                  </svg>
                </span>
              </summary>
              <p className="mt-3 text-[14px] leading-relaxed text-[--color-fog]">
                {item.a}
              </p>
            </details>
          ))}
        </div>
      </section>

      {/* Final CTA */}
      <section className="glow px-6 pb-24 pt-8 text-center">
        <h2 className="mx-auto max-w-xl text-balance text-3xl font-bold tracking-tight sm:text-4xl">
          Your photos. Your server. Your Finder.
        </h2>
        <div className="mt-7 flex items-center justify-center gap-3">
          <a
            href={GITHUB}
            className="btn-primary flex items-center gap-2 rounded-full px-5 py-2.5 text-[14px] font-semibold"
          >
            <GitHubIcon className="h-4 w-4" />
            Get it on GitHub
          </a>
        </div>
      </section>

      {/* Footer */}
      <footer className="border-t border-[--color-line]">
        <div className="mx-auto flex max-w-5xl flex-col items-center justify-between gap-3 px-6 py-8 text-[12.5px] text-[--color-fog] sm:flex-row">
          <p>
            Built by{" "}
            <a href="https://quub.app" className="font-medium text-[--color-ink] hover:text-[--color-accent]">
              Quub
            </a>
            . Open source, MIT-spirited.
          </p>
          <p>
            Not affiliated with{" "}
            <a href="https://immich.app" className="font-medium text-[--color-ink] hover:text-[--color-accent]">
              Immich
            </a>
            .
          </p>
        </div>
      </footer>
    </main>
  );
}
