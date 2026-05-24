# ==========================================
# STAGE 1: Compilation Environment Setup
# ==========================================
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 AS torch-builder

ENV DEBIAN_FRONTEND=noninteractive

# Install native compiler toolchain and audio/image decoding dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    curl \
    ca-certificates \
    python3-dev \
    python3-pip \
    libjpeg-dev \
    libpng-dev \
    libtiff-dev \
    libsox-dev \
    libsndfile1-dev \
    libwebp-dev

# Install python build dependencies
RUN pip3 install --no-cache-dir --upgrade pip setuptools wheel typing_extensions ninja

WORKDIR /remote_build

# ------------------------------------------
# CRITICAL: Keep AVX1, Strip AVX2
# ------------------------------------------
ENV USE_AVX=ON
ENV ATEN_CPU_CAPABILITY=avx

# Explicitly isolate and destroy internal AVX2 capability discovery paths
ENV USE_AVX2=OFF
ENV C_HAS_AVX2_2=OFF
ENV CXX_HAS_AVX2_2=OFF
ENV CAFFE2_COMPILER_SUPPORTS_AVX512_EXTENSIONS=OFF

# Tell compiler to allow AVX, but explicitly deny AVX2 instructions
ENV CMAKE_C_FLAGS="-mavx -mno-avx2 -mno-avx512f -mno-avx512pf -mno-avx512er -mno-avx512cd"
ENV CMAKE_CXX_FLAGS="-mavx -mno-avx2 -mno-avx512f -mno-avx512pf -mno-avx512er -mno-avx512cd"
ENV CFLAGS="-mavx -mno-avx2 -mno-avx512f"
ENV CXXFLAGS="-mavx -mno-avx2 -mno-avx512f"

# ------------------------------------------
# CRITICAL: Activate CUDA Frameworks
# ------------------------------------------
ENV FORCE_CPU=0
ENV NO_CUDA=0
ENV USE_CUDA=1
ENV USE_CUDNN=1

# Select the target GPU Architectures to compile for (e.g., 7.5=T4/RTX20xx, 8.0=A100, 8.6=RTX30xx/A40, 8.9=RTX40xx/L4, 9.0=H100)
# Adjust TORCH_CUDA_ARCH_LIST to match your exact deployment GPU to reduce compile time
ENV TORCH_CUDA_ARCH_LIST="7.5;8.6"

# Memory reduction
ENV MAX_JOBS=4
ENV BUILD_TEST=0
ENV USE_DISTRIBUTED=0
# ENV USE_MKLDNN=0
# ENV USE_QNNPACK=0
ENV REL_WITH_DEB_INFO=0
ENV DEBUG=0


# ==========================================
# STEP 1: Build PyTorch Core (v2.5.1)
# ==========================================
ENV PYTORCH_BUILD_VERSION=2.4.0
ENV PYTORCH_BUILD_NUMBER=1
RUN git clone --recursive --branch v2.4.0 https://github.com/pytorch/pytorch.git \
    && cd pytorch \
    && pip install -r requirements.txt \
    && python3 setup.py bdist_wheel \
    && pip install dist/torch-*.whl \
    && mkdir -p /wheels && cp dist/*.whl /wheels/ \
    && cd .. && rm -rf pytorch

# ==========================================
# STEP 2: Build TorchVision (v0.20.1)
# ==========================================
ENV BUILD_VERSION=0.17.0
RUN git clone --branch v0.17.0 https://github.com/pytorch/vision.git \
    && cd vision \
    && python3 setup.py bdist_wheel \
    && pip install dist/torchvision-*.whl \
    && cp dist/*.whl /wheels/ \
    && cd .. && rm -rf vision

# ==========================================
# STEP 3: Build TorchAudio (v2.5.1)
# ==========================================
ENV BUILD_VERSION=2.4.0
RUN git clone --recursive --branch v2.4.0 https://github.com/pytorch/audio.git \
    && cd audio \
    && python3 setup.py bdist_wheel \
    && cp dist/*.whl /wheels/ \
    && cd .. && rm -rf audio


# --- STAGE 2: Build kornia-rs
# 1. Build Stage (Pre-packaged with Rust and Cargo)
FROM python:3.10-slim AS kornia

# Install system build dependencies
RUN apt-get update && apt-get install -y --no-install-recommends \
    build-essential \
    cmake \
    git \
    pkg-config \
    libssl-dev \
    curl

# Install specific Python dependencies required to build Kornia
RUN pip3 install setuptools wheel numpy

# Create a build directory
COPY --from=torch-builder /wheels/ /wheels/
WORKDIR /wheels
RUN find /wheels -name '*.whl' -type f -exec pip3 install --find-links /wheels {} +

# Install Rust and Cargo
ENV RUSTUP_HOME=/usr/local/rustup \
    CARGO_HOME=/usr/local/cargo \
    PATH=/usr/local/cargo/bin:$PATH
RUN curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --default-toolchain stable --profile minimal

# Force Rust to use AVX while explicitly disabling AVX2 and AVX512
ENV RUSTFLAGS="-C target-feature=+avx,-avx2,-avx512f,-avx512cd,-avx512er,-avx512pf,-avx512bw,-avx512dq,-avx512vl"

# Download and build Kornia 0.7.1 & kornia-rs
RUN pip3 wheel --no-cache-dir --no-deps kornia_rs==0.1.0 kornia==0.7.1


# --- STAGE 3: Your ComfyUI Image ---
FROM nvidia/cuda:12.1.0-devel-ubuntu22.04 AS comfyui

# Accept IDs from build-args
ARG USER_ID=1000
ARG GROUP_ID=1000

ENV DEBIAN_FRONTEND=noninteractive
RUN apt-get update && apt-get install -y software-properties-common && \
    add-apt-repository ppa:deadsnakes/ppa && \
    apt-get update && apt-get install -y --no-install-recommends \
    python3 python3-pip python3-venv git curl ca-certificates libgomp1 libpng16-16 libjpeg-turbo8 \
    libxcb-randr0-dev libxcb-xtest0-dev libxcb-xinerama0-dev libxcb-shape0-dev libxcb-xkb-dev

# Create group and user matching your host IDs
RUN groupadd -g ${GROUP_ID} comfy && \
    useradd -l -u ${USER_ID} -g comfy -m comfy

RUN chmod u+s "$(which pip3)"

# Copy the built wheels from the wheel-builder stage
COPY --from=torch-builder /wheels/ /wheels/
COPY --from=kornia /wheels/*.whl /wheels/

# Install the copied wheels
RUN find /wheels -name '*.whl' -type f -exec pip3 install --find-links /wheels {} +

# Get ComfyUI
WORKDIR /home/comfy
RUN git clone --branch v0.22.1 'https://github.com/comfy-org/ComfyUI'
WORKDIR /home/comfy/ComfyUI
RUN pip3 install -r requirements.txt
RUN pip3 install -r manager_requirements.txt

RUN apt-get install -y libgl1
RUN chown -R comfy:comfy /home/comfy/ComfyUI
RUN chmod u+s /usr/lib/python3
USER comfy

EXPOSE 8188
CMD ["python3", "main.py", "--enable-manager", "--listen", "0.0.0.0"]
