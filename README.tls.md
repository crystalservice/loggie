# TLS для sink kafka

Опциональный TLS для sink `type: kafka` (в терминах Kafka — SSL / SASL_SSL): шифрование соединения с брокером, свой CA и клиентский сертификат (mTLS).

Адрес в `brokers` остаётся `host:port` — TLS включается только секцией `tls`, не схемой URL. SASL и TLS независимы: вместе это `SASL_SSL`, только TLS — `SSL`, с клиентским сертификатом — mTLS.

## Настройки `tls`

| Поле | Тип | По умолчанию | Описание |
|------|-----|--------------|----------|
| `enabled` | bool | `false` | Включить TLS. При `false` остальные поля игнорируются, соединение без шифрования. |
| `caCertFile` | string | — | Путь к PEM-файлу CA для проверки сертификата брокера. Если пусто — используются системные корневые CA. |
| `clientCertFile` | string | — | Путь к клиентскому сертификату (PEM) для mTLS. Задаётся только вместе с `clientKeyFile`. |
| `clientKeyFile` | string | — | Путь к приватному ключу клиента (PEM). Задаётся только вместе с `clientCertFile`. |
| `insecureSkipVerify` | bool | `false` | Не проверять сертификат брокера. Только для отладки — в проде не использовать. |

### Валидация

- При `enabled: false` остальные поля не проверяются.
- Если задан один из `clientCertFile` / `clientKeyFile`, обязательны оба.
- Ошибка чтения или разбора сертификатов при старте sink — ошибка запуска.

## Как работает проверка

В TLS две независимые стороны проверки:

1. **Клиент → брокер** — Loggie проверяет сертификат Kafka (`caCertFile` / системные CA, либо отключение через `insecureSkipVerify`).
2. **Брокер → клиент** — Kafka проверяет сертификат Loggie (**mTLS**: `clientCertFile` + `clientKeyFile`). Это предъявление своего сертификата брокеру, а не проверка CA клиентом.

При `enabled: true` канал всегда шифруется. `insecureSkipVerify` и отсутствие клиентского сертификата влияют только на проверку личности, не на шифрование.

### `caCertFile`

| Значение | Поведение |
|----------|-----------|
| задан | Сертификат брокера проверяется по этому CA (если `insecureSkipVerify: false`). |
| пустой | Используются системные корневые CA. |
| + `insecureSkipVerify: true` | CA не используется для решения «доверять / нет» — проверка пропускается. |

`caCertFile` не заменяет клиентский сертификат и не включает mTLS.

### `clientCertFile` + `clientKeyFile`

| Значение | Поведение |
|----------|-----------|
| оба заданы | Loggie предъявляет клиентский сертификат в handshake. Если брокер настроен на mTLS — ок; если нет — обычно игнорирует. |
| оба пустые | Клиентский cert не отправляется. Если брокер требует mTLS — соединение упадёт. |
| задан только один | Ошибка валидации при старте. |

Эти поля не участвуют в проверке сертификата брокера — только в аутентификации клиента.

### Типичные комбинации

| Конфиг | Что происходит |
|--------|----------------|
| только `enabled: true` | Шифрование; брокер проверяется по системным CA. |
| + `caCertFile` | Шифрование; брокер проверяется по указанному CA. |
| + `insecureSkipVerify: true` | Шифрование; личность брокера не проверяется. |
| + `clientCertFile` / `clientKeyFile` | То же + mTLS (если брокер это требует или принимает). |
| CA + client cert/key, `insecureSkipVerify: false` | Полный прод-вариант: шифрование + доверие к брокеру + клиентский сертификат. |

Кратко: `caCertFile` — «кому я доверяю как брокеру»; `clientCertFile` / `clientKeyFile` — «вот кто я для брокера»; `insecureSkipVerify` — «не проверяй брокера» (перебивает смысл CA).

## Пример

```yaml
sink:
  type: kafka
  brokers: ["kafka.example.com:9093"]
  topic: loggie
  sasl:
    type: scram
    username: loggie
    password: secret
    algorithm: sha512
  tls:
    enabled: true
    caCertFile: /etc/loggie/certs/ca.pem
    clientCertFile: /etc/loggie/certs/client.crt
    clientKeyFile: /etc/loggie/certs/client.key
    insecureSkipVerify: false
```

Минимальный вариант (только шифрование с проверкой по своему CA, без mTLS и без SASL):

```yaml
sink:
  type: kafka
  brokers: ["kafka.example.com:9093"]
  topic: loggie
  tls:
    enabled: true
    caCertFile: /etc/loggie/certs/ca.pem
```
