#!/bin/bash

# Проверка аргументов
if [ $# -ne 4 ]; then
    echo "Usage: sh $0 <target_username> <target_ip> <target_port> <port_open_seq>"
    echo "Example: sh $0 username 111.11.11.111 2222 7000,8000,9000"
    exit 1
fi

target_username="$1"
target_ip="$2"
target_port="$3"
port_open_seq="$4"
port_close_seq=$(echo "$port_open_seq" | awk -F, '{OFS=ORS=","; for(i=NF;i>=1;i--) printf "%s%s",$i,(i>1?OFS:"")}' | sed 's/,$//')

# Проверка зависимостей
check_deps() {
    for cmd in nmap ssh; do
        if ! command -v "$cmd" &> /dev/null; then
            echo "Error: Required command '$cmd' not found"
            exit 1
        fi
    done
}

# Функция для knocking портов
knock_ports() {
    local sequence=$1
    echo "Knocking sequence: $sequence"
    IFS=',' read -ra ports <<< "$sequence"
    for port in "${ports[@]}"; do
        nmap -Pn --host-timeout 100 --max-retries 0 -p "$port" "$target_ip" > /dev/null 2>&1
        sleep 0.5
    done
}

# Основная функция
connect() {
    # Выполняем knocking для открытия
    knock_ports "$port_open_seq"
    
    # Проверяем доступность порта
    echo -n "Checking port $target_port... "
    if ! nc -z -w3 "$target_ip" "$target_port"; then
        echo "Failed! Port not opened."
        exit 1
    fi
    echo "OK"
    
    # Подключаемся по SSH
    echo "Connecting to $target_username@$target_ip:$target_port"
    ssh -o ConnectTimeout=10 -p "$target_port" "$target_username@$target_ip"
    
    # Выполняем knocking для закрытия после отключения
    echo "Closing port..."
    knock_ports "$port_close_seq"
}

# Обработчик прерывания для гарантированного закрытия
trap 'echo "Interrupted! Closing port..."; knock_ports "$port_close_seq"; exit 1' INT

# Запуск
check_deps
connect
