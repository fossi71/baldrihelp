#!/bin/bash
set -e

# Prüfen, ob als root ausgeführt
if [ "$EUID" -ne 0 ]; then
  echo "[FEHLER] Bitte als root oder mit sudo ausführen."
  exit 1
fi

TARGET_BIN="/usr/local/bin/notify-login.sh"
PAM_FILE="/etc/pam.d/common-session"
PAM_ENTRY="session optional pam_exec.so seteuid $TARGET_BIN"

echo "==> Installiere ntfy Login-Notification..."

# 1. Login-Skript erzeugen (baut das Topic dynamisch aus $(hostname)_ntfy zusammen)
cat << 'EOF' > "$TARGET_BIN"
#!/bin/bash

if [ "$PAM_TYPE" = "open_session" ]; then
    USER_NAME="$PAM_USER"
    SERVICE_NAME="$PAM_SERVICE"
    RHOST="${PAM_RHOST:-lokal}"
    HOSTNAME="$(hostname)"

    TOPIC="${HOSTNAME}_ntfy"
    SERVER_URL="${NTFY_SERVER_URL:-https://ntfy.sh}"

    TITLE="Login auf $HOSTNAME"
    MESSAGE="User '$USER_NAME' via '$SERVICE_NAME' (IP: $RHOST)"

    curl -s \
      -H "Title: $TITLE" \
      -H "Priority: high" \
      -H "Tags: warning,key" \
      -d "$MESSAGE" \
      "${SERVER_URL}/${TOPIC}" > /dev/null 2>&1 &
fi
EOF

# 2. Ausführbar machen & Rechte setzen
chmod 755 "$TARGET_BIN"
chown root:root "$TARGET_BIN"

# 3. In PAM eintragen (duplikatfrei)
if ! grep -qF "$PAM_ENTRY" "$PAM_FILE"; then
    echo "$PAM_ENTRY" >> "$PAM_FILE"
    echo "[OK] PAM-Eintrag in $PAM_FILE hinzugefügt."
else
    echo "[INFO] PAM-Eintrag war bereits vorhanden."
fi

# 4. Statusmeldung mit dynamischem Topic
HOSTNAME=$(hostname)
echo "==> Erfolgreich installiert!"
echo "ntfy-Topic für diesen Server: https://ntfy.sh/${HOSTNAME}_ntfy"