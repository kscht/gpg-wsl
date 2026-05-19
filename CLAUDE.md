# CLAUDE.md

Заметки для будущих сессий Claude Code в этом репозитории.

## О чём проект

Связка для WSL2, которая позволяет одной YubiKey OpenPGP-карте обслуживать
двух пользователей системы одновременно. Один scdaemon (под `PRIMARY_USER`)
работает в `multi-server` режиме; gpg-agent второго пользователя
(`SECONDARY_USER`) через wrapper-скрипт + socat подключается к тому же
scdaemon. Это даёт общий PIN-кеш и снимает конфликт `LIBUSB_ERROR_BUSY`.

## Структура

- `Makefile` — точка входа. Цели `install`, `uninstall`, `status`, `help`.
  Требует `PRIMARY_USER` и `SECONDARY_USER`, дефолтов нет.
- `scripts/install.sh|uninstall.sh|status.sh` — выполняют работу. Получают
  переменные через окружение (`PRIMARY_USER`, `SECONDARY_USER`,
  `PROJECT_DIR`), общая логика в `scripts/lib.sh`.
- `files/` — шаблоны конфигов. Файлы с расширением `.in` содержат
  плейсхолдеры `@PRIMARY_USER@`, `@SECONDARY_USER@`, `@PRIMARY_UID@`,
  которые подставляются функцией `render` из `lib.sh` через `sed`.

## Условности

- В коде нигде не должно быть хардкода имён `kostich`, `kscht` или
  конкретного UID. Если потребовалось добавить — оформить через
  плейсхолдер и `render`.
- Все правки `.bashrc` обрамлены маркерами `# BEGIN gpg-wsl` / `# END
  gpg-wsl` для безопасного удаления.
- Sudoers-правило в `files/sudoers/96-yubikey-proxy.in` экранирует `:`
  как `\:` — это требование грамматики sudoers, не shell.

## Чего не делать

- Не возвращать `pcsc-shared` в `scdaemon.conf`: в этом режиме теряется
  PIN-кеш на карте между Assuan-командами, ssh и подписи падают.
- Не вводить отдельные `disable-ccid` для `SECONDARY_USER`: его
  scdaemon вообще не запускается, его `scdaemon.conf` неактуален.
- Не давать `NOPASSWD: ALL`. Все sudo-исключения должны быть узкими
  (конкретная команда + конкретный target user).
- Не предлагать `gpgsw`-свитчер (старая схема через `pkill чужого
  scdaemon`). Она работает, но проксирование лучше.

## Тестирование изменений

### Автоматическое (CI)

`.github/workflows/test.yml` запускается на push/PR в `main`:

- `shellcheck` (с `-x --severity=warning`) — линт всех скриптов.
- `install-cycle` — на тестовых юзерах `alice`/`bob` прогоняет
  install → verify-artifacts → idempotent install → snippet dedup →
  uninstall → verify-clean.
- `pcsc-visibility` — поднимает виртуальный reader через `vicc`,
  проверяет, что оба тестовых юзера видят его через pcscd
  (покрывает polkit-сторону).

Real OpenPGP/scdaemon-flow CI **не покрывает** — `vsmartcard-vpicc`
эмулирует только ISO-7816, нет OpenPGP applet. Эту часть проверяй
вручную на машине с YubiKey.

### Локальное

1. `sudo make uninstall PRIMARY_USER=… SECONDARY_USER=…` — снести всё.
2. `sudo make install PRIMARY_USER=… SECONDARY_USER=…` — поставить заново.
3. `make status PRIMARY_USER=… SECONDARY_USER=…` — проверить.
4. В двух разных сессиях (по пользователю на каждую) попробовать
   `gpg --card-status` и `ssh -A` — оба должны работать без перехвата
   карты.

Pre-commit:

```bash
pre-commit install     # ставит хук
pre-commit run -a      # прогнать на всех файлах
```

Конфиг — `.pre-commit-config.yaml`, гонит `shellcheck`.

## Ссылки

- Репозиторий: https://github.com/kscht/gpg-wsl
- usbipd-win: https://github.com/dorssel/usbipd-win
- GnuPG scdaemon `--multi-server`, `pcsc-shared`, `disable-ccid`:
  https://www.gnupg.org/documentation/manuals/gnupg/Scdaemon-Options.html
