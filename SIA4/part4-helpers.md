###4. Busctl и базовая работа с dbus.

Дальше мы переходим к обзору небольших дополнительных утилит в systemd. У многих людей возникает мысль: "Зачем нужно столько утилит: `timedated`, `hostnamed`, `localed` и прочих? Они же написаны явно от нечего делать." На самом деле подобные демоны раньше присутствовали в KDE: там был свой особый демон с поддержкой dbus и которому передавались различные параметры. Сейчас есть множество приложений, которые используют dbus в своей работе, также не можем не упомянуть `policykit` - менеджер прав доступа, который работает с dbus-вызовами и может принимать или отклонять их.
Зачем все это нужно? Дело в том, что традиционный подход в виде suid-обертки или вообще без нее, требующий указания пароля суперпользователя - далеко не идеал. Например, для того чтобы сменить hostname DE просто делало форк скорее всего `kdesudo hostname`, этот процесс спрашивал пароль суперпользователя и в успешном случае все работало. Не слишком удобно, не так ли?
Эта проблема решается с помощью микродемонодов, которые вы наблюдали раньше в составе systemd. Точнее не совсем демоны, потому что они активируются с помощью dbus и не работают все время.

Для начала мы продемонстрируем как обращаться к dbus-объектам и как устроена иерархия методов на dbus-шине. Для упрощения жизни у нас есть удобная утилита `busctl`, которая выгодно отличается от страшных на вид существующих аналогов предоставляющих доступ к dbus. В наших примерах мы будем также использовать утилиту dbus-send, которая есть почти везде. Для начала давайте получим список методов и свойств, предоставляемых главным обьектом systemd — `org.freedesktop.systemd1`:
```
$ busctl introspect org.freedesktop.systemd1 /org/freedesktop/systemd1
NAME                                TYPE      SIGNATURE        RESULT/VALUE
org.freedesktop.DBus.Introspectable interface -                -
.Introspect                         method    -                s
org.freedesktop.DBus.Peer           interface -                -
.GetMachineId                       method    -                s
.Ping                               method    -                -
org.freedesktop.DBus.Properties     interface -                -
.Get                                method    ss               v
.GetAll                             method    s                a{sv}
.Set                                method    ssv              -
.PropertiesChanged                  signal    sa{sv}as         -
org.freedesktop.systemd1.Manager    interface -                -
.AddDependencyUnitFiles             method    asssbb           a(sss)
.CancelJob                          method    u                -
.ClearJobs                          method    -                -
.CreateSnapshot                     method    sb               o
.DisableUnitFiles                   method    asb              a(sss)
.Dump                               method    -                s
.EnableUnitFiles                    method    asbb             ba(sss)
.Exit                               method    -                -
.GetDefaultTarget                   method    -                s
.GetJob                             method    u                o
.GetUnit                            method    s                o
```
Аналогичная операция с помощью утилиты `dbus-send` будет выглядеть так:
```
# dbus-send --system --type=method_call --print-reply --dest=org.freedesktop.systemd1 /org/freedesktop/systemd1 /org/freedesktop.DBus.Introspectable.Introspect
```
Мы обращаемся к системной шине(--system), дальше производим вызов метода(`--type=method_call`) и желаем получить ответ; с помощью флага `--dest` мы указываем обьект, к которому отправляем этот вызов. Дальше мы указываем путь внутри этого обьекта(`/org/freedesktop.DBus.Introspectable`) и интерфейс с методом в последнем флаге. Продемонстрируем часть вывода:
```
...
<signal name="StartupFinished">
 <arg type="t"/>
 <arg type="t"/>
 <arg type="t"/>
 <arg type="t"/>
 <arg type="t"/>
 <arg type="t"/>
</signal>
<signal name="UnitFilesChanged">
</signal>
<signal name="Reloading">
 <arg type="b"/>
</signal>
</interface>
</node>
```

Какой вариант более лаконичен и удобен судить вам, но думаю что это совершенно очевидно.
Мы видим четыре интерфейса, которые реализуются этим обьектом. Каждый интерфейс является совокупностью методов, свойств и сигналов, также у них есть сигнатуры и возвращаемый результат. Для понимания практического применения давайте сменим дату в нашей операционной системе с помощью dbus-интерфейса timedated1.
```
$ busctl introspect org.freedesktop.timedate1 /org/freedesktop/timedate1
NAME                                TYPE      SIGNATURE RESULT/VALUE     FLAGS
org.freedesktop.DBus.Introspectable interface -         -                -
.Introspect                         method    -         s                -
org.freedesktop.DBus.Peer           interface -         -                -
.GetMachineId                       method    -         s                -
.Ping                               method    -         -                -
org.freedesktop.DBus.Properties     interface -         -                -
.Get                                method    ss        v                -
.GetAll                             method    s         a{sv}            -
.Set                                method    ssv       -                -
.PropertiesChanged                  signal    sa{sv}as  -                -
org.freedesktop.timedate1           interface -         -                -
.SetLocalRTC                        method    bbb       -                -
.SetNTP                             method    bb        -                -
.SetTime                            method    xbb       -                -
.SetTimezone                        method    sb        -                -
.CanNTP                             property  b         true             -
.LocalRTC                           property  b         false            emits-change
.NTP                                property  b         true             emits-change
.NTPSynchronized                    property  b         true             -
.RTCTimeUSec                        property  t         1432108225000000 -
.TimeUSec                           property  t         1432108225986680 -
.Timezone                           property  s         "Europe/Kiev"    emits-change
```

Обратите внимание на свойства обьекта: текущее время, временная зона, параметры NTP-синхронизации и прочее. Нам нужен метод `.SetTime`, который принимает три параметра, описанные в сигнатуре: время в микросекундах, на которое мы должны сдвинуться; нужность авторизации; сдвиг во времени или установка времени начиная от начала эпохи.

Давайте сдвинем время на 1 час вперед. Для этого воспользуемся утилитой `busctl`, а для возвращения к текущему времени — `dbus-send`.
```
# busctl call org.freedesktop.timedate1 /org/freedesktop/timedate1 org.freedesktop.timedate1 SetTime xbb $((3600*1000*1000)) true false
```
Алгоритм тот же: обьект на шине, путь внутри этого обьекта, интерфейс(совпадает с именем обьекта), имя метода и параметры. Первый параметр - сдвиг времени в микросекундах, дальше мы устанавливаем время относительно текущего и не используем относительную авторизацию относительно policykit, так как выполняем запрос от суперпользователя.

Посмотрим изменилось ли время c помощью dbus для единства стиля:
```
$ busctl call org.freedesktop.timedate1 /org/freedesktop/timedate1
...
.RTCTimeUSec                        property  t         1424552366000000 -
.TimeUSec                           property  t         1424552366243943 -
...

```
Как видим, все работает. Тепер вернем время вспять с помощью `dbus-send`:
```
# dbus-send --print-reply --system --type=method_call --dest=org.freedesktop.timedate1 /org/freedesktop/timedate1 org.freedesktop.timedate1.SetTime int64:$((-3600*1000*1000))  boolean:true boolean:false
```

Прочитать больше про D-Bus API systemd можно [здесь](http://www.freedesktop.org/wiki/Software/systemd/dbus/). Будут полезными также `man D-Bus`, `man kdbus`, `man sd-bus`, `man busctl`.


