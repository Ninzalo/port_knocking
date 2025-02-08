#!/bin/bash

# Проверка наличия всех аргументов
if [ $# -ne 4 ]; then
    echo "Usage: sh $0 <target_ip> <target_port> <target_username> <port_open_seq>"
    echo "Example: sh $0 111.11.11.111 2222 username 7000,8000,9000"
    exit 1
fi

# Запрос пароля с безопасным вводом
read -sp "Enter password for your new user (not root): " username_password
echo  # Переход на новую строку после ввода пароля

# Параметры
target_ip="$1"
target_port="$2"
target_username="$3"
port_open_seq="$4"

# Проверка введенного пароля
if [ -z "$username_password" ]; then
    echo -e "\nError: Password cannot be empty" >&2
    exit 1
fi

# Генерация закрывающей последовательности портов
IFS=',' read -ra ports <<< "$port_open_seq"
port_close_seq=""
for ((i=${#ports[@]}-1; i>=0; i--)); do
    [ -n "$port_close_seq" ] && port_close_seq+=","
    port_close_seq+="${ports[i]}"
done

# ==============================================
# Функции валидации и утилиты
# ==============================================

validate_ip() {
    local ip=$1
    [[ $ip =~ ^[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}\.[0-9]{1,3}$ ]] && 
    IFS='.' read -ra ip_parts <<< "$ip" &&
    [[ ${ip_parts[0]} -le 255 && ${ip_parts[1]} -le 255 && 
       ${ip_parts[2]} -le 255 && ${ip_parts[3]} -le 255 ]]
}

validate_port() {
    [[ $1 =~ ^[0-9]+$ ]] && (( $1 >= 1 && $1 <= 65535 ))
}

check_remote_command() {
    ssh -q -o BatchMode=yes -o ConnectTimeout=5 root@$target_ip exit
}

check_if_port_open() {
    echo "Checking port status..."
    if ! nc -z -w5 "$target_ip" "$target_port"; then
        echo "Error: Port $target_port not opened after knocking" >&2
        exit 1
    fi
}

check_if_port_closed() {
    echo "Verifying port closure..."

    # Добавляем задержку для применения правил iptables
    sleep 2

    # Проверяем порт с помощью netcat и nmap
    local max_retries=3
    local success=0

    for ((i=1; i<=max_retries; i++)); do
        # Проверка через netcat
        if ! nc -z -w 3 "$target_ip" "$target_port"; then
            success=1
            break
        fi
        
        # Дополнительная проверка через nmap с определением состояния
        nmap_result=$(nmap -Pn -p "$target_port" "$target_ip" | grep "$target_port/tcp")
        if [[ ! $nmap_result =~ "closed" && ! $nmap_result =~ "filtered" ]]; then
            echo "Warning: Port $target_port appears open (attempt $i)"
            sleep 1
        else
            success=1
            break
        fi
    done

    if (( success == 0 )); then
        echo "Error: Port $target_port remains open after closing sequence" >&2
        exit 1
    fi

    # Проверка через SSH
    ssh_timeout=5
    if ssh -p "$target_port" -o ConnectTimeout=$ssh_timeout -q "$target_username@$target_ip" exit; then
        echo "Error: SSH connection still active after port closure" >&2
        exit 1
    fi

    echo "Port $target_port successfully closed"
}

# Валидация IP
if ! validate_ip "$target_ip"; then
    echo "Error: Invalid IP address format" >&2
    exit 1
fi

# Валидация портов
if ! validate_port "$target_port"; then
    echo "Error: Invalid target port" >&2
    exit 1
fi

IFS=',' read -ra open_ports <<< "$port_open_seq"
for port in "${open_ports[@]}"; do
    if ! validate_port "$port"; then
        echo "Error: Invalid port in sequence: $port" >&2
        exit 1
    fi
    if (( port == target_port )); then
        echo "Error: Knock sequence contains target port ($target_port)" >&2
        exit 1
    fi
done

# Проверка зависимостей
for cmd in sshpass ssh scp nmap nc; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "Error: Required command '$cmd' not found" >&2
        exit 1
    fi
done

# Проверка наличия change_value.sh
if [[ ! -f "./change_value.sh" ]]; then
    echo "Error: change_value.sh not found in current directory" >&2
    exit 1
fi

# Проверка доступа root
echo -n "Checking root access... "
if ! check_remote_command; then
    echo -e "\nError: Failed to connect to root@$target_ip" >&2
    echo "Verify: 1) IP 2) SSH keys 3) Network" >&2
    exit 1
fi
echo "OK"

# Проверка существования пользователя
if ssh root@$target_ip "getent passwd $target_username" &>/dev/null; then
    echo "Error: User $target_username already exists" >&2
    exit 1
fi

# ==============================================
# Основной скрипт
# ==============================================

function remote_change_value() {
    local ssh_port=$1 file=$2 key=$3 value=$4
    if ! scp -P "$ssh_port" -q ./change_value.sh "$target_username@$target_ip:/tmp/"; then
        echo "Error: Failed to copy change_value.sh (port $ssh_port)" >&2
        exit 1
    fi
    ssh -p "$ssh_port" "$target_username@$target_ip" \
        "sudo chmod +x /tmp/change_value.sh && sudo /tmp/change_value.sh '$file' '$key' '$value' && rm /tmp/change_value.sh" || {
        echo "Error: Failed to modify $file via port $ssh_port" >&2
        exit 1
    }
}

knock_ports() {
    local sequence=$1
    echo "Knocking sequence: $sequence"
    IFS=',' read -ra ports <<< "$sequence"
    for port in "${ports[@]}"; do
        nmap -Pn --host-timeout 100 --max-retries 0 -p "$port" "$target_ip" > /dev/null 2>&1
        sleep 0.5
    done
}

echo "=== Starting Port Knocking Setup ==="

# 1. Создание пользователя и базовая настройка SSH
{
echo "Step 1/10: Creating user and SSH setup..."
ssh -T root@$target_ip <<EOF
apt-get update
apt-get upgrade -y
apt-get -y install sudo

# Удаление предыдущего пользователя если существует
if getent passwd "$target_username" >/dev/null; then
    userdel -rf "$target_username" || rm -rf "/home/$target_username"
fi

# Создание пользователя с проверкой домашней директории
if ! adduser --disabled-password --gecos "" "$target_username" --force-badname; then
    echo "Failed to create user" >&2
    exit 1
fi

# Установка пароля
if ! echo "$target_username:$username_password" | chpasswd; then
    echo "Failed to set password" >&2
    exit 1
fi

# Настройка sudo
if ! usermod -aG sudo "$target_username" || 
   ! echo "$target_username ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/"$target_username" ||
   ! chmod 440 /etc/sudoers.d/"$target_username"; then
    echo "Failed to configure sudo" >&2
    exit 1
fi

# Проверка синтаксиса перед перезапуском
if ! sshd -t; then
    echo "Invalid SSH configuration" >&2
    exit 1
fi

systemctl restart ssh
EOF
} || exit 1

# 2. Копирование SSH-ключа
{
echo "Step 2/10: Copying SSH key..."
cat ~/.ssh/id_rsa.pub | ssh root@$target_ip \
    "mkdir -p /home/$target_username/.ssh && 
    cat >> /home/$target_username/.ssh/authorized_keys && 
    chmod 700 /home/$target_username/.ssh && 
    chmod 600 /home/$target_username/.ssh/authorized_keys && 
    chown -R $target_username:$target_username /home/$target_username/.ssh"
} || exit 1

# 3. Настройка SSH-доступа
{
echo "Step 3/10: Setting up SSH access..."
sshpass -p "$username_password" ssh-copy-id -f -o StrictHostKeyChecking=no -o PasswordAuthentication=yes "$target_username@$target_ip"
} || exit 1

# 4. Защита SSH
{
echo "Step 4/10: Securing SSH..."
remote_change_value 22 /etc/ssh/sshd_config PasswordAuthentication no
remote_change_value 22 /etc/ssh/sshd_config PermitRootLogin no
remote_change_value 22 /etc/ssh/sshd_config Port "$target_port"
remote_change_value 22 /etc/ssh/sshd_config AllowUsers "$target_username"

ssh -p 22 "$target_username@$target_ip" "sudo sshd -t && sudo systemctl restart ssh" || {
    echo "SSH configuration test failed" >&2
    exit 1
}

# Проверка доступности нового порта
for i in {1..5}; do
    if nc -z -w3 "$target_ip" "$target_port"; then
        break
    fi
    sleep 2
    [[ $i == 5 ]] && { echo "Port $target_port not accessible" >&2; exit 1; }
done

} || exit 1

# 5. Установка пакетов
{
echo "Step 5/10: Installing packages..."
ssh -p "$target_port" "$target_username@$target_ip" \
    "sudo apt update && sudo apt upgrade -y && 
    sudo apt install -y knockd iptables iptables-persistent"
} || exit 1

# 6. Определение интерфейса
{
echo "Step 6/10: Detecting interface..."
interface=$(ssh -p "$target_port" "$target_username@$target_ip" \
    "ip -o link show | awk -F': ' '/state UP/ {print \$2; exit}'")
} || exit 1

# 7. Настройка knockd
{
echo "Step 7/10: Configuring knockd..."
remote_change_value "$target_port" /etc/default/knockd START_KNOCKD 1
remote_change_value "$target_port" /etc/default/knockd KNOCKD_OPTS "-i $interface"

ssh -p "$target_port" "$target_username@$target_ip" <<EOF
sudo bash -c 'cat > /etc/knockd.conf <<KNOCKD_CFG
[options]
    UseSyslog
    Interface = $interface

[openSSH]
    sequence    = $port_open_seq
    seq_timeout = 5
    command     = /sbin/iptables -I INPUT 1 -s %IP% -p tcp --dport $target_port -j ACCEPT
    tcpflags    = syn

[closeSSH]
    sequence    = $port_close_seq
    seq_timeout = 5
    command     = /sbin/iptables -D INPUT -s %IP% -p tcp --dport $target_port -j ACCEPT
    tcpflags    = syn
KNOCKD_CFG'

# Принудительная перезагрузка knockd
sudo pkill knockd || true
sudo systemctl restart knockd
sudo systemctl enable knockd
EOF
} || exit 1

# 8. Настройка iptables
{
echo "Step 8/10: Configuring iptables..."
ssh -p "$target_port" "$target_username@$target_ip" <<EOF
sudo iptables -F
sudo iptables -A INPUT -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
sudo iptables -A INPUT -p tcp --dport $target_port -j REJECT
sudo iptables-save | sudo tee /etc/iptables/rules.v4 >/dev/null
EOF
} || exit 1

# 9. Проверка
{
echo "Step 9/10: Testing..."

# Проверка закрытия порта
check_if_port_closed

knock_ports "$port_open_seq"

# Проверка открытия порта
check_if_port_open

# Подключение
echo "Connecting..."
ssh -o ConnectTimeout=10 -p "$target_port" "$target_username@$target_ip" "echo 'Connection successful!'"

# Закрытие порта
knock_ports "$port_close_seq"

# Проверка закрытия порта
check_if_port_closed
} || exit 1

# Завершение работы
echo "=== Port Knocking Setup Completed ==="
echo "Your username: $target_username"
echo "Your password: (hidden)"
echo "Your IP address: $target_ip"
echo "Your target port: $target_port"
echo "Open ports sequence: $port_open_seq"
echo "Close ports sequence: $port_close_seq"
