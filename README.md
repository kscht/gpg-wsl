# gpg-wsl

Расшарить одну YubiKey OpenPGP-карту между двумя пользователями WSL
(`PRIMARY_USER`, `SECONDARY_USER`) так, чтобы оба могли использовать её
из `gpg`, `ssh -A` и т.д., без ручного переключения карты между сессиями.

## Оглавление

- [Как это работает](#как-это-работает)
- [Ограничение](#ограничение)
- [Использование](#использование)
- [Подготовка Windows (usbipd-win)](#подготовка-windows-usbipd-win)
  - [Установка](#установка)
  - [Привязать устройство](#привязать-устройство-один-раз-сохраняется-между-перезагрузками)
  - [Приаттачить к WSL](#приаттачить-к-wsl)
  - [Проверка из WSL](#проверка-из-wsl)
  - [Отвязать](#отвязать-если-потребуется)
- [Что устанавливается](#что-устанавливается)
- [Зачем так](#зачем-так)
- [Безопасность](#безопасность)

## Как это работает

- `scdaemon` пользователя `PRIMARY_USER` работает в режиме `multi-server`
  и слушает сокет `/run/user/<primary_uid>/gnupg/S.scdaemon`.
- `gpg-agent` пользователя `SECONDARY_USER` через директиву
  `scdaemon-program` запускает не свой `scdaemon`, а маленький
  скрипт-обёртку. Обёртка проксирует stdin/stdout через `socat` к
  сокету выше, выполняясь под `sudo -u PRIMARY_USER` благодаря узкому
  правилу `NOPASSWD` в `sudoers`.
- В итоге `gpg --card-status`, `gpg --sign`, `ssh -A` и прочее у
  `SECONDARY_USER` обслуживаются тем же `scdaemon`, что и у
  `PRIMARY_USER`. PIN-кеш общий — после ввода PIN одним юзером
  второй подписывает без повторного запроса.

## Ограничение

Чтобы прокси работал, `gpg-agent` пользователя `PRIMARY_USER` должен
быть запущен — его первый `gpg --card-status` поднимает `scdaemon` и
создаёт сокет. `install` прогревает сокет автоматически, а
bashrc-сниппет (`gpgconf --launch gpg-agent`) держит агент готовым
при старте оболочки.

Доступ к карте остаётся последовательным (PC/SC отдаёт карту по
одной операции за раз), но видна она обоим, и PIN-кеш не теряется
между ними.

## Использование

```bash
sudo make install   PRIMARY_USER=alice SECONDARY_USER=bob
make status         PRIMARY_USER=alice SECONDARY_USER=bob
sudo make uninstall PRIMARY_USER=alice SECONDARY_USER=bob
```

Переменные `PRIMARY_USER` и `SECONDARY_USER` обязательны — дефолтов нет.

После `install` пользователям нужно открыть **новые** вкладки WSL
(или выполнить `wsl --shutdown` в PowerShell и снова открыть WSL),
чтобы вступило в силу членство в группах `scard` и `plugdev`.

## Подготовка Windows (usbipd-win)

YubiKey виден внутри WSL только если устройство проброшено через
[usbipd-win](https://github.com/dorssel/usbipd-win). Все команды ниже —
в **PowerShell от администратора**.

### Установка

Скопируй и выполни блок целиком — поставит usbipd-win, если его ещё нет,
и покажет версию:

```powershell
if (-not (Get-Command usbipd -ErrorAction SilentlyContinue)) {
    winget install --silent --accept-package-agreements --accept-source-agreements --exact dorssel.usbipd-win
    $env:Path = [System.Environment]::GetEnvironmentVariable('Path','Machine') + ';' + [System.Environment]::GetEnvironmentVariable('Path','User')
}
usbipd --version
```

Альтернативы, если `winget` недоступен:

```powershell
# через Chocolatey
choco install usbipd

# через Scoop
scoop bucket add extras
scoop install usbipd-win
```

Либо MSI с https://github.com/dorssel/usbipd-win/releases.

После установки **перезапусти PowerShell** (или открой новое окно от
администратора), иначе `usbipd` может ещё не оказаться в `PATH`.

### Привязать устройство (один раз, сохраняется между перезагрузками)

```powershell
usbipd list
```

Найди строку с YubiKey, запомни `BUSID` (например `2-1`), затем:

```powershell
usbipd bind --busid 2-1
```

После `bind` устройство помечено как shared и доступно для проброса
в WSL без повторного `bind`.

### Приаттачить к WSL

```powershell
usbipd attach --busid 2-1 --wsl Ubuntu
```

Имя дистрибутива (`Ubuntu`) — из вывода `wsl -l -v`. Если дистрибутив
один, `--wsl` без значения тоже сработает.

`attach` нужно повторять после каждого `wsl --shutdown` или
перезагрузки Windows. Чтобы автоматически переподключать устройство:

```powershell
usbipd attach --busid 2-1 --wsl Ubuntu --auto-attach
```

Флаг `--auto-attach` держит фоновый процесс и приаттачивает устройство
при каждом старте WSL — окно PowerShell должно оставаться открытым.
Альтернатива — задача в Task Scheduler, выполняющая `usbipd attach`
при входе в Windows.

### Проверка из WSL

```bash
lsusb | grep -i yubi
```

Если строка вида `Yubico.com Yubikey ...` появилась — устройство
пробросилось, можно запускать `make install`.

### Отвязать (если потребуется)

```powershell
usbipd detach --busid 2-1
usbipd unbind --busid 2-1
```

## Что устанавливается

- `/etc/polkit-1/rules.d/45-pcscd-scard.rules` — группа `scard` получает
  доступ к pcscd. Нужно потому, что в WSL у пользовательской сессии
  нет активного seat, и стандартное правило `allow_active` не
  пропускает.
- `/etc/sudoers.d/96-yubikey-proxy` — `SECONDARY_USER` может выполнить
  **только** одну конкретную команду (`socat - UNIX-CONNECT:...`) от
  имени `PRIMARY_USER`, ничего больше.
- `/usr/local/bin/scdaemon-proxy.sh` — скрипт-обёртка.
- `~PRIMARY_USER/.gnupg/scdaemon.conf` — `disable-ccid` + `multi-server`.
- `~SECONDARY_USER/.gnupg/gpg-agent.conf` — строка
  `scdaemon-program /usr/local/bin/scdaemon-proxy.sh`.
- В `~/.bashrc` обоих юзеров — экспорт `SSH_AUTH_SOCK` и
  `gpgconf --launch gpg-agent`.

Пакеты, устанавливаемые при отсутствии: `pcscd scdaemon gnupg2
yubikey-manager socat`.

## Зачем так

В WSL2 USB-устройства пробрасываются через `usbipd`, и у
пользовательских сессий нет настоящего seat, из-за чего стандартные
правила polkit для pcscd не дают доступ к карте. К тому же
`scdaemon` GnuPG по умолчанию хватает CCID-интерфейс через libusb
эксклюзивно, и второй пользователь упирается в
`LIBUSB_ERROR_BUSY`. Этот проект приводит всё к одному `scdaemon`
и открывает к нему доступ обоим пользователям через сокет.

## Безопасность

Граница безопасности между `PRIMARY_USER` и `SECONDARY_USER` ослаблена
осознанно: `SECONDARY_USER` пользуется PIN-кешем `PRIMARY_USER`. Это
устраивает, когда оба пользователя принадлежат одному физическому
человеку или членам одной семьи. Не использовать в случаях, когда
разные пользователи системы — это разные люди с разным уровнем
доверия.
