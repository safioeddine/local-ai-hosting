#!/bin/bash
# local-ai-hosting — Qwen3.6-35B-A3B on Kaggle (2x Tesla T4)
# The proven recipe (tested October 2026): pinned llama.cpp 1268eda + CUDA patch,
# 64K context, tensor-split over both GPUs, Cloudflare quick tunnel at the end.
# Run inside a Kaggle notebook cell:  !bash setup-qwen36-35b.sh
# WARNING: the tunnel URL printed at the end has NO authentication.
# Treat it like a password — never share it publicly, never commit it anywhere.
set -u
M=/root/models
mkdir -p "$M"

echo "=== [1/4] model downloads (cmp-nct/Qwen3.6-35B-A3B-GGUF) ==="
cd "$M"
# main model: 22,134,528,992 bytes — mmproj (vision): 739,699,424 bytes
[ -f Qwen3.6-35B-A3B-UD-Q4_K_M.gguf ] || wget -c https://huggingface.co/cmp-nct/Qwen3.6-35B-A3B-GGUF/resolve/main/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf
[ -f mmproj-Qwen3.6-35B-A3B-Q8_0.gguf ] || wget -c https://huggingface.co/cmp-nct/Qwen3.6-35B-A3B-GGUF/resolve/main/mmproj-Qwen3.6-35B-A3B-Q8_0.gguf
ls -la "$M"
[ "$(stat -c%s Qwen3.6-35B-A3B-UD-Q4_K_M.gguf)" -eq 22134528992 ] || { echo "FATAL: main model size wrong"; exit 1; }
[ "$(stat -c%s mmproj-Qwen3.6-35B-A3B-Q8_0.gguf)" -eq 739699424 ] || { echo "FATAL: mmproj size wrong"; exit 1; }
echo "download sizes OK"

echo "=== [2/4] llama.cpp build (pinned 1268eda — do NOT use newer master) ==="
if [ ! -x /root/llama.cpp/build/bin/llama-server ]; then
  cd /root
  [ -d llama.cpp ] || git clone https://github.com/ggml-org/llama.cpp.git
  cd llama.cpp
  git checkout 1268eda
  # Kaggle's /usr/local/cuda is read-only: link libcuda.so directly instead of CUDA::cuda_driver
  python3 - << 'EOF'
p = 'ggml/src/ggml-cuda/CMakeLists.txt'
s = open(p).read()
s2 = s.replace('CUDA::cuda_driver', '/usr/local/nvidia/lib64/libcuda.so')
assert s2 != s, 'patch did not apply'
open(p, 'w').write(s2)
print('patched OK')
EOF
  cmake -B build -DGGML_CUDA=ON -DCMAKE_BUILD_TYPE=Release
  # -j2 ONLY: unlimited parallelism OOM-killed a Kaggle VM (nvcc jobs eat GBs each)
  cmake --build build -j2 --target llama-server
else echo "llama-server exists, skip build"; fi
/root/llama.cpp/build/bin/llama-server --version

echo "=== [3/4] launch server (2xT4 tensor-split, 64K context) ==="
pkill -x llama-server 2>/dev/null || true; sleep 2
LD_LIBRARY_PATH=/usr/local/nvidia/lib64:${LD_LIBRARY_PATH} \
nohup /root/llama.cpp/build/bin/llama-server \
  -m "$M/Qwen3.6-35B-A3B-UD-Q4_K_M.gguf" \
  --mmproj "$M/mmproj-Qwen3.6-35B-A3B-Q8_0.gguf" \
  -c 65536 -ngl 99 --tensor-split 1,1 \
  --host 127.0.0.1 --port 8080 \
  > /tmp/llama.log 2>&1 &
echo "waiting for /health ..."
for i in $(seq 1 60); do
  if curl -s --max-time 5 http://127.0.0.1:8080/health | grep -q '"status":"ok"'; then echo "HEALTHY after ~$((i*5))s"; break; fi
  sleep 5
  if [ "$i" -eq 60 ]; then echo "FATAL: server never healthy"; tail -30 /tmp/llama.log; exit 1; fi
done
nvidia-smi --query-gpu=index,memory.used,memory.total --format=csv

echo "=== [4/4] Cloudflare quick tunnel ==="
if ! command -v cloudflared > /dev/null; then
  wget -q https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-amd64 -O /usr/local/bin/cloudflared
  chmod +x /usr/local/bin/cloudflared
fi
pkill -f "cloudflared tunnel" 2>/dev/null || true; sleep 2
nohup cloudflared tunnel --no-autoupdate --protocol http2 --edge-ip-version 4 \
  --url http://127.0.0.1:8080 --http-host-header localhost:8080 \
  > /tmp/cf.log 2>&1 &
sleep 30
URL=$(grep -o 'https://[a-z0-9-]*\.trycloudflare\.com' /tmp/cf.log | head -1)
echo "TUNNEL_URL: $URL"
echo "Hermes endpoint: ${URL}/v1   (model name: qwen3.6, API key: any value)"
echo "=== DONE — keep the tunnel URL private ==="
