# gpg-wsl

Расшарить одну YubiKey OpenPGP-карту между двумя пользователями WSL
(`PRIMARY_USER`, `SECONDARY_USER`) так, чтобы оба могли использовать её
из `gpg`, `ssh -A` и т.д., без ручного переключения карты между сессиями.

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
