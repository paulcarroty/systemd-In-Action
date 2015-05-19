###2. Передача логов
Дальше мы поговорим о важной функции journal, которую мы упустили в предыдущей части - прием и передача логов. Для этого у нас есть три утилиты, встроеные в journal: `systemd-journal-remote`, `systemd-journal-gatewayd` и `systemd-journal-upload`.
Cуществуют два способа передачи логов. Первый - когда соединение инициирует машина, которая принимает логи: `systemd-journal-remote` на этой машине инициирует соединение с демоном `systemd-journal-gatewayd` на машине, которая отдает логи. И второй, когда все наоборот: клиент отдает логи на сервер и на клиенте запускается утилита `systemd-journal-upload` для передачи логов, а на сервере `systemd-journal-remote` для приема.

Продемонстрируем первый способ. Для начала запустим `systemd-remote-gatewayd` на сервере, который являет собой простой http-сервер отдающий нам логи с помощью HTTP-запросов.
```
server: # systemctl start systemd-journal-gatewayd.socket
client: $ curl -H"Accept: text/plain" "http://77.41.63.43:19531/entries?boot" > remote-current-boot-export
```

Итак, мы получили все сообщения с момента последней загрузки в текстовом формате. Теперь попробуем добыть логи в формате, предназначеном для експорта. Для этого сменим заголовок следующим образом:
```
$  curl -H"Accept: application/vnd.fdo.journal" "http://77.41.63.43:19531/entries?boot" > remote-current-boot-export
 % Total    % Received % Xferd  Average Speed   Time    Time     Time  Current
                                 Dload  Upload   Total   Spent    Left  Speed
100 15.1M    0 15.1M    0     0   918k      0 --:--:--  0:00:16 --:--:--  930k
```

Теперь получим все логи с удаленной машины с помощью `systemd-journal-remote`:
```
# lib/systemd/systemd-journal-remote --url=http://77.41.63.43:19531
Received 0 descriptors
Spawning curl http://77.41.63.43:19531/entries...
/var/log/journal/remote/remote-77.41.63.43:19531.journal: Successful
ly rotated journal
/var/log/journal/remote/remote-77.41.63.43:19531.journal: Successful
ly rotated journal
```
Читать логи journal с директории удобно с помощью команды `# journalctl -d /path/to/directory`. В `systemd-journal-remote` также есть удобный параметр
`--split-mode`, который  позволяет указывать как именно нужно формировать файлы журнала. По умолчанию, разбиение файлов журнала делается по `machine-id`.
Также нужно вспомнить об авторизации: в данном случае мы ее не используем ради простоты демонстрации, как и поддержку https.

Теперь перейдем к второму способу передачи логов. Напомним, что в первом способе сервер забирал логи с клиента, здесь же все будет наоборот.
Перед запуском systemd-journal-remote посмотрим в его конфигурационный файл `/etc/systemd/journal-remote.conf`:
```
[Remote]                                                            │
# SplitMode=host
# ServerKeyFile=/etc/ssl/private/journal-remote.pem
# ServerCertificateFile=/etc/ssl/certs/journal-remote.pem
# TrustedCertificateFile=/etc/ssl/ca/trusted.pem
```
Как видно, по умолчанию файлы journal разбиваются по хостах, а точнее machineid; также есть настроки аутентификации по ключу.
Для запуска передачи логов у нас уже есть готовый юнит `systemd-journal-upload.service`, нам всего лишь остается указать хост в конфиге(`/etc/systemd/system/journal-upload.conf`), на который собственно мы хотим передавать данные:
```
[Upload]
URL= http://systemd.cd:19532
# ServerKeyFile=/etc/ssl/private/journal-upload.pem
# ServerCertificateFile=/etc/ssl/certs/journal-upload.pem
# TrustedCertificateFile=/etc/ssl/ca/trusted.pem
```
Запускаем сервис:
```
# systemctl start systemctl-journal-upload
```

Cервис запустился успешно, посмотрим в логи клиента и сервера:
```
фев 21 21:35:36 server-9-20 systemd[1]: Starting Journal Remote Upload Service...
```
```
Feb 21 18:30:10 systemd.cf systemd[1]: Listening on Journal Remote Sink Socket.
Feb 21 18:30:10 systemd.cf systemd[1]: Starting Journal Remote Sink Socket.
```

