#!/usr/bin/env bash
# Prueba de punta a punta con curl contra la API REST (solo clave pública anon).
# Uso: bash supabase/prueba-api.sh     (crea 1 pedido y mensajes de prueba en "dulces")
set -e
U=https://xcaasrvlpyxfjeyqhyve.supabase.co
AK=$(grep -o "VA_ANON='[^']*'" "$(dirname "$0")/../vendedor/core.js" | cut -d"'" -f2)
H=(-H "apikey: $AK" -H "Authorization: Bearer $AK" -H "Content-Type: application/json")
rpc(){ curl -s "${H[@]}" -X POST "$U/rest/v1/rpc/$1" -d "$2"; echo; }
CL=$(cat /proc/sys/kernel/random/uuid)
echo "== ping (keep-alive)";            rpc va_ping '{}'
echo "== catálogo dulces";              curl -s "${H[@]}" "$U/rest/v1/va_productos?select=id,n,p&biz=eq.dulces&order=orden"; echo
echo "== anon NO puede leer pedidos";   curl -s "${H[@]}" "$U/rest/v1/va_pedidos?select=*&limit=1"; echo
echo "== crear pedido";                 rpc va_crear_pedido "{\"p_biz\":\"dulces\",\"p_cliente\":\"$CL\",\"p_nombre\":\"Prueba API\",\"p_tel\":\"04140000000\",\"p_dir\":\"Centro\",\"p_items\":[{\"id\":\"1\",\"q\":1}],\"p_cuenta\":\"zelle\",\"p_ref_pago\":\"PRUEBA-1\",\"p_ref\":\"ANA01\"}"
echo "== mensaje del cliente";          rpc va_cliente_enviar "{\"p_biz\":\"dulces\",\"p_cliente\":\"$CL\",\"p_nombre\":\"Prueba API\",\"p_texto\":\"Hola, prueba\"}"
echo "== login panel PIN 0000";         TOK=$(rpc va_login_panel '{"p_biz":"dulces","p_pin":"0000"}' | tr -d '"\n'); echo "token: ${TOK:0:8}… (${#TOK} car.)"
echo "== panel ve el pedido";           rpc va_panel_datos "{\"p_token\":\"$TOK\"}" | grep -o '"cod": *"#[0-9]*"' | tail -1
echo "== panel responde";               rpc va_panel_enviar "{\"p_token\":\"$TOK\",\"p_cliente\":\"$CL\",\"p_texto\":\"Recibido, gracias\"}"
echo "== cliente lee su chat";          rpc va_cliente_sync "{\"p_biz\":\"dulces\",\"p_cliente\":\"$CL\"}" | grep -o '"texto": *"[^"]*"'
echo "== cerrar sesión";                rpc va_logout "{\"p_token\":\"$TOK\"}"
