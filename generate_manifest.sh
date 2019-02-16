#!/bin/sh
# Generate .manifest.tmpl

docker_image=${1}
shift
archs_filtered=${@}

cat << EOF > ./.manifest.tmpl
image: phasecorex/${docker_image}:{{#if build.tag}}{{trimPrefix build.tag "v"}}{{else}}latest{{/if}}
{{#if build.tags}}
tags:
{{#each build.tags}}
  - {{this}}
{{/each}}
{{/if}}
manifests:
EOF

for arch in ${archs_filtered}; do
    case ${arch} in
        amd64   ) tag_arch="amd64"; os="linux"; variant="" ;;
        arm32v5 ) tag_arch="arm"; os="linux"; variant="v5" ;;
        arm32v6 ) tag_arch="arm"; os="linux"; variant="v6" ;;
        arm32v7 ) tag_arch="arm"; os="linux"; variant="v7" ;;
        arm64v8 ) tag_arch="arm64"; os="linux"; variant="v8" ;;
        *)
            echo ERROR: Unknown tag arch.
            exit 1
    esac
    cat << EOF >> ./.manifest.tmpl
  -
    image: phasecorex/${docker_image}:{{#if build.tag}}{{trimPrefix build.tag "v"}}-{{/if}}${arch}
    platform:
      architecture: ${tag_arch}
      os: ${os}
EOF

    if [[ ! -z ${variant} ]]; then
        cat << EOF >> ./.manifest.tmpl
      variant: ${variant}
EOF
    fi
done
