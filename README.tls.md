---
name: Kafka sink TLS
overview: "Добавить в sink `kafka` опциональный TLS (то, что в Kafka называется SSL / SASL_SSL): шифрование соединения, свой CA и клиентский сертификат. HTTPS и source не трогаем."
todos:
  - id: config-tls
    content: Добавить структуру TLS, валидацию и tlsConfig() в pkg/sink/kafka/config.go
    status: completed
  - id: wire-writer
    content: Передать *tls.Config в kafka.Transport в pkg/sink/kafka/sink.go
    status: completed
isProject: false
---

# TLS для sink kafka

Kafka-брокер шифруется через TLS, а не HTTPS. Адрес в `brokers` остаётся `host:port`. Включение — поле `TLS` у `kafka.Transport` в [pkg/sink/kafka/sink.go](pkg/sink/kafka/sink.go). Сейчас туда попадают только SASL и `MetadataTTL`.

## Конфиг

В [pkg/sink/kafka/config.go](pkg/sink/kafka/config.go) добавить в `Config`:

```go
TLS TLS `yaml:"tls,omitempty"`
```

```go
type TLS struct {
    Enabled            bool   `yaml:"enabled,omitempty"`
    CaCertFile         string `yaml:"caCertFile,omitempty"`
    ClientCertFile     string `yaml:"clientCertFile,omitempty"`
    ClientKeyFile      string `yaml:"clientKeyFile,omitempty"`
    InsecureSkipVerify bool   `yaml:"insecureSkipVerify,omitempty"`
}
```

В `Validate()`: если задан один из `clientCertFile` / `clientKeyFile`, обязательны оба. При `enabled: false` остальные поля не проверять.

Метод `tlsConfig() (*tls.Config, error)`:

- `enabled: false` — вернуть `nil, nil` (соединение без TLS, как сейчас).
- Иначе собрать `*tls.Config`: `InsecureSkipVerify`, при непустом `caCertFile` — PEM в `RootCAs`, при паре cert/key — `tls.LoadX509KeyPair` в `Certificates`.
- Пустой CA не читать с диска (в отличие от `franz.NewTLSConfig`, который падает на пустой строке).

## Подключение в writer

В `Start()` до создания `kafka.Writer` вызвать `c.TLS.tlsConfig()` и передать результат в `Transport.TLS` рядом с существующим `SASL`. `Addr: kafka.TCP(...)` не менять: TLS включается только конфигом транспорта. Ошибка загрузки сертификатов — ошибка старта sink.

Пример:

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
```

SASL и TLS независимы: вместе это `SASL_SSL`, только TLS — `SSL`, клиентский сертификат — mTLS.

Source `type: kafka` не менять.