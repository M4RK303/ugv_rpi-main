#!/bin/bash

set -euo pipefail  # Безопасный режим: выход при ошибках, проверка неустановленных переменных

# Цвета для вывода
readonly RED='\033[0;31m'
readonly GREEN='\033[0;32m'
readonly YELLOW='\033[1;33m'
readonly BLUE='\033[0;34m'
readonly NC='\033[0m' # No Color

# Логирование
LOG_FILE="/var/log/ugv_setup.log"
exec > >(tee -a "$LOG_FILE") 2>&1

# Константы
readonly SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly USER_NAME="$(logname)"
readonly UGV_DIR="/home/${USER_NAME}/ugv_rpi"
readonly VENV_NAME="ugv-env"
readonly RELEASE_NAME="bookworm"

# Функции для вывода
print_info() { echo -e "${BLUE}[INFO]${NC} $1"; }
print_success() { echo -e "${GREEN}[SUCCESS]${NC} $1"; }
print_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
print_error() { echo -e "${RED}[ERROR]${NC} $1"; }

# Проверка прав
check_privileges() {
    if [[ $EUID -ne 0 ]]; then
        print_error "This script must be run with sudo."
        print_error "Use 'sudo $0' instead of './$0'"
        exit 1
    fi
}

# Парсинг аргументов
parse_arguments() {
    local use_index=false

    while [[ $# -gt 0 ]]; do
        case $1 in
            -i|--index)
                use_index=true
                shift
                ;;
            -h|--help)
                show_help
                exit 0
                ;;
            *)
                print_error "Unknown option: $1"
                show_help
                exit 1
                ;;
        esac
    done

    echo "$use_index"
}

show_help() {
    cat << EOF
Usage: $0 [OPTIONS]

UGV Raspberry Pi Setup Script

OPTIONS:
    -i, --index    Use alternative package mirrors (Tsinghua University)
    -h, --help     Show this help message

Examples:
    sudo $0              # Standard setup with default sources
    sudo $0 --index      # Setup with alternative mirrors
EOF
}

# Определение параметров системы
detect_system_config() {
    local firmware=""
    local config_path=""
    local cmdline_path=""

    if [[ -e /boot/firmware/config.txt ]]; then
        firmware="/firmware"
    fi

    config_path="/boot${firmware}/config.txt"

    if is_pi; then
        local prefix=""
        if [[ -e /proc/device-tree/chosen/os_prefix ]]; then
            prefix="$(cat /proc/device-tree/chosen/os_prefix)"
        fi
        cmdline_path="/boot${firmware}/${prefix}cmdline.txt"
    else
        cmdline_path="/proc/cmdline"
    fi

    echo "$config_path" "$cmdline_path"
}

# Проверка архитектуры
is_pi() {
    local arch
    arch=$(dpkg --print-architecture)
    [[ "$arch" == "armhf" || "$arch" == "arm64" ]]
}

# Проверка Pi 5
is_pifive() {
    grep -q "^Revision\s*:\s*[ 123][0-9a-fA-F][0-9a-fA-F]4[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$" /proc/cpuinfo
}

# Настройка cmdline.txt
configure_cmdline() {
    local cmdline_path="$1"

    print_info "Configuring cmdline.txt..."

    if [[ ! -w "$cmdline_path" ]]; then
        print_error "No write permission for: $cmdline_path"
        return 1
    fi

    # Создаем backup
    cp "$cmdline_path" "${cmdline_path}.backup"

    # Удаляем параметры консоли
    sed -i -e "s/console=ttyAMA0,[0-9]\+ //" \
           -e "s/console=serial0,[0-9]\+ //" \
           "$cmdline_path"

    print_success "cmdline.txt configured"
}

# Функция для редактирования config.txt
set_config_var() {
    local key="$1"
    local value="$2"
    local config_file="$3"

    lua - "$key" "$value" "$config_file" <<EOF > "${config_file}.bak"
local key=assert(arg[1])
local value=assert(arg[2])
local fn=assert(arg[3])
local file=assert(io.open(fn))
local made_change=false

for line in file:lines() do
    if line:match("^#?%s*"..key.."=.*$") then
        line=key.."="..value
        made_change=true
    end
    print(line)
end

if not made_change then
    print(key.."="..value)
end
EOF

    mv "${config_file}.bak" "$config_file"
}

# Настройка config.txt
configure_system_config() {
    local config_path="$1"

    print_info "Configuring system settings..."

    # Базовая настройка UART
    set_config_var "dtparam" "uart0=on" "$config_path"

    # Отключение Bluetooth (кроме Pi 5)
    if ! is_pifive; then
        if ! grep -q 'dtoverlay=disable-bt' "$config_path"; then
            echo 'dtoverlay=disable-bt' >> "$config_path"
            print_success "Bluetooth disabled in config"
        fi
    else
        print_info "Pi 5 detected - skipping Bluetooth disable"
    fi

    # Отключение сервисов Bluetooth
    if systemctl is-active --quiet hciuart.service; then
        systemctl disable hciuart.service
        print_success "hciuart service disabled"
    fi

    if systemctl is-active --quiet bluetooth.service; then
        systemctl disable bluetooth.service
        print_success "bluetooth service disabled"
    fi
}

# Настройка источников пакетов
configure_package_sources() {
    local use_index="$1"

    if [[ "$use_index" != "true" ]]; then
        print_info "Using default package sources"
        return 0
    fi

    print_info "Configuring alternative package sources..."

    local mirror_url="https://mirrors.tuna.tsinghua.edu.cn"

    # Backup оригинальных файлов
    backup_file "/etc/apt/sources.list"
    backup_file "/etc/apt/sources.list.d/raspi.list"

    # Debian sources
    cat > "/tmp/sources.list" << EOF
deb ${mirror_url}/debian ${RELEASE_NAME} main contrib non-free non-free-firmware
deb ${mirror_url}/debian-security ${RELEASE_NAME}-security main contrib non-free non-free-firmware
deb ${mirror_url}/debian ${RELEASE_NAME}-updates main contrib non-free non-free-firmware
EOF
    mv "/tmp/sources.list" "/etc/apt/sources.list"

    # Raspberry Pi sources
    if [[ -f "/etc/apt/sources.list.d/raspi.list" ]]; then
        echo "deb ${mirror_url}/raspberrypi ${RELEASE_NAME} main" > "/etc/apt/sources.list.d/raspi.list"
    fi

    print_success "Package sources configured to use Tsinghua University mirror"
}

# Backup файла
backup_file() {
    local file="$1"
    local backup="${file}.backup.$(date +%Y%m%d_%H%M%S)"

    if [[ -f "$file" ]]; then
        cp "$file" "$backup"
        print_info "Backup created: $backup"
    fi
}

# Установка пакетов
install_packages() {
    print_info "Updating system and installing packages..."

    # Обновление пакетов
    if ! apt update; then
        print_error "Failed to update package lists"
        return 1
    fi

    if ! apt upgrade -y; then
        print_warning "Some packages failed to upgrade"
    fi

    # Основные пакеты
    local base_packages=(
        libopenblas-dev libatlas3-base libcamera-dev
        python3-opencv portaudio19-dev
        util-linux procps hostapd iproute2 iw
        haveged dnsmasq iptables espeak
    )

    if ! apt install -y "${base_packages[@]}"; then
        print_error "Failed to install base packages"
        return 1
    fi

    print_success "All packages installed successfully"
}

# Настройка Python окружения
setup_python_environment() {
    local use_index="$1"

    print_info "Setting up Python virtual environment..."

    cd "$UGV_DIR" || {
        print_error "Cannot access UGV directory: $UGV_DIR"
        return 1
    }

    # Создание virtual environment
    if ! python -m venv --system-site-packages "$VENV_NAME"; then
        print_error "Failed to create virtual environment"
        return 1
    fi

    # Активация и установка зависимостей
    local pip_index=""
    [[ "$use_index" == "true" ]] && pip_index="-i https://pypi.tuna.tsinghua.edu.cn/simple"

    if [[ -f "requirements.txt" ]]; then
        if ! sudo -H -u "$USER_NAME" bash -c "
            source '${UGV_DIR}/${VENV_NAME}/bin/activate' &&
            pip install --upgrade pip &&
            pip install ${pip_index} -r requirements.txt &&
            deactivate
        "; then
            print_error "Failed to install Python dependencies"
            return 1
        fi
    else
        print_warning "requirements.txt not found - skipping dependency installation"
    fi

    print_success "Python environment setup completed"
}

# Настройка прав доступа
setup_permissions() {
    print_info "Setting up user permissions..."

    # Добавление в группу dialout для serial
    if ! groups "$USER_NAME" | grep -q "dialout"; then
        if usermod -aG dialout "$USER_NAME"; then
            print_success "User added to dialout group"
        else
            print_error "Failed to add user to dialout group"
        fi
    fi
}

# Настройка аудио
setup_audio() {
    local audio_config="${UGV_DIR}/asound.conf"

    print_info "Configuring audio..."

    if [[ -f "$audio_config" ]]; then
        cp -f "$audio_config" "/etc/asound.conf"
        print_success "Audio configuration applied"
    else
        print_warning "Audio configuration file not found: $audio_config"
    fi
}

# Настройка OAK-D камеры
setup_oak_camera() {
    local oak_rules="${UGV_DIR}/99-dai.rules"

    print_info "Setting up OAK-D camera..."

    if [[ -f "$oak_rules" ]]; then
        cp -f "$oak_rules" "/etc/udev/rules.d/99-dai.rules"
        udevadm control --reload-rules
        udevadm trigger
        print_success "OAK-D camera rules installed"
    else
        print_warning "OAK-D rules file not found: $oak_rules"
    fi
}

# Финальные инструкции
show_completion_message() {
    cat << EOF

${GREEN}================================================${NC}
${GREEN}🚀 UGV SETUP COMPLETED SUCCESSFULLY!${NC}
${GREEN}================================================${NC}

${YELLOW}IMPORTANT NEXT STEPS:${NC}

1. ${BLUE}REBOOT REQUIRED:${NC}
   sudo reboot

2. ${BLUE}TEST THE APPLICATION:${NC}
   cd ${UGV_DIR}
   sudo chmod +x autorun.sh
   ./autorun.sh

3. ${BLUE}ENABLE AUTOSTART (optional):${NC}
   Add to crontab: @reboot ${UGV_DIR}/autorun.sh
   Or use: systemctl enable ugv.service

4. ${BLUE}VERIFY HARDWARE:${NC}
   - Check OAK-D camera connection
   - Verify serial devices
   - Test audio output

${YELLOW}QUICK COMMANDS:${NC}
   Status check: systemctl status ugv
   View logs: tail -f /var/log/ugv_setup.log
   Reconfigure: sudo ${UGV_DIR}/$(basename "$0") [options]

${GREEN}Your UGV is ready for development!${NC}
EOF
}

# Главная функция
main() {
    print_info "Starting UGV Raspberry Pi Setup..."
    print_info "Log file: $LOG_FILE"

    # Проверка прав
    check_privileges

    # Парсинг аргументов
    local use_index
    use_index=$(parse_arguments "$@")

    # Определение конфигурации системы
    read -r config_path cmdline_path < <(detect_system_config)

    print_info "Detected system configuration:"
    print_info "  Config: $config_path"
    print_info "  Cmdline: $cmdline_path"
    print_info "  User: $USER_NAME"
    print_info "  UGV Directory: $UGV_DIR"

    # Основные этапы настройки
    configure_cmdline "$cmdline_path"
    configure_system_config "$config_path"
    configure_package_sources "$use_index"
    install_packages
    setup_python_environment "$use_index"
    setup_permissions
    setup_audio
    setup_oak_camera

    show_completion_message
}

# Запуск главной функции
main "$@"
