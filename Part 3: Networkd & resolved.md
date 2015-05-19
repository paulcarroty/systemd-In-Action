###3. Настройка сети в systemd
Дальше мы перейдем к `systemd-networkd` — настройке сети в формате и духе systemd. Конфигурационные файлы `networkd` расположены в директории `/etc/systemd/network`. Networkd имеет три типа конфигурационных файлов: `*.link,` `*.network` и `*.netdev`.
Файлы настройки с расширением `.link` описывают физические параметры интерфейсов — каждый файл описывает один интерфейс: MAC-адресс, имя интерфейса, MTU, и прочие параметры, которые не относятся к сетевым. Эти файлы считываются каждый раз одним из обработчиков udev при запуске или перенастройке системы.
Файлы с расширением `.network` считываются непосредственно демоном networkd и содержат сетевые параметры интерфейсов: IP-адреса, маршруты, шлюзы, DNS-сервера и прочее.
И, наконец,  файлы `*.netdev` служат для описания виртуальных интерфейсов.

Для демонстрации работы networkd мы выполним перевод конфигурации нашей машины с legacy sysv-initscript `/etc/init.d/network` на `networkd`. Напомним, что мы используем Fedora 21, systemd 219 и статическую конфигурацию сети:
```
$ ip addr
1: lo: <LOOPBACK,UP,LOWER_UP> mtu 65536 qdisc noqueue state UNKNOWN group default
    link/loopback 00:00:00:00:00:00 brd 00:00:00:00:00:00
    inet 127.0.0.1/8 scope host lo
       valid_lft forever preferred_lft forever
    inet6 ::1/128 scope host
       valid_lft forever preferred_lft forever
2: eth0: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 04:01:40:23:1f:01 brd ff:ff:ff:ff:ff:ff
    inet 188.166.46.238/18 brd 188.166.63.255 scope global eth0
       valid_lft forever preferred_lft forever
    inet6 2a03:b0c0:2:d0::69:7001/64 scope global
       valid_lft forever preferred_lft forever
    inet6 fe80::601:40ff:fe23:1f01/64 scope link
       valid_lft forever preferred_lft forever
3: eth1: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 qdisc fq_codel state UP group default qlen 1000
    link/ether 04:01:40:23:1f:02 brd ff:ff:ff:ff:ff:ff
    inet 10.133.248.54/16 brd 10.133.255.255 scope global eth1
       valid_lft forever preferred_lft forever
    inet6 fe80::601:40ff:fe23:1f02/64 scope link
       valid_lft forever preferred_lft forever
```

Посмотрим на интерфейсы, которые находятся под управлением `networkd` с помощью утилиты `networkctl`:
```
$ networkctl
IDX LINK             TYPE               OPERATIONAL SETUP
  1 lo               loopback           n/a         n/a
  2 eth0             ether              n/a         n/a
  3 eth1             ether              n/a         n/a
```
Мы увидели только список интерфейсов и их типов, так как сервис networkd у нас пока не запущен. После запуска перед нами предстанет немного другая картина:
```
# systemctl start systemd-networkd
# networkctl
IDX LINK             TYPE               OPERATIONAL SETUP
  1 lo               loopback           carrier     unmanaged
  2 eth0             ether              routable    unmanaged
  3 eth1             ether              routable    unmanaged

3 links listed.
```
`Unmanaged` говорит нам, что данный интерфейс пока не находится под управлением networkd, который вполне свободно допускает подобную практику. Посмотрим сетевые параметры интерфейсов, чтобы перенести их в конфигурацию networkd:
```
# cat /etc/sysconfig/network-scripts/ifcfg-eth0
DEVICE='eth0'
TYPE=Ethernet
BOOTPROTO=none
ONBOOT='yes'
HWADDR=04:01:40:23:1f:01
IPADDR=188.166.46.238
NETMASK=255.255.192.0
GATEWAY=188.166.0.1
NM_CONTROLLED='yes'
IPV6INIT=yes
IPV6ADDR=2A03:B0C0:0002:00D0:0000:0000:0069:7001/64
IPV6_DEFAULTGW=2A03:B0C0:0002:00D0:0000:0000:0000:0001
IPV6_AUTOCONF=no
DNS1=2001:4860:4860::8844
DNS2=2001:4860:4860::8888
DNS3=8.8.8.8
```
Для дистрибутивов, отличных от Red Hat-based эти конфигурационные файлы будут выглядеть иначе, но скорее всего нужную информацию можно получить без проблем. В текущей конфигурации интерфейс `eth0` используется для доступа в интернет, а `eth1` - в локальную сеть. Также рекомендуем перед запуском networkd переместить эти конфигурационные файлы в другую директорию, так как некоторые правила udev cчитывают их.

Перейдем к созданию link-файлов. Для начала пару слов как именно они обрабатываются udev.
У нас уже есть дефолтный link-файл `/lib/systemd/network/99-default.link`, в котором настраивается политики назначения MAC-адреса и именования сетевых интерфейсов.
```
[Link]
NamePolicy=kernel database onboard slot path
MACAddressPolicy=persistent
```

Создадим link-файлы для каждого интерфейса, где укажем интерфейсы и MAC-адреса:
```
cat /etc/systemd/network/90-external.link
[Match]
MACAddress=04:01:40:23:1f:01
[Link]
Name=eth-external
```
```
cat /etc/systemd/network/90-internal.link
[Match]
MACAddress=04:01:40:23:1f:02
[Link]
Name=eth-inner
```

Чтобы сетевые интерфейсы работали под управлением `networkd`, нам также необходимы конфигурационные файлы `*.network`:
```
cat eth-external.network
[Match]
Name= eth-outer
[Network]
DHCP=no
Adress=188.166.46.238/18
Adress=2A03:B0C0:0002:00D0:0000:0000:0000:0069:7001/64
Gateway=188.166.0.1
Gateway= 2A03:B0C0:0002:00D0:0000:0000:0000:0000:0001
DNS=2001:4860:4860:8844
DNS=2001:4860:4860:8888
DNS=8.8.8.8
```
```
cat eth-internal.network
[Match]
Name=eth-inner
[Network]
Address=10.133.248.54/16
```
Конфигурация готова, дальше остается отключить дефолтный сервис network и включить автозагрузку networkd:
```
# systemctl disable network && systemclt enable networkd.
```
Для уверенности, что данная конфигурация будет стабильно работать, перезапустим машину и посмотрим работает ли сеть:
```
$ ping systemd.cf
PING systemd.cf (188.166.46.238) 56(84) bytes of data.
64 bytes from systemd.cf (188.166.46.238): icmp_seq=6 ttl=56 time=48.7 ms
64 bytes from systemd.cf (188.166.46.238): icmp_seq=7 ttl=56 time=48.7 ms
64 bytes from systemd.cf (188.166.46.238): icmp_seq=8 ttl=56 time=48.4 ms
64 bytes from systemd.cf (188.166.46.238): icmp_seq=9 ttl=56 time=50.5 ms
64 bytes from systemd.cf (188.166.46.238): icmp_seq=10 ttl=56 time=48.1 ms
```
Ура, мы успешно настроили сеть с помощью networkd!
```
$ networkctl
IDX LINK             TYPE               OPERATIONAL SETUP
  1 lo               loopback           n/a         n/a
  2 eth-outer        ether              routable    configured
  3 eth-inner        ether              routable    configured
```
Теперь пришла пора обратить внимание на `systemd-resolved` - кеширующий DNS-сервер, точнее прослойка между glibc и DNS-серверами.
Его конфигурационный файл `/run/systemd/resolve/resolve.conf` можно использовать только как симлинк к `/etc/resolv.conf`, так что изначально он не влияет на сетевую подсистему.
Запустим `resolved` и покажем как его можно использовать в качестве кеширующего резолвера:
```
# systemctl enable systemd-resolvd && systemctl start systemd-resolvd
```

Зделаем симлинк на `/etc/resolv.conf`:
```
ln -sf /run/systemd/resolve/resolve.conf /etc/resolve.conf
```
В отличие от таких программ как `dnsmasq`, `resolved` не является DNS-proxy - он не представляет виртуальный DNS-сервер, к которому можно отправлять запросы. Вместо этого он предоставляет nss-модуль, который встраивается в glibc, и позволяет любой программе использующей glibc, использовать кеш запросов. Управление осуществляется с помощью файла `nssswitch.conf` в секции hosts:
```
hosts: files dns myhostname mymashines
```
Краткое пояснение: `Files` - считывание с `/etc/hosts`, `dns` - встроеный glibc-ресолвер c `resolv.conf`,  `myhostname`&`mymashine` - nss модули поставляемые с systemd.

`myhostname` - резолвит строку `localhost` и имя хоста, а `mymachines` ресолвит имена контейнеров и их адреса виртуальных интерфейсов.

Для использования `resolved` мы должны заменить модуль `dns` на `resolve`. Давайте проверим:
```
$ getenv hosts goo.gl
2a00:1450:4001:80f::1009 goo.gl
```
Мы получили IP-адрес с ~1с задержкой. При повторном запуске она должна исчезнуть - это означает, что кеш работает и адрес берется с него, а не с помощью DNS-запроса.



