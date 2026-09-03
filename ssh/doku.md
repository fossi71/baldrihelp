1. Status Quo: Was aktuell geloggt wird

Anmeldungen & Sessions (PAM Login-Shipper)

Auslöser: Jedes erfolgreiche Login über SSH, Konsole oder Benutzerwechsel (su).

Inhalt: Benutzername (user), Quell-IP/Terminal (remote_ip), verwendeter Service (sshd, su, login), Zeitstempel.

Datei- & Systemüberwachung (Auditd-Shipper)

sys_config: Schreib- und Rechtemodifikationen an Sicherheitsdateien (/etc/passwd, /etc/shadow, /etc/sudoers).

sys_keys: Änderungen an SSH-Keys (/root/.ssh/authorized_keys).

web_change: Schreibzugriffe und neue Dateien im Web-Root (/var/www/).

honeypot_trigger: Lese- oder Schreibzugriffe auf Lockvogel-Dateien (/var/www/config.old.php).

Beispiel-Payload (JSON-Format an dein Backend):

JSON
{
  "node": "suseweb-clone",
  "event": "audit_event",
  "raw_log": "type=SYSCALL msg=audit(1788443516.126:185554): arch=c000003e syscall=257 success=yes exe=\"/usr/bin/touch\" key=\"sys_config\"",
  "timestamp": "1788443516"
}
2. Was du zusätzlich loggen kannst (Praxisbeispiele)

Du kannst die Datei /etc/audit/rules.d/cms-honeypot.rules beliebig um weitere Regeln ergänzen:

Ausführung von Programmen aus /tmp (Malware-Indikator):

Plaintext
-a always,exit -F arch=b64 -S execve -F dir=/tmp -k tmp_exec
Änderungen an Netzwerkkonfigurationen:

Plaintext
-w /etc/hosts -p wa -k net_config
-w /etc/resolv.conf -p wa -k net_config
Ausführung von Cron- & Scheduled-Jobs:

Plaintext
-w /etc/crontab -p wa -k cron_change
-w /var/spool/cron/crontabs/ -p wa -k cron_change
System-Neustarts oder Herunterfahren:

Plaintext
-w /sbin/shutdown -p x -k power_action
-w /sbin/reboot -p x -k power_action
3. Spickzettel: Regel-Syntax & Einbindung

Auditd-Regeln zur Dateiüberwachung folgen dem Schema:

-w <PFAD> -p <RECHTE> -k <SCHLÜSSEL>

Berechtigungen (-p):

r = Lesen (Read), w = Schreiben (Write), x = Ausführen (Execute), a = Attribute ändern (chmod, chown).

Schlüssel (-k):

Der Bezeichner, über den der Shipper das Event sucht.

So fügst du einen neuen Filter ein:

Regel in /etc/audit/rules.d/cms-honeypot.rules eintragen.

Den neuen Key-Namen in cms-audit-shipper.sh in die Schleife aufnehmen:

for key in sys_config sys_keys web_change honeypot_trigger DEIN_NEUER_KEY; do

Regel-Set im Kernel neu laden:

augen-load