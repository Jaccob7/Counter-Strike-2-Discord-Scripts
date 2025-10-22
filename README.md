# CS2 Server Monitor

A lightweight bash script that monitors Counter-Strike 2 servers via RCON and posts real-time status updates to Discord using webhooks.

## Features

- 🔄 **Live Updates**: Automatically updates a single Discord message every 20 seconds
- 👥 **Player Tracking**: Shows current player count for each server
- ⏱️ **Restart Countdown**: Displays time until next scheduled restart (supports 3 daily restart times)
- 🎯 **Multi-Server Support**: Monitor multiple CS2 servers simultaneously
- 🤖 **Service Mode**: Run as a background service with start/stop commands
- 💾 **State Persistence**: Maintains message state across restarts

## Prerequisites

The script requires the following dependencies:

- `mcrcon` - Minecraft RCON client (works with CS2)
- `curl` - For Discord webhook communication
- `jq` - JSON processor for API responses
- `bash` - Version 4.0 or higher

### Installing Dependencies

**Ubuntu/Debian:**
```bash
sudo apt-get update
sudo apt-get install mcrcon curl jq
```

**CentOS/RHEL:**
```bash
sudo yum install curl jq
# mcrcon may need to be compiled from source
```

**macOS:**
```bash
brew install mcrcon curl jq
```

## Setup

### 1. Clone the Repository

```bash
git clone https://github.com/yourusername/cs2-server-monitor.git
cd cs2-server-monitor
chmod +x cs2_monitor.sh
```

### 2. Configure the Script

Edit `cs2_monitor.sh` and update the following sections:

#### RCON Password
```bash
RCON_PASSWORD="your_rcon_password_here"
```

#### Discord Webhook
Create a webhook in your Discord server:
1. Go to Server Settings → Integrations → Webhooks
2. Click "New Webhook"
3. Copy the webhook URL
4. Update the script:

```bash
DISCORD_WEBHOOK_URL="https://discord.com/api/webhooks/YOUR_WEBHOOK_URL"
```

#### Server Configuration

Configure your servers in the associative arrays:

```bash
declare -A SERVER_NAMES=(
    ["10.0.0.1:27015"]="Server 1"
    ["10.0.0.1:27016"]="Server 2"
)

declare -A SERVER_PUBLIC_IPS=(
    ["10.0.0.1:27015"]="your.public.ip:27015"
    ["10.0.0.1:27016"]="your.public.ip:27016"
)

declare -A SERVER_EMOJIS=(
    ["10.0.0.1:27015"]="🌊"
    ["10.0.0.1:27016"]="🎮"
)

declare -A SERVER_CHANNELS=(
    ["10.0.0.1:27015"]="<#1234567890123456789>"
    ["10.0.0.1:27016"]="<#1234567890123456789>"
)

SERVERS=(
    "10.0.0.1:27015"
    "10.0.0.1:27016"
)
```

**Note:** Discord channel IDs should be in the format `<#CHANNEL_ID>` to create clickable links.

### 3. Customize Restart Times (Optional)

The script defaults to 8-hour restart cycles at:
- 02:00 (2 AM)
- 10:00 (10 AM)
- 18:00 (6 PM)

To change these times, edit the `calculate_restart_countdown()` function:

```bash
local target_times=("02:00:00" "10:00:00" "18:00:00")
```

## Usage

### Run in Foreground (Testing)
```bash
./cs2_monitor.sh
```

Stop with `Ctrl+C`.

### Run as Background Service

**Start the monitor:**
```bash
./cs2_monitor.sh start
```

**Stop the monitor:**
```bash
./cs2_monitor.sh stop
```

**Check if running:**
```bash
ps aux | grep cs2_monitor
```

## Discord Message Format

The Discord message displays real-time server status with clean, organized formatting:

![Discord Monitor Example](screenshot.png)

Each server shows:
- **Server name** and 24/7 status indicator
- **IP address** with port (clickable for easy copying)
- **Current player count** with status indicator
- **Restart countdown** showing time until next scheduled restart
- **Channel link** for server-specific discussions

The message footer displays total players across all servers and updates automatically every 20 seconds.

## How It Works

1. **RCON Connection**: The script uses `mcrcon` to connect to each CS2 server and execute the `status` command
2. **Player Parsing**: Extracts player count from the RCON response
3. **Countdown Calculation**: Calculates time remaining until next scheduled restart based on clock time
4. **Discord Integration**: 
   - On first run, posts a new message to Discord
   - On subsequent runs, updates the same message (avoids spam)
   - Stores the message ID in `/tmp/cs2_discord_message_id.txt`

## Troubleshooting

### Script won't start
- Check dependencies: `which mcrcon curl jq`
- Verify script has execute permissions: `chmod +x cs2_monitor.sh`

### Can't connect to servers
- Verify RCON is enabled on your CS2 servers
- Check RCON password is correct
- Ensure network connectivity to server IPs
- Test manually: `mcrcon -H 10.0.0.1 -P 27015 -p yourpassword status`

### Discord messages not appearing
- Verify webhook URL is correct
- Check webhook hasn't been deleted from Discord
- Test webhook manually:
```bash
curl -H "Content-Type: application/json" -X POST \
  -d '{"content":"Test message"}' \
  "YOUR_WEBHOOK_URL"
```

### Player count shows 0 or ERROR
- Check RCON response format: `mcrcon -H <host> -P <port> -p <password> status`
- The script may need adjustment if your CS2 version has different output format

## Systemd Service (Optional)

To run as a proper systemd service:

Create `/etc/systemd/system/cs2-monitor.service`:

```ini
[Unit]
Description=CS2 Server Monitor
After=network.target

[Service]
Type=simple
User=youruser
WorkingDirectory=/path/to/cs2-server-monitor
ExecStart=/path/to/cs2-server-monitor/cs2_monitor.sh loop
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
```

Enable and start:
```bash
sudo systemctl daemon-reload
sudo systemctl enable cs2-monitor
sudo systemctl start cs2-monitor
sudo systemctl status cs2-monitor
```

## Security Considerations

⚠️ **Important Security Notes:**

- Never commit your actual RCON password or Discord webhook URL to version control
- Consider using environment variables or a separate config file for secrets
- Restrict file permissions: `chmod 600 cs2_monitor.sh` if it contains secrets
- Use a dedicated Discord webhook for monitoring (easy to revoke if compromised)
- Consider firewall rules to restrict RCON access

## Contributing

Contributions are welcome! Please feel free to submit a Pull Request.

## License

MIT License - feel free to use and modify as needed.

## Acknowledgments

- Built for CS2 server administrators
- Uses `mcrcon` by Tiiffi
- Discord webhook documentation: https://discord.com/developers/docs/resources/webhook

## Support

For issues or questions, please open an issue on GitHub.
