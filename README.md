# autoXRAY - личный ВПН сервер
Bash-скрипт для автоматической настройки ядра [Xray](https://github.com/XTLS/Xray-core). Предназначен для удобного получения актуальных конфигураций VPN для семейного/личного использования, настраивает selfsteal VLESS [XHTTP](https://github.com/XTLS/Xray-core/discussions/4113#discussioncomment-11468947) / [RAW](https://github.com/XTLS/REALITY/blob/main/README.en.md) REALITY.

===========================================================================

## Конфигурация с клиентским конфигом для РФ (рекомендуется)
Будем использовать маскировку под собственный сайт (selfsteal), который крутится на вашем же VPS. 

Для установки надо арендовать VPS и получить домен.

Автоматически перенаправляет весь ру трафик напрямую.
```bash

bash -c "$(curl -L https://raw.githubusercontent.com/v0vc/autoXRAY/main/autoXRAY1.sh)" -- вашДОМЕН.com
```

**Вы получите:**
1) vless RAW reality VISION на 443 порту - хорошая маскировка, быстрый.
2) Hysteria2 на 8080 порту

===========================================================================

## Получаем домен

**Получаем бесплатный поддомен**: регестрируемся в [cloudns](https://www.cloudns.net/aff/id/1919804/). Далее: Управление -> DNS Хостинг -> Создать зону -> Свободная зона -> вводим рандомное имя для поддомена.
Теперь надо создать A-запись: Новая запись -> Тип А -> Хост (имя субдомена) -> Указывает на (IP адрес вашего VPS).

Еще бесплатный поддомен можно получить тут: https://www.duckdns.org/ или https://freedns.afraid.org/

Помните, что DNS-записи обновляются не сразу: иногда это занимает 15 минут, иногда — час и более. Проверить - [xseo.in/dns](https://xseo.in/dns).

## Настройка VPN
**Скопируйте конфиг (страничка подписки) в специализированное приложение:**

- iOS/macOS: [Happ](https://www.happ.su/main/ru) или [v2rayTun](https://v2raytun.com/) | (FoXray, Hiddify)
- Android: [Happ](https://www.happ.su/main/ru) или [v2rayTun](https://v2raytun.com/) | (v2rayNG, SimpleXray)
- Windows: [Happ](https://www.happ.su/main/ru) или [winLoadXray](https://github.com/xVRVx/winLoadXRAY/releases/latest/download/winLoadXRAY.exe) или [v2rayN](https://github.com/2dust/v2rayN/releases/) | (v2rayTun, Throne, Hiddify)
- Linux: [Happ](https://www.happ.su/main/ru) или [v2rayN](https://github.com/2dust/v2rayN/releases/) | (Throne, Hiddify)

() - не поддерживают клиентский конфиг, только vless:// (конфиг для роутера).


===========================================================================

## Пояснение и рекомендации

Сейчас в сети много инструкций по установке GUI-панелей, таких как PasarGuard, 3x-ui или новая RemnaWave. Однако все они избыточны для домашнего использования, так как предназначены для крупных проектов и отличаются высокой сложностью настройки (также используют ядро xray). 

Мануал, который необходимо пройти до получения первого рабочего конфига, занимает более 10 страниц. 
Кроме того, подходящий конфиг для Xray нужно ещё поискать и правильно настроить — с этим отлично справляется данный скрипт.

Без GUI и базы данных Xray потребляет меньше ресурсов сервера и отлично подходит для запуска на слабых VPS-конфигурациях!

При каждом запуске autoXRAY генерирует новые UUID, ключи и пароли для защиты пользователей.

**Преимущества selfsteal**
- Сайт всегда работает на вашем ВПС - устраняется точка отказа.
- Ниже пинг - быстрее соединение.
- Не используются CDN, которые есть на многих популярных сайтах.
- Лучше маскировка - т.к. сайт находится в той же сети что и сервер.

**Перейти на алгоритм BBR**
Текущий скрипт автоматически настраивает включение BBR.
Если у вас много одновременных подключений, то можно включить алгоритм BBR (от гугла) - поможет повысить пропускную способность VPN.
Проверка текущего алгоритма: sysctl net.ipv4.tcp_congestion_control


## Как обновить autoXRAY

**Весь скрипт**: если пользуетесь подпиской, то запомните ее ссылку, переустановите скрипт и поменяйте путь на старый в /var/www/домен/xxxXXXxxx.json после этого обновите подписку в приложении.
Если только ключами, то такой возможности нет. P.S.: удобно воспользоваться QR-кодом для переноса на мобильное устройство.

**Только ядро**
```bash
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ install
```
**Обновить WARP-cli**
```bash
bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) v
```

## Как удалить скрипт
**Удаляем nginx & certbot**
```
systemctl disable nginx certbot; systemctl stop nginx certbot; apt remove nginx certbot -y
```

**Удаляем WARP-cli**
```
echo -e "y" | bash <(curl -fsSL https://gitlab.com/fscarmen/warp/-/raw/main/menu.sh) u
```

**Удаляем XRAY**
```
bash -c "$(curl -L https://github.com/XTLS/Xray-install/raw/main/install-release.sh)" @ remove --purge
```

## Создание конфигов для нескольких пользователей

Это не нужно, потому что одним конфигом могут пользоваться сразу несколько человек, а чтобы управлять пользователями, следить за их трафиком нужны уже gui панели: 3x-ui или Remnawave, PasarGuard.

## Смена паролей и сайта маскировки

Запустите скрипт заново - он сформирует новые конфигурации VPN для YouTube, chatGPT и других нужных сайтов.

## Повышенная маскировка

Настоятельно рекомендуется: сменить порт ssh со стандартного 22 на другой и/или сделать вход на сервер по ключу. Настроить файрвол и оставить открытыми порты для работы скрипта: ваш ssh порт, 80 для certbot, 443, 8443, 10443 для xray, 2408 для warp

Если вы хотите погрузиться в дело конфигурации xray есть отличный [справочник](https://xtls.github.io/ru/config/outbounds/vless.html) и [руководство](https://github.com/XTLS/Xray-core/discussions/3518).

Редактировать конфиг можно тут: **/usr/local/etc/xray/config.json**

После изменений ядро надо перезапустить: **systemctl restart xray**

===========================================================================

**Если вы хотите пускать YouTube через ruVPS (у вас он без ТСПУ или вы поставили и настроили [zapret4rocket](https://github.com/IndeecFOX/zapret4rocket))**

Тогда в конфиге ruVPS, который лежит /usr/local/etc/xray/config.json надо добавить в секцию "domain": [сюда], "outboundTag": "direct"
```bash
"geosite:youtube",
"youtube.com",
"googlevideo.com",
"ytimg.com",
"ggpht.com",
```
и перезапустить ядро: **systemctl restart xray**

===========================================================================

## Отключение или рекдактирование маршрутов WARP-cli
В конфиге /usr/local/etc/xray/config.json находим 
```bash
	{
	  "outboundTag": "warp",
	  "domain": ["2ip.io","habr.com","geosite:google-gemini","geosite:canva","geosite:openai","geosite:whatsapp","geosite:category-ru"]
	}
```
**Чтобы отключить**: меняем "outboundTag": "warp" на "outboundTag": "direct"


**Чтобы рекдактировать**: меняем строку "domain"

После изменений ядро надо перезапустить: **systemctl restart xray**

После этого можно удалить WARP-cli, если это необходимо.

**Если возникла ошбика при установке WARP** - [читайте инструкцию.](https://github.com/xVRVx/autoXRAY/blob/main/test/warp-readme.md)

Скрипты будут дорабатываться до актуального состояния.

**[Поддержать автора.](https://pay.trybit.com/pos/Weu1Y0fOhLho0nte)**
