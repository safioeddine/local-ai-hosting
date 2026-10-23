# local-ai-hosting

I wanted to run a strong open AI model for my own agents (I use Hermes every day)
without paying for an API. Kaggle gives you 2 free Tesla T4 GPUs, so I turned a
Kaggle notebook into my personal AI server.

This repo is the setup that actually worked, with the real numbers I measured —
not a tutorial I copied from somewhere.

## How it works

1. A Kaggle notebook (GPU T4 x2, internet on) downloads a GGUF model.
2. `llama.cpp` is built from source and serves the model on both GPUs.
3. A Cloudflare quick tunnel exposes the server as an OpenAI-compatible
   endpoint (`/v1`), so any app or agent can connect to it.
4. I paste the tunnel URL into Hermes as the endpoint, and my agent runs on
   a 35B model hosted by... me.

## The setup that worked (October 2026)

Model: **Qwen3.6-35B-A3B** (UD-Q4_K_M) + vision projector (mmproj Q8_0)

| Test | Result |
|---|---|
| GPU offload | 100% — both T4s used (~83% / ~73% while answering) |
| Speed | ~57 tokens/s |
| Context | 64K, verified with a hidden-needle test at 61,204 tokens |
| Vision | Answered correctly on a test image |
| Coding test | Correct answer, clean stop |

Run it with one file: [`setup-qwen36-35b.sh`](setup-qwen36-35b.sh) — it downloads
the model, builds llama.cpp, starts the server and prints the tunnel URL.

## Lessons that cost me time (so they don't cost you)

- **Pin llama.cpp to commit `1268eda`.** A newer master failed to link on
  Kaggle's image (it needs a newer glibc than the image has).
- **Build with `-j2`, never unlimited.** A full-parallel build ate all the RAM
  and Kaggle killed/restarted the VM mid-build.
- The CUDA patch in the script is not optional: on Kaggle `/usr/local/cuda`
  is read-only, so the build has to link `libcuda.so` directly.
- `LD_LIBRARY_PATH` is needed when *running* the server too, not just building.

## Honest limits

- Kaggle sessions end after ~12 hours and the free GPU quota is ~30 h/week.
  This is a personal server, not a 24/7 production one.
- The tunnel URL changes every time the tunnel restarts.
- ⚠️ **The endpoint has no authentication.** The tunnel URL works like a
  password — never share it publicly, and never commit it to a repo.

## What's next

- Test the newer Qwen3.8-27B on the same recipe (build started, waiting for
  GPU quota to reset).
- Store the model files as a private Kaggle model so a rebuild doesn't
  re-download ~23 GB every time.

---

Built and tested by Safi Eddine — DUT IDS student, EST Fkih Ben Salah, Morocco.
Part of the projects I'm doing during my DUT (2026–2028).
