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
    export CHUNKAH_CONFIG_STR="$(podman inspect "{{IMAGE_NAME}}")"
    sudo podman run --rm \
        --mount=type=image,src="{{IMAGE_NAME}}",target=/chunkah \
        -e CHUNKAH_CONFIG_STR \
        quay.io/coreos/chunkah build --label containers.bootc=1 --label ostree.bootable=1 --compressed --max-layers 128 | \
        sudo podman load | \
        sort -n | \
        head -n1 | \
        cut -d, -f2 | \
        cut -d: -f3 | \
        xargs -I{} sudo podman tag {} "{{IMAGE_NAME}}:{{image_tag}}"
