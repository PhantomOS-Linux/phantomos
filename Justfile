image_name := env("BUILD_IMAGE_NAME", "")
image_tag := env("BUILD_IMAGE_TAG", "latest")
base_dir := env("BUILD_BASE_DIR", ".")
filesystem := env("BUILD_FILESYSTEM", "ext4")
container_runtime := env("CONTAINER_RUNTIME", `command -v podman >/dev/null 2>&1 && echo podman || echo docker`)

build-image IMAGE_NAME:
    echo "Building image ${image_name}:${image_tag} using ${container_runtime}"
    sudo ${container_runtime} build -t ${image_name}:${image_tag} -f Dockerfile .


rechunk-image IMAGE_NAME:
    #!/usr/bin/bash
    export CHUNKAH_CONFIG_STR="$(podman inspect "${image_name}")"
    podman run --rm "--mount=type=image,src=${image_name},dest=/chunkah" -e CHUNKAH_CONFIG_STR quay.io/coreos/chunkah build --label ostree.bootable=1 --compressed --max-layers 128 | \
        podman load | \
        sort -n | \
        head -n1 | \
        cut -d, -f2 | \
        cut -d: -f3 | \
        xargs -I{} podman tag {} "${image_name}"