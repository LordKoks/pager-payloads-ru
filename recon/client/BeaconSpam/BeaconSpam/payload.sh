#!/bin/bash
. /root/payloads/library/nullsec-ui.sh
# Title: Спам маяков
# Author: bad-antics
# Description: Массовый спам маяков с пользовательскими сообщениями
# Category: nullsec

# Autodetect the right wireless interface (exports $IFACE).
# Falls back to showing the pager error dialog if nothing is plugged in.
. /root/payloads/library/nullsec-iface.sh 2>/dev/null || . "$(dirname "$0")/../../../lib/nullsec-iface.sh"
nullsec_require_iface || exit 1

PROMPT "СПАМ МАЯКОВ

Массовое вещание маяков
кадров с пользовательскими
SSID сообщениями.

Заполните список WiFi
вашими пользовательскими сообщениями!

Нажмите OK для настройки."

PROMPT "ВЫБЕРИТЕ ПАКЕТ СООБЩЕНИЙ:

1. Хакерские сообщения
2. Любовные сообщения
3. Цитаты из фильмов
4. Предупреждающие сообщения
5. Коллекция мемов
6. Пользовательское сообщение

Введите номер на следующем экране."

PACK=$(NUMBER_PICKER "Пакет (1-6):" 1)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) PACK=1 ;; esac

rm -f /tmp/beacon_ssids.txt

case $PACK in
    1) # Hacker
cat > /tmp/beacon_ssids.txt << 'SSIDLIST'
>>> ВЗЛОМАНО NULLSEC <<<
Вы были взломаны
Все ваши WiFi принадлежат нам
Пароль password123
Бесплатный вирус скачать здесь
Фургон наблюдения ФБР #42
Мобильный отряд АНБ 7
Ваш принтер заражен вирусом
sudo rm -rf /*
while(true){fork();}
Загрузка вируса... 100%
Взломай планету!
SSIDLIST
        ;;
    2) # Love
cat > /tmp/beacon_ssids.txt << 'SSIDLIST'
Ты выйдешь за меня?
Я люблю тебя Сара
Позвони мне, может
WiFi одиноких сердец
Ищу любовь
Одинок и готов общаться
Свайп вправо на этой точке
Розы красные WiFi бесплатный
Будь моим Валентином
SSIDLIST
        ;;
    3) # Movies
cat > /tmp/beacon_ssids.txt << 'SSIDLIST'
Ты не пройдешь!
Люк, я твой роутер
Да пребудет с тобой WiFi
Ложки нет
Я Грут
Быть WiFi или не быть
Ходор Ходор Ходор
Зима близко
Это СПАРТА-сеть!
Я вижу мертвые пакеты
SSIDLIST
        ;;
    4) # Warnings
cat > /tmp/beacon_ssids.txt << 'SSIDLIST'
!!! ВИРУС ОБНАРУЖЕН !!!
ЗВОНИТЕ 1-800-ВЗЛОМАНО СЕЙЧАС
Ваш ПК заражен
Предупреждение: найден малварь
Система скомпрометирована
Идет утечка данных
Уровень тревоги безопасности 5
Активен вымогатель
Фаервол взломан
Система экстренных оповещений
SSIDLIST
        ;;
    5) # Memes
cat > /tmp/beacon_ssids.txt << 'SSIDLIST'
Этот WiFi ложь
Никогда не брошу тебя
Один не просто WiFi
Это больше 9000 Мбит/с!
Много WiFi очень подключиться
Харамбе живет здесь
Спрячьте детей спрячьте WiFi
WiFi.exe остановлен
Сеть одобрена догом
Стонкс только вверх
SSIDLIST
        ;;
    6) # Custom
        CUSTOM_MSG=$(TEXT_PICKER "Пользовательский SSID:" "ВЗЛОМАНО")
        for i in $(seq 1 20); do
            echo "$CUSTOM_MSG" >> /tmp/beacon_ssids.txt
        done
        ;;
esac

DURATION=$(NUMBER_PICKER "Длительность (секунды):" 300)
case $? in $DUCKYSCRIPT_CANCELLED|$DUCKYSCRIPT_REJECTED) DURATION=300 ;; esac

COUNT=$(wc -l < /tmp/beacon_ssids.txt)

resp=$(CONFIRMATION_DIALOG "Запустить спам маяков?

Пакет: $PACK
Сообщения: $COUNT
Длительность: ${DURATION}с

Нажмите OK для начала!")
[ "$resp" != "$DUCKYSCRIPT_USER_CONFIRMED" ] && exit 0

LOG "Запуск спама маяков..."

if command -v mdk4 >/dev/null 2>&1; then
    mdk4 $IFACE b -f /tmp/beacon_ssids.txt -c 1,6,11 &
elif command -v mdk3 >/dev/null 2>&1; then
    mdk3 $IFACE b -f /tmp/beacon_ssids.txt -c 1,6,11 &
else
    ERROR_DIALOG "Требуется mdk3/mdk4!"
    exit 1
fi

PROMPT "СПАМ МАЯКОВ АКТИВЕН

Вещание $COUNT SSID

Проверьте ближайшие списки WiFi!

Нажмите OK для остановки."

killall mdk4 mdk3 2>/dev/null

PROMPT "СПАМ МАЯКОВ ОСТАНОВЛЕН

Длительность: ${DURATION}с
Сообщения: $COUNT

Нажмите OK для выхода."
