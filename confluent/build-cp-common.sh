#!/usr/bin/env bash
set -e
SCRIPT_DIR=$(dirname $(readlink -f ${BASH_SOURCE[0]}))
BUILD_DIR=${SCRIPT_DIR}/build

CONFLUENT_GIT_REPO=${CONFLUENT_GIT_REPO:-https://github.com/confluentinc/common.git}

function usage () {
    echo "$0: $1" >&2
    echo
    echo "Usage: BUILD=7.0.0 MAVEN_REPO_ID=confluent-snapshots::default::\${MAVEN_URL} SHOULD_PUBLISH=true $0"
    echo
    return 1
}

function resolve_confluent_main_version () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        local maven_version="$(cat pom.xml | head -n50 | grep "<version>" | sed 's/.*>\([^<]*\)<.*/\1/')"
        echo ${maven_version} | sed 's/^\([0-9]\+\.[0-9]\+\.[0-9]\+\).*$/\1/'
    )
}

function resolve_confluent_version () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "$(resolve_confluent_main_version ${confluent_git_refspec})-SNAPSHOT"
}

function resolve_confluent_kafka_version () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "$(resolve_confluent_main_version ${confluent_git_refspec})-ccs-SNAPSHOT"
}

function replace_value_in_pom () {
    local file=${1:?"Missing file as first parameter!"}
    local attribute=${2:?"Missing attribute as second parameter!"}
    local new_value=${3:?"Missing new value as third parameter!"}
    sed -i "s/<${attribute}>[^<]*<\/${attribute}>/<${attribute}>${new_value}<\/${attribute}>/" ${file}
}

function resolve_build_dir () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "${BUILD_DIR}/cp-common-${confluent_git_refspec//\//-}"
}

function cleanup_confluent_build () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Removing Confluent build dir for ${confluent_git_refspec}"
    if [ -d "$(resolve_build_dir ${confluent_git_refspec})" ]; then
        rm -rf "$(resolve_build_dir ${confluent_git_refspec})"
    fi
}

function clone_confluent () {  
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Cloning Confluent ${confluent_git_refspec}"
    (
        mkdir -p "$(resolve_build_dir ${confluent_git_refspec})"
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        git init
        git remote add origin ${CONFLUENT_GIT_REPO}
        git fetch --depth 1 origin ${confluent_git_refspec}
        git reset --hard FETCH_HEAD
    )
}

function build_confluent () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Building Confluent ${confluent_git_refspec}"
    local version=$(resolve_confluent_version ${confluent_git_refspec})
    local kafka_version=$(resolve_confluent_kafka_version ${confluent_git_refspec})
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        if [ -d "assembly-plugin-boilerplate" ]; then
            cd assembly-plugin-boilerplate
            mvn versions:set -DnewVersion=${version}
        fi
    )
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        if [ -d "build-tools" ]; then
            cd build-tools
            mvn versions:set -DnewVersion=${version}
        fi
    )
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        for pom in $(find . -name pom.xml); do
            replace_value_in_pom ${pom} io.confluent.common.version ${version}
            replace_value_in_pom ${pom} kafka.version ${kafka_version}
            replace_value_in_pom ${pom} confluent.version.range ${kafka_version}
            replace_value_in_pom ${pom} installed.pom.file pom.xml
        done
        mvn versions:set -DnewVersion=${version}
        mvn versions:update-child-modules
        git apply ${SCRIPT_DIR}/cp-common.manifest.patch
        mvn install --update-snapshots \
            -DgitRepo=${CONFLUENT_GIT_REPO} -DgitRef=${confluent_git_refspec} -DbuildTimestamp=$(date -Iseconds --utc)
    )
}

function publish_confluent () {
    local confluent_git_refspec=${1:?"Missing Confluent Git refspec as first parameter!"}
    echo "Publishing Confluent ${confluent_git_refspec} to ${MAVEN_REPO_ID}"
    (
        cd "$(resolve_build_dir ${confluent_git_refspec})"
        mvn deploy -DaltDeploymentRepository=${MAVEN_REPO_ID} -DskipTests=true \
            -DgitRepo=${CONFLUENT_GIT_REPO} -DgitRef=${confluent_git_refspec} -DbuildTimestamp=$(date -Iseconds --utc)
    )
}

function build_and_publish () {
    for build in "${BUILDS[@]}"; do
        local confluent_git_refspec=$(git ls-remote ${CONFLUENT_GIT_REPO} --tags "**/v${build}-[0-9]*" | awk '{ print $2}' | sort -V | tail -n1)
        cleanup_confluent_build ${confluent_git_refspec}
        clone_confluent ${confluent_git_refspec}
        build_confluent ${confluent_git_refspec}
        if [ "${SHOULD_PUBLISH}" == "true" ]; then
            publish_confluent ${confluent_git_refspec}
        fi
    done
}

function parseCmd () {
    while [[ $# -gt 0 ]]; do
        case "$1" in
            --publish)
                SHOULD_PUBLISH=true
                shift
                ;;
            *)
                usage "Unknown option: $1"
                return $?
                ;;
        esac
    done
    if [ -z "${BUILD}" ]; then
        usage "Missing env var BUILD: $1"
        return $?
    fi
    BUILDS=(${BUILD})
    if [ -z "${MAVEN_REPO_ID}" ] && [ "${SHOULD_PUBLISH}" == "true" ]; then
        usage "Missing env var MAVEN_REPO_ID: $1"
        return $?
    fi
    return 0
}

function main () {
    parseCmd "$@"
    local retval=$?
    if [ $retval != 0 ]; then
        exit $retval
    fi

    build_and_publish
}

main "$@"