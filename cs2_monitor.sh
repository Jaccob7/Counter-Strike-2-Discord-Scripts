#!/bin/bash
# cs2_monitor.sh
# Monitors CS2 servers via RCON (mcrcon) and updates a single Discord webhook message every 20s.
# The restart countdown is clock-based for 02:00, 10:00, 18:00 restarts.

# ====== CONFIGURATION & SECRETS ======
RCON_PASSWORD="your_rcon_password_here"
DISCORD_WEBHOOK_URL="your_discord_webhook_url_here"

# Temporary files for state management
MESSAGE_ID_FILE="/tmp/cs2_discord_message_id.txt"
PID_FILE="/tmp/cs2_monitor_pid.txt"

# ====== SERVER CONFIG ======
declare -A SERVER_NAMES=(
    ["10.0.0.1:27015"]="Server 1"
    ["10.0.0.1:27016"]="Server 2"
    ["10.0.0.1:27017"]="Server 3"
    ["10.0.0.1:27018"]="Server 4"
)

declare -A SERVER_PUBLIC_IPS=(
    ["10.0.0.1:27015"]="your.public.ip:27015"
    ["10.0.0.1:27016"]="your.public.ip:27016"
    ["10.0.0.1:27017"]="your.public.ip:27017"
    ["10.0.0.1:27018"]="your.public.ip:27018"
)

declare -A SERVER_EMOJIS=(
    ["10.0.0.1:27015"]="🌊"
    ["10.0.0.1:27016"]="🌊"
    ["10.0.0.1:27017"]="🌊"
    ["10.0.0.1:27018"]="🌊"
)

declare -A SERVER_CHANNELS=(
    ["10.0.0.1:27015"]="<#1234567890123456789>"
    ["10.0.0.1:27016"]="<#1234567890123456789>"
    ["10.0.0.1:27017"]="<#1234567890123456789>"
    ["10.0.0.1:27018"]="<#1234567890123456789>"
)

SERVERS=(
    "10.0.0.1:27015"
    "10.0.0.1:27016"
    "10.0.0.1:27017"
    "10.0.0.1:27018"
)

# ====== DEPENDENCY CHECKS ======
check_dependencies() {
    for dep in mcrcon curl jq; do
        if ! command -v "$dep" &> /dev/null; then
            echo "Error: Required dependency '$dep' is not installed."
            exit 1
        fi
    done
}

# ====== PURE CLOCK-BASED COUNTDOWN CALCULATION ======
calculate_restart_countdown() {
    local now_epoch
    local target_epoch
    local remaining_seconds
    local countdown_time
    
    # Get current Unix timestamp
    now_epoch=$(date +%s)
    
    # --- Define the three daily restart times (Local Time) ---
    # The 8-hour cycle restarts at: 02:00, 10:00, and 18:00 (6 PM)
    local target_times=("02:00:00" "10:00:00" "18:00:00")
    
    # Initialize the next target time to tomorrow's first slot as a default
    target_epoch=$(date -d "tomorrow ${target_times[0]}" +%s 2>/dev/null)
    
    # --- Loop through targets to find the closest future restart time ---
    for time_str in "${target_times[@]}"; do
        local current_day_target_epoch
        current_day_target_epoch=$(date -d "${time_str}" +%s 2>/dev/null)
        
        # Check if this target is in the future AND is closer than the current target_epoch
        if [ "$current_day_target_epoch" -gt "$now_epoch" ] && [ "$current_day_target_epoch" -lt "$target_epoch" ]; then
            target_epoch="$current_day_target_epoch"
        fi
    done
    
    # Calculate time difference
    remaining_seconds=$(( target_epoch - now_epoch ))
    
    # Format the remaining seconds into HH:MM:SS
    countdown_time=$(date -u -d "@$remaining_seconds" +%H:%M:%S)
    
    echo "$countdown_time"
}

# ====== GET PLAYER COUNT VIA RCON ======
get_server_info() {
    local server=$1
    local host=${server%%:*}
    local port=${server##*:}
    local response
    local status_code
    
    # Use mcrcon to get server status
    response=$(mcrcon -H "$host" -P "$port" -p "$RCON_PASSWORD" status 2>/dev/null)
    status_code=$?

    local player_count="ERROR"

    if [ $status_code -eq 0 ] && [ -n "$response" ]; then
        
        # 1. Player Count
        # Try to extract the number from a key/value pair
        player_count=$(echo "$response" | grep -oP 'players\s*:\s*\K\d+' | head -1 | tr -d '\n\r')
        
        # Fallback: Count player lines
        if [ -z "$player_count" ] || [ "$player_count" -eq 0 ]; then
            player_count=$(echo "$response" | grep -c "^#")
            [ "$player_count" -gt 0 ] && player_count=$((player_count - 1)) # Subtract 1 for the header line
        fi
        player_count="${player_count:-0}"
    fi

    # Output only the player count
    echo "$player_count"
}

# ====== DISCORD JSON PAYLOAD GENERATION ======
generate_json_payload() {
    local content_text="$1"
    local message_id="$2"

    local action="POST"
    if [ -n "$message_id" ]; then
        action="PATCH"
    fi

    local payload
    payload=$(echo -e "$content_text" | jq -Rs --arg action "$action" '
        if $action == "PATCH" then
            {content: ., flags: 0}
        else
            {content: ., flags: 0}
        end
    ')
    echo "$payload"
}

# ====== DISCORD POST / PATCH ======
send_initial_discord_message() {
    local message=$1
    local json_payload
    json_payload=$(generate_json_payload "$message" "")

    local response
    local http_code
    response=$(curl -s -o /dev/stdout -w "%{http_code}" -H "Content-Type: application/json" -X POST -d "$json_payload" "$DISCORD_WEBHOOK_URL?wait=true")
    
    http_code="${response: -3}"
    response="${response:0:${#response}-3}"

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        local message_id
        message_id=$(echo "$response" | jq -r '.id // empty')

        if [ -n "$message_id" ]; then
            echo "$message_id" > "$MESSAGE_ID_FILE"
            echo "Initial message posted to Discord (ID: $message_id)"
            return 0
        else
            echo "Failed to parse message ID from successful POST response." >&2
            return 1
        fi
    else
        echo "Failed to post initial message to Discord (HTTP $http_code)" >&2
        echo "Response: $response" >&2
        return 1
    fi
}

update_discord_message() {
    local message=$1
    local message_id=$2
    local json_payload
    json_payload=$(generate_json_payload "$message" "$message_id")

    local webhook_id webhook_token
    webhook_id=$(echo "$DISCORD_WEBHOOK_URL" | grep -oP 'webhooks/\K\d+')
    webhook_token=$(echo "$DISCORD_WEBHOOK_URL" | grep -oP 'webhooks/\d+/\K[^/]+')

    local http_code
    http_code=$(curl -s -o /dev/null -w "%{http_code}" -H "Content-Type: application/json" -X PATCH \
        -d "$json_payload" \
        "https://discord.com/api/webhooks/${webhook_id}/${webhook_token}/messages/${message_id}")

    if [ "$http_code" -ge 200 ] && [ "$http_code" -lt 300 ]; then
        return 0 # Success
    else
        echo "Discord PATCH failed (Message ID: $message_id). HTTP code: $http_code" >&2
        return 1 # Failure
    fi
}

# ====== MAIN MONITOR LOOP ======
monitor_servers() {
    check_dependencies

    echo "==================================="
    echo "       CS2 Server Monitor (RCON)       "
    echo "==================================="

    local message_id=""
    local first_run=true

    if [ -f "$MESSAGE_ID_FILE" ]; then
        message_id=$(cat "$MESSAGE_ID_FILE")
        first_run=false
    fi

    while true; do
        echo "[$(date '+%Y-%m-%d %H:%M:%S')] Checking servers..."
        
        # --- 1. Calculate the Countdown ONCE per loop ---
        local restart_countdown
        restart_countdown=$(calculate_restart_countdown)
        
        local message_content=""
        local total_players=0

        # --- Header ---
        message_content+="**🎮 CS2 SERVERS 🎮**\n\n"

        # --- Iterate servers and build message body ---
        for server in "${SERVERS[@]}"; do
            # Get only player_count from the simplified function
            local player_count
            player_count=$(get_server_info "$server")
            
            server_name="${SERVER_NAMES[$server]}"
            public_ip="${SERVER_PUBLIC_IPS[$server]}"
            emoji="${SERVER_EMOJIS[$server]}"
            channels="${SERVER_CHANNELS[$server]}"

            # Determine server status and format the line
            if [ "$player_count" = "ERROR" ]; then
                message_content+="${emoji} **${server_name}** | 🔴 **OFFLINE**\n"
                message_content+="→ \`${public_ip}\`\n\n"
                echo "  $server_name - OFFLINE"
            else
                # ensure numeric
                player_count=$((player_count + 0))
                total_players=$((total_players + player_count))

                local status_tag=" | 24/7"
                
                # --- Newlines to separate metrics ---
                message_content+="${emoji} **${server_name}${status_tag}**\n"
                message_content+="→ \`${public_ip}\`\n" 
                message_content+="🟢 **${player_count} players**\n" 
                message_content+="🔄 **${restart_countdown}** (Restart)\n"
                message_content+="${channels}\n\n" 
                
                # Log the data 
                echo "  $server_name - $player_count players, Countdown: $restart_countdown"
            fi
        done

        # --- Footer ---
        message_content+="\n**👥 Total Players Online: ${total_players}**\n"
        message_content+="_Updates every 20 seconds_"


        # --- Discord Communication ---
        if [ "$first_run" = true ]; then
            if send_initial_discord_message "$message_content"; then
                if [ -f "$MESSAGE_ID_FILE" ]; then
                    message_id=$(cat "$MESSAGE_ID_FILE")
                    first_run=false
                fi
            else
                echo "Will retry sending initial Discord message on next loop."
            fi
        else
            if [ -n "$message_id" ]; then
                if update_discord_message "$message_content" "$message_id"; then
                    echo "Discord message updated"
                else
                    echo "Discord update failed. Clearing old message ID and retrying on next cycle..."
                    rm -f "$MESSAGE_ID_FILE"
                    message_id=""
                    first_run=true
                fi
            else
                echo "No message ID found, attempting to create new message..."
                if send_initial_discord_message "$message_content"; then
                    message_id=$(cat "$MESSAGE_ID_FILE")
                fi
            fi
        fi

        echo ""
        sleep 20
    done
}

# ====== SERVICE CONTROL FUNCTIONS ======
cleanup() {
    echo -e "\n\nMonitoring stopped."
    [ -f "$MESSAGE_ID_FILE" ] && rm "$MESSAGE_ID_FILE"
    [ -f "$PID_FILE" ] && rm "$PID_FILE"
    exit 0
}

start_service() {
    if [ -f "$PID_FILE" ]; then
        echo "Monitor is already running (PID $(cat "$PID_FILE"))."
        exit 0
    fi
    SCRIPT_PATH=$(realpath "$0")
    echo "Starting monitor loop in background..."
    "$SCRIPT_PATH" fg-loop &
    echo $! > "$PID_FILE"
    echo "Monitor started with PID $!."
}

stop_service() {
    if [ -f "$PID_FILE" ]; then
        PID=$(cat "$PID_FILE")
        echo "Stopping monitor (PID $PID)..."
        kill "$PID" 2>/dev/null
        rm "$PID_FILE"
        echo "Monitor stopped."
        [ -f "$MESSAGE_ID_FILE" ] && rm "$MESSAGE_ID_FILE"
    else
        echo "Monitor is not running or PID file not found."
    fi
}

# ====== MAIN EXECUTION ENTRY POINT ======
case "$1" in
    start)
        start_service
        ;;
    stop)
        stop_service
        ;;
    loop)
        trap cleanup SIGINT SIGTERM
        monitor_servers
        ;;
    fg-loop)
        trap cleanup SIGINT SIGTERM
        monitor_servers
        ;;
    *)
        trap cleanup SIGINT
        monitor_servers
        ;;
esac
