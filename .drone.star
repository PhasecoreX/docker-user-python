def main(ctx):
    # image_name = "ubuntu"
    # all_image_tags_arches = [
    #     {
    #         "tags": ["18.04", "bionic", "latest"],
    #         "arches": ["amd64", "arm32v7", "arm64v8"],
    #         "base_tag": "base_tag_test",
    #         "dockerfile": "debian",
    #     },
    #     {
    #         "tags": ["20.04", "focal", "devel"],
    #         "arches": ["amd64", "arm32v7", "arm64v8"],
    #         "dockerfile": "debian",
    #     },
    #     {
    #         "tags": ["16.04", "xenial"],
    #         "arches": ["amd64", "arm32v7", "arm64v8"],
    #         "dockerfile": "debian",
    #     },
    # ]
    # downstream_builds = ["PhasecoreX/docker-red-discordbot", "nice", "lol"]
    image_name = "python"
    all_image_tags_arches = [{'tags': ['2.7-alpine', '2-alpine'], 'arches': ['arm64v8', 'arm32v7', 'arm32v6', 'amd64'], 'dockerfile': 'alpine'}, {'tags': ['2.7-slim', '2-slim'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'dockerfile': 'debian'}, {'tags': ['2.7', '2'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'base_tag': '2-buster', 'dockerfile': 'debian'}, {'tags': ['3.5-alpine'], 'arches': ['arm64v8', 'arm32v7', 'arm32v6', 'amd64'], 'dockerfile': 'alpine'}, {'tags': ['3.5-slim'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'dockerfile': 'debian'}, {'tags': ['3.5'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'base_tag': '3.5-buster', 'dockerfile': 'debian'}, {'tags': ['3.6-alpine'], 'arches': ['arm64v8', 'arm32v7', 'arm32v6', 'amd64'], 'dockerfile': 'alpine'}, {'tags': ['3.6-slim'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'dockerfile': 'debian'}, {'tags': ['3.6'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'base_tag': '3.6-buster', 'dockerfile': 'debian'}, {'tags': ['3.7-alpine'], 'arches': ['arm64v8', 'arm32v7', 'arm32v6', 'amd64'], 'dockerfile': 'alpine'}, {'tags': ['3.7-slim'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'dockerfile': 'debian'}, {'tags': ['3.7'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'base_tag': '3.7-buster', 'dockerfile': 'debian'}, {'tags': ['3.8-alpine', '3-alpine'], 'arches': ['arm64v8', 'arm32v7', 'arm32v6', 'amd64'], 'dockerfile': 'alpine'}, {'tags': ['3.8-slim', '3-slim'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'dockerfile': 'debian'}, {'tags': ['latest', '3.8', '3'], 'arches': ['arm64v8', 'arm32v7', 'arm32v5', 'amd64'], 'base_tag': 'buster', 'dockerfile': 'debian'}]
    downstream_builds = None

    return generate(image_name, all_image_tags_arches, downstream_builds)


def generate(image_name, all_image_tags_arches, downstream_builds):
    depends_on_manifests = []
    for image_tags_arches in all_image_tags_arches:
        depends_on_manifests.append(
            _get_pipeline_manifest_name(image_name, image_tags_arches["tags"])
        )

    result = (
        gather_all_pipeline_build(image_name, all_image_tags_arches)
        + gather_all_pipeline_manifest(image_name, all_image_tags_arches)
        + [pipeline_notify(depends_on_manifests)]
    )
    if downstream_builds:
        result.append(
            pipeline_downstream_build(depends_on_manifests, downstream_builds)
        )
    return result


def gather_all_pipeline_build(image_name, all_image_tags_arches):
    # One for each architecture
    result = []
    all_arches = {}
    for image_tags_arches in all_image_tags_arches:
        for image_arch in image_tags_arches["arches"]:
            arch_dict_value = {
                "tags": image_tags_arches["tags"],
                "dockerfile": image_tags_arches["dockerfile"],
                "base_tag": (
                    image_tags_arches["base_tag"]
                    if "base_tag" in image_tags_arches
                    else None
                ),
            }
            if image_arch in all_arches:
                all_arches[image_arch].append(arch_dict_value)
            else:
                all_arches[image_arch] = [arch_dict_value]
    for image_arch, arch_infos in all_arches.items():
        # [{"base_tag": "18.04", "dockerfile": "debian", "tags": ["18.04", "bionic", "latest"]},...]
        # pipeline_build(image_name, "amd64", ^^^)
        result.append(pipeline_build(image_name, image_arch, arch_infos))
    return result


def gather_all_pipeline_manifest(image_name, all_image_tags_arches):
    # One for each tag set
    result = []
    for image_tags_arches in all_image_tags_arches:
        # pipeline_manifest(image_name, ["18.04", "bionic", "latest"], ["amd64", "arm32v7", "arm64v8"])
        result.append(
            pipeline_manifest(
                image_name, image_tags_arches["tags"], image_tags_arches["arches"]
            )
        )
    return result


def pipeline_build(image_name, image_arch, arch_infos):
    steps = [get_build_prepare_step(image_name, image_arch)]
    for info in arch_infos:
        steps.append(
            get_build_step(
                image_name,
                image_arch,
                info["tags"],
                info["dockerfile"],
                info["base_tag"],
            )
        )
    return {
        "kind": "pipeline",
        "name": _get_pipeline_build_name(image_name, image_arch),
        "trigger": _get_trigger(),
        "platform": {
            "os": "linux",
            "arch": _get_drone_arch(image_arch)[0],
            # "variant": _get_drone_arch(image_arch)[1],
        },
        "steps": steps,
    }


def pipeline_manifest(image_name, image_tags, image_arches):
    image_tag = _correct_image_tag(image_tags)
    return {
        "kind": "pipeline",
        "name": _get_pipeline_manifest_name(image_name, image_tags),
        "trigger": _get_trigger(),
        "depends_on": ["build-user-" + image_name + "-" + s for s in image_arches],
        "steps": [get_manifest_generate_step(image_name, image_tag, image_arches)]
        + [get_manifest_step(image_name, image_tag) for image_tag in image_tags],
    }


def pipeline_notify(depends_on):
    return {
        "kind": "pipeline",
        "name": "notify",
        "trigger": _get_trigger(any_status=True),
        "clone": {"disable": True},
        "depends_on": depends_on,
        "steps": [
            {
                "name": "send-discord-notification",
                "image": "appleboy/drone-discord",
                "allow_failure": True,
                "settings": {
                    "webhook_id": {"from_secret": "discord_webhook_id"},
                    "webhook_token": {"from_secret": "discord_webhook_token"},
                    "message": "{{#success build.status}}**{{repo.name}}**: Build #{{build.number}} on {{build.branch}} branch succeeded!{{else}}**{{repo.name}}**: Build #{{build.number}} on {{build.branch}} branch failed. Fix me please. {{build.link}}{{/success}}",
                },
            }
        ],
    }


def pipeline_downstream_build(depends_on, downstream_images):
    return {
        "kind": "pipeline",
        "name": "downstream-build",
        "trigger": _get_trigger(),
        "clone": {"disable": True},
        "depends_on": depends_on,
        "steps": [
            {
                "name": "trigger",
                "image": "plugins/downstream",
                "settings": {
                    "server": "https://cloud.drone.io",
                    "token": {"from_secret": "drone_token"},
                    "fork": True,
                    "last_successful": True,
                    "repositories": downstream_images,
                },
            }
        ],
    }


def get_build_prepare_step(image_name, image_arch):
    return {
        "name": "prepare-build-user-{image_name}-{image_arch}".format(
            image_name=image_name, image_arch=image_arch
        ),
        "image": "docker:git",
        "commands": [
            "git submodule update --init --recursive",
            'echo "Pulled latest template files:"',
            "ls -1 docker-user-image",
        ],
    }


def get_build_step(image_name, image_arch, image_tags, dockerfile, image_base_tag):
    image_tag = _correct_image_tag(image_tags)
    if not image_base_tag:
        image_base_tag = image_tag
    return {
        "name": "build-user-{image_name}-{image_tag}-{image_arch}".format(
            image_name=image_name, image_tag=image_tag, image_arch=image_arch
        ),
        "image": "plugins/docker",
        "settings": {
            "username": {"from_secret": "docker_username"},
            "password": {"from_secret": "docker_password"},
            "create_repository": True,
            "cache_from": "phasecorex/user-{name}:{image_tag}-{arch}".format(
                name=image_name, image_tag=image_tag, arch=image_arch
            ),
            "repo": "phasecorex/user-{name}-test".format(name=image_name),
            "tags": [s + "-" + image_arch for s in image_tags],
            "context": "docker-user-image",
            "dockerfile": "docker-user-image/Dockerfile.{dockerfile}".format(
                dockerfile=dockerfile + (".qemu" if image_arch != "amd64" else "")
            ),
            "build_args": [
                "QEMU_ARCH={qemu_arch}".format(qemu_arch=_get_qemu_arch(image_arch)),
                "ARCH_IMG={arch}/{name}:{tag}".format(
                    arch=image_arch, name=image_name, tag=image_base_tag
                ),
                "ARCH={arch}".format(arch=image_arch),
            ],
        },
    }


def get_manifest_generate_step(image_name, image_tag, image_arches):
    image_arches_string = " ".join(image_arches)
    return {
        "name": "prepare-manifest-user-{image_name}-{image_tag}".format(
            image_name=image_name, image_tag=image_tag
        ),
        "image": "docker:git",
        "commands": [
            "./generate_manifest.sh user-{image_name} {image_arches_string}".format(
                image_name=image_name, image_arches_string=image_arches_string
            ),
            'echo "Generated docker manifest template:"',
            "cat manifest.tmpl",
        ],
    }


def get_manifest_step(image_name, image_tag):
    return {
        "name": "manifest-user-{image_name}-{image_tag}".format(
            image_name=image_name, image_tag=image_tag
        ),
        "image": "plugins/manifest",
        "environment": {"DRONE_TAG": "{image_tag}".format(image_tag=image_tag)},
        "settings": {
            "username": {"from_secret": "docker_username"},
            "password": {"from_secret": "docker_password"},
            "spec": "manifest.tmpl",
        },
    }


def _get_drone_arch(image_arch):
    if image_arch == "amd64":
        return "amd64", ""
    if image_arch.startswith("arm32"):
        return "arm", image_arch[5:]
    if image_arch.startswith("arm64"):
        return "arm64", "v8"
    return "ERROR_GET_DRONE_ARCH_" + image_arch


def _get_qemu_arch(image_arch):
    if image_arch == "amd64":
        return "x86_64"
    if image_arch.startswith("arm32"):
        return "arm"
    if image_arch.startswith("arm64"):
        return "aarch64"
    return "ERROR_GET_QEMU_ARCH_" + image_arch


def _get_trigger(any_status=False):
    result = {"branch": ["master"], "event": ["push"]}
    if any_status:
        result["status"] = ["success", "failure"]
    return result


def _correct_image_tag(image_tags):
    image_tag = image_tags[0]
    if image_tag == "latest" and len(image_tags) > 1:
        image_tag = image_tags[1]
    return image_tag


def _get_pipeline_build_name(image_name, image_arch):
    return "build-user-{image_name}-{image_arch}".format(
        image_name=image_name, image_arch=image_arch
    )


def _get_pipeline_manifest_name(image_name, image_tags):
    return "manifest-user-{image_name}-{image_tag}".format(
        image_name=image_name, image_tag=_correct_image_tag(image_tags)
    )
