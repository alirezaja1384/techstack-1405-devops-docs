#!/usr/bin/env bash
# Verify a Week 4 submission in an isolated statusapi deployment.
#
# This script intentionally removes every statusapi deployment footprint during
# setup and teardown: the running process, systemd unit and enablement links,
# /opt/statusapi, and the statusapi system user/group. Do not run it on a host
# where a real service with that name must be preserved.
set -uo pipefail

umask 022

BASE_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
readonly BASE_DIR
ASSETS_DIR="${ASSETS_DIR:-${1:-}}"

if [[ -z ${ASSETS_DIR} ]]; then
    ASSETS_DIR="$(find "${BASE_DIR}/repos" -type d -path '*/4/assets' -print -quit 2>/dev/null)"
fi
if [[ -z ${ASSETS_DIR} || ! -d ${ASSETS_DIR} ]]; then
    printf 'Usage: %s ASSETS_DIR\n' "$0" >&2
    printf '       ASSETS_DIR=path %s\n' "$0" >&2
    exit 2
fi
ASSETS_DIR="$(cd "${ASSETS_DIR}" && pwd)"

if [[ ${EUID} -eq 0 ]]; then
    SUDO=()
else
    SUDO=(sudo)
    if ! sudo -n true 2>/dev/null; then
        printf 'Requesting sudo credentials (required to test systemd installation)...\n'
        sudo -v || { printf 'sudo authentication failed\n' >&2; exit 1; }
    fi
fi

as_root() {
    "${SUDO[@]}" "$@"
}

readonly SERVICE_NAME="statusapi"
readonly SERVICE_USER="statusapi"
readonly APP_DIR="/opt/statusapi"
readonly UNIT_PATH="/etc/systemd/system/statusapi.service"
readonly UNIT_NAME="${SERVICE_NAME}.service"
STAGE="$(mktemp -d /tmp/statusapi-week4.XXXXXX)"
readonly STAGE
chmod 0755 "${STAGE}"

PASS=0
FAIL=0
declare -a FAILURES=()

if [[ -t 1 ]]; then
    GREEN=$'\033[32m'; RED=$'\033[31m'; YELLOW=$'\033[33m'; BOLD=$'\033[1m'; RESET=$'\033[0m'
else
    GREEN=''; RED=''; YELLOW=''; BOLD=''; RESET=''
fi

section() { printf '\n%s== %s ==%s\n' "${BOLD}" "$1" "${RESET}"; }
ok() { PASS=$((PASS + 1)); printf '  %s[PASS]%s %s\n' "${GREEN}" "${RESET}" "$1"; }
bad() { FAIL=$((FAIL + 1)); FAILURES+=("$1"); printf '  %s[FAIL]%s %s\n' "${RED}" "${RESET}" "$1"; }
note() { printf '  %s%s%s\n' "${YELLOW}" "$1" "${RESET}"; }

check() {
    local description=$1
    shift
    if "$@" >/dev/null 2>&1; then ok "${description}"; else bad "${description}"; fi
}

is_empty_directory() {
    local directory=$1
    [[ -d ${directory} && -z $(find "${directory}" -mindepth 1 -print -quit) ]]
}

wait_for_health() {
    local remaining=10

    while ((remaining > 0)); do
        if curl --fail --silent --max-time 2 http://127.0.0.1:8090/health \
            | jq -e '.status == "ok"' >/dev/null 2>&1; then
            return 0
        fi
        sleep 1
        remaining=$((remaining - 1))
    done
    return 1
}

find_shellcheck() {
    local candidate
    if [[ -n ${SHELLCHECK_BIN:-} && -x ${SHELLCHECK_BIN} ]]; then
        printf '%s\n' "${SHELLCHECK_BIN}"
        return 0
    fi
    if candidate="$(command -v shellcheck 2>/dev/null)"; then
        printf '%s\n' "${candidate}"
        return 0
    fi
    for candidate in "${BASE_DIR}"/bin/shellcheck*/shellcheck; do
        [[ -x ${candidate} ]] && { printf '%s\n' "${candidate}"; return 0; }
    done
    return 1
}

ensure_shellcheck() {
    local shellcheck_bin

    if shellcheck_bin="$(find_shellcheck)"; then
        printf '%s\n' "${shellcheck_bin}"
        return 0
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        printf 'Error: shellcheck is missing and apt-get is unavailable.\n' >&2
        return 1
    fi

    note 'shellcheck is missing; installing it with apt-get.' >&2
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update >&2
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends shellcheck >&2

    if shellcheck_bin="$(find_shellcheck)"; then
        printf '%s\n' "${shellcheck_bin}"
        return 0
    fi

    printf 'Error: shellcheck could not be found after installation.\n' >&2
    return 1
}

remove_statusapi_footprint() {
    set +e

    # Stop first so the service cannot retain an executable or a deleted UID.
    as_root systemctl disable --now "${UNIT_NAME}" >/dev/null 2>&1
    as_root systemctl stop "${UNIT_NAME}" >/dev/null 2>&1
    as_root pkill --kill --user "${SERVICE_USER}" >/dev/null 2>&1

    # systemctl disable normally removes these links. Remove them explicitly
    # as well so a malformed unit or interrupted run cannot leak enablement
    # into the next submission's test.
    as_root find /etc/systemd/system -type l -name "${UNIT_NAME}" -delete >/dev/null 2>&1
    as_root rm -f "${UNIT_PATH}"
    as_root systemctl daemon-reload >/dev/null 2>&1
    as_root systemctl reset-failed "${UNIT_NAME}" >/dev/null 2>&1
    as_root rm -rf "${APP_DIR}"
    if getent passwd "${SERVICE_USER}" >/dev/null 2>&1; then
        as_root userdel --remove "${SERVICE_USER}" >/dev/null 2>&1
    fi
    if getent group "${SERVICE_USER}" >/dev/null 2>&1; then
        as_root groupdel "${SERVICE_USER}" >/dev/null 2>&1
    fi
}

cleanup() {
    remove_statusapi_footprint
    rm -rf "${STAGE}"
}
trap cleanup EXIT INT TERM

statusapi_footprint_is_absent() {
    ! getent passwd "${SERVICE_USER}" >/dev/null 2>&1 \
        && ! getent group "${SERVICE_USER}" >/dev/null 2>&1 \
        && [[ ! -e ${APP_DIR} ]] \
        && [[ ! -e ${UNIT_PATH} ]] \
        && ! find /etc/systemd/system -type l -name "${UNIT_NAME}" -print -quit 2>/dev/null | grep -q . \
        && ! systemctl is-active --quiet "${UNIT_NAME}" \
        && ! systemctl is-enabled --quiet "${UNIT_NAME}"
}

check_running_deployment() {
    local implementation=$1

    check "${implementation}: statusapi user exists" getent passwd statusapi
    check "${implementation}: statusapi group exists" getent group statusapi
    check "${implementation}: statusapi account uses nologin" sh -c "getent passwd statusapi | awk -F: '{exit !(\$7 ~ /nologin$/)}'"
    check "${implementation}: /opt/statusapi is owned by statusapi" sh -c "test \"\$(stat -c '%U:%G' /opt/statusapi)\" = statusapi:statusapi"
    check "${implementation}: venv Python exists" test -x /opt/statusapi/venv/bin/python
    check "${implementation}: venv pip module is available" /opt/statusapi/venv/bin/python -m pip --version
    check "${implementation}: Flask is importable from the venv" /opt/statusapi/venv/bin/python -c 'from flask import Flask, jsonify'
    check "${implementation}: installed systemd unit validates" as_root systemd-analyze verify "${UNIT_PATH}"
    check "${implementation}: systemd service is active" as_root systemctl is-active --quiet statusapi
    check "${implementation}: systemd service is enabled" as_root systemctl is-enabled --quiet statusapi
    check "${implementation}: health endpoint returns expected JSON" sh -c "curl --fail --silent http://127.0.0.1:8090/health | jq -e '.status == \"ok\"'"
    check "${implementation}: status endpoint has all required fields" sh -c "curl --fail --silent http://127.0.0.1:8090/api/v1/status | jq -e 'has(\"service\") and has(\"version\") and has(\"hostname\") and has(\"uptime_seconds\") and has(\"status\")'"
}

run_ansible_playbook() {
    "${ANSIBLE_PLAYBOOK}" \
        -i "${STAGE}/ansible/inventory.ini" \
        "${STAGE}/ansible/playbook.yml"
}

ensure_ansible_playbook() {
    local ansible_bin

    if ansible_bin="$(command -v ansible-playbook 2>/dev/null)"; then
        printf '%s\n' "${ansible_bin}"
        return 0
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        printf 'Error: ansible-playbook is missing and apt-get is unavailable.\n' >&2
        return 1
    fi

    note 'ansible-playbook is missing; installing Ansible with apt-get.' >&2
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update >&2
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends ansible >&2

    if ansible_bin="$(command -v ansible-playbook 2>/dev/null)"; then
        printf '%s\n' "${ansible_bin}"
        return 0
    fi

    printf 'Error: ansible-playbook could not be found after installation.\n' >&2
    return 1
}

ensure_make() {
    local make_bin

    if make_bin="$(command -v make 2>/dev/null)"; then
        printf '%s\n' "${make_bin}"
        return 0
    fi

    if ! command -v apt-get >/dev/null 2>&1; then
        printf 'Error: make is missing and apt-get is unavailable.\n' >&2
        return 1
    fi

    note 'make is missing; installing it with apt-get.' >&2
    as_root env DEBIAN_FRONTEND=noninteractive apt-get update >&2
    as_root env DEBIAN_FRONTEND=noninteractive apt-get install --yes --no-install-recommends make >&2

    if make_bin="$(command -v make 2>/dev/null)"; then
        printf '%s\n' "${make_bin}"
        return 0
    fi

    printf 'Error: make could not be found after installation.\n' >&2
    return 1
}

write_reference_app() {
    cat >"${STAGE}/app.py" <<'PYTHON'
import os
import socket
import time
from flask import Flask, jsonify

app = Flask(__name__)
start_time = time.time()

@app.route("/health", methods=["GET"])
def health():
    return jsonify({"status": "ok"}), 200

@app.route("/api/v1/status", methods=["GET"])
def status():
    return jsonify({
        "service": "statusapi",
        "version": "1.0.0",
        "hostname": socket.gethostname(),
        "uptime_seconds": int(time.time() - start_time),
        "status": "running",
    }), 200

if __name__ == "__main__":
    app.run(
        host=os.environ.get("STATUSAPI_HOST", "127.0.0.1"),
        port=int(os.environ.get("STATUSAPI_PORT", 8090)),
    )
PYTHON
    printf 'Flask==3.0.3\n' >"${STAGE}/requirements.txt"
}

section 'pre-run reset'
note 'The statusapi service, unit/enablement links, app files, and user/group are removed before and after this check.'
cleanup
mkdir -p "${STAGE}"
chmod 0755 "${STAGE}"
check 'pre-run statusapi footprint is absent' statusapi_footprint_is_absent

section 'inputs and static analysis'
printf '  assets: %s\n' "${ASSETS_DIR}"
for file in install.sh client.sh statusapi.service Makefile; do
    check "${file} exists" test -f "${ASSETS_DIR}/${file}"
done

HAS_ANSIBLE=0
RUN_ANSIBLE=0
ANSIBLE_PLAYBOOK=""
if [[ -e ${ASSETS_DIR}/ansible || -e ${ASSETS_DIR}/ansible/inventory.ini || -e ${ASSETS_DIR}/ansible/playbook.yml ]]; then
    HAS_ANSIBLE=1
    check 'ansible/inventory.ini exists' test -f "${ASSETS_DIR}/ansible/inventory.ini"
    check 'ansible/playbook.yml exists' test -f "${ASSETS_DIR}/ansible/playbook.yml"
    if [[ -f ${ASSETS_DIR}/ansible/inventory.ini && -f ${ASSETS_DIR}/ansible/playbook.yml ]]; then
        RUN_ANSIBLE=1
    fi
else
    note 'Ansible assets not supplied; optional Ansible tests will be skipped.'
fi

if [[ ! -f ${ASSETS_DIR}/install.sh || ! -f ${ASSETS_DIR}/client.sh || ! -f ${ASSETS_DIR}/statusapi.service || ! -f ${ASSETS_DIR}/Makefile ]]; then
    note 'Required assets are missing; dynamic tests cannot run.'
else
    check 'install.sh Bash syntax' bash -n "${ASSETS_DIR}/install.sh"
    check 'client.sh Bash syntax' bash -n "${ASSETS_DIR}/client.sh"
    check 'install.sh has Bash shebang' grep -qx '#!/usr/bin/env bash' "${ASSETS_DIR}/install.sh"
    check 'client.sh has Bash shebang' grep -qx '#!/usr/bin/env bash' "${ASSETS_DIR}/client.sh"
    check 'install.sh enables strict mode' grep -Eq '^[[:space:]]*set -euo pipefail' "${ASSETS_DIR}/install.sh"
    check 'client.sh enables strict mode' grep -Eq '^[[:space:]]*set -euo pipefail' "${ASSETS_DIR}/client.sh"
    check 'install.sh checks for root privileges' grep -Eq 'EUID|id -u' "${ASSETS_DIR}/install.sh"
    check 'install.sh creates a Python virtual environment' grep -Eq 'python3[[:space:]]+-m[[:space:]]+venv' "${ASSETS_DIR}/install.sh"
    check 'install.sh provisions Python venv support' grep -Eq 'python.*-venv|python3-venv' "${ASSETS_DIR}/install.sh"
    check 'install.sh provisions curl and jq' grep -Eq 'packages.*curl|curl.*packages|apt-get install.*curl' "${ASSETS_DIR}/install.sh"
    check 'install.sh enables and starts a service' grep -Eq 'systemctl[[:space:]]+enable.*--now|systemctl[[:space:]]+enable[[:space:]]+--now' "${ASSETS_DIR}/install.sh"
    check 'client.sh uses curl' grep -q 'curl' "${ASSETS_DIR}/client.sh"
    check 'client.sh uses jq' grep -q 'jq' "${ASSETS_DIR}/client.sh"
    check 'Makefile declares required phony targets' grep -Eq '^\.PHONY:.*install.*start.*stop.*status.*client' "${ASSETS_DIR}/Makefile"
    check 'Makefile recipes use tabs' grep -q $'^\t' "${ASSETS_DIR}/Makefile"
    if ((RUN_ANSIBLE)); then
        check 'Makefile provides an Ansible target' grep -Eq '^ansible:' "${ASSETS_DIR}/Makefile"
        check 'Ansible playbook uses apt' grep -q 'ansible.builtin.apt' "${ASSETS_DIR}/ansible/playbook.yml"
        check 'Ansible playbook uses user and group modules' grep -Eq 'ansible.builtin.(user|group)' "${ASSETS_DIR}/ansible/playbook.yml"
        check 'Ansible playbook uses systemd_service' grep -q 'ansible.builtin.systemd_service' "${ASSETS_DIR}/ansible/playbook.yml"
        check 'Ansible playbook creates a venv' grep -qx '          - venv' "${ASSETS_DIR}/ansible/playbook.yml"
    fi

    check 'unit: Type=simple' grep -qx 'Type=simple' "${ASSETS_DIR}/statusapi.service"
    check 'unit: User=statusapi' grep -qx 'User=statusapi' "${ASSETS_DIR}/statusapi.service"
    check 'unit: Group=statusapi' grep -qx 'Group=statusapi' "${ASSETS_DIR}/statusapi.service"
    check 'unit: expected working directory' grep -qx 'WorkingDirectory=/opt/statusapi' "${ASSETS_DIR}/statusapi.service"
    check 'unit: expected Python command' grep -qx 'ExecStart=/opt/statusapi/venv/bin/python /opt/statusapi/app.py' "${ASSETS_DIR}/statusapi.service"
    check 'unit: restarts automatically' grep -qx 'Restart=always' "${ASSETS_DIR}/statusapi.service"
    check 'unit: enabled at boot' grep -qx 'WantedBy=multi-user.target' "${ASSETS_DIR}/statusapi.service"

    SHELLCHECK="$(ensure_shellcheck || true)"
    if [[ -n ${SHELLCHECK} ]]; then
        if "${SHELLCHECK}" "${ASSETS_DIR}/install.sh" "${ASSETS_DIR}/client.sh"; then
            ok 'shellcheck clean'
        else
            bad 'shellcheck clean'
        fi
    else
        bad 'shellcheck is installed and available'
    fi

    section 'stage submission'
    cp -a "${ASSETS_DIR}/." "${STAGE}/"
    # The assignment supplies these two files outside assets/. Use the exact
    # reference application so the verifier tests deployment, not Flask code.
    write_reference_app
    chmod 0755 "${STAGE}/install.sh" "${STAGE}/client.sh"

    section 'root guard'
    set +e
    as_root runuser -u nobody -- "${STAGE}/install.sh" >"${STAGE}/nonroot.out" 2>"${STAGE}/nonroot.err"
    root_guard_rc=$?
    set -e
    if [[ ${root_guard_rc} -ne 0 ]]; then ok 'install.sh refuses non-root execution'; else bad 'install.sh refuses non-root execution'; fi
    check 'root guard writes an error to stderr' test -s "${STAGE}/nonroot.err"

    section 'installation and idempotency'
    set +e
    as_root bash "${STAGE}/install.sh" >"${STAGE}/install-1.out" 2>"${STAGE}/install-1.err"
    install_first_rc=$?
    set -e
    if [[ ${install_first_rc} -eq 0 ]]; then ok 'first install succeeds'; else bad "first install succeeds (rc=${install_first_rc})"; fi
    if [[ ${install_first_rc} -ne 0 ]]; then
        note "first-install stderr: $(tr '\n' ' ' <"${STAGE}/install-1.err" | head -c 500)"
    fi

    set +e
    as_root bash "${STAGE}/install.sh" >"${STAGE}/install-2.out" 2>"${STAGE}/install-2.err"
    install_second_rc=$?
    set -e
    if [[ ${install_second_rc} -eq 0 ]]; then ok 'second install succeeds (idempotency)'; else bad "second install succeeds (idempotency; rc=${install_second_rc})"; fi
    if [[ ${install_second_rc} -ne 0 ]]; then
        note "second-install stderr: $(tr '\n' ' ' <"${STAGE}/install-2.err" | head -c 500)"
    fi

    check_running_deployment 'shell installer'

    section 'self-healing: empty virtualenv directory'
    # A partially completed deployment can leave the venv directory behind
    # without its interpreter. The installer must recover rather than treating
    # directory existence as proof that a usable virtual environment exists.
    as_root systemctl stop statusapi
    as_root rm -rf /opt/statusapi/venv
    as_root install -d -o statusapi -g statusapi -m 0755 /opt/statusapi/venv
    check 'broken venv directory is empty' is_empty_directory /opt/statusapi/venv

    set +e
    as_root bash "${STAGE}/install.sh" >"${STAGE}/install-repair.out" 2>"${STAGE}/install-repair.err"
    repair_rc=$?
    set -e
    if [[ ${repair_rc} -eq 0 ]]; then
        ok 'installer repairs an empty venv directory'
    else
        bad "installer repairs an empty venv directory (rc=${repair_rc})"
        note "venv-repair stderr: $(tr '\n' ' ' <"${STAGE}/install-repair.err" | head -c 500)"
    fi
    check_running_deployment 'shell installer empty-venv repair'

    section 'self-healing: venv without pip'
    as_root systemctl stop statusapi
    VENV_SITE_PACKAGES="$(/opt/statusapi/venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    readonly VENV_SITE_PACKAGES
    as_root rm -rf "${VENV_SITE_PACKAGES}/pip" "${VENV_SITE_PACKAGES}"/pip-*.dist-info
    check 'venv Python remains but pip module is broken' sh -c '! /opt/statusapi/venv/bin/python -m pip --version >/dev/null 2>&1'

    set +e
    as_root bash "${STAGE}/install.sh" >"${STAGE}/install-pip-repair.out" 2>"${STAGE}/install-pip-repair.err"
    pip_repair_rc=$?
    set -e
    if [[ ${pip_repair_rc} -eq 0 ]]; then
        ok 'installer repairs a venv with no pip module'
    else
        bad "installer repairs a venv with no pip module (rc=${pip_repair_rc})"
        note "pip-repair stderr: $(tr '\n' ' ' <"${STAGE}/install-pip-repair.err" | head -c 500)"
    fi
    check_running_deployment 'shell installer pip repair'

    section 'self-healing: venv with corrupted Flask'
    as_root systemctl stop statusapi
    FLASK_PACKAGE_DIR="$(/opt/statusapi/venv/bin/python -c 'import os, flask; print(os.path.dirname(flask.__file__))')"
    as_root rm -f "${FLASK_PACKAGE_DIR}/app.py"
    check 'venv pip remains but Flask import is broken' sh -c '! /opt/statusapi/venv/bin/python -c "from flask import Flask, jsonify" >/dev/null 2>&1'
    set +e
    as_root bash "${STAGE}/install.sh" >"${STAGE}/install-flask-repair.out" 2>"${STAGE}/install-flask-repair.err"
    flask_repair_rc=$?
    set -e
    if [[ ${flask_repair_rc} -eq 0 ]]; then
        ok 'installer repairs a venv with corrupted Flask'
    else
        bad "installer repairs a venv with corrupted Flask (rc=${flask_repair_rc})"
        note "Flask-repair stderr: $(tr '\n' ' ' <"${STAGE}/install-flask-repair.err" | head -c 500)"
    fi
    check_running_deployment 'shell installer Flask repair'

    section 'client behavior'
    set +e
    "${STAGE}/client.sh" health >"${STAGE}/health.out" 2>"${STAGE}/health.err"
    health_rc=$?
    "${STAGE}/client.sh" status >"${STAGE}/status.out" 2>"${STAGE}/status.err"
    status_rc=$?
    "${STAGE}/client.sh" invalid >"${STAGE}/usage.out" 2>"${STAGE}/usage.err"
    usage_rc=$?
    set -e
    if [[ ${health_rc} -eq 0 ]]; then ok 'client health exits 0'; else bad "client health exits 0 (rc=${health_rc})"; fi
    check 'client health prints required message' grep -qx 'OK: Service is healthy' "${STAGE}/health.out"
    check 'client health keeps stderr empty' test ! -s "${STAGE}/health.err"
    if [[ ${status_rc} -eq 0 ]]; then ok 'client status exits 0'; else bad "client status exits 0 (rc=${status_rc})"; fi
    check 'client status includes readable service field' grep -qi '^Service:' "${STAGE}/status.out"
    check 'client status final line has required compact JSON' sh -c "tail -n 1 '${STAGE}/status.out' | jq -ce 'keys == [\"service\", \"status\", \"uptime_seconds\"]' >/dev/null"
    if [[ ${usage_rc} -eq 2 ]]; then ok 'invalid client command exits 2'; else bad "invalid client command exits 2 (rc=${usage_rc})"; fi
    check 'invalid client command writes Usage to stderr' grep -q 'Usage' "${STAGE}/usage.err"
    check 'invalid client command keeps stdout empty' test ! -s "${STAGE}/usage.out"

    as_root systemctl stop statusapi
    set +e
    "${STAGE}/client.sh" health >"${STAGE}/stopped.out" 2>"${STAGE}/stopped.err"
    stopped_rc=$?
    set -e
    if [[ ${stopped_rc} -eq 1 ]]; then ok 'client reports stopped service with exit 1'; else bad "client reports stopped service with exit 1 (rc=${stopped_rc})"; fi
    check 'stopped-service error goes to stderr' test -s "${STAGE}/stopped.err"
    as_root systemctl start statusapi
    check 'service is healthy again before Makefile tests' wait_for_health

    section 'Makefile'
    MAKE_BIN="$(ensure_make || true)"
    if [[ -n ${MAKE_BIN} ]]; then
        ok 'make is installed and available'
        check 'make health succeeds' "${MAKE_BIN}" -C "${STAGE}" health
        check 'make client succeeds' "${MAKE_BIN}" -C "${STAGE}" client
    else
        bad 'make is installed and available'
    fi

    if ((RUN_ANSIBLE)); then
        section 'Ansible deployment and idempotency'
        remove_statusapi_footprint
        check 'Ansible pre-run statusapi footprint is absent' statusapi_footprint_is_absent
        ANSIBLE_PLAYBOOK="$(ensure_ansible_playbook || true)"
        if [[ -n ${ANSIBLE_PLAYBOOK} ]]; then
            ok 'ansible-playbook is installed and available'
        else
            bad 'ansible-playbook is installed and available'
        fi

        if [[ -n ${ANSIBLE_PLAYBOOK} ]]; then
            set +e
            run_ansible_playbook >"${STAGE}/ansible-1.out" 2>"${STAGE}/ansible-1.err"
            ansible_first_rc=$?
            set -e
            if [[ ${ansible_first_rc} -eq 0 ]]; then
                ok 'first Ansible deployment succeeds'
            else
                bad "first Ansible deployment succeeds (rc=${ansible_first_rc})"
                note "Ansible first-run stderr: $(tr '\n' ' ' <"${STAGE}/ansible-1.err" | head -c 500)"
            fi
            check_running_deployment 'Ansible first run'

    set +e
    run_ansible_playbook >"${STAGE}/ansible-2.out" 2>"${STAGE}/ansible-2.err"
    ansible_second_rc=$?
    set -e
    if [[ ${ansible_second_rc} -eq 0 ]]; then
        ok 'second Ansible deployment succeeds (idempotency)'
    else
        bad "second Ansible deployment succeeds (idempotency; rc=${ansible_second_rc})"
        note "Ansible second-run stderr: $(tr '\n' ' ' <"${STAGE}/ansible-2.err" | head -c 500)"
    fi
    check 'second Ansible deployment reports changed=0' grep -Eq 'changed=0[[:space:]]+unreachable=0[[:space:]]+failed=0' "${STAGE}/ansible-2.out"
    check_running_deployment 'Ansible second run'

    section 'Ansible self-healing: empty virtualenv directory'
    as_root systemctl stop statusapi
    as_root rm -rf /opt/statusapi/venv
    as_root install -d -o statusapi -g statusapi -m 0755 /opt/statusapi/venv
    check 'Ansible broken venv directory is empty' is_empty_directory /opt/statusapi/venv
    set +e
    run_ansible_playbook >"${STAGE}/ansible-venv-repair.out" 2>"${STAGE}/ansible-venv-repair.err"
    ansible_venv_repair_rc=$?
    set -e
    if [[ ${ansible_venv_repair_rc} -eq 0 ]]; then
        ok 'Ansible repairs an empty venv directory'
    else
        bad "Ansible repairs an empty venv directory (rc=${ansible_venv_repair_rc})"
        note "Ansible venv-repair stderr: $(tr '\n' ' ' <"${STAGE}/ansible-venv-repair.err" | head -c 500)"
    fi
    check_running_deployment 'Ansible empty-venv repair'

    section 'Ansible self-healing: venv without pip'
    as_root systemctl stop statusapi
    ANSIBLE_VENV_SITE_PACKAGES="$(/opt/statusapi/venv/bin/python -c 'import sysconfig; print(sysconfig.get_paths()["purelib"])')"
    as_root rm -rf "${ANSIBLE_VENV_SITE_PACKAGES}/pip" "${ANSIBLE_VENV_SITE_PACKAGES}"/pip-*.dist-info
    check 'Ansible venv Python remains but pip module is broken' sh -c '! /opt/statusapi/venv/bin/python -m pip --version >/dev/null 2>&1'
    set +e
    run_ansible_playbook >"${STAGE}/ansible-pip-repair.out" 2>"${STAGE}/ansible-pip-repair.err"
    ansible_pip_repair_rc=$?
    set -e
    if [[ ${ansible_pip_repair_rc} -eq 0 ]]; then
        ok 'Ansible repairs a venv with no pip module'
    else
        bad "Ansible repairs a venv with no pip module (rc=${ansible_pip_repair_rc})"
        note "Ansible pip-repair stderr: $(tr '\n' ' ' <"${STAGE}/ansible-pip-repair.err" | head -c 500)"
    fi
    check_running_deployment 'Ansible pip repair'

    section 'Ansible self-healing: venv with corrupted Flask'
    as_root systemctl stop statusapi
    ANSIBLE_FLASK_PACKAGE_DIR="$(/opt/statusapi/venv/bin/python -c 'import os, flask; print(os.path.dirname(flask.__file__))')"
    as_root rm -f "${ANSIBLE_FLASK_PACKAGE_DIR}/app.py"
    check 'Ansible venv pip remains but Flask import is broken' sh -c '! /opt/statusapi/venv/bin/python -c "from flask import Flask, jsonify" >/dev/null 2>&1'
    set +e
    run_ansible_playbook >"${STAGE}/ansible-flask-repair.out" 2>"${STAGE}/ansible-flask-repair.err"
    ansible_flask_repair_rc=$?
    set -e
    if [[ ${ansible_flask_repair_rc} -eq 0 ]]; then
        ok 'Ansible repairs a venv with corrupted Flask'
    else
        bad "Ansible repairs a venv with corrupted Flask (rc=${ansible_flask_repair_rc})"
        note "Ansible Flask-repair stderr: $(tr '\n' ' ' <"${STAGE}/ansible-flask-repair.err" | head -c 500)"
    fi
            check_running_deployment 'Ansible Flask repair'
        else
            note 'Ansible dynamic tests skipped because ansible-playbook is unavailable.'
        fi
    elif ((HAS_ANSIBLE)); then
        note 'Ansible tests skipped because the optional Ansible implementation is incomplete.'
    fi
fi

section 'teardown'
cleanup
check 'statusapi user is removed' sh -c '! getent passwd statusapi >/dev/null 2>&1'
check 'statusapi group is removed' sh -c '! getent group statusapi >/dev/null 2>&1'
check '/opt/statusapi is removed' test ! -e /opt/statusapi
check 'systemd unit file is removed' test ! -e /etc/systemd/system/statusapi.service
check 'systemd enablement links are removed' sh -c '! find /etc/systemd/system -type l -name statusapi.service -print -quit | grep -q .'
check 'statusapi has no active or enabled unit' statusapi_footprint_is_absent

section 'summary'
printf '  checks: %d; %spassed: %d%s; %sfailed: %d%s\n' \
    "$((PASS + FAIL))" "${GREEN}" "${PASS}" "${RESET}" "${RED}" "${FAIL}" "${RESET}"
if ((FAIL > 0)); then
    printf '  Failed checks:\n' >&2
    printf '    - %s\n' "${FAILURES[@]}" >&2
    exit 1
fi
printf '  %sRESULT: PASSED%s\n' "${GREEN}" "${RESET}"
