
### Возможности сетевого транспорта логов

Наверняка многие считают, что journald, в отличие от многих реализаций syslogd,
не умеет передавать логи по сети и ограничен исключительно локальной их обработкой.
Однако, это не совсем так. Сам по себе `systemd-journald`, действительно, ничего
не знает про сеть и пишет либо в syslog-совместимый сокет, либо в файлы нативного
формата. Тем не менее, в комплекте поставки systemd существуют три вспомогательные
утилиты, с помощью которых и реализуется передача логов по сети в реальном времени
"своими силами".

*Важное замечание: эти утилиты работают исключительно с логфайлами на диске (т. е.
в нулевом приближении они похожи на `tail -f | netcat`). Поэтому для того, чтобы
передавать логи по сети средствами journald, необходимо включить запись файлов в
нативном формате --- хотя бы в режиме `Storage=volatile`.*

Итак, в systemd/journald существуют два способа передачи логов через сеть:

* достаточно необычная **pull-модель**, при которой лог-сервер инициирует соединение
  и запрашивает данные, в то время как на самом деле сервер ([`systemd-journal-gatewayd`][10])
  работает на источнике;

* и более традиционная **push-модель**, когда лог-сервер в действительности является
  сервером, а открывает соединение и отправляет данные машина-источник
  (а именно утилита [`systemd-journal-upload`][11]).

На лог-сервере же в обоих случаях запускается [`systemd-journal-remote`][12].

Данные передаются по сети поверх протокола HTTP(S) в подробном [почти текстовом формате][13]
вида `KEY=VALUE`. Именно в этом формате логи отображаются командой `journalctl -o export`.

#### Способ первый --- "pull"

В этом режиме на источнике логов мы запускаем самый настоящий специализированный
HTTP-сервер `systemd-journal-gatewayd` (реализованный с помощью libmicrohttpd).

Вообще, у этого сервера нет даже конфигурационного файла: всё достигается прямым
редактированием юнитов. Так, например, он представляет собой обычный сокет-активируемый
сервис, поэтому чтобы изменить порт, на котором он будет принимать соединения,
следует обратиться к юниту `systemd-journal-gatewayd.socket` и изменить в нём
значение директивы [`ListenStream=`][14]. Или, например, для того, чтобы задать
сертификат и секретный ключ HTTPS, достаточно изменить юнит `systemd-journal-gatewayd.service`,
дописав в командную строку демона параметры `--cert=` и `--key=`.

Нас вполне устраивает стандартный порт 19531 (а настройку HTTPS для краткости мы опустим),
поэтому сразу перейдём к запуску этого сервера на отдельной машине:

```
# systemctl start systemd-journal-gatewayd.socket
```

HTTP API этого сервера достаточно прост и описан в документации. В частности:

---------------------------------------------------------------------------------------------------------
Адрес                    Ответ сервера
------------------------ --------------------------------------------------------------------------------
[`/browse`][15]          интерактивная веб-консоль

[`/entries`][16]         *(основной метод)* дамп журнала

[`/machine`][17]         JSON-структура, описывающая систему (machine-id, boot-id, ...)

[`/fields/<field>`][18]  список всех значений, которые принимает поле `<field>` на данном участке журнала
---------------------------------------------------------------------------------------------------------

Запрос `/entries` может принимать несколько [URL-параметров][19], управляющих фильтрацией.

---------------------------------------------------------------------------------
URL-параметр             Значение
------------------------ --------------------------------------------------------
[`?boot`][20]            эквивалент `journalctl --this-boot`

[`?follow`][21]          эквивалент `journalctl --follow`

[`?discrete`][22]        вернуть только ту запись, на которую указывает заголовок
                         `Range:` (об этом чуть дальше)

[`?<field>=<value>`][23] добавить фильтр по значению поля `<field>`
---------------------------------------------------------------------------------

При этом формат возвращаемых данных и требуемый диапазон записей задаются при помощи специальных HTTP-заголовков.

----------------------------------------------------------------------------------------------------------------------------------------
HTTP-заголовок                                     Значение
-------------------------------------------------- -------------------------------------------------------------------------------------
[`Range: entries=<cursor>[[:<skip>]:<count>]`][24] выбор диапазона отображения: начать с курсора `<cursor>`, пропустить `<skip>` записей
                                                   и вывести не более, чем `<count>` записей *(по умолчанию --- все или одну,
                                                   в зависимости от параметра `?discrete`)*

[`Accept: <MIME-тип>`][25]                         выбор формата данных: например, [`text/plain`][26] (простой текст) или
                                                   [`application.vnd.fdo.journal`][27] (`journalctl -o export`-подобный формат)
----------------------------------------------------------------------------------------------------------------------------------------

Сначала попробуем получить логи с тестовой машины, пользуясь только curl.

```
# curl -H"Accept: text/plain" "http://77.41.63.43:19531/entries?boot" > remote-current-boot-export

# curl -H"Accept: application/vnd.fdo.journal" "http://77.41.63.43:19531/entries?boot" > remote-current-boot-export
  % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 15.1M    0 15.1M    0     0   918k      0 --:--:--  0:00:16 --:--:--  930k
```

Как видим, это вполне себе нормальный HTTP, с которым можно работать привычными средствами.

Теперь попробуем сделать то же самое, но уже с помощью утилиты `systemd-journal-remote`.
"Комплектный" юнит запускает её в push-конфигурации, поэтому сейчас мы будем делать это
вручную из консоли.

```
# lib/systemd/systemd-journal-remote --url=http://77.41.63.43:19531
Received 0 descriptors
Spawning curl http://77.41.63.43:19531/entries...
/var/log/journal/remote/remote-77.41.63.43:19531.journal: Successfully rotated journal
/var/log/journal/remote/remote-77.41.63.43:19531.journal: Successfully rotated journal
```

Собственно, внутри это тот же самый curl. Да, у этой утилиты конфигурационный
файл уже есть: `/etc/systemd/journal-remote.conf`. С его помощью можно задать
сертификат и секретный ключ HTTPS, а также (директивой `SplitMode=`) выбрать
способ разбиения получаемых данных на отдельные файлы. Мы вернёмся к этой настройке
при разборе push-конфигурации.

Помимо этих настроек, `systemd-journal-remote` позволяет указать в командной строке
(параметром `--output=`) директорию или файл назначения, куда будут сохраняться получаемые от
удалённой машины логи. Если этот параметр не указан, в качестве назначения по умолчанию
будет взята директория `/var/log/journal/remote`, а выходной файл будет назван согласно
hostname-части указанного URL.

На остальных параметрах этой утилиты мы останавливаться не будем --- они все документированы
в man-странице [systemd-journal-remote(8)][12]. Но отдельно отметим, что просматривать лог-файлы
в нестандартной директории можно с помощью команды `journalctl -D <директория>`. Кстати,
точно таким же способом можно получить доступ к логам не запущенной в данной момент системы
(например, при восстановлении).

#### Способ второй --- "push"

Теперь перейдём к рассмотрению более привычной модели взаимодействия, в которой
соединение с лог-сервером инициируется машиной-источником логов.

Сначала запустим лог-сервер, представленный всё той же утилитой `systemd-journal-remote`.
На этот раз мы будем запускать её с помощью комплектных юнитов, как обычный
сокет-активируемый демон. Как и в предыдущем случае, для изменения порта или адреса,
на котором будет создан сокет, предлагается напрямую править юнит `systemd-journal-remote.socket`.

Вернёмся к конфигурационному файлу этой утилиты.

```
[Remote]
# SplitMode=host
# ServerKeyFile=/etc/ssl/private/journal-remote.pem
# ServerCertificateFile=/etc/ssl/certs/journal-remote.pem
# TrustedCertificateFile=/etc/ssl/ca/trusted.pem
```

Директива `SplitMode=` (и параметр командной строки `--split-mode=`) позволяет
указать, как сохранять данные, получаемые с разных хостов. Допустимы всего два значения:

----------------------------------------------------------------------------------
Значение           Описание
------------------ ---------------------------------------------------------------
`none`             записывать все получаемые логи сплошным потоком

`host`             распределять логи по файлам в зависимости от hostname источника
----------------------------------------------------------------------------------

Итак, нас устраивает значение по умолчанию (`host`) и стандартный порт (на этот
раз 19532), поэтому просто активируем `.socket`-юнит:

```
# systemctl start systemd-journal-remote.socket
```

После этого настроим и запустим на второй машине утилиту `systemd-journal-upload`.
Для неё уже есть готовый юнит `systemd-journal-upload.service`, не требующий изменений,
а также конфигурационный файл `/etc/systemd/system/journal-upload.conf`.

Нам остаётся всего лишь указать в этом файле (директивой `URL=`) адрес сервера,
на который мы собственно хотим передавать данные:

```
[Upload]
URL= http://systemd.cf:19532
# ServerKeyFile=/etc/ssl/private/journal-upload.pem
# ServerCertificateFile=/etc/ssl/certs/journal-upload.pem
# TrustedCertificateFile=/etc/ssl/ca/trusted.pem
```

После чего запускаем `systemd-journal-upload` и убеждаемся, что всё работает.

```
# systemctl start systemd-journal-upload
```

Логи машины-источника:

```
<...>
фев 21 21:35:36 server-9-20 systemd[1]: Starting Journal Remote Upload Service...
<...>
```

Логи машины-сервера:

```
<...>
Feb 21 18:30:10 systemd.cf systemd[1]: Listening on Journal Remote Sink Socket.
Feb 21 18:30:10 systemd.cf systemd[1]: Starting Journal Remote Sink Socket.
<...>
```

Как видим --- всё работает.

[10]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html
[11]: http://www.freedesktop.org/software/systemd/man/systemd-journal-upload.html
[12]: http://www.freedesktop.org/software/systemd/man/systemd-journal-remote.html
[13]: https://wiki.freedesktop.org/www/Software/systemd/export/
[14]: http://www.freedesktop.org/software/systemd/man/systemd.socket.html#ListenStream=
[15]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#/browse
[16]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#/entries[?option1&option2=value...]
[17]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#/machine
[18]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#/fields/FIELD_NAME
[19]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#URL%20GET%20parameters
[20]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#boot
[21]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#follow
[22]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#discrete
[23]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#KEY=match
[24]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#Range%20header
[25]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#Accept%20header
[26]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#text/plain
[27]: http://www.freedesktop.org/software/systemd/man/systemd-journal-gatewayd.service.html#application/vnd.fdo.journal