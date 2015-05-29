systemd In Action, volume 3
===========================

Теперь пришло время посмотреть на `systemd-journald` --- компонент systemd, отвечающий за общесистемное логирование. Сначала, разумеется, стоит определиться с тем, что мы понимаем под этим термином. `journald` отвечает не только и не столько за хранение логов (в виде бинарной БД), сколько за *сбор и обработку* потоков текста из различных источников.

## I. Посмотрим с большой высоты.

Итак, `journald` --- это то место, куда `systemd` (PID 1) подсоединяет stdout и stderr запускаемых процессов, чтобы не заниматься их обработкой самостоятельно (что попросту снижает надёжность, т. к. у PID 1 появляется лишний повод свалиться). Так, многое проясняет сравнение возможных значений параметра [`DefaultStandardOutput=`](http://www.freedesktop.org/software/systemd/man/systemd-system.conf.html#LogLevel=) в `/etc/systemd/system.conf`, или, что то же самое, директивы [`StandardOutput=`](http://www.freedesktop.org/software/systemd/man/systemd.exec.html#StandardOutput=) в юнит-файлах, описывающих запуск внешних программ, и [настроек `journald`](http://www.freedesktop.org/software/systemd/man/journald.conf.html#Options) в `/etc/systemd/journald.conf`.

### The redirection game

Директива `StandardOutput=` в юнит-файле определяет, куда нужно подсоединять стандартный вывод запускаемых в рамках данного юнита процессов. Вариантов не так много, и их объединяет то, что каждый из них реализуется простым перенаправлением, без какой-либо дополнительной обработки потока текста в контексте PID 1.

Table: Возможные значения директивы `StandardOutput=`

--------------------------------------------------------------------------------------------------------------------------------------------------------
Значение             Описание
-------------------- -----------------------------------------------------------------------------------------------------------------------------------
`null`               отбросить stdout

`inherit`            *(по умолчанию)* подключить stdout к тому же файловому дескриптору, что и stdin
                     (cf. [`StandardInput=`](http://www.freedesktop.org/software/systemd/man/systemd.exec.html#StandardInput=) в юнит-файле)

`tty`                подключить stdout к терминалу, указанному директивой
                     [`TTYPath=`](http://www.freedesktop.org/software/systemd/man/systemd.exec.html#TTYPath=) в юнит-файле

`socket`             *(только для сокет-активируемых юнитов)* подключить stdout к сокету

`journal`            направить stdout в `journald`

`syslog`             направить stdout в `journald` и включить для данного юнита перенаправление в syslog
                     (cf. [`ForwardToSyslog=`](http://www.freedesktop.org/software/systemd/man/journald.conf.html#ForwardToSyslog=) в `journald.conf`)

`kmsg`               направить stdout в `journald` и включить для данного юнита перенаправление в буфер сообщений ядра
                     (cf. [`ForwardToKMsg=`](http://www.freedesktop.org/software/systemd/man/journald.conf.html#ForwardToKMsg=) в `journald.conf`)

`journal+console`, \ то же самое, плюс перенаправление в `/dev/console`
`syslog+console`, \  (cf. [`ForwardToConsole=`](http://www.freedesktop.org/software/systemd/man/journald.conf.html#ForwardToConsole=) в `journald.conf`)
`kmsg+console`
--------------------------------------------------------------------------------------------------------------------------------------------------------

*(Также существует директива [`StandardError=`](http://www.freedesktop.org/software/systemd/man/systemd.exec.html#StandardError=), принимающая аналогичный набор значений.)*

Можно видеть, что перенаправление в `/dev/null`, tty или сокет выполняется "напрямую", без использования промежуточного звена в виде демона `journald`.

А вот перенаправление в syslog, kmsg или `/dev/console` (альтернативный путь можно указать директивой [`TTYPath=`](http://www.freedesktop.org/software/systemd/man/journald.conf.html#TTYPath=) в `journald.conf`) выполняется только через `journald`, что и неудивительно: в каждом из этих случаев текстовый поток необходимо дополнительно обрабатывать. Чем, собственно, демон и занимается.

### Так что, всё-таки, происходит в системе?

Итак, мы выяснили, что `journald` --- это, в первую очередь, сборщик логов, а не писатель в бинарные файлы. Теперь разберёмся с тем, откуда он может получать информацию.

* Во-первых, это нативный API для логгирования: [`sd-journal.h`](http://www.freedesktop.org/software/systemd/man/sd-journal.html) (в частности, [`sd_journal_print(3)`](http://www.freedesktop.org/software/systemd/man/sd_journal_print.html)). Он отличается, например, от того же [syslog(3)](http://linux.die.net/man/3/syslog) тем, что позволяет присоединять к сообщениям произвольные метаданные в форме `KEY=VALUE` (об этом позже).

* Во-вторых, это, собственно, [syslog(3)](http://linux.die.net/man/3/syslog). `journald` открывает и слушает сокет `/dev/log` (являясь в некотором смысле альтернативой [syslogd(8)](http://linux.die.net/man/8/syslogd) для Linux-систем).

* В-третьих, это буфер сообщений ядра, `/proc/kmsg` (тот, который отображает команда [`dmesg(1)`](http://linux.die.net/man/1/dmesg)).

* Наконец, в-четвёртых, это stdout и stderr процессов, подконтрольных systemd (мы их как раз рассмотрели разделом выше).

...а также с тем, куда он её способен впоследствии передавать/сохранять.


3. Journald - демон-сборщик логов и опционально писатель, который отвечает за сбор сообщений ядра, initrd, и также STDOUT & STDERR от различных процессов. Хранением логов может заниматься как сам journal, так и опционально syslog c помощью форвардинга от journal.
Вопреки  распространенному мифу, что логи journal могут читаться только  journalctl и это может стать большой проблемой, они также  могут  читаться утилитой strings. Пример: strings  /var/log/journal/name_of_log_file | grep -i message
Где же хранятся логи? Для хранения используется директория /var/log/journal, для буфера используется /run/log/journal. Размер хранилища, ротация и другие параметры кофигурации настраиваются в
/etc/systemd/journald.conf.
ForwardToSyslog    перенаправление в syslog
Storage                    где именно будут хранится логи (или не храниться вовсе в случае Storage=none;             "volatile" - только в RAM, "persistent" - на диске, "auto" - аналогично "persistent" но без директории /var/log/journal/)
SystemMaxUse=,
 SystemKeepFree=,
 SystemMaxFileSize=,
RuntimeMaxUse=,
RuntimeKeepFree=, RuntimeMaxFileSize=    - отвечает за различные лимиты: максимальный размер файла, максимальный размер свободного места, максимальный размер логов journal и т.д
...
Compress        поддержка xz-комрессии
MaxFileSec     максимальный час записи логов в один файл
                        Более детально можно посмотреть в  man  journald.conf.
Просмотром логов и их фильтрацией занимается команда journalctl.

    journalctl -f     просмотр логов в реальном времени(tail -f)

    journalctl -b = просмотр логов с момента загрузки

    journalctl -e = сразу перейти в конец вывода

                    -a      показать вывод посностью, включая непечатные символы

                   -o       вывод логов в различных форматах и структурах

                  -m       вывод логов со всех доступных журналов

                   -k       только сообщения ядра

    --disk-usage      показать сколько использовано места на диске

 --verify                  проверка логов
  --flush                  принудительный перенос логов на диск, если его использование разрешено
-M                          указание контейнера
Также доступны фильтры:
-u, --unit по юниту( -u avahi-daemon)
-p, --priority по приоритету("emerg" (0), "alert" (1), "crit"
           (2), "err" (3), "warning" (4), "notice" (5), "info" (6), "debug"
           (7))
--since, --until   по времени( --since "2015-01-12 23:00:00")
В качестве аргументов journalctl также можно указывать блочные устройства и полные пути к бинарным файлам:
journalctl /usr/bin/mount
 journalctl /dev/sdb
Также для безопастности можно активировать шифрование логов  (Seal=yes в /etc/system/journald.conf)
Для начала генерируем ключи:

    journalctl --setup-keys

И мы получаем великий и страшный qr-code. Это зделано для того, чтобы не хранить ключ на машине, на которой собственно хранятся логи. Но можно также получить ключ в текстовом виде:


    journalctl --setup-keys --force | cat

/var/log/journal, /run/log/journal

    место хранения логов

/etc/systemd/journald.conf

    как отключить хранение

    как включить постоянное хранение (Storage=persistent vs. Storage=auto)

    как включить форвардинг

    как установить ограничения на размер хранимых логов

journalctl

    journalctl -f = tail -f

    journalctl -b = с момента загрузки

    journalctl -e = сразу перейти в конец вывода

    фильтры:

    -u, --unit

    -p, --priority

    --since, --until

фичи:

    подписывание (Seal=yes)

    QR-коды (продемонстрировать и показать, что от них можно избавиться)

