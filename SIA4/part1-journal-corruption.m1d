###1. Journal, продолжение
Приветствуем всех. Эту часть серии мы начнем с опровержения очередного мифа о хрупкости логов `Journal`. Удивительно, но много людей верят, что при малейшем повреждении файлов логи будет невозможно использовать в дальнейшем. Давайте посмотрим как обстоят дела в реальном мире.
Для начала проверим целостность системных логов с помощью утилиты `journalctl`:
```
# journalctl --verify
PASS: /run/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal
0015d0: invalid data hash table item (290/233016) head_hash_offset: b5d9a2492d2da8f7
0015d0: invalid object contents: Bad message
File corruption detected at /var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal:0015d0 (of 8388608 bytes, 0%).
FAIL: /var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal (Bad message)
```

Журнал поврежден нами намеренно. Простейший путь получить целостные логи - рестарт машины, при котором `journal` получит новые системные сообщения.
Проверим целостность:
```
# cd /var/log/journal/$(< /etc/machine-id )
# l
total 8.1M
drwxr-sr-x+ 2 root systemd-journal 4.0K Feb 21 17:50 .
drwxr-sr-x+ 4 root systemd-journal 4.0K Feb 19 19:40 ..
-rw-r-x---+ 1 root systemd-journal 8.0M Feb 21 17:50 system.journal
# journalctl --verify
PASS: /var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal
```

Проверка успешна, как и ожидалось. Дальше экспортируем бинарный файл в текст в формате "одно поле на строку":
```
# journalctl -o export > uncorrupted
```

Теперь намеренно повреждаем файл system.journal, записав в него 1 килобайт случайных данных:
```
# dd if=/dev/urandom of=/var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal bs=1K count=1 seek=10 conv=notrunc
1+0 records in
1+0 records out
1024 bytes (1.0 kB) copied, 0.0022644 s, 452 kB/s
```
Экспортируем данные еще раз:
```
#  journalctl -o export > corrupted
# l corrupted
-rw-r--r--. 1 root root 871K Feb 21 17:53 corrupted
```
Экспорт прошел успешно и на выходе мы получили файл ненулевой длины. Сравним поврежденный и неповрежденный файлы в текстовом формате:
```
$ diff -u uncorrupted corrupted
--- uncorrupted 2015-02-21 17:52:12.701000000 +0000
+++ corrupted   2015-02-21 17:53:30.576000000 +0000
@@ -25526,3 +25526,16 @@
 _SYSTEMD_UNIT=session-3.scope
 _SOURCE_REALTIME_TIMESTAMP=1424541030255833

+__CURSOR=s=00000000000000000000000000000000;i=560f;b=ca178527e7014a6c868084dac3960dd2;m=8d4be3a;t=50f9cd5ee7c96;x=fef0f211c7d6b5b0
+__REALTIME_TIMESTAMP=1424541162044566
+__MONOTONIC_TIMESTAMP=148160058
+_BOOT_ID=ca178527e7014a6c868084dac3960dd2
+_MACHINE_ID=fe39ba83b9244251b1704fc655fbff2f
+_HOSTNAME=systemd.cf
+_TRANSPORT=kernel
+PRIORITY=5
+SYSLOG_FACILITY=0
+SYSLOG_IDENTIFIER=kernel
+_SOURCE_MONOTONIC_TIMESTAMP=148159245
+MESSAGE=random: nonblocking pool is initialized
```
При повреждении у нас потерялась только одна запись, а основная часть остается доступной благодаря встроенной проверки хешей бинарных логов. Тут возникает логичный вопрос: что делать дальше и как восстановить утерянную запись или записи? Ответ - ничего, как видно выше journalctl при чтении восстанавливает все что может, так что отдельной операции восстановления просто не требуется. Если вам нужна дополнительная устойчивость, используйте RAID, snapshots и т.д.
Миф опровергнут. Больше информации вы можете найти в `man journalctl`, `man systemd.journal-fields`.


