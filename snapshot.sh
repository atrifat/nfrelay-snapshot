#!/bin/sh
set -o pipefail 2>/dev/null || true

# Set timezone in UTC.
export TZ=UTC

# Set maximum number of retries
MAX_RETRIES=${MAX_RETRIES:-3}
RETRY_DELAY=${RETRY_DELAY:-30} # seconds
RELAY="${RELAY:-wss://nfrelay.app/?content=all}"
MINIMUM_EVENTS_CHECK="${MINIMUM_EVENTS_CHECK:-5}"

# Get the start of yesterday (UTC) in Unix time
SINCE=${SINCE:-$(date -d 'yesterday 00:00:00 UTC' '+%s')}
# Also get yesterday's date in YYYYMMDD format
SINCE_DATE=$(date -d @$SINCE '+%Y%m%d')

# Get the start of today (UTC) in Unix time
UNTIL=${UNTIL:-$(date -d 'today 00:00:00 UTC' '+%s')}
# Also get today's date in YYYYMMDD format
UNTIL_DATE=$(date -d @$UNTIL '+%Y%m%d')

BACKUP_FILE=${BACKUP_FILE:-"backup_${SINCE_DATE}_to_${UNTIL_DATE}.jsonl.gz"}

echo "Starting regular snapshot..."
echo "At: $(date)"
echo "Backup of '$RELAY'"
echo "Since: $SINCE ($SINCE_DATE), Until: $UNTIL ($UNTIL_DATE)"

# Check if nak exists and is executable
if [ ! -f "$(which nak)" ]; then
    echo "Error: nak is not found" >&2
    exit 1
elif [ ! -x "$(which nak)" ]; then
    echo "Error: nak is not executable" >&2
    exit 1
fi

# Try to run the command with retries
attempt=1
success=false

while [ $attempt -le $MAX_RETRIES ] && [ "$success" = false ]; do
    echo "Attempt $attempt of $MAX_RETRIES: Running regular backup..."

    exit_code=0

    # Check if backup file exists
    if [ -f "$BACKUP_FILE" ]; then
        echo "Backup file $BACKUP_FILE already exists. Aborting."
    else
        # Backup relay events
        nak req --paginate -s $SINCE -u $UNTIL $RELAY | gzip >$BACKUP_FILE
        exit_code=$?
    fi

    # Check if the file is empty using wc
    if [[ "$BACKUP_FILE" == *.gz ]]; then
        line_count=$(zcat "$BACKUP_FILE" 2>/dev/null | wc -l || echo 0)
    else
        line_count=$(wc -l <"$BACKUP_FILE" 2>/dev/null || echo 0)
    fi

    echo "$line_count events"

    if [ "$line_count" -lt $MINIMUM_EVENTS_CHECK ]; then
        echo "Error: Command failed due to number of events smaller than minimum number expected. Backup is probably incorrect or corrupted." >&2
        exit_code=1
        # Remove incorrect or corrupted backup.
        rm -f $BACKUP_FILE || true
    fi

    if [ $exit_code -eq 0 ]; then
        echo "Successfully completed on attempt $attempt"
        success=true
    else
        echo "Error: Command failed with exit code $exit_code on attempt $attempt" >&2

        if [ $attempt -lt $MAX_RETRIES ]; then
            echo "Retrying in $RETRY_DELAY seconds..."
            sleep $RETRY_DELAY
        else
            echo "Maximum retry attempts reached. Giving up." >&2
        fi

        ( (attempt++))
    fi
done

echo "At: $(date)"
if [ "$success" = true ]; then
    echo "Data backup is completed and saved to $BACKUP_FILE"
    exit 0
else
    echo "Failed to backup data after $MAX_RETRIES attempts" >&2
    exit 1
fi
