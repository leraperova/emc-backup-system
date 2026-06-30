DB_NAME="emc_clinic"
BACKUP_DIR="/var/backups/emc"
NAS_MOUNT="/mnt/nas/backups"
S3_BUCKET="s3://emc-backups"
TIMESTAMP=$(date +%Y%m%d_%H%M)
TEMP_FILE="$BACKUP_DIR/emc_${TIMESTAMP}.dump.zst"
ENCRYPTED_FILE="$BACKUP_DIR/emc_${TIMESTAMP}.dump.zst.enc"
KEY_FILE="/etc/backup/emc.key"
LOG_FILE="/var/log/emc_backup.log"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $1" | tee -a "$LOG_FILE"
}

log "=== НАЧАЛО РЕЗЕРВНОГО КОПИРОВАНИЯ ==="


log "Создание дампа PostgreSQL..."
pg_dump -U postgres -Fc "$DB_NAME" | zstd -o "$TEMP_FILE"
log "Дамп создан: $(du -h "$TEMP_FILE" | cut -f1)"

log "Шифрование AES-256-CBC..."
openssl enc -aes-256-cbc -pbkdf2 -iter 100000 \
    -in "$TEMP_FILE" \
    -out "$ENCRYPTED_FILE" \
    -pass file:"$KEY_FILE"
shred -u "$TEMP_FILE"
log "Файл зашифрован: $ENCRYPTED_FILE"

log "Копирование на NAS..."
cp "$ENCRYPTED_FILE" "$NAS_MOUNT/"
log "Копия на NAS сохранена"

log "Отправка в облачное хранилище..."
s3cmd put "$ENCRYPTED_FILE" "$S3_BUCKET/" --encrypt
log "Копия в облаке сохранена"

log "Ротация старых копий..."
find "$BACKUP_DIR" -name "*.enc" -mtime +7 -delete
find "$NAS_MOUNT" -name "*.enc" -mtime +7 -delete
s3cmd ls "$S3_BUCKET/" | grep -v "$(date +%Y%m)" | while read -r line; do
    s3cmd rm "$(echo "$line" | awk '{print $NF}')"
done
log "Ротация завершена"

log "=== РЕЗЕРВНОЕ КОПИРОВАНИЕ УСПЕШНО ЗАВЕРШЕНО ==="
