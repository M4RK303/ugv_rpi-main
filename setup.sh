#!/bin/bash

#  UGV (Unmanned Ground Vehicle):

# Скрипт начинается с shebang (также называемый hashbang) ((hash)!/bin/bash),
# который указывает, что скрипт должен быть выполнен с помощью bash shell (Bourne Again SHell) .
# Должна быть ПЕРВОЙ строкой в файле
# Обязательно должен быть исполняемым файл:
# chmod +x script.sh  -  Делает скрипт исполняемым
# ./script.sh  -   Запуск скрипта


# Проверяет, запущен ли скрипт с правами суперпользователя (root). Если нет,
# то выводится сообщение об ошибке и скрипт завершается.

# $EUID - это переменная среды, которая содержит эффективный идентификатор
# пользователя (Effective User ID). Для root пользователя этот идентификатор
# равен 0. -ne - это оператор сравнения "not equal" (не равно).
# Если условие ложно (то есть пользователь root), то блок после then не выполняется, и скрипт
# переходит к следующей строке. Если пользователь НЕ root, выполняется блок кода внутри then
# exit 1 - завершает скрипт с кодом ошибки 1
# Код 0 означает успех, любое другое число - ошибку

if [ "$EUID" -ne 0 ]; then
    echo "This script must be run with sudo."
    echo "Use 'sudo ./setup.sh' instead of './setup.sh'"
    echo "Exiting..."
    exit 1
fi

# Default value for using other source (Значение по умолчанию для использования другого источника)
# Затем устанавливается переменная use_index в значение false.
# Переменная use_index=false вероятно управляет выбором источника данных или репозитория в дальнейшей логике скрипта.

use_index = false

# Parse command line arguments (Разбор аргументов командной строки)
# $# - количество переданных аргументов
# -gt 0 - проверяет, что количество аргументов БОЛЬШЕ 0
# Цикл продолжается, пока есть необработанные аргументы
# Извлечение текущего аргумента: key="$1"
# $1 - первый аргумент в списке
# Сохраняем его в переменную key для обработки
# Конструкция case для анализа аргумента: case $key in
# Сравнивает значение $key с различными шаблонами
# -i|--index) - обрабатывает оба варианта: короткий (-i) и длинный (--index)
# use_index=true - устанавливает флаг в true
# shift - удаляет обработанный аргумент из списка
# Обработка неизвестных опций:
# *) - шаблон "все остальное"
# shift - критически важная команда, которая "сдвигает" аргументы:
# Было: $1=-i, $2=--index, $3=other_arg
# После shift: $1=--index, $2=other_arg, $# уменьшается на 1
# $0 - автоматически подставляется как имя текущего скрипта

while [[ $# -gt 0 ]]; do
  key = "$1"
  case $key in
    -i|--index)
      use_index = true
      shift
      ;;
    *)
      # Unknown option (Неизвестный вариант)
      echo "Usage: $0 [-i | --index] (to use other source)"
      exit 1
      ;;
  esac
done

# Этот код обрабатывает аргументы командной строки, переданные скрипту.
# Он проверяет каждый аргумент и, если находит опцию -i или --index, устанавливает переменную use_index в true.
# Если встречает любой другой аргумент, выводит сообщение об использовании и завершает скрипт с кодом ошибки 1.
# Поскольку в начале скрипта мы проверяем права root, а затем обрабатываем аргументы, то, вероятно, этот скрипт предназначен для настройки системы и может использовать разные источники данных в зависимости от флага.

# Этот код определяет путь к файлу конфигурации в зависимости от структуры каталогов системы.
# [ -e /path/to/file ] - проверяет, существует ли указанный файл
# /boot/firmware/config.txt - путь к проверяемому файлу

if [ -e /boot/firmware/config.txt ] ; then
  FIRMWARE=/firmware
else
  FIRMWARE=
fi
CONFIG=/boot${FIRMWARE}/config.txt

# На некоторых системах Raspberry Pi:
# Конфиг находится в /boot/firmware/config.txt
# На других - в /boot/config.txt
# Резервное копирование
# cp $CONFIG $CONFIG.backup
# Редактирование конфигурации
# sed -i 's/some_setting=0/some_setting=1/' $CONFIG
# Просмотр конфигурации
# cat $CONFIG

# Мы имеем функцию с именем is_pi, которая проверяет, является ли архитектура, на которой запущен скрипт, одной из двух: armhf или arm64.
# Функция использует команду dpkg --print-architecture для получения архитектуры системы.
# Затем она сравнивает полученное значение с "armhf" и "arm64".
# Проверяет, является ли архитектура:
# armhf - 32-битная ARM архитектура
# arm64 - 64-битная ARM архитектура
# Если архитектура совпадает с одной из этих двух, функция возвращает 0 (что в bash означает истину/успех).
# В противном случае возвращает 1 (ложь/ошибка).
# В bash возвращаемое значение 0 означает успех (истина), а ненулевое (обычно 1) - неудачу (ложь).


is_pi () {
  ARCH=$(dpkg --print-architecture)
  if [ "$ARCH" = "armhf" ] || [ "$ARCH" = "arm64" ] ; then
    return 0
  else
    return 1
  fi
}

# В этом коде мы проверяем, является ли устройство Pi, и в зависимости от этого устанавливаем путь к файлу командной строки (cmdline).
# Если это Pi, то мы проверяем наличие файла /proc/device-tree/chosen/os_prefix, который содержит префикс пути к файлу cmdline.txt.
# Если файл существует, то читаем его содержимое в переменную PREFIX.
# Затем формируем путь CMDLINE как /boot${FIRMWARE}/${PREFIX}cmdline.txt.
# Примечание: переменная FIRMWARE должна быть определена ранее

if is_pi ; then
  if [ -e /proc/device-tree/chosen/os_prefix ]; then
    PREFIX="$(cat /proc/device-tree/chosen/os_prefix)"
  fi
  CMDLINE="/boot${FIRMWARE}/${PREFIX}cmdline.txt"
else
  CMDLINE=/proc/cmdline
fi

# Мы имеем функцию с именем is_pifive, которая проверяет, является ли плата Raspberry Pi 5.
# В Raspberry Pi 5 ревизия кода в /proc/cpuinfo имеет определенный формат, и мы проверяем, что ревизия соответствует шаблону для Pi 5.
# Функция is_pifive ищет в /proc/cpuinfo строку с ревизией, которая соответствует шаблону, и возвращает 0, если такая строка найдена.
# Возвращает код выхода команды grep (0 = найдено, 1 = не найдено)
# ^Revision - строка начинается с "Revision"
# \s*:\s* - двоеточие с возможными пробелами вокруг
# [ 123] - пробел или цифра 1, 2, 3 (тип ревизии)
# [0-9a-fA-F] - шестнадцатеричная цифра
# 4 - буквально цифра 4 (код Raspberry Pi 5)
# [0-9a-fA-F][0-9a-fA-F][0-9a-fA-F] - три шестнадцатеричные цифры
# $ - конец строки

is_pifive() {
  grep -q "^Revision\s*:\s*[ 123][0-9a-fA-F][0-9a-fA-F]4[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F]$" /proc/cpuinfo
  return $?
}


# Команды sed выполняют удаление из файла указанных строковых шаблонов.
# sed -i $CMDLINE -e "s/console=ttyAMA0,[0-9]+ //"
# Заменяет в файле $CMDLINE строку "console=ttyAMA0,<число> " на пустую строку (удаляет).
# Здесь [0-9]+ означает одну или более цифр.
# sed -i $CMDLINE -e "s/console=ttyACM0,[0-9]+ //"
# Аналогично, удаляет "console=ttyACM0,<число> "
# sed -i $CMDLINE -e "s/console=serial0,[0-9]+ //"
# Удаляет "console=serial0,<число> "
# Важно: после удаления этих console параметров, возможно, освобождается место для других настроек или отключается вывод на эти устройства.
# Однако, обратите внимание, что в командах после шаблона есть пробел, который также удаляется.
# Это означает, что в исходном файле после параметра console должен быть пробел, иначе мы можем задеть следующий параметр.
# -i - редактирование файла "на месте" (in-place)
# s/pattern/replacement/ - команда замены
# [0-9]\+ - одна или более цифр (скорость передачи, например 115200)
# Замена на пробел " " - удаляет параметр, сохраняя разделители

# Config cmdline.txt
sed -i $CMDLINE -e "s/console=ttyAMA0,[0-9]\+ //"
sed -i $CMDLINE -e "s/console=ttyACM0,[0-9]\+ //"
sed -i $CMDLINE -e "s/console=serial0,[0-9]\+ //"

# Мы имеем функцию на Lua, которая изменяет или добавляет параметр в конфигурационном файле (config.txt).
# Создает bash-функцию с тремя параметрами: ключ, значение и файл
# lua - - запускает интерпретатор Lua
# "$1" "$2" "$3" - передает аргументы функции в Lua-скрипт
# <<EOF - heredoc для встроенного скрипта Lua
# > "$3.bak" - перенаправляет вывод во временный файл
# Функция set_config_var принимает три аргумента: ключ, значение и файл конфигурации.
# Открытие файла:
# lua
# local file=assert(io.open(fn))
# Открывает файл конфигурации для чтения
# Она читает файл, ищет строку, содержащую ключ (который может быть закомментирован или нет), и заменяет её на новую строку "ключ=значение".
# Если ключ не найден, то он добавляется в конец.


# Config config.txt
set_config_var() {
  lua - "$1" "$2" "$3" <<EOF > "$3.bak"
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
mv "$3.bak" "$3"
}

# Добавление нового параметра:
# Если параметр не был найден, добавляет его в конец
# mv "$3.bak" "$3" Заменяет оригинальный файл обработанной версией

# Затем мы используем эту функцию для установки двух параметров: dtparam=uart0 и dtparam i2c_arm=on.

# set_config_var "dtparam" "uart0=on" "$CONFIG"
# set_config_var "dtparam" "i2c_arm=on" "$CONFIG"

set_config_var dtparam=uart0 on $CONFIG
set_config_var dtparam=i2c_arm on $CONFIG

# dtparam=uart0=on
# Включает UART0 (последовательный порт)
# Нужен для Serial Console или подключения устройств по UART
# -------->
# dtparam=i2c_arm=on
# Включает I2C на GPIO-пинах
# Используется для подключения датчиков и периферии
# -------->
# dtoverlay=disable-bt
# Отключает встроенный Bluetooth
# Освобождает UART для других целей
# Не применяется на Pi 5 (имеет другую архитектуру)


# Добавляем отключение Bluetooth (кроме Pi 5)
# После этого, если мы не на Pi 5 (закомментированная проверка is_pifive), мы добавляем строку 'dtoverlay=disable-bt' в /boot/firmware/config.txt, если её там нет.
# Закомментирована проверка is_pifive, поэтому код добавления dtoverlay=disable-bt выполняется всегда.

if is_pifive ; then
  echo "# pi5: skip step"
else
  echo "# Add dtoverlay=disable-bt to /boot/firmware/config.txt"
if ! grep -q 'dtoverlay=disable-bt' /boot/firmware/    config.txt; then
  echo 'dtoverlay=disable-bt' >> /boot/firmware/config.txt
fi

# dtoverlay=ov5647 (закомментировано)
# Включает поддержку камеры OV5647
# Раскомментировать при наличии такой камеры

# fi

# echo "# Add dtoverlay=ov5647 to /boot/firmware/config.txt"
# if ! grep -q 'dtoverlay=ov5647' /boot/firmware/config.txt; then
#   echo 'dtoverlay=ov5647' >> /boot/firmware/config.txt
# fi

# Отключение служб Bluetooth
# Отключаем службы hciuart (для UART Bluetooth) и bluetooth (сам Bluetooth).
# Это предотвратит автоматический запуск этих служб при загрузке системы.
# disable - отключает автозапуск, но службу можно запустить вручную

sudo systemctl disable hciuart.service
sudo systemctl disable bluetooth.service

# Скрипт, который в зависимости от флага use_index (который устанавливается через аргументы командной строки) меняет источники пакетов на зеркала от TUNA (Tsinghua University) или оставляет по умолчанию.
# Если use_index истинно, то:
# a. Создаем резервные копии файлов sources.list и raspi.list, если они еще не созданы.
# b. Записываем новые источники в /etc/apt/sources.list и /etc/apt/sources.list.d/raspi.list.
# c. Обновляем список пакетов.

# Change sources

if $use_index; then
  # Backup the original sources.list file
  if ! [ -e /etc/apt/sources.list.bak ]; then
    sudo cp /etc/apt/sources.list /etc/apt/sources.list.bak
  fi

  # Create a new sources.list file with other mirrors, keeping the release name "bookworm"

  echo "Updating sources.list with other mirrors..."
  sudo sh -c 'echo "deb https://mirrors.tuna.tsinghua.edu.cn/debian bookworm main contrib non-free non-free-firmware\ndeb https://mirrors.tuna.tsinghua.edu.cn/debian-security bookworm-security main contrib non-free non-free-firmware\ndeb https://mirrors.tuna.tsinghua.edu.cn/debian bookworm-updates main contrib non-free non-free-firmware" > /etc/apt/sources.list'


  if ! [ -e /etc/apt/sources.list.d/raspi.list.bak ]; then
    sudo cp /etc/apt/sources.list.d/raspi.list /etc/apt/sources.list.d/raspi.list.bak
  fi

  sudo sh -c 'echo "deb https://mirrors.tuna.tsinghua.edu.cn/raspberrypi bookworm main" > /etc/apt/sources.list.d/raspi.list'


  # Update the package list
  echo "Updating package list..."
  sudo apt update

  echo "Done! Your sources.list has been updated with Aliyun mirrors while keeping the release name 'bookworm'."
else
  echo "# Using default sources."
fi

# Установка программного обеспечения через apt

# Install required software

echo "=== Installing Required Software ==="
# Обновление пакетного менеджера
sudo apt update
# Установка обновлений системы
sudo apt upgrade -y

# Установка основных зависимостей:
# Пакеты и их назначение:
# libopenblas-dev - библиотека для высокопроизводительных линейных алгебраических операций
#  -  Используется в машинном обучении и научных вычислениях
#  -  Альтернатива BLAS/LAPACK с оптимизацией для многопоточности
# libatlas3-base - автоматически настраиваемая система линейной алгебры
#  -  Базовая версия библиотек BLAS и LAPACK
#  -  Используется для математических вычислений
# libcamera-dev - библиотека для работы с камерами в Linux
#  -  Особенно важна для Raspberry Pi Camera Module
#  -  Предоставляет API для управления камерами
# python3-opencv - библиотека компьютерного зрения для Python 3
#  -  Обработка изображений и видео
#  -  Распознавание объектов, машинное обучение
#  -  Работа с камерами и видеопотоками
# portaudio19-dev - библиотека для аудио ввода/вывода
#  -  Используется для записи и воспроизведения звука
#  -  Необходима для аудиоприложений и голосовых интерфейсов


sudo apt install -y libopenblas-dev libatlas3-base libcamera-dev python3-opencv portaudio19-dev
sudo apt install -y util-linux procps hostapd iproute2 iw haveged dnsmasq iptables espeak

# Пакеты и их назначение:
# util-linux - набор системных утилит Linux
#  -  Содержит команды like mount, fdisk, dmesg
# procps - утилиты для мониторинга процессов
#  -  Содержит ps, top, free, vmstat
# hostapd - демон для создания точки доступа Wi-Fi
#  -  Превращает Raspberry Pi в Wi-Fi роутер
#  -  Используется для создания беспроводных сетей
# iproute2 - современные сетевые утилиты
#  -  Замена устаревшим ifconfig, route
#  -  Содержит ip, ss, tc
# iw - утилиты для настройки беспроводных сетей
#  -  Настройка Wi-Fi интерфейсов
#  -  Сканирование сетей, управление режимами
# haveged - демон для увеличения энтропии системы
#  -  Улучшает генерацию случайных чисел
#  -  Важно для криптографических операций
# dnsmasq - легкий DNS и DHCP сервер
#  -  Используется для раздачи IP-адресов в локальной сети
#  -  Кэширование DNS-запросов
# iptables - система фильтрации сетевых пакетов
#  -  Фаервол для настройки правил сети
#  -  NAT, перенаправление портов
# espeak - синтезатор речи
#  -  Преобразование текста в речь
#  -  Используется в голосовых интерфейсах и доступности

# Проекты компьютерного зрения:
# Для работы с камерами и обработки изображений
# libcamera-dev python3-opencv

# Создание точки доступа Wi-Fi:
# Для превращения RPi в роутер
# hostapd dnsmasq iptables

# Машинное обучение на edge-устройствах:
# Для нейросетей и математических вычислений
# libopenblas-dev libatlas3-base

# Голосовые приложения:
# Для работы со звуком и речью
# portaudio19-dev espeak




# Код создания и активации Python виртуального окружения
# Создаем виртуальное окружение Python с именем ugv-env, используя системные сайт-пакеты (флаг --system-site-packages).
# Затем мы активируем это виртуальное окружение.

echo "# Create a Python virtual environment."
# Create a Python virtual environment

cd $PWD
# Создание виртуального окружения:
# Создает изолированную среду Python
#  --system-site-packages дает доступ к системным пакетам
python -m venv --system-site-packages ugv-env

echo "# Activate a Python virtual environment."
# Активируем и устанавливаем зависимости
echo "# Install dependencies from requirements.txt"
# Install dependencies from requirements.txt
if $use_index; then
  sudo -H -u $USER bash -c 'source $PWD/ugv-env/bin/activate && pip install -i https://pypi.tuna.tsinghua.edu.cn/simple -r requirements.txt && deactivate'
else
  sudo -H -u $USER bash -c 'source $PWD/ugv-env/bin/activate && pip install -r requirements.txt && deactivate'
fi

# Код добавления пользователя в группу dialout для работы с serial-портами (последовательным портам)

echo "# Add current user to group so it can use serial."
sudo usermod -aG dialout $USER

# Группа dialout:
# Предоставляет доступ к последовательным портам (serial ports)

# Дополнительные группы для разработки
# local groups=("dialout" "gpio" "i2c" "spi")



# Audio Config
# скопировать файл asound.conf из домашней директории пользователя в /etc/

echo "# Audio Config."
sudo cp -v -f /home/$(logname)/ugv_rpi/asound.conf /etc/asound.conf



# OAK Config
# Копирует правила udev для предоставления прав доступа к OAK-D камере
# копируем файл правил udev для устройства OAK (DepthAI) и затем перезагружаем правила udev.
# Файл 99-dai.rules содержит правила для предоставления прав доступа к устройствам OAK (например, камерам) обычным пользователям.
# После копирования правил мы перезагружаем правила udev и запускаем триггер для применения изменений без перезагрузки.
# Этот код обеспечивает правильную настройку прав доступа к OAK-D камере, которая является ключевым компонентом системы компьютерного зрения в проектах автономных наземных транспортных средств (UGV).

# Копируем правила udev для OAK-D камеры
sudo cp -v -f /home/$(logname)/ugv_rpi/99-dai.rules /etc/udev/rules.d/99-dai.rules

# Перезагружаем правила udev
sudo udevadm control --reload-rules

# Активируем новые правила без перезагрузки
sudo udevadm trigger

# Для проектов UGV OAK-D используется для:
#  - Компьютерного зрения - обнаружение объектов и навигация
#  - Глубинного восприятия - 3D карта окружения
#  - Слежения за объектами - отслеживание целей
#  - Навигации - избегание препятствий
#  - Картографирования - построение карты местности


echo "Setup completed. Please to reboot your Raspberry Pi for the changes to take effect."
echo "Use the command below to run app.py onboot."
echo "sudo chmod +x autorun.sh"
echo "./autorun.sh"

echo ""
echo "========================"
echo "  UGV Setup Complete!   "
echo "========================"

while true; do
    echo ""
    echo "What would you like to do next?"
    echo "1) Reboot now"
    echo "2) Test autorun script"
    echo "3) Show system status"
    echo "4) Exit and reboot later"
    echo ""
    read -p "Enter your choice [1-4]: " choice

    case $choice in
        1)
            echo "Rebooting system..."
            sudo reboot
            ;;
        2)
            echo "Testing autorun script..."
            sudo chmod +x autorun.sh
            ./autorun.sh
            ;;
        3)
            echo "System status:"
            echo "Python env: $(if [ -d 'ugv-env' ]; then echo 'OK'; else echo 'MISSING'; fi)"
            echo "OAK-D rules: $(if [ -f '/etc/udev/rules.d/99-dai.rules' ]; then echo 'OK'; else echo 'MISSING'; fi)"
            echo "Audio config: $(if [ -f '/etc/asound.conf' ]; then echo 'OK'; else echo 'MISSING'; fi)"
            ;;
        4)
            echo "Exit selected."
            echo "Remember to reboot later with: sudo reboot"
            break
            ;;
        *)
            echo "Invalid option. Please try again."
            ;;
    esac
done
