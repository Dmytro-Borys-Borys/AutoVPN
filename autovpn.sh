#!/bin/bash

# este script se debe de ejecutar en el equipo cliente

# no es necesaria la instalación previa de openvpn (se va a realizar mediante el script)

# es imperativo el poder hacer ssh al servidor desde el cliente con la cuenta definida debajo
# para evitar errores se recomienda utilizar cuenta root (de lo contrario la copia de la clave privada puede fallar)
# para habilitar el acceso de la cuenta root por ssh se necesita editar /etc/ssh/sshd_config en el servidor
# se necesita establecer (antes de recargar el servidor, evidentemente)
# PermitRootLogin yes
# PasswordAuthentication yes


# Declarar variables para el certificados. son comunes para los 3 salvo 1 excepción
COUNTRY="ES"                  # país
STATE="Cantabria"             # estado
CITY="Torrelavega"            # localidad
ORG="IES Miguel Herrero"      # organización
OU="IT"                       # unidad organizativa
EMAIL="admin@mydomain.com"    # correo
DURATION=1825                 # duración

# --------- es muy importante que los ajustes de common name debajo tengan valores distintos ---------
# está prohibido que la autoridad certificadora tenga el mismo common name que los certificados hijos
CNCA="ca.com"                 # common name del certificado raíz
CN="openssl.com"              # common name de los certificados server y client.


# Declarar variables server
SERVER_IP="10.5.2.12"         # básicamente, esto es lo único que hay que cambiar en todo el script y todo funcionará de serie
SERVER_USER="root"            # siempre y cuando se haya dado acceso a root por ssh como se indicaba arriba

OPVN_SERVER_DIR="/etc/openvpn/server"                         # Directorio donde se guardarán los archivos de OpenVPN
OVPN_SERVER_CA_KEY="$OPVN_SERVER_DIR/ca.key"                  # Ruta para el archivo de clave del certificado raíz (CA)
OVPN_SERVER_CA_CRT="$OPVN_SERVER_DIR/ca.crt"                  # Ruta para el archivo de certificado raíz (CA)
OVPN_DH_PARAM="$OPVN_SERVER_DIR/dh2048.pem"                   # Ruta para el archivo de parámetros DH
OVPN_SERVER_KEY="$OPVN_SERVER_DIR/server-vpn.key"             # Ruta para el archivo de clave del servidor
OVPN_SERVER_P10="$OPVN_SERVER_DIR/server-vpn.p10"             # Ruta para el archivo de solicitud de firma de certificado del servidor
OVPN_SERVER_CRT="$OPVN_SERVER_DIR/server-vpn.crt"             # Ruta para el archivo de certificado del servidor
OVPN_SERVER_CONF="$OPVN_SERVER_DIR/server-vpn.conf"           # Ruta para el archivo de configuración del servidor
OVPN_SERVERSIDE_CLIENT_KEY="$OPVN_SERVER_DIR/client-vpn.key"  # Ruta para el archivo de clave del servidor
OVPN_SERVERSIDE_CLIENT_P10="$OPVN_SERVER_DIR/client-vpn.p10"  # Ruta para el archivo de solicitud de firma de certificado del servidor
OVPN_SERVERSIDE_CLIENT_CRT="$OPVN_SERVER_DIR/client-vpn.crt"  # Ruta para el archivo de certificado del servidor
OVPN_SERVER_LOG="/var/log/server-vpn.log"                     # Ruta para el archivo de registro del servidor
OVPN_TUN_IP="10.0.0.1" # Dirección IP del túnel de OpenVPN


# Declarar variables client

OVPN_CLIENT_DIR="/etc/openvpn/client"                         # Directorio donde se guardarán los archivos de OpenVPN
#OVPN_CLIENT_CA_KEY="$OVPN_CLIENT_DIR/ca.key"                 # Ruta para el archivo de clave del certificado raíz (CA)
OVPN_CLIENT_CA_CRT="$OVPN_CLIENT_DIR/ca.crt"                  # Ruta para el archivo de certificado raíz (CA)
OVPN_CLIENT_KEY="$OVPN_CLIENT_DIR/client-vpn.key"             # Ruta para el archivo de clave del servidor
#OVPN_CLIENT_P10="$OVPN_CLIENT_DIR/client-vpn.p10"            # Ruta para el archivo de solicitud de firma de certificado del servidor
OVPN_CLIENT_CRT="$OVPN_CLIENT_DIR/client-vpn.crt"             # Ruta para el archivo de certificado del servidor
OVPN_CLIENT_CONF="$OVPN_CLIENT_DIR/client-vpn.conf"           # Ruta para el archivo de configuración del servidor
OVPN_CLIENT_LOG="/var/log/client-vpn.log"                     # Ruta para el archivo de registro del servidor
OVPN_CLIENT_IP="10.0.0.2"                                     # Dirección IP del cliente de OpenVPN

# intentar copiar la clave pública al servidor para facilitar ssh
ssh-copy-id $SERVER_USER@$SERVER_IP || (ssh-keygen -t rsa -f ~/.ssh/id_rsa -N '' && ssh-copy-id $SERVER_USER@$SERVER_IP )

# Ajustes de servidor. Aquí empieza la magia
ssh $SERVER_USER@$SERVER_IP << EOF

# comprobar si hace falta instalar openvpn
apt --installed list | grep -q openvpn || (apt update && apt install openvpn -y)

# Crear directorio si no existe
mkdir -p $OPVN_SERVER_DIR
cd $OPVN_SERVER_DIR || exit

# Generar clave y certificado raíz (CA)
openssl genrsa -out $OVPN_SERVER_CA_KEY 2048
openssl req -new -x509 -key $OVPN_SERVER_CA_KEY -out $OVPN_SERVER_CA_CRT -days $DURATION \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CNCA/emailAddress=$EMAIL"

# Generar parámetros DH
openssl dhparam -out $OVPN_DH_PARAM -check -text -5 2048

# Generar clave y certificado del servidor
openssl genrsa -out $OVPN_SERVER_KEY 2048
openssl req -new -key $OVPN_SERVER_KEY -out $OVPN_SERVER_P10 \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CN/emailAddress=$EMAIL"
openssl x509 -req -in $OVPN_SERVER_P10 -out $OVPN_SERVER_CRT -CA $OVPN_SERVER_CA_CRT -CAkey $OVPN_SERVER_CA_KEY -CAcreateserial -days $DURATION

# Generar clave y certificado del cliente
openssl genrsa -out $OVPN_SERVERSIDE_CLIENT_KEY 2048
openssl req -new -key $OVPN_SERVERSIDE_CLIENT_KEY -out $OVPN_SERVERSIDE_CLIENT_P10 \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$OU/CN=$CN/emailAddress=$EMAIL"
openssl x509 -req -in $OVPN_SERVERSIDE_CLIENT_P10 -out $OVPN_SERVERSIDE_CLIENT_CRT -CA $OVPN_SERVER_CA_CRT -CAkey $OVPN_SERVER_CA_KEY -CAcreateserial -days $DURATION

# Generar archivo de configuración del servidor. Más magia!
cat <<SERVERCONF > $OVPN_SERVER_CONF
dev tun                     # Selecciona el tipo de dispositivo de red (tun/tap)
ifconfig $OVPN_TUN_IP $OVPN_CLIENT_IP # Asigna la dirección IP del túnel y del cliente
tls-server                  # Activa el modo servidor de OpenVPN con TLS
dh   $OVPN_DH_PARAM         # Especifica el archivo de parámetros DH
ca   $OVPN_SERVER_CA_CRT    # Especifica el archivo de certificado raíz (CA)
cert $OVPN_SERVER_CRT       # Especifica el archivo de certificado del servidor
key  $OVPN_SERVER_KEY       # Especifica el archivo de clave del servidor
comp-lzo                    # Habilita la compresión LZO
keepalive 20 100            # Configura los parámetros de keepalive
log $OVPN_SERVER_LOG        # Especifica el archivo de registro del servidor
verb 3                      # Establece el nivel de verbosidad
SERVERCONF

# Iniciar servidor OpenVPN en segundo plano
openvpn $OVPN_SERVER_CONF &>> $OVPN_SERVER_LOG &

EOF

# comprobar si hace falta instalar openvpn
apt --installed list | grep -q openvpn || (apt update && apt install openvpn -y)

# Crear directorio si no existe
mkdir -p $OVPN_CLIENT_DIR
cd $OVPN_CLIENT_DIR || exit
# copia de certificados y claves necesarias
# scp $SERVER_USER@$SERVER_IP:$OVPN_SERVER_CA_KEY $OVPN_CLIENT_CA_KEY
scp $SERVER_USER@$SERVER_IP:$OVPN_SERVER_CA_CRT $OVPN_CLIENT_CA_CRT
scp $SERVER_USER@$SERVER_IP:$OVPN_SERVERSIDE_CLIENT_KEY $OVPN_CLIENT_KEY
scp $SERVER_USER@$SERVER_IP:$OVPN_SERVERSIDE_CLIENT_CRT $OVPN_CLIENT_CRT




# Generar archivo de configuración del servidor
cat <<CLIENTCONF > $OVPN_CLIENT_CONF
dev tun                     # Selecciona el tipo de dispositivo de red (tun/tap)
ifconfig $OVPN_CLIENT_IP $OVPN_TUN_IP # Asigna la dirección IP del túnel y del servidor
tls-client                  # Activa el modo cliente de OpenVPN con TLS
remote $SERVER_IP           # IP del servidor remoto
ca   $OVPN_CLIENT_CA_CRT    # Especifica el archivo de certificado raíz (CA)
cert $OVPN_CLIENT_CRT       # Especifica el archivo de certificado del cliente
key  $OVPN_CLIENT_KEY       # Especifica el archivo de clave del cliente
comp-lzo                    # Habilita la compresión LZO
keepalive 20 100            # Configura los parámetros de keepalive
log $OVPN_CLIENT_LOG        # Especifica el archivo de registro del cliente
verb 3                      # Establece el nivel de verbosidad
CLIENTCONF

# Iniciar servidor OpenVPN en segundo plano
openvpn $OVPN_CLIENT_CONF &>> $OVPN_CLIENT_LOG &
tail -f $OVPN_CLIENT_LOG
