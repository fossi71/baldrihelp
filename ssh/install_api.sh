#!/bin/bash
set -e

# --- KONFIGURATION ---
# Traefik-Bypass URL & Echter Key
CMS_URL="${CMS_URL:-https://baldricore.baldri.com/index.php?ajax=1&action=ingest}"
API_KEY="${API_KEY:-DEIN_GEHEIMER_API_KEY_HIER}"
# ----------------------

if [ "$EUID" -ne 0 ]; then
  echo "[FEHLER] Bitte als root oder mit sudo ausführen."
  exit 1
fi

TARGET_PAM_BIN="/usr/local/bin/cms-login-shipper.sh"
TARGET_AUDIT_BIN="/usr/local/bin/cms-audit-shipper.sh"
PAM_FILE="/etc/pam.d/common-session"
PAM_ENTRY="session optional pam_exec.so seteuid $TARGET_PAM_BIN"

echo "==> Installiere CMS-Security-Shipper & Auditd..."

# 1. Benötigte Pakete installieren
echo "[1/5] Installiere Pakete (auditd, jq, curl)..."
apt-get update -qq
apt-get install -y -qq auditd jq curl > /dev/null

# 2. Login-Shipper für PAM erzeugen (JSON an CMS)
echo "[2/5] Erzeuge PAM Login-Shipper..."
cat << 'EOF' > "$TARGET_PAM_BIN"
#!/bin/bash

if [ "$PAM_TYPE" = "open_session" ]; then
    USER_NAME="$PAM_USER"
    SERVICE_NAME="$PAM_SERVICE"
    RHOST="${PAM_RHOST:-lokal}"
    HOSTNAME="$(hostname)"

    PAYLOAD=$(jq -n \
        --arg node "$HOSTNAME" \
        --arg type "login" \
        --arg user "$USER_NAME" \
        --arg ip "$RHOST" \
        --arg service "$SERVICE_NAME" \
        --arg time "$(date +%s)" \
        '{node: $node, event: $type, user: $user, remote_ip: $ip, service: $service, timestamp: $time}')

    curl -s -A "Mozilla/5.0 (Windows NT 10.0; Win64; x64)" -X POST "@@CMS_URL@@" \
         -H "Content-Type: application/json" \
         -H "X-API-Key: @@API_KEY@@" \
         -d "$PAYLOAD" > /dev/null 2>&1 &
fi
EOF

sed -i "s|@@CMS_URL@@|$CMS_URL|g" "$TARGET_PAM_BIN"
sed -i "s|@@API_KEY@@|$API_KEY|g" "$TARGET_PAM_BIN"
chmod 755 "$TARGET_PAM_BIN"
chown root:root "$TARGET_PAM_BIN"

# 3. In PAM eintragen (duplikatfrei)
echo "[3/5] Registriere PAM-Modul..."
if ! grep -qF "$PAM_ENTRY" "$PAM_FILE"; then
    echo "$PAM_ENTRY" >> "$PAM_FILE"
    echo "[OK] PAM-Eintrag in $PAM_FILE hinzugefügt."
else
    echo "[INFO] PAM-Eintrag war bereits vorhanden."
fi

# 4. Kernel-Audit-Regeln (Dateien & Honeypot)
echo "[4/5] Konfiguriere auditd-Regeln..."
cat << 'EOF' > /etc/audit/rules.d/cms-honeypot.rules
# Critical System Files
-w /etc/passwd -p wa -k sys_config
-w /etc/shadow -p wa -k sys_config
-w /etc/sudoers -p wa -k sys_config
-w /root/.ssh/authorized_keys -p wa -k sys_keys

# Web & Honeypot Targets
-w /var/www/ -p wa -k web_change
-w /var/www/config.old.php -p rwa -k honeypot_trigger
EOF

augen-load > /dev/null 2>&1 || auditctl -R /etc/audit/rules.d/cms-honeypot.rules

# 5. Audit-Shipper & Cronjob anlegen
echo "[5/5] Erzeuge Audit-Log-Shipper (Cronjob)..."
cat << 'EOF' > "$TARGET_AUDIT_BIN"
#!/bin/bash

LOGS=$(ausearch -ts recent -k sys_config -k sys_keys -k web_change -k honeypot_trigger 2>/dev/null | ausearch-probes 2>/dev/null || true)

if [ -n "$LOGS" ]; then
    PAYLOAD=$(jq -n \
        --arg node "$(hostname)" \
        --arg type "audit_event" \
        --arg raw "$LOGS" \
        --arg time "$(date +%s)" \
        '{node: $node, event: $type, raw_log: $raw, timestamp: $time}')

    curl -s -X POST "@@CMS_URL@@" \
         -H "Content-Type: application/json" \
         -H "X-API-Key: @@API_KEY@@" \
         -d "$PAYLOAD" > /dev/null 2>&1
fi
EOF

sed -i "s|@@CMS_URL@@|$CMS_URL|g" "$TARGET_AUDIT_BIN"
sed -i "s|@@API_KEY@@|$API_KEY|g" "$TARGET_AUDIT_BIN"
chmod 755 "$TARGET_AUDIT_BIN"
chown root:root "$TARGET_AUDIT_BIN"

# Cronjob stumm im Minuten-Takt
(crontab -l 2>/dev/null | grep -v "$TARGET_AUDIT_BIN" ; echo "* * * * * $TARGET_AUDIT_BIN >/dev/null 2>&1") | crontab -

echo "==> Erfolgreich installiert!"
echo "Server '$(hostname)' meldet Logins & Audit-Events an: $CMS_URL"