#!/bin/bash

#######################################################################
# OnlyOffice Package Builder

# Copyright (C) 2024 BTACTIC, SCCL

# This program is free software: you can redistribute it and/or modify
# it under the terms of the GNU General Public License as published by
# the Free Software Foundation, either version 3 of the License, or
# (at your option) any later version.

# This program is distributed in the hope that it will be useful,
# but WITHOUT ANY WARRANTY; without even the implied warranty of
# MERCHANTABILITY or FITNESS FOR A PARTICULAR PURPOSE.  See the
# GNU General Public License for more details.

# You should have received a copy of the GNU General Public License
# along with this program.  If not, see <http://www.gnu.org/licenses/>.
#######################################################################

usage() {
cat <<EOF

  $0
  Copyright BTACTIC, SCCL
  Licensed under the GNU PUBLIC LICENSE 3.0

  Usage: $0 --product-version=PRODUCT_VERSION --build-number=BUILD_NUMBER --unlimited-organization=ORGANIZATION --tag-suffix=-TAG_SUFFIX --debian-package-suffix=-DEBIAN_PACKAGE_SUFFIX
  Example: $0 --product-version=7.4.1 --build-number=36 --unlimited-organization=btactic-oo --tag-suffix=-btactic --debian-package-suffix=-btactic

  For Github actions you might want to either build only binaries or build only deb so that it's easier to prune containers
  Example: $0 --product-version=7.4.1 --build-number=36 --unlimited-organization=btactic-oo --tag-suffix=-btactic --debian-package-suffix=-btactic --binaries-only
  Example: $0 --product-version=7.4.1 --build-number=36 --unlimited-organization=btactic-oo --tag-suffix=-btactic --debian-package-suffix=-btactic --deb-only

EOF

}

BINARIES_ONLY="false"
DEB_ONLY="false"

UPSTREAM_ORGANIZATION="ONLYOFFICE"

SERVER_CUSTOM_COMMITS="69dce08b04ac1dde93d74d5a38614841be166fce"
WEB_APPS_CUSTOM_COMMITS="101f045c7d9cf56692304b6ac2f91fc4f9b5874f"

# Check the arguments.
for option in "$@"; do
  case "$option" in
    -h | --help)
      usage
      exit 0
    ;;
    --product-version=*)
      PRODUCT_VERSION=`echo "$option" | sed 's/--product-version=//'`
    ;;
    --build-number=*)
      BUILD_NUMBER=`echo "$option" | sed 's/--build-number=//'`
    ;;
    --unlimited-organization=*)
      UNLIMITED_ORGANIZATION=`echo "$option" | sed 's/--unlimited-organization=//'`
    ;;
    --tag-suffix=*)
      TAG_SUFFIX=`echo "$option" | sed 's/--tag-suffix=//'`
    ;;
    --debian-package-suffix=*)
      DEBIAN_PACKAGE_SUFFIX=`echo "$option" | sed 's/--debian-package-suffix=//'`
    ;;
    --binaries-only)
      BINARIES_ONLY="true"
    ;;
    --deb-only)
      DEB_ONLY="true"
    ;;
  esac
done

BUILD_BINARIES="true"
BUILD_DEB="true"

if [ "$EUID" -ne 0 ]
  then echo "Please run as root"
  exit 1
fi

# Avoid HTTP/2 stream cancel flakes on large GitHub clones (host + container).
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60

if [ ${BINARIES_ONLY} == "true" ] ; then
  BUILD_BINARIES="true"
  BUILD_DEB="false"
fi

if [ ${DEB_ONLY} == "true" ] ; then
  BUILD_BINARIES="false"
  BUILD_DEB="true"
fi

if [ "x${PRODUCT_VERSION}" == "x" ] ; then
    cat << EOF
    --product-version option must be informed.
    Aborting...
EOF
    usage
    exit 1
fi

if [ "x${BUILD_NUMBER}" == "x" ] ; then
    cat << EOF
    --build-number option must be informed.
    Aborting...
EOF
    usage
    exit 1
fi

if [ "x${UNLIMITED_ORGANIZATION}" == "x" ] ; then
    cat << EOF
    --unlimited-organization option must be informed.
    Aborting...
EOF
    usage
    exit 1
fi

if [ "x${TAG_SUFFIX}" == "x" ] ; then
    cat << EOF
    --tag-suffix option must be informed.
    Aborting...
EOF
    usage
    exit 1
fi

if [ "x${DEBIAN_PACKAGE_SUFFIX}" == "x" ] ; then
    cat << EOF
    --debian-package-suffix option must be informed.
    Aborting...
EOF
    usage
    exit 1
fi

PRUNE_DOCKER_CONTAINERS_ACTION="false"
if [ "x${PRUNE_DOCKER_CONTAINERS}" != "x" ] ; then
  if [ ${PRUNE_DOCKER_CONTAINERS} == "true" ] -o [ ${PRUNE_DOCKER_CONTAINERS} == "TRUE" ] ; then
    PRUNE_DOCKER_CONTAINERS_ACTION="true"
    cat << EOF
    WARNING !
    WARNING !
    --prune-docker-containers has been set to true
    This will erase all of your docker containers
    after the binaries build.

    Waiting for 30s so that you can CTRL+C
EOF
    sleep 30s
  fi
fi

prepare_custom_repo() {

  _REPO=$1
  shift
  _TAG=$1
  shift
  _UNLIMITED_ORGANIZATION=$1
  shift
  # Rest of arguments are commits to cherry-pick in order

  rm -rf ${_REPO}
  if ! git clone https://github.com/${_UNLIMITED_ORGANIZATION}/${_REPO}; then
    echo "Error: git clone of ${_REPO} failed" >&2
    exit 3
  fi
  cd ${_REPO}
  git remote add upstream-origin https://github.com/${UPSTREAM_ORGANIZATION}/${_REPO}

  git checkout master
  git pull upstream-origin master
  git fetch --all --tags
  git checkout tags/${_TAG} -b ${_TAG}-custom

  # Hard-code temp git user.name and user.email for this local cherry-picked commit
  git config user.name 'CherryPick User'
  git config user.email 'cherrypick@btacticoo.com'

  while [ "$#" -gt 0 ]; do
    _ncommit=$1
    if ! git cherry-pick "${_ncommit}"; then
      echo "Error: cherry-pick of commit ${_ncommit} failed in ${_REPO}" >&2
      echo "Aborting!"
      exit 3
    fi
    shift
  done

  # Force our changes
  git tag --delete ${_TAG}
  git tag -a "${_TAG}" -m "${_TAG}"

  cd ..

}

build_oo_binaries() {

  _OUT_FOLDER=$1 # out
  _PRODUCT_VERSION=$2 # 7.4.1
  _BUILD_NUMBER=$3 # 36
  _TAG_SUFFIX=$4 # -btactic
  _UNLIMITED_ORGANIZATION=$5 # btactic-oo

  _UPSTREAM_TAG="v${_PRODUCT_VERSION}.${_BUILD_NUMBER}"
  _UNLIMITED_ORGANIZATION_TAG="${_UPSTREAM_TAG}${_TAG_SUFFIX}"

  prepare_custom_repo "server" "${_UPSTREAM_TAG}" "${_UNLIMITED_ORGANIZATION}" ${SERVER_CUSTOM_COMMITS}
  prepare_custom_repo "web-apps" "${_UPSTREAM_TAG}" "${_UNLIMITED_ORGANIZATION}" ${WEB_APPS_CUSTOM_COMMITS}

  rm -rf build_tools
  if ! git clone \
    --depth=1 \
    --recursive \
    --branch ${_UPSTREAM_TAG} \
    https://github.com/${UPSTREAM_ORGANIZATION}/build_tools.git \
    build_tools; then
    echo "Error: git clone of build_tools failed" >&2
    exit 3
  fi
  # Ignore detached head warning
  cd build_tools
  mkdir ${_OUT_FOLDER}
  docker build --tag onlyoffice-document-editors-builder .
  docker run -i \
    -e BRANCH=tags/${_UPSTREAM_TAG} \
    -e PRODUCT_VERSION=${_PRODUCT_VERSION} \
    -e BUILD_NUMBER=${_BUILD_NUMBER} \
    -e NODE_ENV='production' \
    -v $(pwd)/${_OUT_FOLDER}:/build_tools/out \
    -v $(pwd)/../server:/server \
    -v $(pwd)/../web-apps:/web-apps \
    onlyoffice-document-editors-builder \
    /bin/bash -s <<'EOF'
set -e
export DEPOT_TOOLS_UPDATE=0
export VPYTHON_BYPASS="manually managed python not supported by chrome operations"
export GCLIENT_SUPPRESS_GIT_VERSION_WARNING=1
cd /build_tools/tools/linux
if [ ! -d python3 ]; then
  ./python.sh
fi
if [ ! -f packages_complete ]; then
  ./python3/bin/python3 ./deps.py
  sudo ./cmake.sh
fi
if [ ! -d qt_build ]; then
  ./python3/bin/python3 ./qt_binary_fetch.py all
fi
cd /build_tools
./tools/linux/python3/bin/python3 ./configure.py \
  --sysroot "1" \
  --clean "0" \
  --update-light "1" \
  --branch "${BRANCH}" \
  --update "1" \
  --module "server" \
  --qt-dir "$(pwd)/tools/linux/qt_build/Qt-5.9.9"
./tools/linux/python3/bin/python3 - <<'PY'
import pathlib

p = pathlib.Path("/build_tools/scripts/core_common/modules/v8_89.py")
text = p.read_text()

clone_block = (
    '  if not base.is_dir("depot_tools"):\n'
    '    base.cmd("git", ["clone", "https://chromium.googlesource.com/chromium/tools/depot_tools.git"])\n'
    '    change_bootstrap()\n'
)
depot_tools_pin = "f394ab2c993283e94680ca13db98b99927868e98"  # Euro-Office/core#130
pin_block = (
    '  if not base.is_dir("depot_tools"):\n'
    '    base.cmd("git", ["clone", "--depth", "500", "https://chromium.googlesource.com/chromium/tools/depot_tools.git"])\n'
    '    base.cmd("git", ["-C", "depot_tools", "checkout", "--detach", "' + depot_tools_pin + '"])  # v8_89 depot_tools pin\n'
    '    os.environ["DEPOT_TOOLS_UPDATE"] = "0"\n'
    '    change_bootstrap()\n'
)
old_pins = (
    "6e5a13d2598ee48c9c7afc750401533f30dde16e",
    "316bb1e1c28d221ed92419622304704c21d50196",
)
new_checkout_pin = (
    '    base.cmd("git", ["-C", "depot_tools", "checkout", "--detach", "' + depot_tools_pin + '"])  # v8_89 depot_tools pin\n'
)
old_rev_list_pin = (
    '    pin = subprocess.check_output(\n'
    '        ["git", "-C", "depot_tools", "rev-list", "-n", "1", "--before=2026-04-01", "HEAD"],\n'
    '        text=True,\n'
    '    ).strip()\n'
    '    base.cmd("git", ["-C", "depot_tools", "checkout", "--detach", pin])  # v8_89 depot_tools pin\n'
)

if old_rev_list_pin in text:
    text = text.replace(old_rev_list_pin, new_checkout_pin, 1)
    print("v8_89.py upgraded: Euro-Office depot_tools pin")
else:
    for old_pin in old_pins:
        old_checkout = (
            '    base.cmd("git", ["-C", "depot_tools", "checkout", "--detach", "' + old_pin + '"])  # v8_89 depot_tools pin\n'
        )
        if old_checkout in text:
            text = text.replace(old_checkout, new_checkout_pin, 1)
            print("v8_89.py upgraded: depot_tools pin -> " + depot_tools_pin)
            break

if "v8_89 depot_tools pin" not in text:
    if clone_block not in text:
        raise SystemExit("v8_89.py: cannot find depot_tools clone block for pin patch")
    text = text.replace(clone_block, pin_block, 1)
    print("v8_89.py patched: Euro-Office depot_tools pin")

path_old = '  os.environ["PATH"] = base_dir + "/depot_tools" + os.pathsep + os.environ["PATH"]'
path_new = (
    '  os.environ["PATH"] = base_dir + "/depot_tools" + os.pathsep + "/usr/bin" + os.pathsep + os.environ["PATH"]  # v8_89 python3 path'
)
if "v8_89 python3 path" not in text:
    if path_old not in text:
        raise SystemExit("v8_89.py: cannot find PATH assignment to insert depot_tools patch")
    text = text.replace(path_old, path_new, 1)
    print("v8_89.py patched: /usr/bin before build_tools python3")

needle = path_new if "v8_89 python3 path" in text else path_old
env_block = (
    '  os.environ["VPYTHON_BYPASS"] = "manually managed python not supported by chrome operations"  # v8_89 depot_tools env\n'
    '  os.environ["DEPOT_TOOLS_UPDATE"] = "0"  # v8_89 depot_tools env\n'
    '  os.environ["GCLIENT_SUPPRESS_GIT_VERSION_WARNING"] = "1"  # v8_89 depot_tools env\n'
    '\n'
)
vpython_fix = (
    '    if base.is_file("./depot_tools/vpython3"):\n'
    '      base.replaceInFile("./depot_tools/vpython3", \'  exec "python3" "${NEWARGS[@]}"\\n\', \'  exec /usr/bin/python3 "${NEWARGS[@]}"\\n\')  # v8_89 vpython3 system python\n'
    '      os.chmod("./depot_tools/vpython3", 0o755)\n'
)
bootstrap_block = (
    '  if base.is_dir("depot_tools") and not base.is_file("./depot_tools/bootstrap/manifest.txt.bak"):\n'
    '    change_bootstrap()\n'
    '\n'
    '  if ("linux" == base.host_platform()) and base.is_dir("depot_tools"):\n'
    '    if not base.is_file("./depot_tools/python3_bin_reldir.txt"):\n'
    '      base.cmd_in_dir("./depot_tools", "./ensure_bootstrap", [], True)  # v8_89 depot_tools bootstrap fix\n'
    + vpython_fix +
    '\n'
)
if needle not in text:
    raise SystemExit("v8_89.py: cannot find PATH assignment to insert depot_tools patch")
insert = ""
if "v8_89 depot_tools env" not in text:
    insert += env_block
    print("v8_89.py patched: depot_tools env (VPYTHON_BYPASS)")
if "v8_89 depot_tools bootstrap fix" not in text:
    insert += bootstrap_block
    print("v8_89.py patched: ensure_bootstrap before fetch v8")
if insert:
    text = text.replace(needle, insert + needle, 1)

if "v8_89 vpython3 system python" not in text:
    boot_line = '      base.cmd_in_dir("./depot_tools", "./ensure_bootstrap", [], True)  # v8_89 depot_tools bootstrap fix\n'
    if boot_line not in text:
        raise SystemExit("v8_89.py: cannot find ensure_bootstrap line for vpython3 patch")
    text = text.replace(boot_line, boot_line + vpython_fix, 1)
    print("v8_89.py patched: vpython3 -> /usr/bin/python3")

p.write_text(text)
if (
    "v8_89 depot_tools pin" in text
    and "v8_89 depot_tools env" in text
    and "v8_89 depot_tools bootstrap fix" in text
    and "v8_89 python3 path" in text
    and "v8_89 vpython3 system python" in text
):
    print("v8_89.py patch complete")

# Host cmake on Ubuntu 24 needs host libstdc++; sysroot's (Ubuntu 16) is too old.
bp = pathlib.Path("/build_tools/scripts/base.py")
btext = bp.read_text()
ld_old = '  os.environ[\'LD_LIBRARY_PATH\'] = config.get_custom_sysroot_lib(platform)\n'
ld_new = (
    '  os.environ[\'LD_LIBRARY_PATH\'] = "/usr/lib/x86_64-linux-gnu:" + config.get_custom_sysroot_lib(platform)'
    '  # sysroot libstdc++ host cmake fix\n'
)
if "sysroot libstdc++ host cmake fix" not in btext:
    if ld_old not in btext:
        raise SystemExit("base.py: cannot find LD_LIBRARY_PATH sysroot assignment")
    bp.write_text(btext.replace(ld_old, ld_new, 1))
    print("base.py patched: host libstdc++ before sysroot for cmake")
else:
    print("base.py already patched: host libstdc++ before sysroot")
PY
# VPYTHON_BYPASS must use /usr/bin/python3 (3.12). make.py prepends build_tools
# python 3.10, which has no httplib2 and no enum.StrEnum.
if ! /usr/bin/python3 -c 'import httplib2.socks' 2>/dev/null \
    || ! /usr/bin/python3 -c 'from distutils import spawn' 2>/dev/null; then
  sudo apt-get -qq update
  sudo apt-get -qq install -y python3-httplib2 python3-setuptools
fi
git config --global http.version HTTP/1.1
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 60
./tools/linux/python3/bin/python3 ./make.py
EOF
  docker_run_exit=$?
  cd ..
  return ${docker_run_exit}

}

if [ "${BUILD_BINARIES}" == "true" ] ; then
  build_oo_binaries "out" "${PRODUCT_VERSION}" "${BUILD_NUMBER}" "${TAG_SUFFIX}" "${UNLIMITED_ORGANIZATION}"
  build_oo_binaries_exit_value=$?
  if [ ${build_oo_binaries_exit_value} -ne 0 ] ; then
    echo "Binaries build failed!"
    echo "Aborting... !"
    exit 1
  fi
fi

# Simulate that binaries build went ok
# when we only want to make the deb
if [ ${DEB_ONLY} == "true" ] ; then
  build_oo_binaries_exit_value=0
fi

if [ "${BUILD_DEB}" == "true" ] ; then
  if [ ${build_oo_binaries_exit_value} -eq 0 ] ; then
    cd deb_build
    docker build --tag onlyoffice-deb-builder . -f Dockerfile-manual-debian-13
    docker run \
      --env PRODUCT_VERSION=${PRODUCT_VERSION} \
      --env BUILD_NUMBER=${BUILD_NUMBER} \
      --env TAG_SUFFIX=${TAG_SUFFIX} \
      --env UNLIMITED_ORGANIZATION=${UNLIMITED_ORGANIZATION} \
      --env DEBIAN_PACKAGE_SUFFIX=${DEBIAN_PACKAGE_SUFFIX} \
      -v $(pwd):/usr/local/unlimited-onlyoffice-package-builder:ro \
      -v $(pwd):/root:rw \
      -v $(pwd)/../build_tools:/root/build_tools:ro \
      onlyoffice-deb-builder /bin/bash -c "/usr/local/unlimited-onlyoffice-package-builder/onlyoffice-deb-builder.sh --product-version ${PRODUCT_VERSION} --build-number ${BUILD_NUMBER} --tag-suffix ${TAG_SUFFIX} --unlimited-organization ${UNLIMITED_ORGANIZATION} --debian-package-suffix ${DEBIAN_PACKAGE_SUFFIX}"
    cd ..
  else
    echo "Binaries build failed!"
    echo "Aborting... !"
    exit 1
  fi
fi
