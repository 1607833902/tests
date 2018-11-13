#!/bin/bash
#
# Copyright (c) 2017-2018 Intel Corporation
#
# SPDX-License-Identifier: Apache-2.0
#

set -e

export KATA_RUNTIME=${KATA_RUNTIME:-kata-runtime}

# If we fail for any reason a message will be displayed
die() {
	msg="$*"
	echo "ERROR: $msg" >&2
	exit 1
}

info() {
	echo -e "INFO: $*"
}

function build() {
	github_project="$1"
	make_target="$2"
	project_dir="${GOPATH}/src/${github_project}"

	[ -d "${project_dir}" ] || go get "${github_project}" || true

	pushd "${project_dir}"

	info "Building ${github_project}"
	if [ ! -f Makefile ]; then
		info "Run autogen.sh to generate Makefile"
		bash -f autogen.sh
	fi

	make

	popd
}

function build_and_install() {
	github_project="$1"
	make_target="$2"
	build "${github_project}" "${make_target}"
	pushd "${GOPATH}/src/${github_project}"
	info "Installing ${github_project}"
	sudo -E PATH="$PATH" KATA_RUNTIME="${KATA_RUNTIME}" make install
	popd
}

function install_yq() {
	GOPATH=${GOPATH:-${HOME}/go}
	local yq_path="${GOPATH}/bin/yq"
	local yq_pkg="github.com/mikefarah/yq"
	[ -x  "${GOPATH}/bin/yq" ] && return

	case "$(arch)" in
	"aarch64")
		goarch=arm64
		;;

	"x86_64")
		goarch=amd64
		;;
	"*")
		echo "Arch $(arch) not supported"
		exit
		;;
	esac

	mkdir -p "${GOPATH}/bin"

	# Workaround to get latest release from github (to not use github token).
	# Get the redirection to latest release on github.
	yq_latest_url=$(curl -Ls -o /dev/null -w %{url_effective} "https://${yq_pkg}/releases/latest")
	# The redirected url should include the latest release version
	# https://github.com/mikefarah/yq/releases/tag/<VERSION-HERE>
	yq_version=$(basename "${yq_latest_url}")


	local yq_url="https://${yq_pkg}/releases/download/${yq_version}/yq_linux_${goarch}"
	curl -o "${yq_path}" -L ${yq_url}
	chmod +x ${yq_path}
}

function get_version(){
	dependency="$1"
	GOPATH=${GOPATH:-${HOME}/go}
	# This is needed in order to retrieve the version for qemu-lite
	install_yq >&2
	runtime_repo="github.com/kata-containers/runtime"
	runtime_repo_dir="$GOPATH/src/${runtime_repo}"
	versions_file="${runtime_repo_dir}/versions.yaml"
	mkdir -p "$(dirname ${runtime_repo_dir})"
	[ -d "${runtime_repo_dir}" ] ||  git clone --quiet https://${runtime_repo}.git "${runtime_repo_dir}"
	[ ! -f "$versions_file" ] && { echo >&2 "ERROR: cannot find $versions_file"; exit 1; }
	result=$("${GOPATH}/bin/yq" read "$versions_file" "$dependency")
	[ "$result" = "null" ] && result=""
	echo "$result"
}

function check_gopath() {
	# Verify GOPATH is set
	if [ -z "$GOPATH" ]; then
		export GOPATH=$(go env GOPATH)
	fi
}

function waitForProcess(){
        wait_time="$1"
        sleep_time="$2"
        cmd="$3"
        while [ "$wait_time" -gt 0 ]; do
                if eval "$cmd"; then
                        return 0
                else
                        sleep "$sleep_time"
                        wait_time=$((wait_time-sleep_time))
                fi
        done
        return 1
}
