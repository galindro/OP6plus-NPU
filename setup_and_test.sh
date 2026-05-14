#!/usr/bin/env bash

set -eo pipefail

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

HUB_REPO="ai_model_hub"
HUB_URL="https://www.modelscope.cn/cix/${HUB_REPO}.git"
HUB_DIR="${HOME}/${HUB_REPO}"
CIX_WHL_DIR="/usr/share/cix/pypi/"
CIX_REQ_VERSION="1.1.0"
VENV_NAME="cix"

# Parse command-line options
while getopts "d:" opt; do
    case $opt in
        d) HUB_DIR="$OPTARG" ;;
        *) echo "Usage: $0 [-d hub_dir]" >&2; exit 1 ;;
    esac
done

echo -e "${GREEN}================================================${NC}"
echo -e "${GREEN}   Orange Pi 6 Plus NPU Setup & Test Utility    ${NC}"
echo -e "${GREEN}================================================${NC}"

echo -e "${YELLOW}This utility will guide you through setting up the NPU environment on your Orange Pi 6 Plus.${NC}"
echo -e "${YELLOW}It will perform the following steps:${NC}"
echo -e "${YELLOW}1. Install necessary system dependencies${NC}"
echo -e "${YELLOW}2. Set up Python environment using pyenv${NC}"
echo -e "${YELLOW}3. Clone the CIX AI Model Hub repository${NC}"
echo -e "${YELLOW}4. Install Python dependencies for the Model Hub${NC}"
echo -e "${YELLOW}5. Install the Zhouyi NPU Runtime and NOE Engine${NC}"

echo -e "${YELLOW}Please ensure you have a stable internet connection and sufficient storage space (60GB-120GB) for the Model Hub.${NC}"
echo -e "\n${RED}This script MUST be run on the official Orange Pi image to ensure compatibility with the NPU runtime.${NC}"

fn_version_greater_equal() {
    printf '%s\n%s\n' "$2" "$1" | sort --check=quiet --version-sort
}

fn_initial_check() {
    if ! [ -d "${CIX_WHL_DIR}" ]; then
        echo -e "${RED}Error: CIX .whl directory not found at ${CIX_WHL_DIR}.${NC}"
        return 1
    fi

    if ! lsmod |grep -q aipu; then
        echo -e "${RED}Error: AIPU kernel module not detected. NPU functionality will not work.${NC}"
        return 1
    fi

    CIX_VERSION=$(dpkg -l | grep cix-npu-onnxruntime | awk '{print $3}')

    if ! fn_version_greater_equal "${CIX_VERSION}" "${CIX_REQ_VERSION}"; then
        echo -e "${RED}Error: Detected CIX ONNX Runtime version ${CIX_VERSION} is less than required ${CIX_REQ_VERSION}.${NC}"
        return 1
    fi
}

fn_step_one() {
    echo -e "\n${YELLOW}[Step 1] Setup and install apt dependencies${NC}"
    echo -e "Please provide root credentials to proceed with system updates and package installations.\n"
    sudo -v

    echo -e "${GREEN}Setting up APT sources...${NC}"
    sudo cp ./ubuntu.sources /etc/apt/sources.list.d/ubuntu.sources

    sudo apt update

    sudo apt install -y \
        build-essential \
        cmake \
        curl \
        git-lfs \
        libbz2-dev \
        libffi-dev \
        liblzma-dev \
        libncursesw5-dev \
        libreadline-dev \
        libsqlite3-dev \
        libssl-dev \
        libxml2-dev \
        libxmlsec1-dev \
        llvm \
        tk-dev \
        wget \
        xz-utils \
        zlib1g-dev
}

fn_step_two() {
    echo -e "\n${YELLOW}[Step 2] Install pyenv and Python 3.11.15${NC}\n"

    pyenv --version || (
        curl -fsSL https://pyenv.run | bash

        # shellcheck source=/dev/null
        cat pyenv.bashrc >> "${HOME}/.bashrc"
    )

    source pyenv.bashrc

    pyenv install 3.11.15
    pyenv virtualenv 3.11.15 "${VENV_NAME}"
    pyenv activate "${VENV_NAME}"
    pyenv virtualenvs

    echo -e "${GREEN}Python environment set up successfully.${NC}"
}

fn_step_three() {
    echo -e "\n${YELLOW}[Step 3] Clone CIX AI Model Hub Repository. This may take a few minutes.${NC}\n"
    if [ -d "${HUB_DIR}" ] && [ -d "${HUB_DIR}/.git" ]; then
        echo -e "${GREEN}Repository already cloned at ${HUB_DIR}.${NC}"
    else
        git clone "${HUB_URL}" "${HUB_DIR}" || {
            echo -e "${RED}Error cloning repository.${NC}"
            return 1
        }
        echo -e "${GREEN}Repository cloned successfully.${NC}"
    fi
}

fn_step_four() {
    echo -e "\n${YELLOW}[Step 4] Install CIX AI Model Hub Python dependencies${NC}\n"

    REQS_FILE="${HUB_DIR}/requirements.txt"

    if [ -f "${REQS_FILE}" ]; then
        pip install -r "${REQS_FILE}" || {
            echo -e "${RED}Error installing Python dependencies.${NC}"
            return 1
        }
        echo -e "${GREEN}Python dependencies installed successfully.${NC}"
    else
        echo -e "${RED}${REQS_FILE} not found.${NC}"
        return 1
    fi
}

fn_step_five() {
    echo -e "\n${YELLOW}[Step 5] Install Zhouyi NPU Runtime and NOE Engine. This replaces the standard CPU-based ONNX runtime with the NPU version.${NC}\n"

    (
        pip uninstall -y onnxruntime
        for whl in "${CIX_WHL_DIR}"/*.whl; do
            pip install "$whl" || {
                echo -e "${RED}Error installing ${whl}.${NC}"
                return 1
            }
        done
    ) || {
        echo -e "${RED}Error installing NPU Runtime or NOE Engine.${NC}"
        return 1
    }

    echo -e "${GREEN}NPU Runtime and NOE Engine installed successfully.${NC}"
}

fn_step_six() {
    echo -e "\n${YELLOW}[Step 6] Final Checks and Test Run${NC}"

    TEST_DIR="$HUB_DIR/models/ComputeVision/Image_Classification/onnx_resnet_v1_50"

    if [ -d "$TEST_DIR" ]; then
        cd "$TEST_DIR"
        echo "Running inference_npu.py..."
        python3 inference_npu.py --images test_data --model_path resnet_v1_50.cix | tee -a /tmp/inference_test.log

        if grep -q "npu: noe_create_job success" /tmp/inference_test.log; then
            echo -e "\n${GREEN}NPU is working correctly! Inference test passed!${NC}\n"
        else
            echo -e "\n${RED}Inference test did not indicate NPU success. Please check the output above for errors.${NC}"
            return 1
        fi
    else
        echo -e "${RED}Test directory not found. Please ensure the Model Hub was downloaded correctly.${NC}"
        return 1
    fi
}

fn_initial_check || exit 1
fn_step_one || exit 1
fn_step_two || exit 2
fn_step_three || exit 3
fn_step_four || exit 4
fn_step_five || exit 5
fn_step_six || exit 6

echo -e "${GREEN}Setup complete! You can now run your NPU-accelerated models.${NC}"
exit 0
