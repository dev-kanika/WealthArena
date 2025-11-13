# ============================================================================
# WealthArena Master Deployment Script
# ============================================================================
# This script handles all deployment scenarios:
#   - Data Pipeline: PDF ingestion and vector store setup
#   - Docker Deployment: Build and run containerized application
#   - Azure Deployment: Deploy to Azure App Service
# ============================================================================
#
# Usage:
#   # Data Pipeline (default)
#   .\deploy-master.ps1
#   .\deploy-master.ps1 --skip-pdf-ingest
#   .\deploy-master.ps1 --full-refresh
#
#   # Docker Deployment
#   .\deploy-master.ps1 --deploy docker
#   .\deploy-master.ps1 --deploy docker -Build
#   .\deploy-master.ps1 --deploy docker -Run
#   .\deploy-master.ps1 --deploy docker -Stop
#   .\deploy-master.ps1 --deploy docker -Logs
#
#   # Azure Deployment
#   .\deploy-master.ps1 --deploy azure -ResourceGroup "rg-wealtharena" -AppName "wealtharena-api"
#   .\deploy-master.ps1 --deploy azure -ResourceGroup "rg-wealtharena" -AppName "wealtharena-api" -Location "eastus" -Sku "B1"
# ============================================================================

param(
    [Parameter(Mandatory=$false)]
    [string]$Deploy = "pipeline",
    
    # Pipeline options
    [Parameter(Mandatory=$false)]
    [switch]$SkipPdfIngest,
    
    [Parameter(Mandatory=$false)]
    [switch]$FullRefresh,
    
    [Parameter(Mandatory=$false)]
    [string]$PdfTimeout = "150",
    
    # Docker options
    [Parameter(Mandatory=$false)]
    [string]$Tag = "latest",
    
    [Parameter(Mandatory=$false)]
    [switch]$Build,
    
    [Parameter(Mandatory=$false)]
    [switch]$Run,
    
    [Parameter(Mandatory=$false)]
    [switch]$Stop,
    
    [Parameter(Mandatory=$false)]
    [switch]$Logs,
    
    # Azure options
    [Parameter(Mandatory=$false)]
    [string]$ResourceGroup,
    
    [Parameter(Mandatory=$false)]
    [string]$AppName,
    
    [Parameter(Mandatory=$false)]
    [string]$Location = "eastus",
    
    [Parameter(Mandatory=$false)]
    [string]$Sku = "B1",
    
    [Parameter(Mandatory=$false)]
    [string]$PythonVersion = "3.12",
    
    [Parameter(Mandatory=$false)]
    [switch]$EnableBackgroundScheduler
)

$ErrorActionPreference = "Stop"

# Handle --deploy syntax (PowerShell doesn't support -- prefix natively)
# Check unbound arguments and command line for --deploy
$unboundArgs = $MyInvocation.UnboundArguments
if ($unboundArgs) {
    for ($i = 0; $i -lt $unboundArgs.Count; $i++) {
        if ($unboundArgs[$i] -eq "--deploy" -and $i + 1 -lt $unboundArgs.Count) {
            $Deploy = $unboundArgs[$i + 1]
            break
        }
    }
}

# Also check $args for --deploy (fallback)
if ($args.Count -gt 0) {
    for ($i = 0; $i -lt $args.Count; $i++) {
        if ($args[$i] -eq "--deploy" -and $i + 1 -lt $args.Count) {
            $Deploy = $args[$i + 1]
            break
        }
    }
}

# Check if PdfTimeout was accidentally set to a deploy value (parameter binding error recovery)
$validDeployValues = @("pipeline", "docker", "azure")
if ($PdfTimeout -in $validDeployValues) {
    # PdfTimeout was bound to a deploy value, swap them
    $Deploy = $PdfTimeout
    $PdfTimeout = "150"
}

# Convert PdfTimeout to int (now that we've handled any binding issues)
try {
    $PdfTimeout = [int]$PdfTimeout
} catch {
    Write-Warning "Invalid PdfTimeout value: $PdfTimeout. Using default: 150"
    $PdfTimeout = 150
}

# Validate Deploy parameter value
if ($Deploy -notin $validDeployValues) {
    Write-Error "Invalid Deploy value: $Deploy. Must be one of: $($validDeployValues -join ', ')"
    Write-Info "Usage: .\deploy-master.ps1 -Deploy docker"
    Write-Info "   or: .\deploy-master.ps1 --deploy docker"
    exit 1
}

# Configuration
$DATA_DIR = "data"
$OUTPUT_DIR = $DATA_DIR
$PIPELINE_SCRIPT = "scripts/run_pipeline.py"

# Helper functions
function Write-Step {
    param([string]$Message)
    Write-Host "`n========================================" -ForegroundColor Cyan
    Write-Host "[STEP] $Message" -ForegroundColor Cyan
    Write-Host "========================================`n" -ForegroundColor Cyan
}

function Write-Success {
    param([string]$Message)
    Write-Host "[OK] $Message" -ForegroundColor Green
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Yellow
}

# ============================================================================
# DOCKER DEPLOYMENT
# ============================================================================
function Deploy-Docker {
    Write-Step "Docker Deployment"
    
    # Check Docker
    Write-Info "Checking Docker..."
    try {
        $dockerVersion = docker --version 2>&1
        Write-Success "Docker found: $dockerVersion"
    } catch {
        Write-Error "Docker not found. Please install Docker Desktop."
        exit 1
    }
    
    # Check .env file
    if (-not (Test-Path ".env")) {
        Write-Error ".env file not found. Please create one from .env.example"
        exit 1
    }
    Write-Success ".env file found"
    
    $imageName = "wealtharena-api:$Tag"
    
    # Build
    if ($Build -or (-not ($Run -or $Stop -or $Logs))) {
        Write-Step "Building Docker Image"
        Write-Info "Building $imageName..."
        docker build -t $imageName .
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Image built successfully"
        } else {
            Write-Error "Build failed"
            exit 1
        }
    }
    
    # Run
    if ($Run -or (-not ($Build -or $Stop -or $Logs))) {
        Write-Step "Starting Container"
        
        # Stop existing container if running
        $existing = docker ps -a --filter "name=wealtharena-api" --format "{{.Names}}"
        if ($existing -eq "wealtharena-api") {
            Write-Info "Stopping existing container..."
            docker stop wealtharena-api 2>&1 | Out-Null
            docker rm wealtharena-api 2>&1 | Out-Null
        }
        
        Write-Info "Starting container..."
        $dockerEnvVars = @(
            "--env-file", ".env",
            "-e", "CHROMA_PERSIST_DIR=/app/data/vectorstore"
        )
        
        # Set ENABLE_BACKGROUND_SCHEDULER if flag is provided
        if ($EnableBackgroundScheduler) {
            $dockerEnvVars += "-e", "ENABLE_BACKGROUND_SCHEDULER=true"
            Write-Info "Background scheduler will be enabled"
        }
        
        docker run -d `
            --name wealtharena-api `
            -p 8000:8000 `
            $dockerEnvVars `
            -v "${PWD}/data:/app/data" `
            --restart unless-stopped `
            $imageName
        
        if ($LASTEXITCODE -eq 0) {
            Write-Success "Container started"
            Write-Info "Waiting for health check (10 seconds)..."
            Start-Sleep -Seconds 10
            
            try {
                $health = Invoke-RestMethod -Uri "http://localhost:8000/healthz" -TimeoutSec 5
                Write-Success "Health check passed: $($health | ConvertTo-Json)"
            } catch {
                Write-Info "Health check pending. View logs: docker logs wealtharena-api"
            }
            
            Write-Host "`nContainer is running!" -ForegroundColor Green
            Write-Host "  API: http://localhost:8000" -ForegroundColor Cyan
            Write-Host "  Docs: http://localhost:8000/docs" -ForegroundColor Cyan
            Write-Host "  Health: http://localhost:8000/healthz" -ForegroundColor Cyan
            Write-Host "`nView logs: docker logs -f wealtharena-api" -ForegroundColor Yellow
        } else {
            Write-Error "Failed to start container"
            exit 1
        }
    }
    
    # Stop
    if ($Stop) {
        Write-Step "Stopping Container"
        docker stop wealtharena-api 2>&1 | Out-Null
        docker rm wealtharena-api 2>&1 | Out-Null
        Write-Success "Container stopped and removed"
    }
    
    # Logs
    if ($Logs) {
        docker logs -f wealtharena-api
    }
}

# ============================================================================
# AZURE DEPLOYMENT
# ============================================================================
function Deploy-Azure {
    Write-Step "Azure App Service Deployment"
    
    if (-not $ResourceGroup -or -not $AppName) {
        Write-Error "Azure deployment requires -ResourceGroup and -AppName parameters"
        Write-Info "Example: .\deploy-master.ps1 --deploy azure -ResourceGroup rg-wealtharena -AppName wealtharena-api"
        exit 1
    }
    
    # Check Azure CLI
    Write-Info "Checking Azure CLI..."
    try {
        $azVersion = az --version 2>&1 | Select-Object -First 1
        Write-Success "Azure CLI found: $azVersion"
    } catch {
        Write-Error "Azure CLI not found. Please install from https://aka.ms/installazurecliwindows"
        exit 1
    }
    
    # Check if logged in
    Write-Info "Checking Azure login status..."
    # Suppress Azure CLI warnings (e.g., 32-bit Python on 64-bit Windows)
    $ErrorActionPreference = 'SilentlyContinue'
    $accountShowArgs = @("account", "show")
    $account = & az @accountShowArgs 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        Write-Error "Not logged in to Azure. Please run: az login"
        exit 1
    }
    Write-Success "Logged in to Azure"
    
    # Trim and validate Python version
    Write-Info "Validating Python version..."
    $PythonVersion = $PythonVersion.Trim()
    $runtimeString = "PYTHON|$PythonVersion"
    
    # Optionally validate runtime exists
    Write-Info "Checking available Python runtimes..."
    $ErrorActionPreference = 'SilentlyContinue'
    $listRuntimesArgs = @("webapp", "list-runtimes", "--os", "linux")
    $availableRuntimesOutput = & az @listRuntimesArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
    $ErrorActionPreference = 'Stop'
    
    # Check if runtime exists in the output (handle both JSON and text formats)
    $runtimeFound = $false
    if ($availableRuntimesOutput) {
        # Convert output to string if it's an array
        $runtimeOutputString = if ($availableRuntimesOutput -is [array]) {
            $availableRuntimesOutput -join "`n"
        } else {
            [string]$availableRuntimesOutput
        }
        
        # Check if runtime string exists in output (case-insensitive)
        if ($runtimeOutputString -match [regex]::Escape($runtimeString)) {
            $runtimeFound = $true
        }
    }
    
    if (-not $runtimeFound) {
        Write-Warning "Python runtime '$runtimeString' not found in available runtimes. Continuing anyway - Azure may accept it."
        Write-Info "Available Python runtimes can be checked with: az webapp list-runtimes --os linux"
        Write-Info "If deployment fails, try a different Python version (e.g., 3.11, 3.10)"
    } else {
        Write-Success "Python version validated: $PythonVersion"
    }
    
    # Check .env file
    Write-Info "Checking .env file..."
    if (-not (Test-Path ".env")) {
        Write-Error ".env file not found. Please create one from .env.example"
        exit 1
    }
    Write-Success ".env file found"
    
    # Create Resource Group
    Write-Step "Ensuring Resource Group Exists"
    # Suppress Azure CLI warnings (e.g., 32-bit Python on 64-bit Windows)
    $ErrorActionPreference = 'SilentlyContinue'
    $rgArgs = @("group", "exists", "--name", $ResourceGroup)
    $rgExists = & az @rgArgs 2>&1
    $ErrorActionPreference = 'Stop'
    if ($rgExists -eq "false") {
        Write-Info "Creating resource group: $ResourceGroup"
        $rgCreateArgs = @("group", "create", "--name", $ResourceGroup, "--location", $Location)
        $null = & az @rgCreateArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
        Write-Success "Resource group created"
    } else {
        Write-Success "Resource group already exists"
    }
    
    # Create App Service Plan
    Write-Step "Ensuring App Service Plan Exists"
    $planName = "$AppName-plan"
    # Suppress Azure CLI warnings (e.g., 32-bit Python on 64-bit Windows)
    $ErrorActionPreference = 'SilentlyContinue'
    $planShowArgs = @("appservice", "plan", "show", "--name", $planName, "--resource-group", $ResourceGroup)
    $planExists = & az @planShowArgs 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating App Service plan: $planName"
        $planCreateArgs = @("appservice", "plan", "create", "--name", $planName, "--resource-group", $ResourceGroup, "--location", $Location, "--sku", $Sku, "--is-linux")
        $null = & az @planCreateArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
        Write-Success "App Service plan created"
    } else {
        Write-Success "App Service plan already exists"
    }
    
    # Create Web App
    Write-Step "Ensuring Web App Exists"
    # Suppress Azure CLI warnings (e.g., 32-bit Python on 64-bit Windows)
    $ErrorActionPreference = 'SilentlyContinue'
    $appShowArgs = @("webapp", "show", "--name", $AppName, "--resource-group", $ResourceGroup)
    $appExists = & az @appShowArgs 2>&1 | Out-Null
    $ErrorActionPreference = 'Stop'
    if ($LASTEXITCODE -ne 0) {
        Write-Info "Creating Web App: $AppName"
        $appCreateArgs = @("webapp", "create", "--name", $AppName, "--resource-group", $ResourceGroup, "--plan", $planName, "--runtime", $runtimeString)
        $null = & az @appCreateArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
        Write-Success "Web App created"
    } else {
        Write-Success "Web App already exists"
    }
    
    # Configure App Settings
    Write-Step "Configuring App Settings"
    
    # Critical: Remove WEBSITE_RUN_FROM_PACKAGE
    Write-Info "Removing WEBSITE_RUN_FROM_PACKAGE setting..."
    $appSettingsDeleteArgs = @("webapp", "config", "appsettings", "delete", "--name", $AppName, "--resource-group", $ResourceGroup, "--setting-names", "WEBSITE_RUN_FROM_PACKAGE")
    $null = & az @appSettingsDeleteArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
    
    # Enable Oryx build
    Write-Info "Enabling Oryx build..."
    $appSettingsSetArgs = @("webapp", "config", "appsettings", "set", "--name", $AppName, "--resource-group", $ResourceGroup, "--settings", "SCM_DO_BUILD_DURING_DEPLOYMENT=true")
    $null = & az @appSettingsSetArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
    
    # Set Python version
    Write-Info "Setting Python version..."
    $configSetRuntimeArgs = @("webapp", "config", "set", "--name", $AppName, "--resource-group", $ResourceGroup, "--linux-fx-version", $runtimeString)
    $null = & az @configSetRuntimeArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
    
    # Set startup command
    Write-Info "Setting startup command..."
    $startupCmd = "gunicorn --bind 0.0.0.0:8000 --workers 2 --worker-class uvicorn.workers.UvicornWorker --timeout 240 app.main:app"
    $configSetStartupArgs = @("webapp", "config", "set", "--name", $AppName, "--resource-group", $ResourceGroup, "--startup-file", $startupCmd)
    $null = & az @configSetStartupArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
    
    # Load environment variables from .env
    Write-Info "Loading environment variables from .env..."
    $envVars = @{}
    Get-Content ".env" | ForEach-Object {
        if ($_ -match '^([^#][^=]+)=(.*)$') {
            $key = $matches[1].Trim()
            $value = $matches[2].Trim()
            if ($key -and $value) {
                # Skip CHROMA_PERSIST_DIR to avoid propagating Windows paths to Azure
                if ($key -ne "CHROMA_PERSIST_DIR") {
                    $envVars[$key] = $value
                }
            }
        }
    }
    
    # Set container-appropriate path for CHROMA_PERSIST_DIR in Azure
    # Use /home/data/vectorstore to match Azure Files mount path (if configured)
    # This path is consistent with the Azure Files mount path documented in DEPLOYMENT.md
    $envVars["CHROMA_PERSIST_DIR"] = "/home/data/vectorstore"
    
    # Set ENABLE_BACKGROUND_SCHEDULER if flag is provided
    if ($EnableBackgroundScheduler) {
        $envVars["ENABLE_BACKGROUND_SCHEDULER"] = "true"
        Write-Info "Background scheduler will be enabled in Azure deployment"
    }
    
    # Convert to Azure format
    $settings = @()
    foreach ($key in $envVars.Keys) {
        $settings += "$key=$($envVars[$key])"
    }
    
    if ($settings.Count -gt 0) {
        $appSettingsSetEnvArgs = @("webapp", "config", "appsettings", "set", "--name", $AppName, "--resource-group", $ResourceGroup, "--settings")
        $appSettingsSetEnvArgs += $settings
        $null = & az @appSettingsSetEnvArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
        Write-Success "Environment variables configured ($($settings.Count) variables)"
    } else {
        Write-Info "No environment variables found in .env"
    }
    
    # Create Deployment Package
    Write-Step "Creating Deployment Package"
    $deployZip = "deploy.zip"
    Write-Info "Creating deployment ZIP: $deployZip"
    
    if (Test-Path $deployZip) {
        Remove-Item $deployZip -Force
    }
    
    # Create zip (exclude unnecessary files)
    $excludePatterns = @(
        "*.pyc", "__pycache__", ".venv", "venv", "*.log", 
        ".git", ".gitignore", "*.md", "docs/*.pdf",
        "tests", "examples", "ml/notebooks", "app-logs",
        "data/raw", "data/processed", ".env"
    )
    
    $filesToZip = Get-ChildItem -Path . -Exclude $excludePatterns -Recurse | 
        Where-Object { $_.FullName -notmatch '\\\.(git|venv|__pycache__)' }
    
    Compress-Archive -Path $filesToZip -DestinationPath $deployZip -Force
    Write-Success "Deployment package created: $deployZip"
    
    # Deploy to Azure
    Write-Step "Deploying to Azure App Service"
    Write-Info "Deploying $deployZip to $AppName..."
    $deployZipArgs = @("webapp", "deployment", "source", "config-zip", "--resource-group", $ResourceGroup, "--name", $AppName, "--src", $deployZip)
    $null = & az @deployZipArgs 2>&1 | Where-Object { $_ -notmatch 'cryptography|UserWarning|32-bit' }
    
    if ($LASTEXITCODE -eq 0) {
        Write-Success "Deployment completed successfully"
    } else {
        Write-Error "Deployment failed"
        exit 1
    }
    
    # Verify Deployment
    Write-Step "Verifying Deployment"
    $appUrl = "https://$AppName.azurewebsites.net"
    Write-Info "Waiting for app to start (30 seconds)..."
    Start-Sleep -Seconds 30
    
    Write-Info "Checking health endpoint: $appUrl/healthz"
    try {
        $response = Invoke-RestMethod -Uri "$appUrl/healthz" -TimeoutSec 10
        Write-Success "Health check passed: $($response | ConvertTo-Json)"
    } catch {
        Write-Error "Health check failed: $_"
        Write-Info "Check logs: az webapp log tail --name $AppName --resource-group $ResourceGroup"
    }
    
    # Summary
    Write-Step "Deployment Summary"
    Write-Host "`n✅ Deployment Complete!" -ForegroundColor Green
    Write-Host "`nApplication URL: $appUrl" -ForegroundColor Cyan
    Write-Host "API Docs: $appUrl/docs" -ForegroundColor Cyan
    Write-Host "Health Check: $appUrl/healthz" -ForegroundColor Cyan
    Write-Host "`nUseful Commands:" -ForegroundColor Yellow
    Write-Host "  View logs: az webapp log tail --name $AppName --resource-group $ResourceGroup" -ForegroundColor Gray
    Write-Host "  Restart app: az webapp restart --name $AppName --resource-group $ResourceGroup" -ForegroundColor Gray
    Write-Host "  View settings: az webapp config appsettings list --name $AppName --resource-group $ResourceGroup" -ForegroundColor Gray
}

# ============================================================================
# DATA PIPELINE (Default)
# ============================================================================
function Deploy-Pipeline {
    Write-Step "Phase 0: Environment Setup"
    
    # Check Python installation
    Write-Info "Checking Python installation..."
    try {
        $pythonVersion = python --version 2>&1
        Write-Success "Python is available: $pythonVersion"
    } catch {
        Write-Error "Python is not installed or not in PATH"
        exit 1
    }
    
    # Check virtual environment
    Write-Info "Checking virtual environment..."
    if (Test-Path ".venv") {
        Write-Success "Virtual environment exists"
    } else {
        Write-Warning "Virtual environment not found - creating..."
        python -m venv .venv
        Write-Success "Virtual environment created"
    }
    
    # Activate virtual environment
    Write-Info "Activating virtual environment..."
    if (Test-Path ".\.venv\Scripts\Activate.ps1") {
        .\.venv\Scripts\Activate.ps1
        Write-Success "Virtual environment activated"
    } else {
        Write-Warning "Virtual environment activation script not found, using system Python"
    }
    
    # Determine Python and pip executables
    $pythonExe = if (Test-Path ".\.venv\Scripts\python.exe") { ".\.venv\Scripts\python.exe" } else { "python" }
    $pipExe = if (Test-Path ".\.venv\Scripts\pip.exe") { ".\.venv\Scripts\pip.exe" } else { "pip" }
    
    # Check required packages
    Write-Info "Checking required packages..."
    $requiredPackages = @("chromadb", "PyPDF2", "pdfplumber", "beautifulsoup4", "lxml", "httpx", "aiohttp", "prometheus_client", "fastapi")
    $missingPackages = @()
    
    foreach ($package in $requiredPackages) {
        $ErrorActionPreference = 'SilentlyContinue'
        $packageName = $package
        if ($package -eq "PyPDF2") {
            $packageName = "PyPDF2"
        } elseif ($package -eq "pdfplumber") {
            $packageName = "pdfplumber"
        } elseif ($package -eq "beautifulsoup4") {
            $packageName = "bs4"
        } elseif ($package -eq "prometheus_client") {
            $packageName = "prometheus_client"
        } elseif ($package -eq "fastapi") {
            $packageName = "fastapi"
        }
        $check = & $pythonExe -c "import $packageName" 2>&1
        $ErrorActionPreference = 'Stop'
        if ($LASTEXITCODE -ne 0) {
            $missingPackages += $package
        }
    }
    
    if ($missingPackages.Count -gt 0) {
        Write-Warning "Missing packages: $($missingPackages -join ', ')"
        Write-Info "Installing missing packages from requirements.txt..."
        & $pipExe install -r requirements.txt
        Write-Success "Packages installed"
    } else {
        Write-Success "All required packages are installed"
    }
    
    # Check environment variables
    Write-Info "Checking environment variables..."
    $requiredVars = @("GROQ_API_KEY", "CHROMA_PERSIST_DIR")
    $missingVars = @()
    
    foreach ($var in $requiredVars) {
        $value = [Environment]::GetEnvironmentVariable($var)
        if (-not $value) {
            # Try .env file
            if (Test-Path ".env") {
                $envContent = Get-Content ".env" -Raw
                if ($envContent -match "$var=(.+)") {
                    continue
                }
            }
            $missingVars += $var
        }
    }
    
    if ($missingVars.Count -gt 0) {
        Write-Warning "Missing environment variables: $($missingVars -join ', ')"
        Write-Info "Please set these in .env file or environment"
    }
    
    # Create data directories
    Write-Info "Creating data directories..."
    $dirs = @("$DATA_DIR/vectorstore")
    foreach ($dir in $dirs) {
        if (-not (Test-Path $dir)) {
            New-Item -ItemType Directory -Path $dir -Force | Out-Null
            Write-Success "Created directory: $dir"
        }
    }
    
    # Check docs directory exists
    Write-Info "Checking docs directory..."
    if (-not (Test-Path "docs")) {
        Write-Warning "docs directory not found - creating..."
        New-Item -ItemType Directory -Path "docs" -Force | Out-Null
        Write-Success "docs directory created"
        Write-Warning "Please add PDF files to the docs directory before running PDF ingestion"
    } else {
        $pdfFiles = Get-ChildItem -Path "docs" -Filter "*.pdf" -ErrorAction SilentlyContinue
        if ($pdfFiles.Count -eq 0) {
            Write-Warning "No PDF files found in docs directory"
            Write-Info "Please add PDF files to the docs directory"
        } else {
            Write-Success "Found $($pdfFiles.Count) PDF file(s) in docs directory"
        }
    }
    
    Write-Success "Phase 0 complete: Environment setup verified"
    
    # ============================================================================
    # PHASE 1: PDF Ingestion
    # ============================================================================
    Write-Step "Phase 1: PDF Ingestion into Vector Database"
    
    if (-not $SkipPdfIngest) {
        # Check if PDF files exist
        $pdfFiles = Get-ChildItem -Path "docs" -Filter "*.pdf" -ErrorAction SilentlyContinue
        if ($pdfFiles.Count -eq 0) {
            Write-Warning "No PDF files found in docs directory"
            Write-Info "Skipping PDF ingestion - add PDF files to docs/ directory and run again"
        } else {
            Write-Info "Found $($pdfFiles.Count) PDF file(s) to process"
            
            # Calculate total size
            $totalSize = ($pdfFiles | Measure-Object -Property Length -Sum).Sum
            $totalSizeMB = [math]::Round($totalSize / 1MB, 2)
            Write-Info "Total size of PDFs: $totalSizeMB MB"
            
            Write-Warning "PDF ingestion may take several minutes depending on the number and size of PDFs"
            Write-Info "The process will show continuous progress updates for each PDF and batch"
            Write-Info "Problematic PDFs will be skipped automatically and processing will continue"
            Write-Info "PDF processing timeout is set to $PdfTimeout seconds per PDF"
            
            if ($FullRefresh) {
                Write-Warning "Full refresh requested - existing PDF chunks will be deleted and re-added"
            }
            
            Write-Info "Starting PDF ingestion..."
            $ingestStartTime = Get-Date
            $ErrorActionPreference = 'Continue'
            $PDF_INGEST_SCRIPT = "scripts/pdf_ingest.py"
            
            # Build command with timeout parameter
            $ingestArgs = @()
            $ingestArgs += "--timeout", $PdfTimeout
            $ingestArgs += "--skip-on-error"
            if ($FullRefresh) {
                $ingestArgs += "--full-refresh"
            }
            
            & $pythonExe $PDF_INGEST_SCRIPT $ingestArgs
            $pdfIngestExitCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            
            $ingestElapsed = (Get-Date) - $ingestStartTime
            $ingestMinutes = [math]::Round($ingestElapsed.TotalMinutes, 2)
            
            Write-Info "PDF ingestion completed in $ingestMinutes minutes"
            
            if ($pdfIngestExitCode -ne 0) {
                Write-Warning "PDF ingestion completed with some failures (exit code: $pdfIngestExitCode)"
                Write-Info "Check the output above for details on which PDFs failed"
                Write-Info "Failed PDFs are listed at the end of the ingestion summary"
                Write-Info "You can retry processing by running the script again"
                
                # Don't exit with error if some PDFs succeeded
                # Only exit if ALL PDFs failed (which would be indicated by the script)
                # The script returns 0 if all succeeded, 1 if any failed
                # We'll continue deployment even if some PDFs failed
            } else {
                Write-Success "PDF ingestion phase completed successfully"
            }
        }
    } else {
        Write-Info "Skipping PDF ingestion phase (--skip-pdf-ingest flag set)"
    }
    
    # ============================================================================
    # PHASE 1b: KB Ingestion
    # ============================================================================
    Write-Step "Phase 1b: KB Ingestion into Vector Database"
    
    # Check if KB directory exists
    $kbDir = "docs\kb"
    if (Test-Path $kbDir) {
        $kbFiles = Get-ChildItem -Path $kbDir -Filter "*.md" -ErrorAction SilentlyContinue
        if ($kbFiles.Count -gt 0) {
            Write-Info "Found $($kbFiles.Count) KB markdown file(s) in docs/kb/"
            Write-Info "Starting KB ingestion..."
            $kbIngestStartTime = Get-Date
            $ErrorActionPreference = 'Continue'
            
            & $pythonExe scripts/kb_ingest.py
            $kbIngestExitCode = $LASTEXITCODE
            $ErrorActionPreference = 'Stop'
            
            $kbIngestElapsed = (Get-Date) - $kbIngestStartTime
            $kbIngestMinutes = [math]::Round($kbIngestElapsed.TotalMinutes, 2)
            
            Write-Info "KB ingestion completed in $kbIngestMinutes minutes"
            
            if ($kbIngestExitCode -eq 0) {
                Write-Success "KB ingestion phase completed successfully"
            } else {
                Write-Warning "KB ingestion completed with warnings (exit code: $kbIngestExitCode)"
                Write-Info "Check the output above for details on KB ingestion status"
            }
        } else {
            Write-Info "No markdown files found in docs/kb/ directory"
            Write-Info "KB ingestion skipped - add .md files to docs/kb/ to enable KB ingestion"
        }
    } else {
        Write-Info "KB directory not found: $kbDir"
        Write-Info "KB ingestion skipped - create docs/kb/ directory and add .md files to enable KB ingestion"
    }
    
    # ============================================================================
    # PHASE 2: API Verification
    # ============================================================================
    Write-Step "Phase 2: API Verification"
    
    Write-Info "Testing API endpoints..."
    $API_URL = "http://localhost:8000"
    
    # Check if server is running
    try {
        $healthResponse = Invoke-RestMethod -Uri "$API_URL/healthz" -TimeoutSec 5 -ErrorAction Stop
        Write-Success "API server is running"
        
        # Test search endpoint
        Write-Info "Testing /v1/search endpoint..."
        try {
            $searchResult = Invoke-RestMethod -Uri "$API_URL/v1/search?q=technical%20analysis&k=3" -TimeoutSec 10 -ErrorAction Stop
            Write-Success "Search endpoint working - found results"
        } catch {
            Write-Warning "Search endpoint test failed: $_"
        }
        
        # Test chat endpoint
        Write-Info "Testing /v1/chat endpoint..."
        try {
            $chatTest = @{
                message = "What is RSI?"
                user_id = "pipeline-test"
            } | ConvertTo-Json
            $chatResponse = Invoke-RestMethod -Uri "$API_URL/v1/chat" -Method Post -ContentType "application/json" -Body $chatTest -TimeoutSec 30
            Write-Success "Chat endpoint working"
        } catch {
            Write-Warning "Chat endpoint test failed: $_"
        }
        
        # Test background status
        Write-Info "Testing /v1/background/status endpoint..."
        try {
            $bgStatus = Invoke-RestMethod -Uri "$API_URL/v1/background/status" -TimeoutSec 10 -ErrorAction Stop
            Write-Success "Background scheduler status accessible"
        } catch {
            Write-Warning "Background status endpoint test failed: $_"
        }
        
    } catch {
        Write-Warning "API server is not running - skipping API verification"
        Write-Info "Start the server with: python -m uvicorn app.main:app --reload"
    }
    
    # ============================================================================
    # PHASE 3: Summary & Next Steps
    # ============================================================================
    Write-Step "Phase 3: Summary & Next Steps"
    
    Write-Success "Pipeline execution completed!"
    Write-Host "`nPipeline Summary:" -ForegroundColor Cyan
    Write-Host "  - PDF documents: docs/" -ForegroundColor Gray
    Write-Host "  - Vector store: $DATA_DIR/vectorstore/" -ForegroundColor Gray
    
    # Check vector store stats
    Write-Info "Checking vector store statistics..."
    try {
        $statsScript = @"
import sys
import os
sys.path.insert(0, os.getcwd())
from app.tools.vector_ingest import get_vector_ingestor
ingestor = get_vector_ingestor()
stats = ingestor.get_collection_stats('pdf_documents')
if stats.get('exists'):
    print(f"PDF documents collection: {stats.get('count', 0)} chunks")
else:
    print("PDF documents collection: not found")
"@
        $statsOutput = $statsScript | & $pythonExe
        Write-Info $statsOutput
    } catch {
        Write-Warning "Could not retrieve vector store statistics"
    }
    
    Write-Host "`nNext Steps:" -ForegroundColor Cyan
    Write-Host "  - Add more PDF files to docs/ directory and run PDF ingestion again" -ForegroundColor Gray
    Write-Host "  - The chatbot will use only information from PDF documents" -ForegroundColor Gray
    Write-Host "  - Background scheduler will periodically re-ingest PDFs (configurable via PDF_INGEST_INTERVAL_HOURS)" -ForegroundColor Gray
    Write-Host "  - Monitor metrics: GET /v1/metrics endpoints" -ForegroundColor Gray
    Write-Host "  - Test chat: POST /v1/chat with your questions" -ForegroundColor Gray
}

# ============================================================================
# MAIN EXECUTION
# ============================================================================
Write-Host "`n========================================" -ForegroundColor Magenta
Write-Host "WealthArena Master Deployment Script" -ForegroundColor Magenta
Write-Host "========================================`n" -ForegroundColor Magenta

switch ($Deploy.ToLower()) {
    "docker" {
        Deploy-Docker
    }
    "azure" {
        Deploy-Azure
    }
    default {
        Deploy-Pipeline
    }
}

Write-Host "`n"
