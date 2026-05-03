image_tag := env("IMAGE_TAG", "latest")
base_dir := env("BASE_DIR", ".")
filesystem := env("FILESYSTEM", "ext4")
container_runtime := env("CONTAINER_RUNTIME", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)

build-image IMAGE_NAME:
    echo "Building image {{IMAGE_NAME}}:{{image_tag}} using {{container_runtime}}"
    sudo {{container_runtime}} build -t "{{IMAGE_NAME}}:{{image_tag}}" -f Containerfile .

rechunk-image IMAGE_NAME:
    #!/usr/bin/bash
    set -euo pipefail
    export CHUNKAH_CONFIG_STR="$(podman inspect --format json "{{IMAGE_NAME}}")"
    podman run --rm "--mount=type=image,src={{IMAGE_NAME}},dest=/chunkah" -e CHUNKAH_CONFIG_STR quay.io/coreos/chunkah build --label ostree.bootable=1 --compressed --max-layers 128 | \
        podman load | \
        sort -n | \
        head -n1 | \
        cut -d, -f2 | \
        cut -d: -f3 | \
        xargs -I{} podman tag {} "{{IMAGE_NAME}}"
