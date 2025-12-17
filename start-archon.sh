#!/bin/bash
# Archon Startup Script - Bypasses corporate proxy for local services
# Location: /mnt/c/Users/nunezes1/Downloads/Projects/MCP Servers/Archon/start-archon.sh
#
# Usage:
#   ./start-archon.sh          # Start all services
#   ./start-archon.sh stop     # Stop all services
#   ./start-archon.sh restart  # Restart all services
#   ./start-archon.sh status   # Check status of all services

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PYTHON_DIR="$SCRIPT_DIR/python"
FRONTEND_DIR="$SCRIPT_DIR/archon-ui-main"
LOG_DIR="/tmp"

# Load nvm for Node.js 20+ (required for frontend)
export NVM_DIR="$HOME/.nvm"
[ -s "$NVM_DIR/nvm.sh" ] && \. "$NVM_DIR/nvm.sh"

# Environment variables
export SUPABASE_URL="https://tnqukarrenvlwlzkimet.supabase.co"
export SUPABASE_SERVICE_KEY="eyJhbGciOiJIUzI1NiIsInR5cCI6IkpXVCJ9.eyJpc3MiOiJzdXBhYmFzZSIsInJlZiI6InRucXVrYXJyZW52bHdsemtpbWV0Iiwicm9sZSI6InNlcnZpY2Vfcm9sZSIsImlhdCI6MTc2NDI0NDMxOCwiZXhwIjoyMDc5ODIwMzE4fQ.m2PwMz-j7T_VTJI5IAwKc0kRJm_SoAlp6sp2DW7N3-w"
export ARCHON_SERVER_PORT=8181

# Ensure no_proxy is set for localhost (bypass corporate proxy)
export no_proxy="localhost,127.0.0.1,::1${no_proxy:+,$no_proxy}"
export NO_PROXY="$no_proxy"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

print_status() {
    echo -e "${GREEN}[✓]${NC} $1"
}

print_error() {
    echo -e "${RED}[✗]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[!]${NC} $1"
}

check_status() {
    echo "=== Archon Services Status ==="
    echo ""

    # Check MCP Docker container
    if docker ps --format '{{.Names}}' | grep -q "archon-mcp"; then
        MCP_STATUS=$(docker ps --filter "name=archon-mcp" --format "{{.Status}}")
        print_status "Archon MCP (Docker): $MCP_STATUS"
    else
        print_error "Archon MCP (Docker): Not running"
    fi

    # Check Server process (check port 8181 for reliability)
    SERVER_PID=$(lsof -ti :8181 2>/dev/null | head -1)
    if [ -n "$SERVER_PID" ]; then
        print_status "Archon Server (Local): Running (PID: $SERVER_PID)"
    else
        print_error "Archon Server (Local): Not running"
    fi

    # Check Frontend process (check port 3737)
    FRONTEND_PID=$(lsof -ti :3737 2>/dev/null | head -1)
    if [ -n "$FRONTEND_PID" ]; then
        print_status "Archon Frontend (Local): Running (PID: $FRONTEND_PID)"
    else
        print_error "Archon Frontend (Local): Not running"
    fi

    echo ""
    echo "=== Health Checks ==="

    # Health check MCP
    if curl -s --max-time 2 http://localhost:8051/mcp > /dev/null 2>&1; then
        print_status "MCP endpoint (http://localhost:8051/mcp): Responding"
    else
        print_warning "MCP endpoint: May need session initialization"
    fi

    # Health check Server
    HEALTH=$(curl -s --max-time 2 http://localhost:8181/health 2>/dev/null)
    if echo "$HEALTH" | grep -q "healthy"; then
        print_status "Server endpoint (http://localhost:8181/health): Healthy"
    else
        print_error "Server endpoint: Not responding"
    fi

    # Health check Frontend
    FRONTEND_STATUS=$(curl -s -o /dev/null -w "%{http_code}" --max-time 2 http://localhost:3737 2>/dev/null)
    if [ "$FRONTEND_STATUS" = "200" ]; then
        print_status "Frontend (http://localhost:3737): Responding"
    else
        print_error "Frontend: Not responding"
    fi

    # Check MCP -> Server connectivity (inside container)
    if docker ps --format '{{.Names}}' | grep -q "archon-mcp"; then
        INTERNAL_HEALTH=$(docker exec archon-mcp python -c "import httpx; r = httpx.get('http://host.docker.internal:8181/health', timeout=2); print(r.text)" 2>/dev/null)
        if echo "$INTERNAL_HEALTH" | grep -q "healthy"; then
            print_status "MCP -> Server connectivity: Working (via host.docker.internal)"
        else
            print_warning "MCP -> Server connectivity: Not working (MCP can't reach local server)"
        fi
    fi
}

stop_services() {
    echo "=== Stopping Archon Services ==="

    # Stop MCP Docker container
    if docker ps --format '{{.Names}}' | grep -q "archon-mcp"; then
        echo "Stopping Archon MCP Docker container..."
        docker stop archon-mcp > /dev/null 2>&1 && print_status "Archon MCP stopped" || print_error "Failed to stop MCP"
    else
        print_warning "Archon MCP was not running"
    fi

    # Stop Server process (by port 8181)
    SERVER_PID=$(lsof -ti :8181 2>/dev/null | head -1)
    if [ -n "$SERVER_PID" ]; then
        echo "Stopping Archon Server (PID: $SERVER_PID)..."
        kill "$SERVER_PID" 2>/dev/null && print_status "Archon Server stopped" || print_error "Failed to stop Server"
    else
        print_warning "Archon Server was not running"
    fi

    # Stop Frontend process (by port 3737)
    FRONTEND_PID=$(lsof -ti :3737 2>/dev/null | head -1)
    if [ -n "$FRONTEND_PID" ]; then
        echo "Stopping Archon Frontend (PID: $FRONTEND_PID)..."
        kill "$FRONTEND_PID" 2>/dev/null && print_status "Archon Frontend stopped" || print_error "Failed to stop Frontend"
    else
        print_warning "Archon Frontend was not running"
    fi
}

start_services() {
    echo "=== Starting Archon Services ==="
    echo ""

    # Start MCP Docker container with host.docker.internal for local server access
    echo "Starting Archon MCP (Docker)..."
    if docker ps --format '{{.Names}}' | grep -q "archon-mcp"; then
        docker restart archon-mcp > /dev/null 2>&1
        print_status "Archon MCP restarted"
    elif docker ps -a --format '{{.Names}}' | grep -q "archon-mcp"; then
        docker start archon-mcp > /dev/null 2>&1
        print_status "Archon MCP started"
    else
        # Create new container with host.docker.internal bridge to reach local server
        echo "Creating new Archon MCP container..."
        docker run -d \
            --name archon-mcp \
            -p 8051:8051 \
            -e SUPABASE_URL="$SUPABASE_URL" \
            -e SUPABASE_SERVICE_KEY="$SUPABASE_SERVICE_KEY" \
            -e TRANSPORT=sse \
            -e LOG_LEVEL=INFO \
            -e ARCHON_SERVER_HOST=host.docker.internal \
            -e ARCHON_SERVER_PORT=8181 \
            -e SERVICE_DISCOVERY_MODE=manual \
            --add-host=host.docker.internal:host-gateway \
            archon-mcp:latest > /dev/null 2>&1 \
            && print_status "Archon MCP container created and started" \
            || print_error "Failed to create Archon MCP container. Build image first: docker compose build archon-mcp"
    fi

    # Start Server locally (bypasses proxy issues with Docker build)
    echo "Starting Archon Server (Local)..."
    if lsof -ti :8181 > /dev/null 2>&1; then
        print_warning "Archon Server already running"
    else
        # Start server in background with proper environment
        cd "$PYTHON_DIR"
        SUPABASE_URL="$SUPABASE_URL" \
        SUPABASE_SERVICE_KEY="$SUPABASE_SERVICE_KEY" \
        ARCHON_SERVER_PORT="$ARCHON_SERVER_PORT" \
        no_proxy="$no_proxy" \
        NO_PROXY="$NO_PROXY" \
        setsid "$PYTHON_DIR/.venv/bin/python" -m uvicorn src.server.main:app --host 0.0.0.0 --port 8181 > "$LOG_DIR/archon-server.log" 2>&1 &
        cd "$SCRIPT_DIR"
        sleep 10

        if lsof -ti :8181 > /dev/null 2>&1; then
            print_status "Archon Server started (log: $LOG_DIR/archon-server.log)"
        else
            print_error "Failed to start Archon Server. Check $LOG_DIR/archon-server.log"
        fi
    fi

    # Start Frontend locally (requires Node.js 20+ via nvm)
    echo "Starting Archon Frontend (Local)..."
    if lsof -ti :3737 > /dev/null 2>&1; then
        print_warning "Archon Frontend already running"
    else
        cd "$FRONTEND_DIR"
        # Check if node_modules exists
        if [ ! -d "node_modules" ]; then
            echo "Installing frontend dependencies..."
            npm install > "$LOG_DIR/archon-frontend-install.log" 2>&1
        fi
        setsid npm run dev > "$LOG_DIR/archon-frontend.log" 2>&1 &
        cd "$SCRIPT_DIR"
        sleep 8

        if lsof -ti :3737 > /dev/null 2>&1; then
            print_status "Archon Frontend started (log: $LOG_DIR/archon-frontend.log)"
        else
            print_error "Failed to start Archon Frontend. Check $LOG_DIR/archon-frontend.log"
        fi
    fi

    echo ""
    sleep 2
    check_status
}

rebuild_mcp() {
    echo "=== Rebuilding Archon MCP Container ==="

    # Stop and remove existing container
    if docker ps -a --format '{{.Names}}' | grep -q "archon-mcp"; then
        echo "Removing existing container..."
        docker stop archon-mcp > /dev/null 2>&1 || true
        docker rm archon-mcp > /dev/null 2>&1 || true
        print_status "Old container removed"
    fi

    # Create new container with proper configuration
    echo "Creating new Archon MCP container with host.docker.internal bridge..."
    docker run -d \
        --name archon-mcp \
        -p 8051:8051 \
        -e SUPABASE_URL="$SUPABASE_URL" \
        -e SUPABASE_SERVICE_KEY="$SUPABASE_SERVICE_KEY" \
        -e TRANSPORT=sse \
        -e LOG_LEVEL=INFO \
        -e ARCHON_SERVER_HOST=host.docker.internal \
        -e ARCHON_SERVER_PORT=8181 \
        -e SERVICE_DISCOVERY_MODE=manual \
        --add-host=host.docker.internal:host-gateway \
        archon-mcp:latest > /dev/null 2>&1 \
        && print_status "Archon MCP container created and started" \
        || print_error "Failed to create container. Build image first: docker compose build archon-mcp"

    echo ""
    sleep 3
    check_status
    echo ""
    print_warning "Run '/mcp' in Claude Code to reconnect to the MCP server"
}

# Main script logic
case "${1:-start}" in
    start)
        start_services
        ;;
    stop)
        stop_services
        ;;
    restart)
        stop_services
        echo ""
        sleep 2
        start_services
        ;;
    status)
        check_status
        ;;
    rebuild)
        rebuild_mcp
        ;;
    *)
        echo "Usage: $0 {start|stop|restart|status|rebuild}"
        echo ""
        echo "Commands:"
        echo "  start    - Start all Archon services"
        echo "  stop     - Stop all Archon services"
        echo "  restart  - Restart all Archon services"
        echo "  status   - Check status of all services"
        echo "  rebuild  - Rebuild MCP container with host.docker.internal bridge"
        exit 1
        ;;
esac
