# WealthArena Troubleshooting Guide

This guide provides detailed solutions for common issues encountered when setting up and running WealthArena.

## Table of Contents

1. [General Troubleshooting](#section-1-general-troubleshooting)
2. [Server Not Running Issues](#section-2-server-not-running-issues)
3. [Port Conflicts](#section-3-port-conflicts)
4. [Dependency Issues](#section-4-dependency-issues)
5. [ChromaDB / Vector Store Issues](#section-5-chromadb--vector-store-issues)
6. [Testing Issues](#section-6-testing-issues)
7. [Data Pipeline Issues](#section-7-data-pipeline-issues)
8. [API and Connection Issues](#section-8-api-and-connection-issues)

---

## Section 1: General Troubleshooting

### Quick Diagnostics

Before diving into specific issues, run these diagnostic commands:

```powershell
# Check server health and prerequisites
python scripts/check_server.py

# Check if API is running
curl http://localhost:8000/healthz

# Check metrics
curl http://localhost:8000/metrics
```

### Common First Steps

1. **Verify Environment Setup**
   - Ensure Python 3.11+ is installed
   - Check that virtual environment (`.venv`) exists
   - Verify `.env` file is configured with `GROQ_API_KEY`

2. **Check Logs**
   - Review console output when starting the server
   - Check for error messages in terminal
   - Look for import errors or missing dependencies

---

## Section 2: Server Not Running Issues

### Symptoms

- Connection refused errors
- `curl http://localhost:8000/healthz` fails
- API endpoints return connection errors
- Server process not found

### Solutions

#### Solution 1: Start the Server

**Windows (PowerShell):**
```powershell
powershell -ExecutionPolicy Bypass -File scripts/dev_up.ps1
```

**macOS/Linux:**
```bash
bash scripts/dev_up.sh
```

**Manual Start:**
```bash
# Activate virtual environment
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

# Start server
python -m uvicorn app.main:app --reload
```

#### Solution 2: Verify Server Started Successfully

Wait for the message: `"Server started successfully!"` or `"Application startup complete"`

Check the console output for:
- ✅ Server running on port 8000
- ✅ No import errors
- ✅ Vector store initialized

#### Solution 3: Check Environment Variables

Ensure `.env` file exists and contains required variables:

```env
GROQ_API_KEY=gsk_your_actual_key_here
CHROMA_PERSIST_DIR=data/vectorstore
APP_HOST=0.0.0.0
APP_PORT=8000
```

#### Solution 4: Verify Dependencies

```powershell
# Check if dependencies are installed
python -c "import fastapi, uvicorn, pydantic, httpx; print('✅ All imports successful')"

# If imports fail, reinstall dependencies
pip install -r requirements.txt
```

#### Solution 5: Check for Port Conflicts

If port 8000 is already in use, see [Section 3: Port Conflicts](#section-3-port-conflicts).

---

## Section 3: Port Conflicts

### Symptoms

- `Address already in use` error
- `Port 8000 is already in use`
- Server fails to start with port binding errors

### Solutions

#### Solution 1: Find and Stop Process Using Port 8000

**Windows (PowerShell):**
```powershell
# Find process using port 8000
netstat -ano | findstr :8000

# Kill the process (replace PID with actual process ID)
taskkill /PID <PID> /F
```

**macOS/Linux:**
```bash
# Find process using port 8000
lsof -i :8000

# Kill the process (replace PID with actual process ID)
kill -9 <PID>
```

#### Solution 2: Use a Different Port

**Option A: Change in .env file**
```env
APP_PORT=8001
```

**Option B: Specify port when starting server**
```bash
uvicorn app.main:app --host 0.0.0.0 --port 8001 --reload
```

**Option C: Use environment variable**
```powershell
# Windows PowerShell
$env:APP_PORT=8001
python -m uvicorn app.main:app --reload

# macOS/Linux
export APP_PORT=8001
python -m uvicorn app.main:app --reload
```

#### Solution 3: Check for Multiple Server Instances

```powershell
# Windows
Get-Process | Where-Object {$_.ProcessName -like "*python*" -or $_.ProcessName -like "*uvicorn*"}

# macOS/Linux
ps aux | grep -E "python|uvicorn"
```

Stop any duplicate server processes before starting a new one.

---

## Section 4: Dependency Issues

### Symptoms

- `ModuleNotFoundError` or `ImportError`
- `No module named 'fastapi'` or similar
- Package installation failures
- Version conflicts

### Solutions

#### Solution 1: Reinstall Dependencies

```powershell
# Activate virtual environment first
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

# Upgrade pip
python -m pip install --upgrade pip

# Install dependencies
pip install -r requirements.txt
```

#### Solution 2: Verify Virtual Environment

```powershell
# Check if virtual environment is activated
# You should see (.venv) in your prompt

# If not activated, activate it:
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

# Verify Python path points to venv
python -c "import sys; print(sys.executable)"
# Should show path to .venv/bin/python or .venv\Scripts\python.exe
```

#### Solution 3: Recreate Virtual Environment

If dependencies are still missing after installation:

```powershell
# Remove old virtual environment
# Windows:
Remove-Item -Recurse -Force .venv
# macOS/Linux:
rm -rf .venv

# Create new virtual environment
python -m venv .venv

# Activate it
# Windows:
.venv\Scripts\activate
# macOS/Linux:
source .venv/bin/activate

# Install dependencies
pip install -r requirements.txt
```

#### Solution 4: Check Python Version

WealthArena requires Python 3.11+:

```powershell
python --version
# Should show Python 3.11.x or higher
```

If you have multiple Python versions, ensure you're using the correct one:

```powershell
# Windows
py -3.11 --version

# macOS/Linux
python3.11 --version
```

#### Solution 5: Install Specific Missing Packages

If a specific package fails to install:

```powershell
# Try installing individually
pip install fastapi
pip install uvicorn
pip install pydantic
pip install chromadb
pip install sentence-transformers
```

#### Solution 6: Handle Version Conflicts

If you encounter version conflicts:

```powershell
# Check installed versions
pip list

# Upgrade specific packages
pip install --upgrade <package-name>

# Or install specific version
pip install <package-name>==<version>
```

---

## Section 5: ChromaDB / Vector Store Issues

### Symptoms

- `No documents in vector store`
- Vector search returns empty results
- ChromaDB initialization errors
- `CHROMA_PERSIST_DIR` path errors

### Solutions

#### Solution 1: Initialize Vector Store

```powershell
# Run initial data load
python scripts/initial_data_load.py

# Or run knowledge base ingestion
python scripts/kb_ingest.py
```

#### Solution 2: Verify Vector Store Path

Check `.env` file:

```env
CHROMA_PERSIST_DIR=data/vectorstore
```

**Important**: Use absolute paths for reliability in containers or production:

```env
# Windows (example)
CHROMA_PERSIST_DIR=C:\Users\DELL\Downloads\WealthArena\data\vectorstore

# macOS/Linux (example)
CHROMA_PERSIST_DIR=/home/user/WealthArena/data/vectorstore
```

#### Solution 3: Check Directory Permissions

Ensure the vector store directory is writable:

```powershell
# Windows
# Check if directory exists and is writable
Test-Path data\vectorstore
New-Item -ItemType Directory -Force -Path data\vectorstore

# macOS/Linux
mkdir -p data/vectorstore
chmod 755 data/vectorstore
```

#### Solution 4: Rebuild Vector Store

If the vector store is corrupted or empty:

```powershell
# Remove existing vector store
# Windows:
Remove-Item -Recurse -Force data\vectorstore
# macOS/Linux:
rm -rf data/vectorstore

# Recreate directory
mkdir data/vectorstore

# Re-run ingestion
python scripts/initial_data_load.py
python scripts/kb_ingest.py
```

#### Solution 5: Verify ChromaDB Installation

```powershell
python -c "import chromadb; print(chromadb.__version__)"
```

If ChromaDB is not installed:

```powershell
pip install chromadb
```

#### Solution 6: Check Vector Store Contents

```powershell
# Check if vector store directory has files
# Windows:
Get-ChildItem data\vectorstore -Recurse
# macOS/Linux:
ls -la data/vectorstore
```

If the directory is empty, run ingestion scripts.

---

## Section 6: Testing Issues

### Symptoms

- Tests fail with connection errors
- `0% success rate` in metrics
- API endpoints not responding during tests
- Import errors in test files

### Solutions

#### Solution 1: Ensure Server is Running

**⚠️ CRITICAL**: The server must be running before running tests!

```powershell
# Start server first
powershell -ExecutionPolicy Bypass -File scripts/dev_up.ps1

# Wait for "Server started successfully!" message

# Then run tests in a NEW terminal
python scripts/print_metrics.py --url http://127.0.0.1:8000 --runs 5
```

#### Solution 2: Verify Server Health Before Testing

```powershell
# Check server is responding
python scripts/check_server.py

# Expected output: "✅ All prerequisites met! Server is ready."
```

#### Solution 3: Check Test Configuration

Ensure tests are pointing to the correct URL:

```powershell
# Default should be http://127.0.0.1:8000
python scripts/print_metrics.py --url http://127.0.0.1:8000

# If using different port
python scripts/print_metrics.py --url http://127.0.0.1:8001
```

#### Solution 4: Run Smoke Tests

```powershell
# Basic endpoint tests
python scripts/smoke_local.py

# API sanity check
python scripts/sanity_check.py
```

#### Solution 5: Check Test Dependencies

```powershell
# Install test dependencies
pip install pytest pytest-cov httpx

# Run pytest
pytest

# Run with coverage
pytest --cov=app --cov-report html
```

#### Solution 6: Fix Import Errors in Tests

If tests have import errors:

```powershell
# Ensure you're in the project root
cd C:\Users\DELL\Downloads\WealthArena

# Activate virtual environment
.venv\Scripts\activate  # Windows
# or
source .venv/bin/activate  # macOS/Linux

# Run tests with Python path
python -m pytest
```

#### Solution 7: Regenerate Metrics

If metrics show 0% success rate, the server was likely not running:

```powershell
# 1. Start server
powershell -ExecutionPolicy Bypass -File scripts/dev_up.ps1

# 2. Wait for server to start

# 3. In new terminal, regenerate metrics
python scripts/print_metrics.py --url http://127.0.0.1:8000 --runs 5
```

---

## Section 7: Data Pipeline Issues

### Symptoms

- No documents in vector store
- Scraper not running
- RSS feed errors
- PDF ingestion stuck or slow

### Solutions

#### Solution 1: No Documents in Vector Store

```powershell
# Run initial data load
python scripts/initial_data_load.py

# Verify data pipeline
python scripts/verify_data_pipeline.py
```

#### Solution 2: Scraper Not Running

```powershell
# Check background job status
curl http://localhost:8000/v1/background/status

# Check logs for scraper errors
# Review console output when server starts
```

#### Solution 3: PDF Ingestion Issues

**Problem**: PDF ingestion gets stuck or takes hours

**Solutions**:

1. **Use smaller batch sizes**:
   ```bash
   python scripts/pdf_ingest.py --batch-size 20 --duplicate-check-batch-size 200
   ```

2. **Enable parallel processing**:
   ```bash
   python scripts/pdf_ingest.py --parallel --max-workers 2
   ```

3. **Resume interrupted uploads**:
   ```bash
   python scripts/pdf_ingest.py --resume
   python scripts/pdf_ingest.py --resume --no-resume-partial
   ```

4. **Skip problematic PDFs**:
   ```bash
   python scripts/pdf_ingest.py --skip-on-error
   ```

**Performance Tips**:
- Typical processing time: 2-5 minutes per PDF
- First batch is slowest (model download + initialization)
- Use `--parallel` for 20+ PDFs

#### Solution 4: RSS Feed Errors

- Check network/firewall settings
- Verify RSS feed URLs are accessible
- Check logs for specific feed errors

#### Solution 5: Reddit Scraping Not Working

Reddit credentials are optional. If not configured, the pipeline will skip Reddit data with a warning.

To enable Reddit scraping:
1. Create Reddit app at https://www.reddit.com/prefs/apps
2. Add credentials to `.env`:
   ```env
   REDDIT_CLIENT_ID=your_client_id
   REDDIT_CLIENT_SECRET=your_client_secret
   REDDIT_USERNAME=your_username
   REDDIT_PASSWORD=your_password
   REDDIT_USER_AGENT=python:com.wealtharena.reddit-scraper:v1.0.0
   ```

#### Solution 6: Investopedia Scraping Issues

Ensure `INVESTOPEDIA_CATEGORIES` is configured in `.env`:

```env
INVESTOPEDIA_CATEGORIES=technical-analysis,fundamental-analysis,risk-management,trading-strategies
```

---

## Section 8: API and Connection Issues

### Symptoms

- API endpoints return errors
- Connection timeouts
- CORS errors
- Authentication failures

### Solutions

#### Solution 1: Verify API Endpoints

```powershell
# Health check
curl http://localhost:8000/healthz

# API docs
# Open in browser: http://localhost:8000/docs

# Metrics
curl http://localhost:8000/metrics
```

#### Solution 2: Check GROQ API Key

```powershell
# Verify API key is set
# Windows PowerShell:
$env:GROQ_API_KEY
# macOS/Linux:
echo $GROQ_API_KEY

# Or check .env file
# Should contain: GROQ_API_KEY=gsk_...
```

Get your API key from: https://console.groq.com/

#### Solution 3: Fix CORS Errors

If using a web UI, add CORS origins to `.env`:

```env
CORS_ALLOWED_ORIGINS=http://localhost:3000,https://yourdomain.com
```

#### Solution 4: Connection Timeouts

- Check network connectivity
- Verify firewall settings
- Increase timeout values if needed
- Check if external APIs (Groq) are accessible

#### Solution 5: Authentication Issues

- Verify API keys are correct
- Check key format (Groq keys start with `gsk_`)
- Ensure keys are not expired
- Check rate limits on API provider

---

## Additional Resources

- **API Documentation**: Visit `http://localhost:8000/docs` when server is running
- **OpenAPI Specification**: Run `python scripts/export_openapi.py`
- **Deployment Guide**: See [DEPLOYMENT.md](../DEPLOYMENT.md)
- **RAG Pipeline Documentation**: See [docs/RAG_PIPELINE.md](RAG_PIPELINE.md)

---

## Still Having Issues?

If you've tried all the solutions above and still encounter problems:

1. **Check Logs**: Review console output and error messages carefully
2. **Verify Environment**: Ensure all environment variables are set correctly
3. **Check Versions**: Verify Python version (3.11+) and package versions
4. **Review Documentation**: Check README.md and other docs for updates
5. **Clean Install**: Try recreating virtual environment and reinstalling dependencies

For deployment-specific issues, see [DEPLOYMENT.md](../DEPLOYMENT.md).

