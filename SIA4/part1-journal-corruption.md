systemd In Action, volume 4
===========================

Приветствуем всех.

В [#3](https://tlhp.cf/systemd-in-action-part-3/) нашего затяжного обзора
возможностей systemd мы разбирались с `systemd-journald` --- подсистемой сбора
системных логов (называть его заменой syslogd не совсем корректно, хотя вести
свой лог в виде бинарной БД он также умеет). Однако, часть аспектов работы с
journald осталась неохваченной.

В связи с этим очередную часть *systemd In Action* мы начнём с двух вещей,
с ним связанных. А именно:

* оценить устойчивость нативного формата БД к произвольным повреждениям;
* рассмотреть возможности journald (точнее, трёх вспомогательных утилит) по
  передаче логов по сети.

Итак,

## The Journal, продолжение.

### Устойчивость к повреждениям

Проверим, насколько нативный формат файлов journald устойчив к
повреждениям. Для этого запишем 1 КиБ мусора в случайное место в файле системного
лога и посмотрим, что изменится в выводе `journalctl`.

Для начала удостоверимся, что исходно файл лога не нарушен. Для этого воспользуемся
штатным средством проверки целостности --- `journalctl --verify`. По умолчанию
этот режим (так же, как и вывод данных) производится над всеми лог-файлами в
стандартных расположениях (`/{var,run}/log/journal`).

```
# journalctl --verify
PASS: /run/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal
0015d0: invalid data hash table item (290/233016) head_hash_offset: b5d9a2492d2da8f7
0015d0: invalid object contents: Bad message
File corruption detected at /var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal:0015d0 (of 8388608 bytes, 0%).
FAIL: /var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal (Bad message)
```

В нашем случае логфайл уже был повреждён (в ходе предыдущих экспериментов). Простейший
способ получить неповреждённый логфайл --- удаление существующего и перезапуск машины,
при котором тот пересоздастся и будет заполнен новыми записями. Собственно, делаем это.

```
# cd /var/log/journal/$(< /etc/machine-id )
# l
total 8.1M
drwxr-sr-x+ 2 root systemd-journal 4.0K Feb 21 17:50 .
drwxr-sr-x+ 4 root systemd-journal 4.0K Feb 19 19:40 ..
-rw-r-x---+ 1 root systemd-journal 8.0M Feb 21 17:50 system.journal
```

Имеем один файл минимального размера (изменение размера логфайлов производится дискретно,
шагами по 8 МиБ). Проверяем целостность ещё раз:

```
# journalctl --verify
PASS: /var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal
```

Проверка успешна, как и ожидалось. Теперь экспортируем бинарный файл в подробный текстовый формат
(`KEY=VALUE` по всем полям всех записей по очереди):

```
# journalctl -o export > uncorrupted
```

Дальше намеренно повреждаем файл `system.journal`, записав в него 1 КиБ случайных данных:

```
# dd if=/dev/urandom of=/var/log/journal/fe39ba83b9244251b1704fc655fbff2f/system.journal bs=1K count=1 seek=10 conv=notrunc
1+0 records in
1+0 records out
1024 bytes (1.0 kB) copied, 0.0022644 s, 452 kB/s
```

*Собственно, так делать было неправильно. За то время, пока мы его повреждали,
в файл успела добавиться ещё одна запись (о подгрузке в ядро модуля ГПСЧ).*

Экспортируем данные еще раз:

```
# journalctl -o export > corrupted
# l corrupted
-rw-r--r--. 1 root root 871K Feb 21 17:53 corrupted
```

Как видим, экспорт повреждённого файла прошел успешно и на выходе мы получили файл ненулевой длины.
Теперь сравниваем полученные текстовые файлы:

```
# diff -u uncorrupted corrupted
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

И вот этот результат мы интерпретировали неправильно, посчитав, что одна запись
из повреждённого файла исчезла. На самом деле нет --- одна запись была добавлена[^1].

#### На самом деле...

...всё не так радужно. При fuzz-тестировании произвольно взятого лог-файла [достаточно простым скриптом][2],
с некоторой степенью точности имитирующим посекторное повреждение, выясняется, что
в некоторых случаях повреждение приводит к нечитаемости штатными средствами всех данных
после места повреждения.

Тем не менее, необходимо подчеркнуть, что речь здесь идёт только о штатных средствах
просмотра: утилите `journalctl`, которая [принудительно прекращает чтение][3]
после первой полученной ошибки. Вполне вероятно, что ситуацию можно улучшить, исправив
утилиту просмотра (или реализовав её аналог, ориентированный именно на восстановление).

Наконец, отметим, что больше информации о том, как работать с журналом, можно
найти в [journalctl(1)][4], а список основных полей -- в [systemd.journal-fields(7)][5].
Ну и сам формат `.journal`-файлов тоже вполне [документирован][6].

[1]: http://www.freedesktop.org/software/systemd/man/machine-id.html
[2]: http://ix.io/iOQ
[3]: https://github.com/systemd/systemd/blob/master/src/journal/journalctl.c#L2161
[4]: http://www.freedesktop.org/software/systemd/man/journalctl.html
[5]: http://www.freedesktop.org/software/systemd/man/systemd.journal-fields.html
[6]: https://wiki.freedesktop.org/www/Software/systemd/journal-files/
