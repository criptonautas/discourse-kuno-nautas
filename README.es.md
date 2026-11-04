# discourse-kuno-nautas

[![Linting and Tests](https://github.com/criptonautas/discourse-kuno-nautas/actions/workflows/plugin-linting-and-tests.yml/badge.svg)](https://github.com/criptonautas/discourse-kuno-nautas/actions/workflows/plugin-linting-and-tests.yml)

[ENGLISH](README.md) | **ESPAÑOL**

Mantenido por Criptonautas. Sin afiliación ni respaldo de Discourse (Civilized Discourse Construction Kit, Inc.).

**Kunos comunitarios**: recaudaciones en Monero que los miembros publican como temas en el foro, con una barra de progreso que cuenta lo que de verdad llegó al monedero del miembro. Opcionalmente enlazadas a una recaudación en [Kuno](https://codeberg.org/nebras/kuno), en cuyo caso la misma barra cuenta las donaciones hechas en Kuno y en el foro, una sola vez.

El foro nunca guarda fondos. Guarda una clave de **vista** por campaña, que no puede gastar, y la usa para mirar el monedero de la campaña.

## Necesita

[discourse-monero-tips](https://github.com/criptonautas/discourse-monero-tips) con las propinas verificadas configuradas: este plugin reutiliza su `monero-wallet-rpc`, su lock, sus formatos de dirección y sus ajustes `monero_tips_*` (`restore_height`, `min_confirmations`, `min_amount`). Las propinas no se tocan: una campaña es un segundo monedero de solo lectura, aparte, atado al tema y nunca al usuario.

## Cómo funciona

1. Un miembro crea un tema en una categoría de campañas (`kuno_nautas_categories`). Quién puede publicar ahí lo decide el permiso de la categoría.
2. En su propio tema toca **Campaña** y llena un único formulario privado: meta en XMR (vacía si no hay meta), enlace a la recaudación en Kuno (opcional, solo `https://`), la dirección **primaria** del monedero (`4…`, 95 caracteres, lo que acepta Kuno), la clave de vista privada y la fecha de inicio. Las advertencias de abajo se muestran antes del campo de la clave.
3. El tema muestra la barra y un botón **Donar**. Cuenta cada transferencia entrante confirmada al monedero, sea a la dirección que sea; por eso Kuno y el foro suman sin contar dos veces. La cifra propia de Kuno nunca se suma.
4. Al terminar toca **Cerrar campaña**: la clave se olvida y la barra queda congelada en su total final.

Un tema lleva una sola campaña, para siempre: después de cerrarla, una recaudación nueva necesita un tema nuevo. Un monedero que falló (RPC caído, timeout) se reintenta en cada corrida de la sincronización, así que una caída no frena una campaña para siempre.

Los admins pueden armar o cerrar una campaña en el tema de otro miembro; cada acción así queda en el registro de acciones del staff como `monero_campaign_set_up` o `monero_campaign_close`.

Dos tipos de campaña:

| | Donación anónima (por defecto) | "Mostrarme como colaborador" |
|---|---|---|
| **Kuno comunitario** (sin enlace a Kuno) | dirección primaria | una subdirección creada para (tema, donante): su avatar se suma a la barra |
| **Kuno enlazado** (con enlace a Kuno) | dirección primaria | no se ofrece: Kuno solo reconoce pagos a la dirección primaria, así que una donación a una subdirección faltaría en la barra de Kuno |

Las donaciones cuentan a las `monero_tips_min_confirmations` (10 por defecto); Kuno cuenta a más o menos 1, así que las dos cifras difieren por unos bloques.

## Instalación

Agregá esto a `containers/app.yml`, después de `discourse-monero-tips`, y reconstruí:

```yaml
hooks:
  after_code:
    - exec:
        cd: $home/plugins
        cmd:
          - git clone https://github.com/criptonautas/discourse-monero-tips.git
          - git clone https://github.com/criptonautas/discourse-kuno-nautas.git
```

Después activá `kuno_nautas_enabled` y elegí `kuno_nautas_categories`.

## Ajustes

| Ajuste | Para qué |
|---|---|
| `kuno_nautas_enabled` | Apagado por defecto |
| `kuno_nautas_categories` | Categorías cuyos temas pueden llevar una campaña |

Todo lo del RPC del monedero, confirmaciones, polvo y altura de restauración se configura en discourse-monero-tips.

## Qué se les dice a los miembros, y por qué

- **Usá un monedero dedicado y no gastes desde él** mientras la barra esté activa: una clave de vista revela todo el historial de entradas del monedero, pasado y futuro, y el propio vuelto del miembro contaría como donación (en Kuno también).
- **En Kuno, borrá la recaudación cuando termine**: desactivarla deja la clave allá, en texto plano.
- Quien lea la clave de vista de un monedero ve cada pago entrante, para siempre. Nunca puede gastar.

La dirección de la campaña tiene que ser distinta de la dirección de propinas del miembro; si no, las propinas contarían como donaciones.

## Qué guarda el foro

- Campos personalizados del tema, públicos: meta, enlace a Kuno, estado.
- La dirección, la clave de vista (cifrada con una clave derivada del secreto del sitio) y el estado del monedero, en el plugin store, nunca serializados.
- `monero_campaign_donations`: una fila por transferencia entrante, con el donante cuando llegó a una subdirección creada.
- `monero_campaign_addresses`: las subdirecciones creadas.

La altura de restauración de un monedero nuevo sale de la altura de la cadena, leída a través de cualquier monedero ya sincronizado que tenga el RPC, menos un día de bloques por cada día desde el inicio de la campaña, nunca por debajo de `monero_tips_restore_height`. Antes de que exista el primer monedero no hay lectura, y se usa el piso.

`monero-wallet-rpc` no puede borrar un archivo de monedero: cerrar una campaña quita la clave de Discourse y deja de abrir ese monedero, pero el archivo de solo lectura queda en el host del RPC hasta que un operador lo borre.

## Banner

[discourse-kuno-banner](https://github.com/criptonautas/discourse-kuno-banner) lee `monero_campaign` de los temas de la lista y dibuja la barra en los temas con campaña dentro de su rotación diaria, junto a los Kunos externos que apoya.

## Desarrollo

```bash
pnpm install && pnpm lint
```

Specs: `bundle exec rspec plugins/discourse-kuno-nautas/spec`, con discourse-monero-tips instalado. Frontend: `/qunit?filter=Kuno`.

## Licencia

MIT. Ver [LICENSE](LICENSE).

Texto de este README bajo [CC BY-NC-SA 4.0](CC-BY-NC-SA-4.0.txt).
